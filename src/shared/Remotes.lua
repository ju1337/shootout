-- Remotes (ModuleScript)
-- Legt alle RemoteEvents an (Server) bzw. wartet darauf (Client).
-- Benutzung: local Remotes = require(Shared.Remotes); Remotes.Fire:FireServer(...)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Fire",       -- Client -> Server: Schuss (Kamera-Ursprung, Richtung, zielt?, Schuss-Nummer)
	"Reload",     -- Client -> Server: Nachladen
	"Equip",      -- Client -> Server: Waffe wechseln
	"AmmoUpdate", -- Server -> Client: Munition (Waffe, Magazin, Reserve, ladeNach, Größe, letzte Schuss-Nummer, unendlich?)
	"Shot",       -- Server -> alle: Schuss-Effekt (Schütze/Bot, Start, Ende, Waffe, Normale, Trefferart)
	"Hitmarker",  -- Server -> Schütze: Treffer (Kopfschuss, getötet, Schaden, Ort, Name, niedergeschlagen, Rüstung, Modell)
	"Killfeed",   -- Server -> alle im Modus: Meldung (Killer oder nil, Opfer, Waffe, Kopfschuss, Art: nil = Kill, "Down" = niedergeschlagen)
	"Announce",   -- Server -> Client(s): große Meldung in der Bildschirmmitte
	"JoinMode",   -- Client -> Server: in Modus oder Hub teleportieren (Modus-Id)
	"MenuStatus", -- Server -> Client: Statuszeile im Menü (Teleport läuft, Fehler)
	"SelectAgent", -- Client -> Server: Agent wählen (Agent-Id)
	"UseAbility", -- Client -> Server: Fähigkeit auslösen
	"Reveal",     -- Server -> Team: Gegner markieren (Charaktere, Dauer)
	"XPGain",     -- Server -> Client: XP bekommen (Menge, Grund, Agent, LevelUp)
	"AdminAction", -- Client -> Server: Admin-Befehl (Aktion, Wert1, Wert2)
	"AdminStatus", -- Server -> Admin: Rückmeldung im Admin-Panel
	"ShopAction", -- Client -> Server: Shop/Rucksack (Aktion, Wert1, Wert2)
	"ShopStatus", -- Server -> Client: Rückmeldung (Text, Erfolg)
	"Revive",     -- Client -> Server: E zum Wiederbeleben gedrückt (true) / losgelassen (false)
	"Buy",        -- Client -> Server: Kaufphase, Gegenstand kaufen (Id)
	"MoneyGain",  -- Server -> Client: Geld bekommen (Menge, Grund)
	"UseGadget",  -- Client -> Server: Gadget werfen (Blickrichtung)
	"Flash",      -- Server -> Client: geblendet (Dauer)
	"ObjectiveAction", -- Client -> Server: E für Ziel (Bombe legen/entschärfen) gedrückt/losgelassen
	"Melee",      -- Client -> Server: Messer-Angriff (Ursprung, Richtung)
	"Ping",       -- Client -> Server: Ort/Gegner markieren (Position, Modell oder nil)
	"PingShow",   -- Server -> Team: Markierung anzeigen (Position, Modell, Name des Pingenden)
	"DeathRecap", -- Server -> Opfer: wer hat dich ausgeschaltet (Name, Waffe, Leben, Agent)
	"AbilityEffect", -- Server -> Client: Fähigkeit auf dem eigenen Charakter ausführen (z.B. Dash)
	"MatchSummary", -- Server -> Client: Match-Ende (Ergebnis, MVP, eigene Statistik)
	"PartyAction", -- Client -> Server: Squad (Invite/Accept/Decline/Leave/Kick, UserId)
	"PartyInvite", -- Server -> Client: Einladung (Name, UserId des Anführers)
	"DamageFrom", -- Server -> Opfer: Treffer aus Richtung (Position des Angreifers, Schaden)
	"MapVote",    -- Client -> Server: Stimme für eine Map (Nummer 1-3)
	"AimState",   -- Client -> Server: Blick nach oben/unten (Grad) und Zielen – für die Third-Person-Pose
}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local Remotes = {}
for _, name in NAMES do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
