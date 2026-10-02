-- Cosmetics (ModuleScript)
-- Alle Skins im Shop: Waffen-Skins (für jede Waffe einzeln ausrüstbar) und Agenten-Skins.
-- Neue Skins einfach hier eintragen. Preise in Münzen.
-- Pass = true: exklusiv aus dem Battle Pass, nicht im Shop kaufbar.
-- Besitz und Ausrüstung kommen vom Server als Spieler-Attribute (JSON): "Owned", "Equipped".
-- Equipped-Schlüssel: "W:<Waffe>" = Waffen-Skin, "A:<Agent>" = Agenten-Skin
-- Mastery = Kills: Meisterschafts-Tarnung (MasteryConfig), nur für die Waffe in Weapon, nicht kaufbar.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)
local MasteryConfig = require(ReplicatedStorage:WaitForChild("Shared").MasteryConfig)

local Cosmetics = {}

Cosmetics.DailyReward = 100            -- Münzen pro täglicher Belohnung
Cosmetics.DailyCooldown = 20 * 3600    -- Sekunden bis zur nächsten
Cosmetics.CoinsPerXP = 0.25            -- 100 XP = 25 Münzen (Kill 25, Rundensieg ~37, Matchsieg 100)

Cosmetics.Rarities = {
	Common = { Name = "Gewöhnlich", Color = Color3.fromRGB(150, 155, 165) },
	Rare = { Name = "Selten", Color = Color3.fromRGB(86, 136, 204) },
	Epic = { Name = "Episch", Color = Color3.fromRGB(148, 104, 204) },
	Legendary = { Name = "Legendär", Color = Color3.fromRGB(214, 160, 62) },
}

