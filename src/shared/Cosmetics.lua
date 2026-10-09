-- Cosmetics (ModuleScript)
-- Alle Skins: Waffen-Skins (für jede Waffe einzeln ausrüstbar) und Agenten-Skins (Type = "Agent": Uniformfarbe und
-- Material des einen Agenten, ausgerüstet im Menü SKINS). Agenten-Skins sind gebunden (kein RAP, kein Markt, keine Kisten).
-- Neue Skins einfach hier eintragen. Preise in Münzen.
-- Pass = true: exklusiv aus dem Battle Pass, nicht im Shop kaufbar.
-- Besitz und Ausrüstung kommen vom Server als Spieler-Attribute (JSON): "Owned", "Equipped".
-- Equipped-Schlüssel: "W:<Waffe>" = Waffen-Skin, "Agent" = Agenten-Skin
-- Mastery = Kills: Meisterschafts-Tarnung (MasteryConfig), nur für die Waffe in Weapon, nicht kaufbar.
-- Effects = Stil aus SkinEffects (Glitzer, Glut, Licht, Feuerstoß beim Schießen). Test = nicht in Kisten.
-- Creator = true: Creator-Skin, frei für alle mit Team-Rang CREATOR oder höher (StaffConfig), nicht kaufbar und nicht
-- handelbar. Er steht nicht im Spielstand: ProgressService zeigt ihn als Besitz, solange der Rang da ist; ohne Rang ist
-- er gesperrt (ausgerüstet bleibt gespeichert und kommt mit dem Rang zurück).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)
local MasteryConfig = require(ReplicatedStorage:WaitForChild("Shared").MasteryConfig)
local StaffConfig = require(ReplicatedStorage:WaitForChild("Shared").StaffConfig)

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
	{ Id = "W_Saison_Elite", Type = "Weapon", Name = "Saison-Elite", Rarity = "Legendary", Pass = true,
		Color = Color3.fromRGB(16, 128, 122), Material = Enum.Material.Foil },
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
	-- Exklusiv im Robux-Shop (RobuxConfig: Royal-Paket), nicht für Münzen kaufbar
	{ Id = "W_Royal", Type = "Weapon", Name = "Royal", Rarity = "Legendary", Reward = true, Robux = true,
		Color = Color3.fromRGB(120, 50, 200), Material = Enum.Material.Foil },
	{ Id = "W_Hologramm", Type = "Weapon", Name = "Hologramm", Rarity = "Legendary", Reward = true, Robux = true,
		Color = Color3.fromRGB(80, 230, 255), Material = Enum.Material.ForceField },
	-- Login-Kalender Tag 7 und Glücksrad (LoginConfig)
	{ Id = "W_Kalender", Type = "Weapon", Name = "Treue", Rarity = "Legendary", Reward = true,
		Color = Color3.fromRGB(255, 120, 60), Material = Enum.Material.Foil },
	{ Id = "W_Gluecksklee", Type = "Weapon", Name = "Glücksklee", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(60, 200, 110), Material = Enum.Material.Glass },
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
	-- VIP & BOOSTER: erster Wochen-Auftrag (QuestConfig.SpecialWeeklyPool)
	{ Id = "W_Unterstuetzer", Type = "Weapon", Name = "Unterstützer", Rarity = "Epic", Reward = true,
		Color = Color3.fromRGB(255, 115, 250), Material = Enum.Material.Foil },
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

	-- Weitere Waffen-Skins
	{ Id = "W_Carbon", Type = "Weapon", Name = "Carbon", Rarity = "Rare", Price = 500,
		Color = Color3.fromRGB(35, 35, 38), Material = Enum.Material.Fabric },
	{ Id = "W_Koralle", Type = "Weapon", Name = "Koralle", Rarity = "Epic", Price = 850,
		Color = Color3.fromRGB(255, 110, 120), Material = Enum.Material.SmoothPlastic },
	{ Id = "W_Chrom", Type = "Weapon", Name = "Chrom", Rarity = "Legendary", Price = 1400,
		Color = Color3.fromRGB(220, 225, 235), Material = Enum.Material.Foil },

	-- Creator-Skins (Creator = true): für Content Creator mit Team-Rang CREATOR, für alle Waffen
	{ Id = "W_Creator", Type = "Weapon", Name = "Creator", Rarity = "Legendary", Reward = true, Creator = true,
		Color = Color3.fromRGB(150, 70, 230), Material = Enum.Material.Foil },
	{ Id = "W_CreatorLive", Type = "Weapon", Name = "Live", Rarity = "Legendary", Reward = true, Creator = true,
		Color = Color3.fromRGB(235, 45, 70), Material = Enum.Material.Neon },

	-- Test-Skins (Test = true): im Shop kaufbar, aber nicht in Kisten (CrateConfig)
	-- Drachengold: nur Sturmgewehr; Texturen in Assets.Weapons.Rifle.Skins.W_Drachengold, Effekte siehe SkinEffects
	{ Id = "W_Drachengold", Type = "Weapon", Name = "Drachengold", Rarity = "Legendary", Price = 1, Test = true,
		Weapon = "Rifle", Effects = "Drachengold", Color = Color3.fromRGB(235, 175, 55), Material = Enum.Material.Foil },
	-- Splitterlicht: Kristall mit Energieadern, prismatische Leuchtspur, Kill-Finisher „Kristallbruch“ (SkinStyles)
	{ Id = "W_Splitterlicht", Type = "Weapon", Name = "Splitterlicht", Rarity = "Legendary", Price = 1, Test = true,
		Weapon = "Rifle", Effects = "Splitterlicht", Color = Color3.fromRGB(140, 90, 240), Material = Enum.Material.Foil },

	-- Agenten-Skins (Type = "Agent"): Uniform = Farbe von Oberkörper und Armen (Beine dunkler), Material des Körpers.
	-- Im SHOP unter AGENTEN-SKINS für Münzen, ausrüsten im Menü SKINS. Ohne Skin: Standard-Look in der Agentenfarbe.
	{ Id = "AS_Feldgrau", Type = "Agent", Name = "Feldgrau", Rarity = "Common", Price = 300,
		Color = Color3.fromRGB(96, 104, 92), Material = Enum.Material.Fabric },
	{ Id = "AS_Sandsturm", Type = "Agent", Name = "Sandsturm", Rarity = "Common", Price = 300,
		Color = Color3.fromRGB(178, 152, 108), Material = Enum.Material.Fabric },
	{ Id = "AS_Nachtwache", Type = "Agent", Name = "Nachtwache", Rarity = "Rare", Price = 600,
		Color = Color3.fromRGB(34, 38, 54), Material = Enum.Material.Fabric },
	{ Id = "AS_Arktis", Type = "Agent", Name = "Arktis", Rarity = "Rare", Price = 600,
		Color = Color3.fromRGB(214, 224, 232), Material = Enum.Material.Fabric },
	{ Id = "AS_Seuche", Type = "Agent", Name = "Seuche", Rarity = "Epic", Price = 1100,
		Color = Color3.fromRGB(104, 150, 46), Material = Enum.Material.DiamondPlate },
	{ Id = "AS_Panzerstahl", Type = "Agent", Name = "Panzerstahl", Rarity = "Epic", Price = 1100,
		Color = Color3.fromRGB(120, 126, 136), Material = Enum.Material.Metal },
	{ Id = "AS_Karmesin", Type = "Agent", Name = "Karmesin", Rarity = "Legendary", Price = 2000,
		Color = Color3.fromRGB(150, 22, 34), Material = Enum.Material.Foil },
	{ Id = "AS_Goldjunge", Type = "Agent", Name = "Goldjunge", Rarity = "Legendary", Price = 2500,
		Color = Color3.fromRGB(226, 178, 58), Material = Enum.Material.Foil },
	-- Agenten-Skins mit eigenem 3D-Modell (Model = true): Modell in ReplicatedStorage.Assets.Agents.<Id>
	-- (docs/agenten-modelle.md). Ohne Modell im Place: Farbe/Material wie die anderen Skins.
	{ Id = "AS_Scout", Type = "Agent", Name = "Scout", Rarity = "Epic", Price = 1, Test = true, Model = true,
		Color = Color3.fromRGB(70, 80, 55), Material = Enum.Material.Fabric },
	{ Id = "AS_TacticalScout", Type = "Agent", Name = "Tactical Scout", Rarity = "Epic", Price = 1, Test = true, Model = true,
		Color = Color3.fromRGB(120, 96, 66), Material = Enum.Material.Fabric },
	{ Id = "AS_ShadowScout", Type = "Agent", Name = "Shadow Scout", Rarity = "Epic", Price = 1, Test = true, Model = true,
		Color = Color3.fromRGB(28, 28, 32), Material = Enum.Material.Fabric },
	-- Creator-Skin: mit Team-Rang CREATOR (wie die Creator-Waffen-Skins)
	{ Id = "AS_Creator", Type = "Agent", Name = "Creator", Rarity = "Legendary", Reward = true, Creator = true,
		Color = Color3.fromRGB(150, 70, 230), Material = Enum.Material.Foil },
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

