-- Admin-Panel (AdminService): Werte der Spieler ändern, Items/Skins geben, Teleport, Einfrieren, Gottmodus, Verstecken
-- vor den Bestenlisten, Daten zurücksetzen nur mit Bestätigung, Suche, Admin-Log, ALLE SERVER (MessagingService),
-- Rangprüfung (Moderatoren dürfen nur Moderation, Admins nichts gegen höhere Ränge).
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local LeaderboardService = require("LeaderboardService")
local AdminService = require("AdminService")
ProgressService.Init()
AdminService.Init({ GetModule = function() return nil end, Join = function() end })

local function lastRemote(name)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == name then
			return entry
		end
	end
	return nil
end
local function status()
	local entry = lastRemote("AdminStatus")
	return entry and tostring(entry.Args[1]) or ""
end
local function act(who, action, a, b)
	Remotes.AdminAction.OnServerEvent:Fire(who, action, a, b)
	SIM.Advance(0.1)
	return status()
end

local admin = SIM.AddPlayer("Admin", 1)
local bob = SIM.AddPlayer("Bob", 2)
SIM.Advance(1)
admin:SetAttribute("IsAdmin", true)
admin:SetAttribute("StaffRank", "Developer")
check(ProgressService.Get(bob) ~= nil, "Bob hat ein Profil")

-- Werte: Münzen +, setzen, Level, RZ
act(admin, "PlayerValue", bob.UserId, { Key = "Coins", Op = "Add", Amount = 500 })
check(ProgressService.Get(bob).Coins == 500 and bob:GetAttribute("Coins") == 500, "+500 Münzen: " .. status())
act(admin, "PlayerValue", bob.UserId, { Key = "Coins", Op = "Set", Amount = 42 })
check(ProgressService.Get(bob).Coins == 42, "Münzen auf 42 gesetzt")
act(admin, "PlayerValue", bob.UserId, { Key = "Coins", Op = "Add", Amount = -100 })
check(ProgressService.Get(bob).Coins == 0, "Münzen nie unter 0")
act(admin, "PlayerValue", bob.UserId, { Key = "Level", Op = "Set", Amount = 25 })
check(require("LevelConfig").Get(bob).Level == 25, "Level 25 gesetzt: " .. status())
act(admin, "PlayerValue", bob.UserId, { Key = "RedPoints", Op = "Add", Amount = 70 })
check(bob:GetAttribute("RedPoints") == 70, "+70 RZ")
act(admin, "PlayerValue", bob.UserId, { Key = "Elo", Op = "Set", Amount = 1 })
check(status() == "Ungültiger Wert.", "unbekannter Wert abgelehnt")

-- Skin und Item der offenen Welt
local Cosmetics = require("Cosmetics")
local skin = Cosmetics.Items[1]
act(admin, "GiveSkin", bob.UserId, skin.Id)
check((ProgressService.Get(bob).Owned[skin.Id] or 0) >= 1, "Skin gegeben: " .. status())
act(admin, "GiveItem", bob.UserId, { Id = "Medkit", Count = 2 })
check(string.find(status(), "Medikit") ~= nil, "Item gegeben: " .. status())
act(admin, "GiveItem", bob.UserId, { Id = "GibtEsNicht", Count = 2 })
check(status() == "Unbekanntes Item.", "unbekanntes Item abgelehnt")

-- Gottmodus, Einfrieren (mit Charakter)
local rig = SIM.MakeRig("Bob")
rig.Parent = workspace
bob.Character = rig
act(admin, "God", bob.UserId)
check(bob:GetAttribute("AdminGod") == true, "Gottmodus an")
local Damage = require("Damage")
local dealt = Damage.Apply(rig, rig:FindFirstChildOfClass("Humanoid"), 50, {})
check(dealt == 0, "Gottmodus: kein Schaden")
act(admin, "God", bob.UserId)
check(bob:GetAttribute("AdminGod") == nil, "Gottmodus aus")
act(admin, "Freeze", bob.UserId)
check(bob:GetAttribute("AdminFrozen") == true and rig.HumanoidRootPart.Anchored == true, "eingefroren")
act(admin, "Freeze", bob.UserId)
check(rig.HumanoidRootPart.Anchored == false, "aufgetaut")

