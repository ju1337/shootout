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
	"SkinFinisher", -- Server -> alle im Modus: Kill-Finisher eines Effekt-Skins (Opfer-Modell, CFrame, Stil, Waffe, Skin-Id)
	"Announce",   -- Server -> Client(s): einfache Textmeldung (Banner ohne Teamfarbe)
	"Notify",     -- Server -> Client: Meldung im CoD-Stil (Art, Daten): "Medal" (Liste), "Banner", "Objective", "Progress"
	"JoinMode",   -- Client -> Server: in einen Modus wechseln (Modus-Id, Modes.Home = zurück ins Camp)
	"MenuStatus", -- Server -> Client: Statuszeile im Menü (Teleport läuft, Fehler)
	"SelectAgent", -- Client -> Server: Agent wählen (Agent-Id)
	"UseAbility", -- Client -> Server: Fähigkeit auslösen
	"UseUltimate", -- Client -> Server: Ultimate auslösen (UltCharge muss 100 sein)
	"Reveal",     -- Server -> Team: Gegner markieren (Charaktere, Dauer)
	"XPGain",     -- Server -> Client: XP bekommen (Menge fürs Spielerlevel, Grund, Agent, LevelUp, Münzen, leise)
	"AdminAction", -- Client -> Server: Admin-Befehl (Aktion, Wert1, Wert2)
	"AdminStatus", -- Server -> Admin: Rückmeldung im Admin-Panel
	"AdminData",   -- Server -> Admin: Daten fürs Admin-Panel (Art, Daten): "Bans" = Sperrliste (BanService)
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
	"Reward",     -- Server -> Client: Belohnung bekommen ({ Title, Lines, Rarity, Key }) – Karte (Notifications)
	"WheelResult", -- Server -> Client: Glücksrad-Ergebnis (Feld-Nummer, Text) – Client dreht das Rad dorthin
	"SpawnChoice", -- Client -> Server: Spawn nach dem Tod (Herrschaft): "Base", "A", "B" oder "C"
	"UseKillstreak", -- Client -> Server: bereite Killstreak auslösen (Id, Zielpunkt beim Luftschlag)
	"AimState",   -- Client -> Server: Blick nach oben/unten (Grad) und Zielen – für die Third-Person-Pose
	"Inspect",    -- Client -> Server: Waffe inspizieren (true = Start, false = Ende) – für die Third-Person-Pose
	"MarketAction", -- Client -> Server: Markt-Stand (Claim, Release, List, Unlist, SetPrice, Buy; MarketService)
	"MarketStatus", -- Server -> Client: Rückmeldung zum Markt (Text, Erfolg)
	"CrateAction", -- Client -> Server: Kiste öffnen ("Open", Kisten-Id; CrateService)
	"CrateResult", -- Server -> Client: Ergebnis der Kiste (Skin, Rolle, Status) oder Fehlermeldung
	"TradeAction", -- Client -> Server: Tausch (Request, Respond, AddItem, RemoveItem, SetRap, Ready, Cancel; TradeService)
	"TradeUpdate", -- Server -> Client: Tausch-Stand (Art, Daten): "Request", "State", "Closed", "Done"
	"ExtAction",  -- Client -> Server: offene Welt (Use, Move, Buy, Sell, Drop, Loot, StoreVehicle, ...; InventoryService)
	"ExtUpdate",  -- Server -> Client: offene Welt (Art, Daten): "Status", "Loot", "LootClosed", "UseStart", "UseEnd", ...
	"StormStrike", -- Server -> alle: Blitzeinschlag der Sturmnacht (Position)
	"PlaySfx",    -- Server -> Client: Geräusch aus SoundLibrary (Name, Position oder nil = 2D, Optionen; Sfx)
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
