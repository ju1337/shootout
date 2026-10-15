-- Waffen-Balance nach Joel (2026-10-12): LMG und Präzisionsgewehr sind die stärksten Waffen, das Präzisionsgewehr die
-- seltenste; das LMG schießt nur aus der Hüfte (auch der Server rechnet so), Streuungs-Aufsätze machen es besser.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local WeaponConfig = require("WeaponConfig")
local AttachmentConfig = require("AttachmentConfig")
local ExtinctionConfig = require("ExtinctionConfig")

-- Stärke: Präzisionsgewehr höchster Schaden pro Kugel, LMG höchster Schaden pro Sekunde
local dmr, lmg = WeaponConfig.Get("DMR"), WeaponConfig.Get("LMG")
for name, cfg in WeaponConfig.Weapons do
	if name ~= "DMR" then
		check(dmr.Damage > cfg.Damage, "Präzisionsgewehr mehr Schaden pro Kugel als " .. name)
	end
	if name ~= "LMG" then
		check(lmg.Damage / lmg.FireDelay > cfg.Damage * (cfg.Pellets or 1) / cfg.FireDelay * (name == "Shotgun" and 0 or 1),
			"LMG mehr Schaden pro Sekunde als " .. name)
	end
end

-- Längere Fights (Julio, 2026-10-15), gerechnet gegen volle Rüstung (schwere Weste) bis 0 Leben, aus kurzer Distanz.
-- Mit Feldbett (bis +15 Leben) gelten dieselben Grenzen.
local health = 90 -- VIPER
local full = health + ExtinctionConfig.MaxArmor
local bed = full + 15
local function shots(cfg, total)
	return math.ceil(total / (cfg.Damage * (cfg.Pellets or 1)) - 1e-9)
end
local function ttk(name, total)
	local cfg = WeaponConfig.Get(name)
	return (shots(cfg, total) - 1) * cfg.FireDelay
end
for _, total in { full, bed } do
	local rifle = shots(WeaponConfig.Get("Rifle"), total)
	check(rifle >= 11 and rifle <= 13, "Sturmgewehr: 11-13 Treffer bis zum Kill (" .. rifle .. " bei " .. total .. ")")
	local sniper = shots(dmr, total)
	check(sniper >= 4 and sniper <= 5, "Präzisionsgewehr: 4-5 Körpertreffer (" .. sniper .. " bei " .. total .. ")")
	check(shots(WeaponConfig.Get("Shotgun"), total) <= 2, "Schrotflinte tötet aus nächster Nähe mit höchstens 2 Schüssen")
	local base = ttk("Rifle", total)
	for name in WeaponConfig.Weapons do
		if name ~= "Shotgun" then
			check(ttk(name, total) >= base * 0.75 and ttk(name, total) <= base * 1.4,
				name .. ": etwa so schnell wie das Sturmgewehr (" .. ttk(name, total) .. " s statt " .. base .. " s)")
		end
	end
	check(ttk("SMG", total) > base and ttk("Pistol", total) > base, "MP und Pistole etwas langsamer als das Sturmgewehr")
	check(ttk("LMG", total) < base, "LMG bleibt am stärksten (schneller als das Sturmgewehr)")
	check(ttk("Revolver", total) < ttk("Pistol", total), "Revolver stärker als die Pistole")
end
-- PvP: kein Kopfschuss tötet mit einem Schuss (alle Kugeln am Kopf). Ohne Weste auch nicht, außer die Schrotflinte
-- aus nächster Nähe (die tötet Ungepanzerte auch mit Körpertreffern).
for name, cfg in WeaponConfig.Weapons do
	local head = cfg.Damage * (cfg.Pellets or 1) * WeaponConfig.PartMultiplier("Head", cfg)
	check(head < full, name .. ": Kopfschuss tötet niemanden mit voller Rüstung (" .. head .. ")")
	if not cfg.Pellets then
		check(head < health, name .. ": Kopfschuss tötet auch ohne Weste nicht (" .. head .. ")")
	end