Cosmetics.Items = {
	-- Waffen-Skins
	{ Id = "W_Wald", Type = "Weapon", Name = "Waldtarn", Rarity = "Common", Price = 250,
		Color = Color3.fromRGB(70, 95, 55), Material = Enum.Material.Fabric },
	{ Id = "W_Wueste", Type = "Weapon", Name = "Wüste", Rarity = "Common", Price = 250,
		Color = Color3.fromRGB(195, 170, 120), Material = Enum.Material.Sand },
	{ Id = "W_Kirsche", Type = "Weapon", Name = "Kirschrot", Rarity = "Rare", Price = 450,
		Color = Color3.fromRGB(170, 30, 45), Material = Enum.Material.SmoothPlastic },
	{ Id = "W_Mitternacht", Type = "Weapon", Name = "Mitternacht", Rarity = "Rare", Price = 450,
		Color = Color3.fromRGB(30, 35, 70), Material = Enum.Material.Metal },
	{ Id = "W_Gletscher", Type = "Weapon", Name = "Gletscher", Rarity = "Epic", Price = 800,
		Color = Color3.fromRGB(160, 220, 255), Material = Enum.Material.Glass },
	{ Id = "W_Lava", Type = "Weapon", Name = "Lava", Rarity = "Legendary", Price = 1200,
		Color = Color3.fromRGB(255, 90, 20), Material = Enum.Material.Neon },
	{ Id = "W_Galaxie", Type = "Weapon", Name = "Galaxie", Rarity = "Legendary", Price = 1500,
		Color = Color3.fromRGB(140, 60, 255), Material = Enum.Material.Neon },

	-- Exklusive Battle-Pass-Skins
	{ Id = "W_Saison", Type = "Weapon", Name = "Saison-Neon", Rarity = "Epic", Pass = true,
		Color = Color3.fromRGB(40, 255, 200), Material = Enum.Material.Neon },
	{ Id = "W_Goldrausch", Type = "Weapon", Name = "Goldrausch", Rarity = "Legendary", Pass = true,
		Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Foil },

	-- Belohnungs-Skins (Reward = true): nicht kaufbar, gibt es für Level, Prestige und Rang (RewardConfig)
	{ Id = "W_Rekrut", Type = "Weapon", Name = "Rekrut", Rarity = "Rare", Reward = true,
		Color = Color3.fromRGB(96, 112, 74), Material = Enum.Material.Fabric },
	{ Id = "W_Veteran", Type = "Weapon", Name = "Veteran", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(70, 78, 88), Material = Enum.Material.DiamondPlate },
	{ Id = "W_Elite", Type = "Weapon", Name = "Elite", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(30, 30, 36), Material = Enum.Material.Metal },
	{ Id = "W_Spezialist", Type = "Weapon", Name = "Spezialist", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(150, 40, 44), Material = Enum.Material.Foil },
	{ Id = "W_Grossmeister", Type = "Weapon", Name = "Großmeister", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(225, 228, 236), Material = Enum.Material.Foil },
	-- Saison-Ende (RewardConfig.SeasonEnd): nach dem höchsten Rang der Saison
	{ Id = "W_SE_Gold", Type = "Weapon", Name = "Saison-Gold", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(240, 195, 60), Material = Enum.Material.DiamondPlate },
	{ Id = "W_SE_Platin", Type = "Weapon", Name = "Saison-Platin", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(90, 220, 200), Material = Enum.Material.Foil },
	{ Id = "W_SE_Diamant", Type = "Weapon", Name = "Saison-Diamant", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(110, 170, 255), Material = Enum.Material.Glass },
	{ Id = "W_SE_Champion", Type = "Weapon", Name = "Champion", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(220, 90, 255), Material = Enum.Material.Neon },
	-- Wochen-Bonus (QuestConfig.WeeklyBonus): wechselt jede Woche
	{ Id = "W_Woche_Kobalt", Type = "Weapon", Name = "Kobalt", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(40, 80, 200), Material = Enum.Material.Foil },
	{ Id = "W_Woche_Smaragd", Type = "Weapon", Name = "Smaragd", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(30, 170, 100), Material = Enum.Material.Glass },
	{ Id = "W_Woche_Purpur", Type = "Weapon", Name = "Purpur", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(120, 40, 150), Material = Enum.Material.Foil },
	{ Id = "W_Woche_Bernstein", Type = "Weapon", Name = "Bernstein", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(230, 140, 30), Material = Enum.Material.Glass },
	{ Id = "W_Woche_Titan", Type = "Weapon", Name = "Titan", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(110, 115, 125), Material = Enum.Material.DiamondPlate },
	{ Id = "W_PrestigeBronze", Type = "Weapon", Name = "Prestige Bronze", Rarity = "Rare", Reward = true,
		Color = Color3.fromRGB(176, 112, 64), Material = Enum.Material.Metal },
	{ Id = "W_PrestigeGold", Type = "Weapon", Name = "Prestige Gold", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(236, 186, 64), Material = Enum.Material.Foil },
	{ Id = "W_PrestigeDiamant", Type = "Weapon", Name = "Prestige Diamant", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(130, 200, 250), Material = Enum.Material.Ice },
	{ Id = "W_PrestigeRubin", Type = "Weapon", Name = "Prestige Rubin", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(196, 28, 52), Material = Enum.Material.Foil },
	{ Id = "W_PrestigeLegende", Type = "Weapon", Name = "Prestige Legende", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(240, 236, 255), Material = Enum.Material.Neon },
	{ Id = "W_SaisonMeister", Type = "Weapon", Name = "Meister · Saison", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(176, 90, 250), Material = Enum.Material.Foil },

	-- Agenten-Skins (Primary = Uniform, Accent = Visier/Weste)
	{ Id = "A_Viper_Nacht", Type = "Agent", Agent = "Viper", Name = "Nachtschlange", Rarity = "Rare", Price = 600,
		Primary = Color3.fromRGB(30, 35, 45), Accent = Color3.fromRGB(80, 255, 160) },
	{ Id = "A_Viper_Gift", Type = "Agent", Agent = "Viper", Name = "Giftgrün", Rarity = "Epic", Price = 1000,
		Primary = Color3.fromRGB(60, 120, 40), Accent = Color3.fromRGB(200, 255, 60) },
	{ Id = "A_Bastion_Stahl", Type = "Agent", Agent = "Bastion", Name = "Stahlwall", Rarity = "Rare", Price = 600,
		Primary = Color3.fromRGB(90, 95, 105), Accent = Color3.fromRGB(255, 170, 40) },
	{ Id = "A_Bastion_Royal", Type = "Agent", Agent = "Bastion", Name = "Königsgarde", Rarity = "Legendary", Price = 1500,
		Primary = Color3.fromRGB(40, 40, 120), Accent = Color3.fromRGB(230, 190, 60) },
	{ Id = "A_Mender_Feld", Type = "Agent", Agent = "Mender", Name = "Feldarzt", Rarity = "Rare", Price = 600,
		Primary = Color3.fromRGB(225, 225, 230), Accent = Color3.fromRGB(220, 40, 50) },
	{ Id = "A_Mender_Neon", Type = "Agent", Agent = "Mender", Name = "Neon-Puls", Rarity = "Epic", Price = 1000,
		Primary = Color3.fromRGB(30, 20, 40), Accent = Color3.fromRGB(255, 60, 200) },
	{ Id = "A_Hawk_Wueste", Type = "Agent", Agent = "Hawk", Name = "Wüstenfalke", Rarity = "Rare", Price = 600,
		Primary = Color3.fromRGB(170, 140, 90), Accent = Color3.fromRGB(255, 120, 40) },
	{ Id = "A_Viper_Saison", Type = "Agent", Agent = "Viper", Name = "Saison-Agentin", Rarity = "Legendary", Pass = true,
		Primary = Color3.fromRGB(20, 40, 50), Accent = Color3.fromRGB(40, 255, 200) },
	{ Id = "A_Ghost_Schatten", Type = "Agent", Agent = "Ghost", Name = "Schattenmann", Rarity = "Rare", Price = 700,
		Primary = Color3.fromRGB(25, 25, 30), Accent = Color3.fromRGB(160, 160, 255) },
	{ Id = "A_Ghost_Nebel", Type = "Agent", Agent = "Ghost", Name = "Nebelgeist", Rarity = "Legendary", Price = 1600,
		Primary = Color3.fromRGB(200, 205, 215), Accent = Color3.fromRGB(120, 255, 230) },
	{ Id = "A_Blaze_Inferno", Type = "Agent", Agent = "Blaze", Name = "Inferno", Rarity = "Epic", Price = 1100,
		Primary = Color3.fromRGB(60, 20, 15), Accent = Color3.fromRGB(255, 90, 20) },
	{ Id = "A_Blaze_Asche", Type = "Agent", Agent = "Blaze", Name = "Asche", Rarity = "Rare", Price = 700,
		Primary = Color3.fromRGB(80, 80, 85), Accent = Color3.fromRGB(255, 160, 60) },
	{ Id = "A_Aegis_Bollwerk", Type = "Agent", Agent = "Aegis", Name = "Bollwerk", Rarity = "Epic", Price = 1100,
		Primary = Color3.fromRGB(30, 50, 90), Accent = Color3.fromRGB(240, 240, 255) },
	{ Id = "A_Aegis_Sanitaet", Type = "Agent", Agent = "Aegis", Name = "Sanitätsdienst", Rarity = "Rare", Price = 700,
		Primary = Color3.fromRGB(230, 230, 235), Accent = Color3.fromRGB(60, 200, 120) },
	{ Id = "A_Trapper_Wildnis", Type = "Agent", Agent = "Trapper", Name = "Wildnis", Rarity = "Rare", Price = 700,
		Primary = Color3.fromRGB(90, 75, 50), Accent = Color3.fromRGB(200, 170, 90) },
	{ Id = "A_Trapper_Jaeger", Type = "Agent", Agent = "Trapper", Name = "Nachtjäger", Rarity = "Legendary", Price = 1600,
		Primary = Color3.fromRGB(20, 30, 25), Accent = Color3.fromRGB(150, 255, 90) },
	{ Id = "A_Volt_Hochspannung", Type = "Agent", Agent = "Volt", Name = "Hochspannung", Rarity = "Epic", Price = 1100,
		Primary = Color3.fromRGB(30, 30, 40), Accent = Color3.fromRGB(255, 240, 60) },
	{ Id = "A_Volt_Kupfer", Type = "Agent", Agent = "Volt", Name = "Kupfer", Rarity = "Rare", Price = 700,
		Primary = Color3.fromRGB(140, 80, 50), Accent = Color3.fromRGB(80, 220, 255) },
	-- Weitere Waffen-Skins
	{ Id = "W_Carbon", Type = "Weapon", Name = "Carbon", Rarity = "Rare", Price = 500,
		Color = Color3.fromRGB(35, 35, 38), Material = Enum.Material.Fabric },
	{ Id = "W_Koralle", Type = "Weapon", Name = "Koralle", Rarity = "Epic", Price = 850,
		Color = Color3.fromRGB(255, 110, 120), Material = Enum.Material.SmoothPlastic },
	{ Id = "W_Chrom", Type = "Weapon", Name = "Chrom", Rarity = "Legendary", Price = 1400,
		Color = Color3.fromRGB(220, 225, 235), Material = Enum.Material.Foil },
	{ Id = "A_Hawk_Phantom", Type = "Agent", Agent = "Hawk", Name = "Phantom", Rarity = "Legendary", Price = 1500,
		Primary = Color3.fromRGB(20, 20, 25), Accent = Color3.fromRGB(120, 200, 255) },
}

