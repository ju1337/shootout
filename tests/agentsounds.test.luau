-- Geräusche für Agenten-Fähigkeiten (jede Art hat einen Eintrag in SoundLibrary, dazu Ultimate und "bereit") und für
-- Aufsätze (Trommelmagazin ersetzt das Nachladen, Anlegen/Anbauen haben Klänge, Mündungsbremse und Kompensator lauter)
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local AgentConfig = require("AgentConfig")
local SoundLibrary = require("SoundLibrary")
local WeaponConfig = require("WeaponConfig")
local AttachmentConfig = require("AttachmentConfig")

local function valid(name)
	local def = SoundLibrary.Get(name)
	if not def or #def.Clips == 0 then
		return false
	end
	for _, clip in def.Clips do
		if type(clip.Id) ~= "string" or not (clip.Id:match("^rbxassetid://%d+$") or clip.Id:match("^rbxasset://sounds/.+")) then
			return false
		end
	end
	return true
end

for _, agent in AgentConfig.Agents do
	check(valid("Ability" .. agent.Ability.Type), agent.Id .. ": Geräusch für " .. agent.Ability.Type)
	check((SoundLibrary.Get("Ability" .. agent.Ability.Type) or {}).Range ~= 0, agent.Id .. ": im Raum zu hören")
end
check(valid("AbilityUltimate") and valid("AbilityReady"), "Ultimate und bereit")
check(SoundLibrary.Get("AbilityReady").Range == 0, "bereit nur für einen selbst (2D)")
check(SoundLibrary.Get("AbilityCloak").Range < SoundLibrary.Get("AbilityDash").Range, "Tarnung leiser als Sprint-Stoß")

for id, swap in WeaponConfig.ActionSoundsByAttachment do
	check(AttachmentConfig.Get(id) ~= nil, "Aufsatz gibt es: " .. id)
	for from, to in swap do
		check(WeaponConfig.ActionSounds[from] ~= nil and WeaponConfig.ActionSounds[to] ~= nil, id .. ": " .. from .. " -> " .. to)
	end
end
check(WeaponConfig.ActionSounds.AimIn ~= nil and WeaponConfig.ActionSounds.AttachClick ~= nil, "Anlegen und Anbauen")

-- Lautstärke über die Aufsätze
local player = SIM.AddPlayer("Schütze")
local HttpService = game:GetService("HttpService")
local function equip(list)
	local owned, equipped = {}, {}
	for _, id in list do
		local item = AttachmentConfig.Get(id)
		owned[id] = true
		equipped[item.Slot] = id
	end
	player:SetAttribute("Attachments", HttpService:JSONEncode({ Owned = { Rifle = owned }, Equipped = { Rifle = equipped } }))
end
check(AttachmentConfig.Effects(player, "Rifle").Loud == 1, "ohne Aufsatz normal laut")
equip({ "MuzzleBrake" })
local loud = AttachmentConfig.Effects(player, "Rifle").Loud
check(math.abs(loud - 1.15) < 1e-9, "Mündungsbremse lauter: " .. tostring(loud))

if failures > 0 then
	error(failures .. " Fehler")
end
print("agentsounds: alles ok")
