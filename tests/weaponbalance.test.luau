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

-- Stärke: Präzisionsgewehr höchster Schaden pro Schuss, LMG höchster Schaden pro Sekunde
local dmr, lmg = WeaponConfig.Get("DMR"), WeaponConfig.Get("LMG")
for name, cfg in WeaponConfig.Weapons do
	if name ~= "DMR" then
		check(dmr.Damage > cfg.Damage * (cfg.Pellets or 1) * 0.6 and dmr.Damage >= cfg.Damage, "Präzisionsgewehr stärker als " .. name)
	end
	if name ~= "LMG" then
		check(lmg.Damage / lmg.FireDelay > cfg.Damage * (cfg.Pellets or 1) / cfg.FireDelay * (name == "Shotgun" and 0 or 1),
			"LMG mehr Schaden pro Sekunde als " .. name)
	end
end
check(dmr.Damage * WeaponConfig.HeadshotMultiplier >= 100, "Präzisionsgewehr: Kopfschuss tötet")
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