end
check(WeaponConfig.ZombieHeadshotKills == true, "Zombies: Kopfschuss tötet (Damage.Apply, tests/zombies)")
check(dmr.AimSpread == 0 and dmr.FireDelay == 0.3, "Präzisionsgewehr behält Zielen ohne Streuung und Feuerrate")

-- LMG nur aus der Hüfte: Zielen ändert nichts an der Streuung (Client wie Server rufen SpreadFor)
check(lmg.HipOnly == true and not WeaponConfig.CanAim("LMG") and WeaponConfig.CanAim("Rifle") and WeaponConfig.CanAim("DMR"),
	"nur das LMG kann nicht zielen")
check(WeaponConfig.SpreadFor(lmg, 0.5, 8, false, true, nil) == WeaponConfig.SpreadFor(lmg, 0.5, 8, false, false, nil),
	"LMG: \"Zielen\" gibt keine kleinere Streuung")
check(WeaponConfig.SpreadFor(WeaponConfig.Get("Rifle"), 0, 0, false, true, nil)
	< WeaponConfig.SpreadFor(WeaponConfig.Get("Rifle"), 0, 0, false, false, nil), "Sturmgewehr zielt weiter genauer")

-- Streuungs-Aufsätze am LMG: Mündungsbremse, Laser, Winkelgriff zusammen fast halbieren die Streuung
local player = Instance.new("Player")
player.Name = "Tester"
player:SetAttribute("Attachments", game:GetService("HttpService"):JSONEncode({
	Owned = { LMG = { MuzzleBrake = true, Laser = true, ShortBarrel = true } },
	Equipped = { LMG = { Muzzle = "MuzzleBrake", Grip = "Laser", Barrel = "ShortBarrel" } } }))
local effects = AttachmentConfig.Effects(player, "LMG")
local plain = WeaponConfig.SpreadFor(lmg, 0, 16, false, false, nil)
local tuned = WeaponConfig.SpreadFor(lmg, 0, 16, false, false, effects)
check(tuned < plain * 0.5, "LMG mit Streuungs-Aufsätzen viel genauer (" .. tuned .. " statt " .. plain .. ")")
check(not AttachmentConfig.Fits("LMG", "HoloSight"), "kein Visier am LMG")
for _, id in { "MuzzleBrake", "Laser", "AngledGrip", "ShortBarrel" } do
	check(AttachmentConfig.Fits("LMG", id), "LMG nimmt " .. id)
end

-- Kein Aufsatz-Satz ist für alle Waffen gleich
local seen = {}
for weaponName, ids in AttachmentConfig.ByWeapon do
	local key = table.concat(ids, ",")
	check(seen[key] == nil, weaponName .. " hat einen eigenen Aufsatz-Satz")
	seen[key] = weaponName
end

-- Seltenheit: Präzisionsgewehr ist die seltenste Waffe
local items = ExtinctionConfig.Items
for name in WeaponConfig.Weapons do
	if name ~= "DMR" and items[name] then
		check(items.DMR.Tier > items[name].Tier and items.DMR.Price > items[name].Price, "Präzisionsgewehr seltener/teurer als " .. name)
	end
end
for _, tableName in { "Tier3", "Airdrop" } do
	local weights = {}
	for _, entry in ExtinctionConfig.LootTables[tableName] do
		if items[entry.Id] and items[entry.Id].Kind == "Weapon" then
			weights[entry.Id] = entry.Weight
		end
	end
	for id, weight in weights do
		if id ~= "DMR" then
			check((weights.DMR or 0) < weight, tableName .. ": Präzisionsgewehr seltener als " .. id)
		end
	end
end
check(table.find(ExtinctionConfig.Bots.Weapons, "DMR") == nil, "Bots lassen kein Präzisionsgewehr fallen")

if failures == 0 then
	print("Waffen-Balance in Ordnung")
end
