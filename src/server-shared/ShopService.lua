-- ShopService (ModuleScript, nur Server)
-- Kaufen und Ausrüsten von Skins, tägliche Belohnung, Codes. Alles wird hier geprüft.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local WeaponConfig = require(Shared.WeaponConfig)
local AgentConfig = require(Shared.AgentConfig)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)

local ShopService = {}

-- Einlösbare Codes (Großschreibung) und ihre Münzen. Jeder Code geht einmal pro Spieler.
local CODES = {
	SHOOTOUT = 500,
	ROGUE = 250,
	DROP = 250,
}

local actions = {}

function actions.Buy(player, itemId)
	local item = Cosmetics.Get(itemId)
	if not item then
		return "Unbekannter Skin.", false
	end
	if item.Pass then
		return "Diesen Skin gibt es nur im Battle Pass.", false
	end
	if ProgressService.Owns(player, itemId) then
		return "Du besitzt " .. item.Name .. " schon.", false
	end
	if not ProgressService.SpendCoins(player, item.Price) then
		return "Nicht genug Münzen.", false
	end
	ProgressService.GiveItem(player, itemId)
	-- Agenten-Skins direkt anziehen
	if item.Type == "Agent" then
		ProgressService.SetEquipped(player, "A:" .. item.Agent, itemId)
	end
	return item.Name .. " gekauft!", true
end

-- Skin ausrüsten. Waffen-Skins brauchen die Zielwaffe.
function actions.Equip(player, itemId, weaponName)
	local item = Cosmetics.Get(itemId)
	if not item or not ProgressService.Owns(player, itemId) then
		return "Diesen Skin besitzt du nicht.", false
	end
	if item.Type == "Weapon" then
		if typeof(weaponName) ~= "string" or not WeaponConfig.Get(weaponName) then
			return "Unbekannte Waffe.", false
		end
		ProgressService.SetEquipped(player, "W:" .. weaponName, itemId)
		return item.Name .. " auf " .. WeaponConfig.Get(weaponName).DisplayName .. " ausgerüstet.", true
	end
	ProgressService.SetEquipped(player, "A:" .. item.Agent, itemId)
	return item.Name .. " ausgerüstet.", true
end

-- Standard-Aussehen: slot = "W:<Waffe>" oder "A:<Agent>"
function actions.Unequip(player, slot)
	if typeof(slot) ~= "string" then
		return "Ungültig.", false
	end
	local kind, name = string.match(slot, "^(%u):(%w+)$")
	local valid = (kind == "W" and WeaponConfig.Get(name)) or (kind == "A" and AgentConfig.Get(name))
	if not valid then
		return "Ungültig.", false
	end
	ProgressService.SetEquipped(player, slot, nil)
	return "Standard ausgerüstet.", true
end

function actions.ClaimDaily(player)
	local profile = ProgressService.Get(player)
	if not profile then
		return "Daten werden noch geladen.", false
	end
	local now = os.time()
	local left = profile.LastDaily + Cosmetics.DailyCooldown - now
	if left > 0 then
		return string.format("Wieder verfügbar in %d h %d min.", left // 3600, (left % 3600) // 60), false
	end
	profile.LastDaily = now
	ProgressService.AddCoins(player, Cosmetics.DailyReward)
	return "+" .. Cosmetics.DailyReward .. " Münzen abgeholt!", true
end

function actions.RedeemCode(player, code)
	local profile = ProgressService.Get(player)
	if not profile or typeof(code) ~= "string" then
		return "Ungültiger Code.", false
	end
	code = string.upper(string.gsub(code, "%s", ""))
	local reward = CODES[code]
	if not reward then
		return "Diesen Code gibt es nicht.", false
	end
	if profile.Codes[code] then
		return "Code schon eingelöst.", false
	end
	profile.Codes[code] = true
	ProgressService.AddCoins(player, reward)
	return "Code eingelöst: +" .. reward .. " Münzen!", true
end

-- Agenten mit Münzen freischalten
function actions.UnlockAgent(player, agentId)
	local agent = typeof(agentId) == "string" and AgentConfig.Get(agentId)
	local profile = ProgressService.Get(player)
	if not agent or not profile then
		return "Unbekannter Agent.", false
	end
	if AgentConfig.IsUnlocked(player, agentId) then
		return agent.Name .. " ist schon freigeschaltet.", false
	end
	if not ProgressService.SpendCoins(player, agent.Price) then
		return "Nicht genug Münzen (" .. agent.Price .. " nötig).", false
	end
	profile.Agents = profile.Agents or {}
	profile.Agents[agentId] = true
	ProgressService.Sync(player)
	return agent.Name .. " freigeschaltet!", true
end

-- Persönliche Einstellungen speichern (Sichtfeld, Empfindlichkeit, Kamera)
function actions.SaveSettings(player, settings)
	local profile = ProgressService.Get(player)
	if not profile or typeof(settings) ~= "table" then
		return nil
	end
	profile.Settings = {
		Fov = math.clamp(tonumber(settings.Fov) or 70, 60, 100),
		Sensitivity = math.clamp(tonumber(settings.Sensitivity) or 1, 0.1, 3),
		ThirdPerson = settings.ThirdPerson == true,
	}
	ProgressService.Sync(player)
	return nil -- keine Meldung nötig
end

function actions.ClaimQuest(player, id)
	return ProgressService.ClaimQuest(player, id)
end

function ShopService.Init()
	Remotes.ShopAction.OnServerEvent:Connect(function(player, action, a, b)
		local handler = typeof(action) == "string" and actions[action]
		if not handler then
			return
		end
		local ok, message, success = pcall(handler, player, a, b)
		if not ok then
			warn("Shop-Fehler: " .. tostring(message))
			message, success = "Fehler, bitte nochmal versuchen.", false
		end
		if message then
			Remotes.ShopStatus:FireClient(player, message, success)
		end
	end)
end

return ShopService
