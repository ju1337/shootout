-- SoundLibrary (ModuleScript, Server und Client)
-- Alle Geräusche außer den Waffen (die stehen in WeaponConfig): Aufnahmen aus der Roblox-Soundbibliothek (Pro Sound
-- Effects, in jedem Spiel frei nutzbar). Je Name mehrere Aufnahmen, abgespielt wird zufällig eine (Sfx).
--   Clips   { Id, Gain, Region = { Start, Ende } } – Gain gleicht die Aufnahmen an, Region spielt nur diesen Teil
--   Range   Hörweite in Studs (0 = überall gleich laut, 2D), Pitch Grundtonhöhe, Looped Schleife
--   Voice   Filter für Stimmen (Sfx): Muffle = Höhen absenken in dB (dumpf, kehlig), Grit = Verzerrung 0..1 (rau)

local SoundLibrary = {}

local function clip(id, gain, a, b)
	return { Id = "rbxassetid://" .. id, Gain = gain, Region = b and { a, b } or nil }
end

-- Geräusch, das Roblox mitliefert (content/sounds, immer verfügbar)
local function builtin(file, gain)
	return { Id = "rbxasset://sounds/" .. file, Gain = gain }
end

-- Eigene Zombie-Aufnahmen (Platzhalter, leer = die Aufnahmen unten). Im Creator Store / in der Toolbox unter Audio nach
-- z.B. "zombie groan", "zombie moan", "zombie scream", "zombie attack" suchen, die Nummer aus der Adresse
-- (create.roblox.com/store/asset/NUMMER) hier eintragen: clip(NUMMER, Lautstärke) oder clip(NUMMER, Lautstärke, von, bis).
-- Nur Audio, das für alle Spiele freigegeben ist (sonst bleibt es im Spiel stumm). Beispiel:
--   Idle = { clip(1234567890, 1), clip(2345678901, 0.8, 0.2, 1.9) },
-- Eigene Zombie-Datei (zombie.mp3, gut 4 Minuten mit 87 Lauten): einmal für die Gruppe hochladen und die Asset-ID hier
-- eintragen. Dann spielt jede Situation nur ihre Stücke daraus (von, bis in Sekunden), leise und ohne Stimmfilter.
-- Leer = die Aufnahmen weiter unten.
local ZOMBIE_FILE: number? = nil

local function zf(gain, a, b)
	return clip(ZOMBIE_FILE or 0, gain, a, b)
end

local ZOMBIE_CLIPS: { [string]: { any } } = {
	Idle = nil, -- Stöhnen beim Herumschlurfen
	Aggro = nil, -- Schrei beim Entdecken
	Chase = nil, -- Knurren / Keuchen beim Jagen
	Attack = nil, -- Grunzen beim Zuschlagen
	Hurt = nil, -- getroffen
	Death = nil, -- Tod
	Scream = nil, -- Schreier ruft die Horde
}
if ZOMBIE_FILE then
	-- Nummern der Laute (Hörseite / zombie-sounds): Idle 1,2,3,7,24,25,50,52,55,73 · Aggro 8,30,37,47,51 · Chase 4,5,10,21,26,27,28
	-- · Attack 18,19,20,22 · Hurt 11,12,60,69 · Death 23,34,59 · Scream 35,40
	ZOMBIE_CLIPS = {
		Idle = { zf(0.35, 13.45, 15.55), zf(0.35, 16.05, 18.7), zf(0.35, 19.3, 21.5), zf(0.35, 28.7, 29.9), zf(0.35, 53.0, 54.2), zf(0.35, 54.85, 56.0), zf(0.35, 121.5, 123.7), zf(0.35, 126.0, 128.55), zf(0.35, 134.45, 137.05), zf(0.35, 187.85, 189.5) },
		Aggro = { zf(0.6, 30.1, 31.9), zf(0.6, 63.0, 65.2), zf(0.6, 79.75, 81.35), zf(0.6, 114.25, 116.85), zf(0.6, 124.1, 125.6) },
		Chase = { zf(0.45, 22.1, 23.1), zf(0.45, 23.4, 24.8), zf(0.45, 32.75, 33.8), zf(0.45, 48.8, 49.85), zf(0.45, 56.35, 57.4), zf(0.45, 57.95, 58.9), zf(0.45, 59.15, 60.25) },
		Attack = { zf(0.5, 46.35, 46.85), zf(0.5, 47.0, 47.55), zf(0.5, 47.75, 48.35), zf(0.5, 50.1, 50.75) },
		Hurt = { zf(0.45, 34.2, 35.2), zf(0.45, 35.55, 36.8), zf(0.45, 146.6, 147.65), zf(0.45, 181.35, 182.15) },
		Death = { zf(0.5, 51.0, 52.75), zf(0.5, 70.65, 73.75), zf(0.5, 143.0, 146.4) },
		Scream = { zf(0.8, 74.9, 76.35), zf(0.8, 87.6, 90.4) },
	}
