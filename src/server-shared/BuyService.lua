-- BuyService (ModuleScript, nur Server)
-- Geld pro Match und Kaufphase in den Team-Modi (Drop, Strikeout). Gekaufte Gegenstände stehen als Spieler-Attribute
-- "Buy_<Id>" bereit, das Geld als "Money". Rüstung wird beim Spawn als Charakter-Attribut
-- "Armor" gesetzt (Damage zieht sie zuerst ab).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local BuyConfig = require(Shared.BuyConfig)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)

local BuyService = {}

-- Gekauft werden darf während der Agentenwahl und im Countdown – und in der Auswahl nach dem Tod
-- (Respawn-Modi, Spieler-Attribut "RespawnAt" gesetzt)
local BUY_PHASES = { Select = true, Countdown = true }

local function clearItems(player, perRoundOnly)
	for _, item in BuyConfig.Items do
		if item.PerRound or not perRoundOnly then
			player:SetAttribute("Buy_" .. item.Id, nil)
		end
	end
end

-- Neues Match: Startgeld, alle Käufe zurücksetzen
function BuyService.StartMatch(player)
	player:SetAttribute("Money", BuyConfig.StartMoney)
	clearItems(player, false)
end

-- Spieler verlässt den Modus: alles weg
function BuyService.Clear(player)
	player:SetAttribute("Money", nil)
	clearItems(player, false)
end

-- Runde vorbei bzw. gestorben (Respawn-Modi): Rüstung und Extra-Gadget verfallen
function BuyService.EndRound(player)
	clearItems(player, true)
end

-- Geld geben (nur wenn der Spieler gerade ein Match spielt)
function BuyService.AddMoney(player, amount, reason)
	local money = player:GetAttribute("Money")
	if money == nil then
		return
	end
	player:SetAttribute("Money", math.min(BuyConfig.MaxMoney, money + amount))
	Remotes.MoneyGain:FireClient(player, amount, reason)
end

local function buy(player, itemId)
	local item = typeof(itemId) == "string" and BuyConfig.Get(itemId)
	if not item then
		return "Unbekannter Gegenstand.", false
	end
	local respawning = player:GetAttribute("RespawnAt") ~= nil
	if not Modes.IsTeamMode(player:GetAttribute("Mode"))
		or not (BUY_PHASES[player:GetAttribute("RoundPhase")] or respawning) then
		return "Kaufen geht nur vor der Runde oder nach dem Tod.", false
	end
	if BuyConfig.Has(player, itemId) then
		return item.Name .. " hast du schon.", false
	end
	local money = player:GetAttribute("Money") or 0
	if money < item.Price then
		return "Nicht genug Geld.", false
	end
	player:SetAttribute("Money", money - item.Price)
	player:SetAttribute("Buy_" .. itemId, true)
	return item.Name .. " gekauft.", true
end

function BuyService.Init()
	Remotes.Buy.OnServerEvent:Connect(function(player, itemId)
		local message, success = buy(player, itemId)
		Remotes.ShopStatus:FireClient(player, message, success)
	end)

	-- Gekaufte Rüstung beim Spawn anlegen
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			local armor = BuyConfig.Has(player, "Armor") and BuyConfig.ArmorAmount or 0
			-- Passiv BASTION: Grundrüstung (nur in Kampfmodi)
			local agent = AgentConfig.Get(player:GetAttribute("Agent"))
			if agent and agent.Passive and agent.Passive.Type == "Armor" and Modes.IsFighting(player) then
				armor += 15
			end
			if armor > 0 then
				character:SetAttribute("Armor", armor)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return BuyService