-- Meisterschafts-Tarnungen: pro Waffe eine je Stufe
for _, weaponName in MasteryConfig.Weapons do
	for _, tier in MasteryConfig.Tiers do
		table.insert(Cosmetics.Items, { Id = MasteryConfig.ItemId(weaponName, tier.Id), Type = "Weapon",
			Weapon = weaponName, Mastery = tier.Kills, Name = tier.Name, Rarity = tier.Rarity, Color = tier.Color,
			Material = tier.Material })
	end
end

local byId = {}
for _, item in Cosmetics.Items do
	byId[item.Id] = item
end

function Cosmetics.Get(id)
	return byId[id]
end

-- Kann der Skin auf diese Waffe? (Meisterschafts-Tarnungen nur auf ihre eigene)
function Cosmetics.FitsWeapon(item, weaponName)
	return item.Type == "Weapon" and (item.Weapon == nil or item.Weapon == weaponName)
end

-- Im Shop kaufbar?
function Cosmetics.ForSale(item)
	return item.Price ~= nil and not item.Pass and not item.Reward and not item.Mastery
end

-- Alle Skins eines Typs ("Weapon"/"Agent"), optional nur für einen Agenten
function Cosmetics.List(itemType, agentId)
	local list = {}
	for _, item in Cosmetics.Items do
		if item.Type == itemType and (not agentId or item.Agent == agentId) then
			table.insert(list, item)
		end
	end
	return list
