-- Cosmetics (ModuleScript)
-- Alle Skins im Shop: Waffen-Skins (für jede Waffe einzeln ausrüstbar) und Agenten-Skins.
-- Neue Skins einfach hier eintragen. Preise in Münzen.
-- Pass = true: exklusiv aus dem Battle Pass, nicht im Shop kaufbar.
-- Besitz und Ausrüstung kommen vom Server als Spieler-Attribute (JSON): "Owned", "Equipped".
-- Equipped-Schlüssel: "W:<Waffe>" = Waffen-Skin, "A:<Agent>" = Agenten-Skin

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)

local Cosmetics = {}

Cosmetics.DailyReward = 100            -- Münzen pro täglicher Belohnung
Cosmetics.DailyCooldown = 20 * 3600    -- Sekunden bis zur nächsten
Cosmetics.CoinsPerXP = 0.1             -- 100 XP = 10 Münzen

Cosmetics.Rarities = {
	Common = { Name = "Gewöhnlich", Color = Color3.fromRGB(150, 155, 165) },
	Rare = { Name = "Selten", Color = Color3.fromRGB(70, 140, 255) },
	Epic = { Name = "Episch", Color = Color3.fromRGB(170, 80, 255) },
	Legendary = { Name = "Legendär", Color = Color3.fromRGB(255, 180, 40) },
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

function Cosmetics.Get(id)
	for _, item in Cosmetics.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
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
	if item and Cosmetics.GetOwned(player)[id] then
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
