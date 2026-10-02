-- MasteryConfig (ModuleScript)
-- Waffen-Meisterschaft: Kills mit einer Waffe schalten Tarnungen nur für diese Waffe frei
-- (Bronze → Silber → Gold → Diamant → Dunkle Materie), dazu Münzen.
-- Die Tarnungen sind normale Waffen-Skins in Cosmetics (Id "M_<Waffe>_<Stufe>", Weapon = Waffe, Mastery = Kills),
-- nicht kaufbar. Gezählt wird in den Statistiken: Stats["WKills_<Waffe>"] (Spieler-Attribut "Stats", JSON).
-- Freischalten macht der Server (RewardService), angezeigt wird es in der Lobby (LOADOUT · SKINS).

local HttpService = game:GetService("HttpService")

local WeaponConfig = require(script.Parent.WeaponConfig)

local MasteryConfig = {}

-- Waffen mit Meisterschaft (Reihenfolge für Listen)
MasteryConfig.Weapons = { "Rifle", "SMG", "Shotgun", "DMR", "LMG", "Pistol", "Revolver" }

MasteryConfig.Tiers = {
	{ Id = "Bronze", Name = "Bronze", Kills = 25, Coins = 100, Rarity = "Common",
		Color = Color3.fromRGB(176, 112, 62), Material = Enum.Material.Metal },
	{ Id = "Silber", Name = "Silber", Kills = 75, Coins = 250, Rarity = "Rare",
		Color = Color3.fromRGB(205, 210, 220), Material = Enum.Material.Foil },
	{ Id = "Gold", Name = "Gold", Kills = 150, Coins = 500, Rarity = "Epic",
		Color = Color3.fromRGB(255, 196, 52), Material = Enum.Material.Foil },
	{ Id = "Diamant", Name = "Diamant", Kills = 300, Coins = 1000, Rarity = "Legendary",
		Color = Color3.fromRGB(150, 225, 255), Material = Enum.Material.Glass },
	{ Id = "DunkleMaterie", Name = "Dunkle Materie", Kills = 500, Coins = 2000, Rarity = "Legendary",
		Color = Color3.fromRGB(110, 40, 200), Material = Enum.Material.Neon },
}

function MasteryConfig.ItemId(weaponName, tierId)
	return "M_" .. weaponName .. "_" .. tierId
end

function MasteryConfig.HasMastery(weaponName)
	return table.find(MasteryConfig.Weapons, weaponName) ~= nil and WeaponConfig.Get(weaponName) ~= nil
end

function MasteryConfig.StatKey(weaponName)
	return "WKills_" .. weaponName
end

-- Kills mit einer Waffe (Client und Server: aus dem Attribut "Stats")
function MasteryConfig.Kills(player, weaponName)
	local raw = player:GetAttribute("Stats")
	if type(raw) ~= "string" then
		return 0
	end
	local ok, stats = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(stats) == "table" and tonumber(stats[MasteryConfig.StatKey(weaponName)]) or 0
end

-- Nächste Stufe für kills: tier (nil = alles frei), Fortschritt 0..1 seit der letzten Stufe
function MasteryConfig.Next(kills)
	local from = 0
	for _, tier in MasteryConfig.Tiers do
		if kills < tier.Kills then
			return tier, (kills - from) / (tier.Kills - from)
		end
		from = tier.Kills
	end
	return nil, 1
end

return MasteryConfig
