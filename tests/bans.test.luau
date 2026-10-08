-- Sperrliste (BanService): Sperren landen im DataStore "Bans_v1" (Schlüssel "List"), gesperrte Spieler werden beim
-- Beitreten gekickt (Nachricht in ihrer Sprache), befristete Sperren laufen ab, Entsperren und Kick gehen über das
-- Admin-Panel (Remotes.AdminAction: Kick, Ban, Unban, BanList -> Remotes.AdminData "Bans"); nur Admins dürfen.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local store = SIM.DataStore("Bans_v1")
local BanService = require("BanService")
BanService.Init()
check(BanService._Loaded(), "Liste beim Start geladen")
check(#BanService.List() == 0, "zu Beginn keine Sperren")

local admin = SIM.AddPlayer("Admin", 1)
admin:SetAttribute("IsAdmin", true)
local bob = SIM.AddPlayer("Bob", 2)
bob.LocaleId = "de-de"
local alice = SIM.AddPlayer("Alice", 3)
alice.LocaleId = "en-us"

-- Sperren: Eintrag, Kick des Online-Spielers, gespeichert
local message = BanService.Ban(admin, bob.UserId, 7, "Cheating")
check(string.find(message, "Bob") ~= nil and string.find(message, "7 Tage") ~= nil, "Rückmeldung: " .. message)
check(SIM.Kicked[bob] ~= nil, "gesperrter Spieler wird gekickt")
check(SIM.Kicked[bob] and string.find(SIM.Kicked[bob], "gesperrt") ~= nil and string.find(SIM.Kicked[bob], "Cheating") ~= nil,
	"Kick-Nachricht auf Deutsch mit Grund: " .. tostring(SIM.Kicked[bob]))
local saved = store:GetAsync("List")
check(type(saved) == "table" and type(saved["2"]) == "table" and saved["2"].Reason == "Cheating", "im DataStore gespeichert")
check(BanService.IsBanned(2) and not BanService.IsBanned(3), "IsBanned")
local list = BanService.List()
check(#list == 1 and list[1].UserId == 2 and list[1].Name == "Bob" and list[1].By == "Admin", "Liste mit Eintrag")

-- Beitreten als Gesperrter: sofort raus, Nachricht auf Englisch (Standard)
SIM.Leave(bob)
SIM.Kicked[bob] = nil
local bob2 = SIM.AddPlayer("Bob", 2)
bob2.LocaleId = "fr-fr"
SIM.Advance(0.1)
check(SIM.Kicked[bob2] ~= nil, "gesperrter Spieler kommt nicht rein")
check(SIM.Kicked[bob2] and string.find(SIM.Kicked[bob2], "banned") ~= nil, "Kick-Nachricht auf Englisch: " .. tostring(SIM.Kicked[bob2]))

-- Selbst sperren geht nicht, ungültige Id auch nicht
check(string.find(BanService.Ban(admin, admin.UserId, 0, "x"), "selbst") ~= nil, "nicht selbst sperren")
check(string.find(BanService.Ban(admin, "abc", 0, "x"), "UserId") ~= nil, "ungültige Id")

-- Entsperren
message = BanService.Unban(admin, 2)
check(string.find(message, "entsperrt") ~= nil, "entsperrt: " .. message)
check(not BanService.IsBanned(2) and #BanService.List() == 0, "nach Unban frei")
check(store:GetAsync("List")["2"] == nil, "Unban gespeichert")
check(string.find(BanService.Unban(admin, 2), "Keine Sperre") ~= nil, "zweites Unban: Hinweis")

-- Befristete Sperre läuft ab
BanService.Ban(admin, 44, 1, "")
check(BanService.IsBanned(44), "befristet gesperrt")
local entry = BanService.Get(44)
check(entry and entry.Reason == "Regelverstoß", "leerer Grund -> Standardgrund")
entry.Until = os.time() - 1
check(not BanService.IsBanned(44) and #BanService.List() == 0, "abgelaufene Sperre zählt nicht mehr")

-- Dauerhaft (0 Tage)
BanService.Ban(admin, 45, 0, "Exploits")
check(BanService.Get(45).Until == 0 and BanService.List()[1].Left == "dauerhaft", "dauerhaft")

-- Anderer Server meldet eine Sperre (MessagingService): Online-Spieler fliegt
local MessagingService = game:GetService("MessagingService")
local subscribed = nil
rawget(MessagingService, "__methods").SubscribeAsync = function(_, _, callback)
	subscribed = callback
	return { Disconnect = function() end }
end
BanService._Reset()
BanService.Init()
check(subscribed ~= nil, "Topic abonniert")
if subscribed then
	subscribed({ Data = { Action = "Ban", UserId = "3", Entry = { Name = "Alice", Reason = "Spam", Until = 0, By = "Admin", At = os.time() } } })
	check(SIM.Kicked[alice] ~= nil, "Sperre von anderem Server kickt sofort")
	check(BanService.IsBanned(3), "Sperre übernommen")
	subscribed({ Data = { Action = "Unban", UserId = "3" } })
	check(not BanService.IsBanned(3), "Unban übernommen")
end

-- Kick
local carl = SIM.AddPlayer("Carl", 5)
message = BanService.Kick(admin, 5, "Bitte freundlich bleiben")
check(SIM.Kicked[carl] ~= nil and string.find(SIM.Kicked[carl], "Bitte freundlich bleiben", 1, true) ~= nil, "Kick mit Grund: " .. tostring(SIM.Kicked[carl]))
check(string.find(message, "rausgeworfen") ~= nil, "Kick-Rückmeldung")
check(string.find(BanService.Kick(admin, 999), "nicht auf diesem Server") ~= nil, "Kick: Spieler fehlt")

-- Admin-Panel: Aktionen über Remotes, Daten zurück
local Remotes = require("Remotes")
local AdminService = require("AdminService")
local ProgressService = require("ProgressService")
ProgressService.Init()
AdminService.Init({ GetModule = function() return nil end })
-- Rückmeldungen landen im RemoteLog (FireClient)
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
	return entry and entry.Args[1] or nil
end
local function data()
	local entry = lastRemote("AdminData")
	return entry and { entry.Args[1], entry.Args[2] } or nil
end
local dave = SIM.AddPlayer("Dave", 6)
admin:SetAttribute("IsAdmin", true)
Remotes.AdminAction.OnServerEvent:Fire(admin, "Ban", dave.UserId, { Days = 1, Reason = "Test" })
SIM.Advance(0.1)
check(status() ~= nil and string.find(status(), "Dave") ~= nil, "Panel: Ban-Rückmeldung: " .. tostring(status()))
check(data() ~= nil and data()[1] == "Bans" and #data()[2] >= 1, "Panel: Sperrliste geschickt")
check(SIM.Kicked[dave] ~= nil, "Panel: Dave gekickt")
Remotes.AdminAction.OnServerEvent:Fire(admin, "Unban", dave.UserId)
SIM.Advance(0.1)
check(not BanService.IsBanned(6), "Panel: Unban")
Remotes.AdminAction.OnServerEvent:Fire(admin, "BanList")
SIM.Advance(0.1)
check(status() ~= nil and string.find(status(), "Sperren") ~= nil, "Panel: BanList-Rückmeldung")
-- kein Admin: nichts passiert
local eve = SIM.AddPlayer("Eve", 7)
eve:SetAttribute("IsAdmin", false)
Remotes.AdminAction.OnServerEvent:Fire(eve, "Ban", admin.UserId, { Days = 0, Reason = "x" })
SIM.Advance(0.1)
check(not BanService.IsBanned(admin.UserId), "Nicht-Admin kann nicht sperren")

if failures == 0 then
	print("ok bans")
end
