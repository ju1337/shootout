-- CrateService (ModuleScript, nur Server)
-- Kisten öffnen (CrateConfig): Münzen abbuchen, Skin ziehen, dem Spieler geben, Ergebnis samt Rolle an den Client.
-- Remotes: CrateAction (Client -> Server: "Open", Kisten-Id), CrateResult (Server -> Client, siehe CrateConfig).
-- Gezogen wird erst nach der Bezahlung; schlägt etwas fehl, bekommt der Spieler seine Münzen zurück.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local CrateConfig = require(Shared.CrateConfig)
local RapConfig = require(Shared.RapConfig)
local ProgressService = require(script.Parent.ProgressService)

local CrateService = {}

local random = Random.new()
local lastOpen = {} -- [Player] = os.clock()

local function modeAllowed(player)
	local mode = player:GetAttribute("Mode")
	for _, id in CrateConfig.Modes do
		if mode == id then
			return true
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
		return false, "Kisten öffnest du im Markt."
	end
	if not ProgressService.IsLoaded(player) then
		return false, "Deine Daten werden noch geladen."
	end
	local now = os.clock()
	if lastOpen[player] and now - lastOpen[player] < CrateConfig.Cooldown then
		return false, "Nicht so schnell."
	end
	if not ProgressService.SpendCoins(player, crate.Price, "Kiste", crateId) then
		return false, "Nicht genug Münzen (" .. crate.Price .. " nötig)."
	end
	lastOpen[player] = now

	local item = CrateConfig.Roll(crate, random)
	if not item then
		ProgressService.AddCoins(player, crate.Price, "Kiste: Rückerstattung")
		return false, "Diese Kiste ist gerade leer."
	end
	local granted = ProgressService.GrantSkin(player, item.Id)
	local status, refund = granted or "duplicate", 0
	if granted == nil then
		refund = math.floor((item.Price or 0) * CrateConfig.DuplicateRefund)
		if refund > 0 then
			ProgressService.AddCoins(player, refund, "Kiste: Duplikat")
		end
	end

	-- Rolle: Gewinn an festem Platz, der Rest nach denselben Chancen
	local reel = {}
	for index = 1, CrateConfig.ReelLength do
		reel[index] = index == CrateConfig.WinnerIndex and item.Id or CrateConfig.Roll(crate, random).Id
	end
	task.spawn(ProgressService.SaveNow, player)
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
