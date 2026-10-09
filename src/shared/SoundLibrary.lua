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
local ZOMBIE_CLIPS: { [string]: { any } } = {
	Idle = nil, -- Stöhnen beim Herumschlurfen
	Aggro = nil, -- Schrei beim Entdecken
	Chase = nil, -- Knurren / Keuchen beim Jagen
	Attack = nil, -- Grunzen beim Zuschlagen
	Hurt = nil, -- getroffen
	Death = nil, -- Tod
	Scream = nil, -- Schreier ruft die Horde
}

-- dumpf und kehlig wie in Unturned
local ZOMBIE_VOICE = { Muffle = -9, Grit = 0.3 }

SoundLibrary.Sounds = {
	-- Zombies klingen wie in Unturned: tief, kehlig, menschlich statt Tiergebrüll. Darum alles tiefer gestimmt, die Höhen
	-- abgesenkt (Muffle) und etwas angeraut (Grit); jeder Zombie bekommt dazu eine eigene Stimmlage (ZombieService).
	-- Zombie schlurft herum: leises Stöhnen, nur in der Nähe zu hören
	ZombieIdle = { Range = 55, Pitch = 0.82, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Idle or {
		clip(9114553974, 1.0, 0.13, 2.09),
		clip(9120005520, 0.8, 0.32, 2.77),
		clip(9113972834, 1.1, 0.01, 2.2),
		clip(9113972977, 1.4, 0.06, 1.78),
		clip(9113973128, 0.6, 0.07, 1.26),
		clip(9125842589, 2.4, 0.04, 1.5),
	} },
	-- Zombie bemerkt einen Spieler: lauter Schrei, weit zu hören (die Warnung, dass einer kommt)
	ZombieAggro = { Range = 110, Pitch = 0.88, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Aggro or {
		clip(9125467848, 2.6, 0, 1.66),
		clip(9113973521, 1.4, 0.12, 2.12),
		clip(9113636490, 4.6, 0, 1.1),
	} },
	-- Zombie jagt: kurzes Knurren und Keuchen, öfter als im Leerlauf
	ZombieChase = { Range = 70, Pitch = 0.9, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Chase or {
		clip(9113972977, 1.4, 0.06, 1.1),
		clip(9113973128, 0.7, 0.07, 0.9),
		clip(9125842589, 2.4, 0.04, 1.0),
		clip(9113973521, 1.2, 0.12, 1.2),
	} },
	-- Zombie schlägt zu: kurzes Grunzen
	ZombieAttack = { Range = 55, Pitch = 0.8, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Attack or {
		clip(9125652662, 1.4, 0, 0.71),
		clip(9113636491, 4.6, 0, 0.82),
		clip(9113799269, 5.5, 0.07, 1.07),
	} },
	-- Zombie getroffen: Würgen
	ZombieHurt = { Range = 55, Pitch = 0.85, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Hurt or {
		clip(9113799417, 5.5, 0, 0.57),
		clip(9113799526, 2.8, 0, 0.58),
		clip(9113799734, 5.5, 0, 0.61),
	} },
	-- Zombie stirbt: kurzes Gurgeln, kein langer Schrei
	ZombieDeath = { Range = 70, Pitch = 0.75, Voice = ZOMBIE_VOICE, Clips = ZOMBIE_CLIPS.Death or {
		clip(9113607285, 1.3, 0.21, 1.4),
		clip(9116454870, 2.5, 0.11, 1.2),
		clip(9120005520, 1.1, 0.32, 1.6),
	} },
	-- Schreier ruft die anderen
	ZombieScream = { Range = 160, Pitch = 0.95, Voice = { Muffle = -4, Grit = 0.2 }, Clips = ZOMBIE_CLIPS.Scream or {
		clip(9113985445, 3.0, 0.27, 2.67),
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
	-- Signalfeuer zischt (Lootdrop, Horden-Kiste)
	FlareLoop = { Range = 90, Pitch = 1, Looped = true, Clips = { clip(9112780743, 6.0) } },
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
	AbilityReady = { Range = 0, Pitch = 1.5, Clips = { builtin("electronicpingshort.wav", 0.35) } },
}

function SoundLibrary.Get(name)
	return SoundLibrary.Sounds[name]
end

return SoundLibrary