-- Alle Skins eines Typs ("Weapon")
function Cosmetics.List(itemType)
	local list = {}
	for _, item in Cosmetics.Items do
		if item.Type == itemType then
			table.insert(list, item)
		end
	end
	return list
end

-- Darf der Spieler die Creator-Skins benutzen? (Team-Rang CREATOR oder höher)
function Cosmetics.CreatorUnlocked(player)
	local creator = StaffConfig.Get("Creator")
	return creator ~= nil and StaffConfig.Power(player) >= creator.Power
end

-- Alle Creator-Skins (Ids)
function Cosmetics.CreatorItems()
	local list = {}
	for _, item in Cosmetics.Items do
		if item.Creator then
			table.insert(list, item.Id)
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

-- Ausgerüsteter Agenten-Skin des Spielers (nur wenn er ihn besitzt), sonst nil
function Cosmetics.AgentSkin(player)
	if not player then
		return nil
	end
	local id = Cosmetics.GetEquipped(player).Agent
	local item = id and Cosmetics.Get(id)
	if item and item.Type == "Agent" and Cosmetics.GetOwned(player)[id] then
		return item
	end
	return nil
end

-- Farben eines Agenten (Uniform, Akzent) und Material des Körpers: mit Agenten-Skin dessen Farbe und Material, sonst
-- der Standard-Look aus der Agentenfarbe (Material nil = Standard)
function Cosmetics.AgentColors(player, agentId)
	local agent = AgentConfig.Get(agentId) or AgentConfig.Agents[1]
	local skin = Cosmetics.AgentSkin(player)
	if skin then
		return skin.Color, agent.Color, skin.Material
	end
	return agent.Color:Lerp(Color3.new(0, 0, 0), 0.6), agent.Color, nil
end

return Cosmetics