end

local function decode(player, attribute)
	local raw = player:GetAttribute(attribute)
	if type(raw) ~= "string" then
		return {}
	end
	local ok, result = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(result) == "table" and result or {}
end

function Cosmetics.GetOwned(player)
	return decode(player, "Owned")
end

function Cosmetics.GetEquipped(player)
	return decode(player, "Equipped")
end

-- Skin für eine Waffe: gekaufter Skin, sonst Level-Belohnung des Agenten (Gold/Diamant), sonst nil
function Cosmetics.WeaponSkin(player, agentId, weaponName)
	local id = Cosmetics.GetEquipped(player)["W:" .. weaponName]
	local item = id and Cosmetics.Get(id)
	if item and Cosmetics.GetOwned(player)[id] and Cosmetics.FitsWeapon(item, weaponName) then
		return item
	end
	if agentId then
		return AgentConfig.SkinForLevel(AgentConfig.LevelFromXP(AgentConfig.GetXP(player, agentId)))
	end
	return nil
end

-- Farben eines Agenten (Uniform, Akzent) mit ausgerüstetem Skin
function Cosmetics.AgentColors(player, agentId)
	local agent = AgentConfig.Get(agentId) or AgentConfig.Agents[1]
	local id = player and Cosmetics.GetEquipped(player)["A:" .. agent.Id]
	local item = id and Cosmetics.Get(id)
	if item and Cosmetics.GetOwned(player)[id] then
		return item.Primary, item.Accent
	end
	return agent.Color:Lerp(Color3.new(0, 0, 0), 0.6), agent.Color
end

return Cosmetics
