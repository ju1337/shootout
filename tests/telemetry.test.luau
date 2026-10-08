-- Spielanalyse (Telemetry): Münzen-Quellen und -Senken aus ProgressService (AddCoins/SpendCoins mit Grund und Item,
-- RAP), Onboarding-Schritte zählen je Spieler nur einmal und merken sich den Stand im Profil, Zähler werden gesammelt
-- und beim Verlassen gesendet. Ohne AnalyticsService (Tests, Studio) passiert nichts Schlimmes.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local Telemetry = require("Telemetry")
Telemetry.KeepSent = true
Telemetry.Init()
local ProgressService = require("ProgressService")
ProgressService.Init()

local function sent(kind)
	local result = {}
	for _, entry in Telemetry.Sent do
		if entry.Kind == kind then
			table.insert(result, entry)
		end
	end
	return result
end

local bob = SIM.AddPlayer("Bob", 1001)
SIM.Advance(0.5)
check(ProgressService.IsLoaded(bob), "Profil geladen")
local onboarding = sent("Onboarding")
check(#onboarding == 1 and onboarding[1][1] == 1 and onboarding[1][2] == "Joined", "Onboarding-Schritt 1 nach dem Laden")

-- Münzen: Quelle mit Grund, Senke mit Grund und Item
ProgressService.AddCoins(bob, 100, "Zombie")
local economy = sent("Economy")
check(#economy == 1 and economy[1][1] == "Source" and economy[1][2] == "Coins" and economy[1][3] == 100
	and economy[1][4] == ProgressService.Get(bob).Coins and economy[1][5] == "Gameplay" and economy[1][7] == "Zombie",
	"AddCoins -> Source Gameplay")
check(ProgressService.SpendCoins(bob, 30, "Stand", "Medkit"), "SpendCoins")
economy = sent("Economy")
check(#economy == 2 and economy[2][1] == "Sink" and economy[2][3] == 30 and economy[2][5] == "Shop"
	and economy[2][6] == "Medkit" and economy[2][7] == "Stand", "SpendCoins -> Sink Shop mit Item")
check(not ProgressService.SpendCoins(bob, 10000, "Stand", "Heli"), "zu teuer")
check(#sent("Economy") == 2, "fehlgeschlagener Kauf zählt nicht")
ProgressService.AddCoins(bob, 50, "Robux")
economy = sent("Economy")
check(economy[3][5] == "IAP", "Robux -> IAP")
ProgressService.AddRap(bob, 500)
ProgressService.SpendRap(bob, 200)
economy = sent("Economy")
check(#economy == 5 and economy[4][2] == "RAP" and economy[4][1] == "Source" and economy[5][1] == "Sink" and economy[5][3] == 200,
	"RAP-Fluss")

-- Onboarding: nur vorwärts, jeder Schritt einmal, Stand im Profil
Telemetry.Onboarding(bob, 2, "EnteredExtinction")
Telemetry.Onboarding(bob, 2, "EnteredExtinction")
Telemetry.Onboarding(bob, 1, "Joined")
Telemetry.Onboarding(bob, 4, "Tutorial:Equip")
Telemetry.Onboarding(bob, 3, "Tutorial:Kit")
onboarding = sent("Onboarding")
check(#onboarding == 3 and onboarding[2][1] == 2 and onboarding[3][1] == 4, "Schritte nur einmal und nur vorwärts (" .. #onboarding .. ")")
check(ProgressService.Get(bob).OnboardingStep == 4, "höchster Schritt im Profil")

-- Zähler: gesammelt, beim Verlassen als ein Ereignis
Telemetry.Count(bob, "ZombieKills", 1)
Telemetry.Count(bob, "ZombieKills", 1)
Telemetry.Count(bob, "ZombieKills", 3)
check(#sent("Event") == 0, "Zähler sendet nicht sofort")
Telemetry.Flush(bob)
local events = sent("Event")
check(#events == 1 and events[1][1] == "ZombieKills" and events[1][2] == 5, "Zähler als Summe")
Telemetry.Count(bob, "ZombieKills", 2)
SIM.Leave(bob)
events = sent("Event")
check(#events == 2 and events[2][2] == 2, "beim Verlassen gesendet")

-- Ereignis mit Feldern, Fortschritt
local alice = SIM.AddPlayer("Alice", 1002)
Telemetry.Event(alice, "ModeJoin", 1, "Extinction")
Telemetry.Progression(alice, "Agent", "Complete", 5, "Scout")
check(sent("Event")[3][3] == "Extinction", "Event mit Feld")
check(#sent("Progression") == 1 and sent("Progression")[1][3] == 5, "Progression")

-- Abgeschaltet (Studio): keine Aufrufe am Dienst, aber auch kein Fehler
Telemetry.Enabled = false
Telemetry.Event(alice, "Death", 1, "Extinction", "Zombie")
check(#sent("Event") == 4, "auch abgeschaltet werden Aufrufe gemerkt (Tests)")

if failures == 0 then
	print("ok telemetry")
end