-- Herholen: Bob landet beim Admin
local adminRig = SIM.MakeRig("Admin")
adminRig.Parent = workspace
adminRig:PivotTo(CFrame.new(100, 3, 100))
admin.Character = adminRig
act(admin, "Bring", bob.UserId)
check((rig.HumanoidRootPart.Position - Vector3.new(100, 3, 100)).Magnitude < 10, "Bob geholt: " .. status())

-- Bestenliste verstecken
act(admin, "HideLeaderboard", bob.UserId)
check(LeaderboardService.IsHidden(bob) and ProgressService.Get(bob).HideBoards == true, "versteckt")
act(admin, "HideLeaderboard", bob.UserId)
check(not LeaderboardService.IsHidden(bob), "wieder sichtbar")

-- Daten zurücksetzen nur mit Bestätigung
act(admin, "ResetData", bob.UserId)
check(status() == "Nicht bestätigt." and SIM.Kicked[bob] == nil, "ohne Bestätigung nichts")

-- Suche: Daten ans Panel
act(admin, "Lookup", tostring(bob.UserId))
local data = lastRemote("AdminData")
check(data and data.Args[1] == "Lookup" and data.Args[2].UserId == bob.UserId and data.Args[2].Found == true
	and data.Args[2].Level == 25, "Suche liefert Bobs Werte")

-- Admin-Log
act(admin, "Logs")
data = lastRemote("AdminData")
check(data and data.Args[1] == "Logs" and #data.Args[2] >= 5 and data.Args[2][1].Admin == "Admin", "Admin-Log mit Einträgen")

-- ALLE SERVER: hier ausgeführt und veröffentlicht
SIM.Messages = {}
act(admin, "AllServers", "SetFog", { A = 1 })
check(ReplicatedStorage:GetAttribute("FogOverride") == 1, "Nebel fest")
check(#SIM.Messages == 1 and SIM.Messages[1].Topic == AdminService.Topic and SIM.Messages[1].Message.Action == "SetFog",
	"an alle Server geschickt")
check(require("DayCycle").Fog(workspace:GetServerTimeNow()) == 1, "DayCycle nimmt den festen Nebel")
act(admin, "AllServers", "SetFog", { A = "auto" })
check(ReplicatedStorage:GetAttribute("FogOverride") == nil, "Nebel wieder automatisch")
act(admin, "AllServers", "PlayerValue", { A = bob.UserId, B = { Key = "Coins", Op = "Add", Amount = 5 } })
check(#SIM.Messages == 2, "Spieler-Aktionen gehen nicht an alle Server")

-- Rang: Developer darf nichts gegen den Owner
bob:SetAttribute("StaffRank", "Owner")
act(admin, "PlayerValue", bob.UserId, { Key = "Coins", Op = "Set", Amount = 999 })
check(ProgressService.Get(bob).Coins ~= 999 and string.find(status(), "Rang") ~= nil, "nicht gegen höheren Rang")
act(admin, "PlayerValue", admin.UserId, { Key = "Coins", Op = "Set", Amount = 999 })
check(ProgressService.Get(admin).Coins == 999, "gegen sich selbst geht es")
bob:SetAttribute("StaffRank", nil)

-- Moderator: nur Moderation und Suche
local mod = SIM.AddPlayer("Mod", 3)
SIM.Advance(1)
mod:SetAttribute("StaffRank", "Mod")
mod:SetAttribute("IsMod", true)
local before = ProgressService.Get(bob).Coins
act(mod, "PlayerValue", bob.UserId, { Key = "Coins", Op = "Set", Amount = 123 })
check(ProgressService.Get(bob).Coins == before, "Moderator darf keine Werte ändern")
act(mod, "Lookup", tostring(bob.UserId))
data = lastRemote("AdminData")
check(data and data.Player == mod and data.Args[1] == "Lookup", "Moderator darf suchen")

-- Zurücksetzen mit Bestätigung: Profil leer, Spieler gekickt
act(admin, "ResetData", bob.UserId, "CONFIRM")
check(SIM.Kicked[bob] ~= nil, "nach dem Zurücksetzen gekickt")

if failures == 0 then
	print("ok adminpanel")
end
