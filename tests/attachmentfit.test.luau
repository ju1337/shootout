-- Aufsätze passen nur auf passende Waffen (AttachmentConfig.ByWeapon): Liste, Lobby-Kauf/-Ausrüsten, Wirkung, alte
-- Spielstände (unpassende werden abgelegt und erstattet)
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Run(SIM.Now + seconds)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local HttpService = game:GetService("HttpService")
local AttachmentConfig = require("AttachmentConfig")
local WeaponConfig = require("WeaponConfig")
local ProgressService = require("ProgressService")
ProgressService.Init()

-- Liste: jede Waffe hat Aufsätze, alle Einträge gibt es, jeder Aufsatz passt irgendwo
for weaponName, ids in AttachmentConfig.ByWeapon do
	check(WeaponConfig.Get(weaponName) ~= nil, "Waffe " .. weaponName .. " gibt es")
	for _, id in ids do
		check(AttachmentConfig.Get(id) ~= nil, "Aufsatz " .. id .. " (" .. weaponName .. ") gibt es")
	end
end
for weaponName in WeaponConfig.Weapons do
	check(#AttachmentConfig.SlotsFor(weaponName) > 0, weaponName .. " hat Aufsatz-Plätze")
end
for _, item in AttachmentConfig.List do
	check(#AttachmentConfig.WeaponsFor(item.Id) > 0, item.Id .. " passt auf mindestens eine Waffe")
end

-- realistische Zuordnung
check(not AttachmentConfig.Fits("Revolver", "VerticalGrip") and not AttachmentConfig.Fits("Revolver", "AngledGrip"),
	"kein Griff am Revolver")
check(not AttachmentConfig.Fits("Pistol", "VerticalGrip"), "kein Griff an der Pistole")
check(not AttachmentConfig.Fits("Pistol", "HoloSight") and not AttachmentConfig.Fits("Revolver", "HoloSight"),
	"kein Visier an Kurzwaffen")
check(not AttachmentConfig.Fits("Revolver", "Suppressor"), "kein Schalldämpfer am Revolver")
check(AttachmentConfig.Fits("Rifle", "VerticalGrip") and AttachmentConfig.Fits("Rifle", "HoloSight"), "Sturmgewehr nimmt alles")
check(AttachmentConfig.Fits("DMR", "HoloSight"), "Visier auf dem Präzisionsgewehr")
check(not AttachmentConfig.Fits("Knife", "Laser"), "unbekannte Waffe nimmt nichts")
local revolverSlots = {}
for _, slot in AttachmentConfig.SlotsFor("Revolver") do
	revolverSlots[slot.Id] = true
end
check(not revolverSlots.Optic and revolverSlots.Barrel, "Revolver: kein Visier-Platz, aber Lauf")
for _, item in AttachmentConfig.ForSlot("Grip", "Revolver") do
	check(item.Id == "Laser", "Revolver: am Griff-Platz nur der Laser")
end

-- alter Spielstand: Griff am Revolver gekauft und ausgerüstet, Laser auch
store.Data.u1 = { XP = {}, Coins = 100, Owned = {}, Equipped = {}, Attachments = {
	Owned = { Revolver = { VerticalGrip = true, Laser = true }, Rifle = { VerticalGrip = true } },
	Equipped = { Revolver = { Grip = "VerticalGrip" }, Rifle = { Grip = "VerticalGrip" } } } }
local alice = SIM.Join("Alice")
step(5)
local profile = ProgressService.Get(alice)
local price = AttachmentConfig.Get("VerticalGrip").Price
check(profile.Coins == 100 + price, "unpassender Griff erstattet (" .. tostring(profile.Coins) .. ")")
check(profile.Attachments.Owned.Revolver.VerticalGrip == nil and profile.Attachments.Owned.Revolver.Laser == true,
	"Griff weg, Laser bleibt")
check(profile.Attachments.Equipped.Revolver.Grip == nil, "Griff am Revolver abgelegt")
check(profile.Attachments.Equipped.Rifle.Grip == "VerticalGrip", "Griff am Sturmgewehr bleibt")
check(AttachmentConfig.Effects(alice, "Rifle").Recoil < 1, "Griff wirkt am Sturmgewehr")

-- Kaufen/Ausrüsten prüft
local coins = profile.Coins
local _, ok = ProgressService.BuyAttachment(alice, "Revolver", "AngledGrip")
check(ok == false and profile.Coins == coins, "Winkelgriff für den Revolver nicht kaufbar")
_, ok = ProgressService.BuyAttachment(alice, "Revolver", "Suppressor")
check(ok == false, "Schalldämpfer für den Revolver nicht kaufbar")
profile.Attachments.Owned.Revolver.AngledGrip = true -- irgendwie doch im Besitz
_, ok = ProgressService.ToggleAttachment(alice, "Revolver", "AngledGrip")
check(ok == false and profile.Attachments.Equipped.Revolver.Grip == nil, "unpassender Aufsatz lässt sich nicht ausrüsten")
_, ok = ProgressService.ToggleAttachment(alice, "Revolver", "Laser")
check(ok == true and profile.Attachments.Equipped.Revolver.Grip == "Laser", "Laser am Revolver")

-- Wirkung: unpassende Aufsätze im Attribut zählen nicht
alice:SetAttribute("Attachments", HttpService:JSONEncode({ Owned = { Pistol = { VerticalGrip = true } },
	Equipped = { Pistol = { Grip = "VerticalGrip" } } }))
check(AttachmentConfig.Effects(alice, "Pistol").Recoil == 1, "Griff an der Pistole wirkt nicht")
check(#AttachmentConfig.EquippedList(alice, "Pistol") == 0, "Griff an der Pistole wird nicht gezeigt")

-- Erweitertes Magazin: Sturmgewehr 40 Schuss, andere Waffen weiter +30 %
local extItem = AttachmentConfig.Get("ExtendedMag")
check(extItem.WeaponEffects.Rifle.Mag == 1.34 and extItem.Effects.Mag == 1.3, "erweitertes Magazin: Werte")
check(math.floor(30 * extItem.WeaponEffects.Rifle.Mag) == 40, "Sturmgewehr: 40 Schuss")
check(AttachmentConfig.Pros(extItem, "Rifle")[1] == "40 Schuss" and AttachmentConfig.Pros(extItem, "SMG")[1] == "+30 % Magazin",
	"Texte je Waffe")
if failures == 0 then
	print("Aufsatz-Kompatibilität in Ordnung")
end
