-- CrateService (ModuleScript, nur Server)
-- Kisten öffnen (CrateConfig): Münzen abbuchen, Skin ziehen, dem Spieler geben, Ergebnis samt Rolle an den Client.
-- Remotes: CrateAction (Client -> Server: "Open", Kisten-Id), CrateResult (Server -> Client, siehe CrateConfig).
-- Gezogen wird erst nach der Bezahlung; schlägt etwas fehl, bekommt der Spieler seine Münzen zurück.
-- Wo Roblox bezahlte Zufallsitems verbietet (PolicyGate), bleibt die Kiste zu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local CrateConfig = require(Shared.CrateConfig)
local Modes = require(Shared.Modes)
local RapConfig = require(Shared.RapConfig)
local ProgressService = require(script.Parent.ProgressService)
local PolicyGate = require(script.Parent.PolicyGate)
local DiscordLog = require(script.Parent.DiscordLog)
local Zentrale = require(Shared.Zentrale)
local LoginConfig = require(Shared.LoginConfig)
local RunService = game:GetService("RunService")

local CrateService = {}

local random = Random.new()
local lastOpen = {} -- [Player] = os.clock()

local function modeAllowed(player)
	local mode = player:GetAttribute("Mode")
	for _, id in CrateConfig.Modes do
		if mode == id then
			return Modes.InLounge(player)
		end
	end
	return false
end

-- Kiste öffnen. Gibt true und die Ergebnis-Tabelle zurück, sonst false und eine Meldung.
function CrateService.Open(player, crateId)
	local crate = typeof(crateId) == "string" and CrateConfig.Get(crateId)
	if not crate then
		return false, "Diese Kiste gibt es nicht."
	end
	if not modeAllowed(player) then
		return false, "Kisten öffnest du im Camp oder in einer Safe Zone."
	end
	-- Roblox: bezahlte Zufallsitems (Münzen gibt es auch für Robux) sind in manchen Ländern verboten (PolicyGate)
	if not PolicyGate.RandomAllowed(player) then
		return false, "Kisten gibt es in deinem Land nicht. Skins kannst du im Shop direkt kaufen."
	end
	if not ProgressService.IsLoaded(player) then
		return false, "Deine Daten werden noch geladen."
	end
	local now = os.clock()
	local cooldown = CrateConfig.Quick(player) and CrateConfig.QuickCooldown or CrateConfig.Cooldown
	if lastOpen[player] and now - lastOpen[player] < cooldown then
		return false, "Nicht so schnell."
	end
	if crate.Product then
		-- Robux-Kiste: nur über den Kauf (RobuxService -> OpenPaid); Admins in Studio öffnen sie zum Testen gratis
		if not LoginConfig.AdminFreeSpins(player, RunService:IsStudio()) then
			return false, "Die ROBUX-KISTE öffnest du mit Robux."
		end
		lastOpen[player] = now
		return CrateService.Deliver(player, crate)
	end
	if not ProgressService.SpendCoins(player, crate.Price, "Kiste", crateId) then
		return false, "Nicht genug Münzen (" .. crate.Price .. " nötig)."
	end
	lastOpen[player] = now
	local ok, result = CrateService.Deliver(player, crate)
	if not ok then
		ProgressService.AddCoins(player, crate.Price, "Kiste: Rückerstattung")
	end
	return ok, result
end

-- Bezahlte Robux-Kiste öffnen (RobuxService nach dem Kauf): ohne Ort, Wartezeit und Münzen; der Kauf ist schon bezahlt
function CrateService.OpenPaid(player, crateId)
	local crate = CrateConfig.Get(crateId)
	if not crate then
		return false, "Diese Kiste gibt es nicht."
	end
	return CrateService.Deliver(player, crate)
end

-- Skin ziehen, geben (Duplikat: Münzen), Rolle bauen, Ergebnis an den Client, Automat in der Welt aufklappen
function CrateService.Deliver(player, crate)
	local item = CrateConfig.Roll(crate, random)
	if not item then
		return false, "Diese Kiste ist gerade leer."
	end
	local granted = ProgressService.GrantSkin(player, item.Id)
	local status, refund = granted or "duplicate", 0
	if granted == nil then
		refund = CrateConfig.DuplicateRefund(crate, item)
		if refund > 0 then
			ProgressService.AddCoins(player, refund, "Kiste: Duplikat")
		end
	end

	-- Rolle: Gewinn an festem Platz, der Rest nach denselben Chancen
	local reel = {}
	for index = 1, CrateConfig.ReelLength do
		reel[index] = index == CrateConfig.WinnerIndex and item.Id or CrateConfig.Roll(crate, random).Id
	end
	if item.Rarity == "Legendary" then
		DiscordLog.Log("Highlight", "Legendärer Skin aus der Kiste", item.Name, { { "Spieler", DiscordLog.Who(player) } })
	end
	task.spawn(ProgressService.SaveNow, player)
	-- Automat im Camp: Deckel klappt für alle auf, wenn beim Spieler die Rolle steht (CrateClient, Attribute am Automaten)
	local machine = Zentrale.Part("Crate" .. crate.Id)
	if machine then
		local quick = CrateConfig.Quick(player)
		task.delay(quick and CrateConfig.QuickSpinTime or CrateConfig.SpinTime, function()
			if machine.Parent then
				machine:SetAttribute("OpenRarity", item.Rarity)
				machine:SetAttribute("OpenCount", (machine:GetAttribute("OpenCount") or 0) + 1)
			end
		end)
	end
	local result = { Ok = true, Crate = crate.Id, Item = item.Id, Reel = reel, Index = CrateConfig.WinnerIndex, Status = status,
		Refund = refund, Coins = player:GetAttribute("Coins") or 0, Tradeable = RapConfig.Tradeable(item.Id) }
	Remotes.CrateResult:FireClient(player, result)
	return true, result
end

function CrateService.Init()
	Remotes.CrateAction.OnServerEvent:Connect(function(player, action, crateId)
		if action ~= "Open" then
			return
		end
		local ok, success, payload = pcall(CrateService.Open, player, crateId)
		if not ok then
			warn("Kisten-Fehler: " .. tostring(success))
			Remotes.CrateResult:FireClient(player, { Ok = false, Message = "Fehler, bitte nochmal versuchen." })
		elseif not success then
			Remotes.CrateResult:FireClient(player, { Ok = false, Message = payload })
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastOpen[player] = nil
	end)
end

return CrateService