end

-- dumpf und kehlig wie in Unturned
local ZOMBIE_VOICE = { Muffle = -9, Grit = 0.3 }

SoundLibrary.Sounds = {
	-- Zombies klingen wie in Unturned: tief, kehlig, menschlich statt Tiergebrüll. Darum alles tiefer gestimmt, die Höhen
	-- abgesenkt (Muffle) und etwas angeraut (Grit); jeder Zombie bekommt dazu eine eigene Stimmlage (ZombieService).
	-- Zombie schlurft herum: leises Stöhnen, nur in der Nähe zu hören
	-- Ruhig gehalten (nicht übertrieben): menschliche Laute – Röcheln, schweres Atmen, Würgen, kurzes Grunzen – tiefer
	-- gestimmt und gedämpft, statt Tiergebrüll. Lautstärken angeglichen (Spitze etwa 0,11 im Leerlauf, 0,2 beim Entdecken).
	ZombieIdle = { Range = 50, Pitch = 0.8, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Idle or {
		clip(9114556822, 0.6, 0.6, 1.9), -- Röcheln (schwer atmen, ersticken)
		clip(9114555705, 0.9, 0, 2.0),
		clip(9114556462, 1.0, 0, 0.7),
		clip(9114554782, 4.4, 0.3, 2.0), -- tiefes Ein- und Ausatmen
		clip(9120659004, 5.0, 0.2, 2.2), -- pfeifendes Atmen
		clip(9113972834, 0.9, 0.1, 1.7), -- leises, kehliges Brummen
	} },
	-- Zombie bemerkt einen Spieler: kehliges Aufstöhnen (deutlich, aber kein Gebrüll)
	ZombieAggro = { Range = 95, Pitch = 0.82, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Aggro or {
		clip(9125467848, 2.6, 0, 1.4),
		clip(9116457545, 1.0, 1.2, 1.8),
		clip(9114558505, 0.55, 0, 0.5),
	} },
	-- Zombie jagt: kurzes Grunzen und Keuchen
	ZombieChase = { Range = 60, Pitch = 0.82, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Chase or {
		clip(9116457545, 0.65, 0.3, 0.65),
		clip(9116457545, 0.65, 1.2, 1.75),
		clip(9116457545, 0.65, 2.55, 3.0),
		clip(9114558305, 0.47, 0, 0.5),
	} },
	-- Zombie schlägt zu: kurzes Grunzen
	ZombieAttack = { Range = 50, Pitch = 0.8, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Attack or {
		clip(9116451739, 1.1, 0, 0.4),
		clip(9116451917, 1.4, 0, 0.35),
		clip(9114558319, 0.45, 0, 0.4),
	} },
	-- Zombie getroffen: kurzes Keuchen
	ZombieHurt = { Range = 50, Pitch = 0.85, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Hurt or {
		clip(9114029889, 0.8, 0, 0.4),
		clip(9114558305, 0.55, 0, 0.45),
	} },
	-- Zombie stirbt: letztes Röcheln, kein Schrei
	ZombieDeath = { Range = 60, Pitch = 0.75, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Death or {
		clip(9114029889, 0.8, 0, 1.2),
		clip(9120005520, 0.7, 0.9, 1.6),
		clip(9114556822, 0.8, 0.6, 1.9),
	} },
	-- Schreier ruft die anderen (soll auffallen, aber nicht ohrenbetäubend)
	ZombieScream = { Range = 140, Pitch = 0.95, Voice = { Muffle = -4, Grit = 0.2 }, Clips = ZOMBIE_CLIPS.Scream or {
		clip(9113985445, 2.0, 0.27, 2.67),
	} },
	-- Brocken brüllt (bemerkt / greift an)
	BruteRoar = { Range = 140, Pitch = 0.8, Clips = { clip(9113987603, 1.71, 0.56, 3.56), clip(9113980319, 3.85, 0, 2.5) } },
	-- Boss erscheint / brüllt
	BossRoar = { Range = 260, Pitch = 0.9, Clips = { clip(9114828918, 0.95, 0.41, 5.41) } },
	-- Funkspruch (Ansage Lootdrop, Kopfgeld)
	RadioCall = { Range = 0, Pitch = 1, Clips = { clip(9117795848, 4.11, 0, 1.51), clip(9116218738, 6.0, 0.18, 1.43) } },
	-- Fallschirm flattert (Lootdrop im Fall)
	ParachuteLoop = { Range = 120, Pitch = 1, Looped = true, Clips = { clip(9113716666, 6.0, 0.53, 16.27) } },
	-- schwere Kiste schlägt auf
	CrateLand = { Range = 220, Pitch = 0.8, Clips = { clip(9116361742, 3.38, 0, 1.2) } },
	-- Signalfackel knistert leise (Lootdrop, Horden-Kiste); früher Feuerwerks-Zischen, das passte nicht
	FlareLoop = { Range = 60, Pitch = 1, Looped = true, Clips = { clip(9112780193, 5.0) } },
	-- Kiste öffnen: schwerer Verschluss
	CrateOpen = { Range = 60, Pitch = 1, Clips = { clip(9116545245, 2.39, 1.0, 3.5) } },
	-- Lkw-Motor (Konvoi)
	TruckLoop = { Range = 260, Pitch = 1, Looped = true, Clips = { clip(9112736299, 1.6) } },
	-- Lkw-Hupe (Konvoi fährt los)
	TruckHorn = { Range = 500, Pitch = 1, Clips = { clip(9114075665, 2.29, 0.52, 2.74) } },
	-- Druckluftbremse (Konvoi hält)
	AirBrakes = { Range = 200, Pitch = 1, Clips = { clip(9113052962, 2.1, 0.11, 2.69) } },
	-- Rotor (abstürzender Heli, Heli-Fahrzeug)
	HeliLoop = { Range = 500, Pitch = 1, Looped = true, Clips = { clip(9113417360, 6.0, 1.73, 45.57) } },
	-- Warnton im Cockpit (abstürzender Heli)
	HeliAlarm = { Range = 160, Pitch = 1, Looped = true, Clips = { clip(9119661709, 6.0) } },
	-- Heli schlägt auf: Metall
	HeliImpact = { Range = 500, Pitch = 0.9, Clips = { clip(9114795278, 1.03, 0, 1.5), clip(9114795267, 0.74, 0.08, 2.6) } },
	-- große Explosion (Heli-Absturz)
	BigExplosion = { Range = 900, Pitch = 1, Clips = { clip(9117876319, 1.09, 0.1, 5.13), clip(9114224721, 1.22, 0, 6.11) } },
	-- großes Feuer (Wrack)
	FireLoopBig = { Range = 110, Pitch = 1, Looped = true, Clips = { clip(9112906396, 6.0) } },
	-- kleines Feuer (Molotow)
	FireLoopSmall = { Range = 60, Pitch = 1, Looped = true, Clips = { clip(9112780438, 6.0) } },
	-- Sirene (Horden-Belagerung startet)
	Siren = { Range = 500, Pitch = 1, Clips = { clip(9119163479, 2.57, 0.26, 6.26) } },
	-- dumpfer Schlag (neue Welle)
	WaveSting = { Range = 300, Pitch = 1, Clips = { clip(9125404320, 1.4, 0, 2.96) } },
	-- Kirchenglocke (Blutmond beginnt)
	ChurchBell = { Range = 0, Pitch = 0.9, Clips = { clip(9113804573, 2.19, 0.56, 9.56) } },
	-- Heulen (Blutmond beginnt)
	Howl = { Range = 0, Pitch = 0.85, Clips = { clip(9113956516, 6.0, 0.1, 9.69) } },
	-- ---------- Welt-Ambiente (Ambience, nur Client, 2D-Schleifen mit weichem Überblenden) ----------------------------
	-- Wind draußen (Tag leise, Nacht etwas lauter)
	AmbientWindDay = { Range = 0, Pitch = 1, Looped = true, Clips = { clip(9114057128, 1.0) } },
	-- Vögel am Tag (Schicht über dem Wind)
	AmbientBirds = { Range = 0, Pitch = 1, Looped = true, Clips = { clip(9112776548, 1.0) } }, -- TODO Julio: Sound-ID prüfen/ersetzen
	-- Nacht draußen: Grillen und Eule
	AmbientNight = { Range = 0, Pitch = 1, Looped = true, Clips = { clip(9112773545, 1.0) } }, -- TODO Julio: Sound-ID prüfen/ersetzen
	-- Camp (Safe Zone): knisterndes Feuer
	AmbientCamp = { Range = 0, Pitch = 0.95, Looped = true, Clips = { clip(9112906396, 1.0) } },
	-- rote Zone: tiefes, bedrohliches Dröhnen (Wind ganz tief gestimmt)
	AmbientRedzone = { Range = 0, Pitch = 0.4, Looped = true, Clips = { clip(9114057128, 1.4) } },
	-- Blutmond: noch dunkleres Dröhnen
	AmbientBloodMoon = { Range = 0, Pitch = 0.3, Looped = true, Clips = { clip(9114057128, 1.8) } },
	-- Blutmond beginnt: dumpfer Schlag (Glocke und Heulen kommen vom BloodMoonService)
	BloodMoonStinger = { Range = 0, Pitch = 0.7, Clips = { clip(9125404320, 1.6, 0, 2.96) } },
	-- Sirene (rote Zone zieht weiter)
	PoliceSiren = { Range = 0, Pitch = 1, Clips = { clip(9117810961, 1.43, 0, 5.0) } },
	-- Ansage: Warnung
	StingWarning = { Range = 0, Pitch = 1, Clips = { clip(9125404320, 1.11, 0, 2.96) } },
	-- Ansage: gut
	StingGood = { Range = 0, Pitch = 1.1, Clips = { clip(9114133258, 0.72, 0.06, 2.56) } },
	-- Ansage: Info
	StingInfo = { Range = 0, Pitch = 1, Clips = { clip(9125531087, 0.92, 0.24, 0.65) } },
	-- Granate springt auf
	GrenadeBounce = { Range = 60, Pitch = 1, Clips = { clip(9114659519, 0.5, 0.47, 1.07) } },
	-- Granaten-Explosion
	GrenadeExplosion = { Range = 600, Pitch = 1, Clips = {
		clip(9114224431, 1.65, 0, 5.0),
		clip(9114224432, 1.84, 0, 5.0),
		clip(9114224721, 1.37, 0, 5.0),
	} },
	-- Druckwelle (Schicht über der Explosion)
	BlastLayer = { Range = 300, Pitch = 0.9, Clips = { clip(9117895638, 0.64, 0.07, 1.37) } },
	-- Molotow zerplatzt
	BottleBreak = { Range = 120, Pitch = 1, Clips = {
		clip(9113552392, 1.42, 0.29, 2.29),
		clip(9113552246, 1.07, 0.35, 2.35),
		clip(9114590269, 2.02, 0.27, 2.05),
	} },
	-- Molotow fängt Feuer
	FireIgnite = { Range = 120, Pitch = 1, Clips = { clip(9114438917, 1.11, 0.39, 3.39) } },
	-- Motor Quad
	QuadLoop = { Range = 150, Pitch = 1, Looped = true, Clips = { clip(9112786418, 6.0) } },
	-- Motor Geländewagen
	CarLoop = { Range = 180, Pitch = 1.25, Looped = true, Clips = { clip(9112736299, 1.6) } },
	-- Motor Sportwagen
	SportsLoop = { Range = 220, Pitch = 0.8, Looped = true, Clips = { clip(9112782019, 2.25) } },
	-- Verband anlegen
	Bandage = { Range = 30, Pitch = 1, Clips = { clip(9113266090, 3.76, 0, 2.0) } },
	-- Reißverschluss (Medikit, Tasche, Leiche durchsuchen)
	Zipper = { Range = 30, Pitch = 1, Clips = { clip(9113259554, 5.89, 0, 1.6), clip(9113259631, 6.0, 0, 1.6) } },
	-- Weste anlegen (Schnalle)
	Buckle = { Range = 30, Pitch = 1, Clips = { clip(9113243990, 6.0, 0, 1.5) } },
	-- Spritze (Adrenalin, Anti-Zombie)
	Spray = { Range = 30, Pitch = 1.3, Clips = { clip(9113046623, 3.79, 0, 1.0) } },
	-- Item aufnehmen
	Pickup = { Range = 30, Pitch = 1, Clips = { clip(9113818339, 1.75, 0.01, 0.53), clip(9113819190, 0.53, 0.02, 0.63) } },
	-- Kaufen (Kasse)
	Register = { Range = 0, Pitch = 1, Clips = { clip(9113728042, 0.66, 0.04, 1.65) } },
	-- Verkaufen (Münzen)
	Coins = { Range = 0, Pitch = 1, Clips = { clip(9113704038, 1.38, 0.19, 1.56) } },
	-- Lager öffnen (Spind)
	Locker = { Range = 0, Pitch = 1, Clips = { clip(9126003568, 0.36, 0.45, 2.45) } },
	-- Kit abholen
	AmmoBox = { Range = 0, Pitch = 1, Clips = { clip(9113102913, 3.06, 0, 1.54) } },

	-- ---------- Agenten-Fähigkeiten (AgentService: "Ability" .. Ability.Type am Agenten, alle in der Nähe hören es) ----
	-- VIPER Adrenalin: Spritze, hoch
	AbilityBoost = { Range = 70, Pitch = 1.25, Clips = { clip(9113046623, 4.2, 0, 1.0) } },
	-- BASTION Schildwand: schwere Platte schlägt auf
	AbilityWall = { Range = 110, Pitch = 1.05, Clips = { clip(9116361742, 3.0, 0, 1.0) } },
	-- MENDER Heilung: Medikit auf
	AbilityHeal = { Range = 50, Pitch = 1.1, Clips = { clip(9113259554, 5.0, 0, 1.2) } },
	-- HAWK Aufklärung: Radar-Ping, tief
	AbilityReveal = { Range = 140, Pitch = 0.55, Clips = { builtin("electronicpingshort.wav", 1.6) } },
	-- GHOST Tarnung: leises Wischen (kaum zu hören, er will ja unsichtbar sein)
	AbilityCloak = { Range = 35, Pitch = 0.6, Clips = { builtin("swoosh.wav", 0.8) } },
	-- BLAZE Sprint-Stoß: Luftstoß
	AbilityDash = { Range = 90, Pitch = 1.1, Clips = { builtin("swoosh.wav", 1.6) } },
	-- AEGIS Team-Heilung: heller Klang
	AbilityTeamHeal = { Range = 90, Pitch = 1.05, Clips = { clip(9114133258, 1.2, 0.06, 2.0) } },
	-- TRAPPER Falle: Metall schnappt ein
	AbilityTrap = { Range = 45, Pitch = 0.9, Clips = { clip(9113243990, 6.0, 0, 1.0) } },
	-- VOLT Geschützturm: Kiste wird abgestellt und klickt
	AbilityTurret = { Range = 90, Pitch = 0.85, Clips = { clip(9113102913, 3.4, 0, 1.2) } },
	-- Ultimate Überladung: Druckwelle
	AbilityUltimate = { Range = 140, Pitch = 1.3, Clips = { clip(9117895638, 1.2, 0.07, 1.37) } },
	-- Fähigkeit wieder bereit (nur für einen selbst, AbilityClient)
	-- Glücksrad (HubWheel, nur am Rad zu hören): Anlauf, Klack am Zeiger, Anhalten, Gewinn nach Seltenheit
	WheelWindup = { Range = 70, Pitch = 0.75, Clips = { builtin("swoosh.wav", 1.2) } },
	WheelTick = { Range = 60, Pitch = 1.1, Clips = { builtin("clickfast.wav", 0.7) } },
	WheelStop = { Range = 70, Pitch = 0.8, Clips = { clip(9113243990, 4.0, 0, 0.8) } },
	WheelWin = { Range = 90, Pitch = 1, Clips = { clip(9114133258, 0.9, 0.06, 2.56) } },
	WheelCoins = { Range = 80, Pitch = 1, Clips = { clip(9113704038, 1.4, 0.19, 1.56) } },
	WheelWinBig = { Range = 120, Pitch = 1, Clips = { clip(9113728042, 0.8, 0.04, 1.65), builtin("electronicpingshort.wav", 1.2) } },
	-- Kisten (CrateClient): Fenster/Rolle starten, Klacken der Rolle, Anhalten, Spannung ab Episch, Gewinn nach Seltenheit
	-- (in der Oberfläche ohne Raumklang; CrateWin/CrateWinBig auch am Automaten in der Welt, wenn der Deckel aufgeht)
	CrateOpen = { Range = 0, Pitch = 1, Clips = { clip(9113102913, 2.6, 0, 1.2) } },
	CrateTick = { Range = 0, Pitch = 1.1, Clips = { builtin("clickfast.wav", 0.55) } },
	CrateStop = { Range = 0, Pitch = 0.8, Clips = { clip(9113243990, 4.0, 0, 0.8) } },
	CrateRise = { Range = 0, Pitch = 0.7, Clips = { builtin("swoosh.wav", 1.5) } },
	CrateWin = { Range = 60, Pitch = 1, Clips = { clip(9114133258, 0.9, 0.06, 2.56) } },
	CrateCoins = { Range = 0, Pitch = 1, Clips = { clip(9113704038, 1.2, 0.19, 1.56) } },
	CrateWinBig = { Range = 80, Pitch = 1, Clips = { clip(9113728042, 0.8, 0.04, 1.65), builtin("electronicpingshort.wav", 1.2) } },
	CrateBoom = { Range = 0, Pitch = 1.3, Clips = { clip(9117895638, 0.9, 0.07, 1.37) } },
	AbilityReady = { Range = 0, Pitch = 1.5, Clips = { builtin("electronicpingshort.wav", 0.35) } },
}

function SoundLibrary.Get(name)
	return SoundLibrary.Sounds[name]
end

-- Mit eigener Zombie-Datei: natürliche Tonhöhe, kein Stimmfilter, kürzere Hörweite (nicht übertrieben)
if ZOMBIE_FILE then
	for _, name in { "ZombieIdle", "ZombieAggro", "ZombieChase", "ZombieAttack", "ZombieHurt", "ZombieDeath", "ZombieScream" } do
		local sound = SoundLibrary.Sounds[name]
		sound.Pitch = 1
		sound.Voice = nil
		sound.Range = math.floor(sound.Range * 0.8)
	end
end

return SoundLibrary
