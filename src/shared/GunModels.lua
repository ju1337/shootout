-- GunModels (ModuleScript)
-- Baut einfache Waffenmodelle aus Parts. Lauf zeigt nach -Z, "Handle" ist der Griffpunkt (Ursprung).
-- Wird für die Waffe vor der eigenen Kamera (Client), in der Hand der Charaktere (Server, Tool) und für
-- Vorschauen benutzt. skin (aus AgentConfig.Skins / Cosmetics) färbt die markierten Teile um.
--
-- Jede Waffe hat eine echte Kimme (hinten) und ein Korn (vorne, mit Leuchtpunkt). Ihre Oberkante liegt
-- genau auf der Visierlinie (Info.SightHeight): Beim Zielen schaut die Kamera über Kimme und Korn.
-- Ausnahme Sturmgewehr: Rotpunktvisier (Info.Reflex) – beim Zielen liegt der rote Punkt in der Bildmitte.
-- Teile mit Group bewegen sich in Animationen gemeinsam (Magazin, Schlitten, Pumpe, Trommel, ...).

local GunModels = {}

-- Größe der Waffe in der Hand der Charaktere (Third-Person), passend zu den Armen der Avatare
GunModels.ToolScale = 0.9 -- Waffe in der Hand (Third-Person): groß genug, um neben dem schlanken Körper gut sichtbar zu sein

local DARK = Color3.fromRGB(45, 45, 50)
local BLACK = Color3.fromRGB(20, 20, 22)
local WOOD = Color3.fromRGB(110, 75, 45)
local GOLD = Color3.fromRGB(190, 150, 60)
local OLIVE = Color3.fromRGB(70, 80, 55)
local GRAY = Color3.fromRGB(70, 73, 80)
local BRASS = Color3.fromRGB(205, 165, 75)
local SHELL = Color3.fromRGB(170, 40, 35)
local DOT = Color3.fromRGB(255, 120, 40)    -- Leuchtpunkt auf dem Korn
local OPTIC = Color3.fromRGB(30, 31, 35)    -- mattschwarzes Gehäuse des Rotpunktvisiers
local LENS = Color3.fromRGB(120, 200, 215)  -- leicht blau getöntes Glas
local RETICLE = Color3.fromRGB(255, 35, 35) -- roter Punkt
local WHITE = Color3.fromRGB(235, 240, 240) -- Punkte an der Kimme (Pistole)
local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.Plastic
local WOODEN = Enum.Material.Wood

local V = Vector3.new
local function rot(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end

-- { Name, Größe, Position (Griffpunkt = 0,0,0), Farbe, Material, Optionen }
-- Optionen: Skin = vom Skin umgefärbt, Group = Animationsgruppe, Hidden = nur in Animationen sichtbar,
-- Rot = Drehung, Shape = Enum.PartType, Neon = leuchtet, Invisible = unsichtbar (nur Griffpunkt),
-- Glass = Durchsichtigkeit (Glas des Rotpunktvisiers)
local HANDLE = { "Handle", V(0.2, 0.2, 0.2), V(0, 0, 0), BLACK, PLASTIC, { Invisible = true } }

local PARTS = {
	Rifle = {
		HANDLE,
		{ "Grip", V(0.24, 0.55, 0.3), V(0, -0.05, 0.05), BLACK, PLASTIC, { Rot = rot(-15) } },
		{ "Body", V(0.35, 0.45, 1.8), V(0, 0.4, -0.35), DARK, METAL, { Skin = true } },
		{ "Handguard", V(0.3, 0.32, 0.75), V(0, 0.44, -1.6), DARK, METAL, { Skin = true } },
		{ "Barrel", V(0.14, 0.14, 0.6), V(0, 0.48, -2.25), BLACK, METAL },
		{ "Muzzle", V(0.18, 0.18, 0.22), V(0, 0.48, -2.62), BLACK, METAL },
		{ "Stock", V(0.3, 0.5, 0.9), V(0, 0.35, 0.95), WOOD, WOODEN, { Skin = true } },
		{ "Magazine", V(0.24, 0.62, 0.34), V(0, -0.08, -0.65), BLACK, METAL, { Group = "Magazine", Rot = rot(10) } },
		{ "Rail", V(0.16, 0.05, 1.25), V(0, 0.65, -0.45), GRAY, METAL },
		{ "Bolt", V(0.22, 0.06, 0.1), V(0, 0.6, 0.6), BLACK, METAL, { Group = "Bolt" } },
		-- Rotpunktvisier (Reflexvisier) auf der Schiene: hinten das flache Gehäuse mit Helligkeitsrad und
		-- Klemmschrauben, vorne der Rahmen mit getöntem Glas. Der rote Punkt sitzt genau auf der
		-- Visierlinie (y = 0.92) mitten im Fenster; das Gehäuse bleibt unter dem Fenster.
		{ "DotMount", V(0.2, 0.06, 0.46), V(0, 0.705, -0.17), OPTIC, PLASTIC },
		{ "DotScrewA", V(0.04, 0.06, 0.06), V(-0.12, 0.705, -0.06), BLACK, METAL, { Shape = Enum.PartType.Cylinder } },
		{ "DotScrewB", V(0.04, 0.06, 0.06), V(-0.12, 0.705, -0.3), BLACK, METAL, { Shape = Enum.PartType.Cylinder } },
		{ "DotBody", V(0.2, 0.075, 0.34), V(0, 0.7725, -0.13), OPTIC, PLASTIC },
		{ "DotDial", V(0.05, 0.1, 0.1), V(-0.125, 0.77, -0.14), BLACK, METAL, { Shape = Enum.PartType.Cylinder } },
		{ "DotDialMark", V(0.052, 0.016, 0.03), V(-0.126, 0.8, -0.14), RETICLE, PLASTIC },
		{ "DotHoodBase", V(0.33, 0.05, 0.12), V(0, 0.79, -0.36), OPTIC, PLASTIC },
		{ "DotHoodL", V(0.035, 0.25, 0.06), V(-0.1475, 0.92, -0.36), OPTIC, PLASTIC },
		{ "DotHoodR", V(0.035, 0.25, 0.06), V(0.1475, 0.92, -0.36), OPTIC, PLASTIC },
		{ "DotHoodTop", V(0.33, 0.035, 0.06), V(0, 1.0425, -0.36), OPTIC, PLASTIC },
		{ "DotHoodCornerL", V(0.035, 0.07, 0.06), V(-0.122, 1.006, -0.36), OPTIC, PLASTIC, { Rot = rot(0, 0, -45) } },
		{ "DotHoodCornerR", V(0.035, 0.07, 0.06), V(0.122, 1.006, -0.36), OPTIC, PLASTIC, { Rot = rot(0, 0, 45) } },
		{ "DotGlass", V(0.26, 0.21, 0.008), V(0, 0.92, -0.36), LENS, Enum.Material.Glass, { Glass = 0.82 } },
		{ "DotReticle", V(0.01, 0.01, 0.01), V(0, 0.92, -0.352), RETICLE, PLASTIC,
			{ Neon = true, Shape = Enum.PartType.Ball } },
	},
	SMG = {
		HANDLE,
		{ "Grip", V(0.22, 0.5, 0.28), V(0, -0.05, 0.04), BLACK, PLASTIC, { Rot = rot(-12) } },
		{ "Body", V(0.3, 0.4, 1.2), V(0, 0.38, -0.2), OLIVE, METAL, { Skin = true } },
		{ "Barrel", V(0.12, 0.12, 0.45), V(0, 0.43, -1.0), BLACK, METAL },
		{ "Muzzle", V(0.16, 0.16, 0.15), V(0, 0.43, -1.28), BLACK, METAL },
		{ "Magazine", V(0.2, 0.75, 0.25), V(0, -0.1, -0.45), BLACK, METAL, { Group = "Magazine" } },
		{ "Stock", V(0.15, 0.3, 0.6), V(0, 0.35, 0.65), BLACK, METAL, { Skin = true } },
		{ "StockPad", V(0.2, 0.4, 0.08), V(0, 0.3, 0.98), BLACK, PLASTIC },
		{ "BoltTube", V(0.08, 0.08, 0.55), V(-0.17, 0.5, -0.5), DARK, METAL },
		{ "Bolt", V(0.06, 0.06, 0.16), V(-0.22, 0.5, -0.55), BLACK, METAL, { Group = "Bolt" } },
		-- Kimme: Lochkimme (Visierlinie y = 0.76)
		{ "RearBase", V(0.13, 0.095, 0.08), V(0, 0.6275, 0.3), BLACK, METAL },
		{ "RearL", V(0.055, 0.17, 0.04), V(-0.0575, 0.76, 0.3), BLACK, METAL },
		{ "RearR", V(0.055, 0.17, 0.04), V(0.0575, 0.76, 0.3), BLACK, METAL },
		{ "RearT", V(0.06, 0.055, 0.04), V(0, 0.8175, 0.3), BLACK, METAL },
		{ "RearB", V(0.06, 0.055, 0.04), V(0, 0.7025, 0.3), BLACK, METAL },
		-- Korn im Ringtunnel
		{ "FrontBase", V(0.11, 0.12, 0.08), V(0, 0.64, -0.72), BLACK, METAL },
		{ "FrontPost", V(0.026, 0.04, 0.026), V(0, 0.72, -0.72), BLACK, METAL },
		{ "FrontDot", V(0.028, 0.02, 0.028), V(0, 0.75, -0.72), DOT, METAL, { Neon = true } },
		{ "HoodL", V(0.022, 0.12, 0.06), V(-0.06, 0.76, -0.72), BLACK, METAL },
		{ "HoodR", V(0.022, 0.12, 0.06), V(0.06, 0.76, -0.72), BLACK, METAL },
		{ "HoodTop", V(0.142, 0.022, 0.06), V(0, 0.831, -0.72), BLACK, METAL },
	},
	Shotgun = {
		HANDLE,
		{ "Grip", V(0.25, 0.5, 0.3), V(0, -0.05, 0.06), BLACK, PLASTIC, { Rot = rot(-18) } },
		{ "Body", V(0.35, 0.4, 1.2), V(0, 0.38, -0.3), DARK, METAL, { Skin = true } },
		{ "Barrel", V(0.2, 0.2, 1.55), V(0, 0.52, -1.675), BLACK, METAL },
		{ "Tube", V(0.15, 0.15, 1.3), V(0, 0.33, -1.55), BLACK, METAL },
		{ "Pump", V(0.28, 0.24, 0.6), V(0, 0.32, -1.35), WOOD, WOODEN, { Group = "Pump" } },
		{ "Stock", V(0.3, 0.5, 1.0), V(0, 0.3, 1.0), WOOD, WOODEN, { Skin = true } },
		{ "Rib", V(0.06, 0.03, 1.5), V(0, 0.635, -1.675), GRAY, METAL },
		-- Kimme: Kerbe auf dem Gehäuse, Korn: Leuchtperle an der Mündung (Visierlinie y = 0.71)
		{ "RearBase", V(0.16, 0.05, 0.06), V(0, 0.605, 0.18), BLACK, METAL },
		{ "RearL", V(0.05, 0.11, 0.06), V(-0.055, 0.685, 0.18), BLACK, METAL },
		{ "RearR", V(0.05, 0.11, 0.06), V(0.055, 0.685, 0.18), BLACK, METAL },
		{ "FrontPost", V(0.03, 0.025, 0.03), V(0, 0.6625, -2.38), BLACK, METAL },
		{ "FrontDot", V(0.07, 0.07, 0.07), V(0, 0.71, -2.38), DOT, METAL, { Neon = true, Shape = Enum.PartType.Ball } },
		-- Patrone beim Nachladen (sonst unsichtbar), liegt vor der Ladeklappe unten am Gehäuse
		{ "Shell", V(0.22, 0.09, 0.09), V(0, 0.08, -0.45), SHELL, PLASTIC,
			{ Group = "Shell", Hidden = true, Shape = Enum.PartType.Cylinder, Rot = rot(0, 90, 0) } },
	},
	DMR = {
		HANDLE,
		{ "Grip", V(0.24, 0.52, 0.3), V(0, -0.05, 0.05), BLACK, PLASTIC, { Rot = rot(-15) } },
		{ "Body", V(0.32, 0.42, 2.0), V(0, 0.4, -0.4), DARK, METAL, { Skin = true } },
		{ "Barrel", V(0.14, 0.14, 1.45), V(0, 0.46, -2.12), BLACK, METAL },
		{ "Muzzle", V(0.2, 0.17, 0.25), V(0, 0.46, -2.95), BLACK, METAL },
		{ "Magazine", V(0.22, 0.45, 0.3), V(0, 0.0, -0.6), BLACK, METAL, { Group = "Magazine" } },
		{ "Stock", V(0.3, 0.5, 1.0), V(0, 0.35, 1.0), DARK, METAL, { Skin = true } },
		{ "Rail", V(0.14, 0.05, 1.1), V(0, 0.635, -0.35), GRAY, METAL },
		{ "Bolt", V(0.18, 0.06, 0.06), V(0.22, 0.5, 0.15), BLACK, METAL, { Group = "Bolt" } },
		-- Kimme: Diopter (Visierlinie y = 0.88)
		{ "RearBase", V(0.15, 0.13, 0.12), V(0, 0.725, 0.15), BLACK, METAL },
		{ "RearL", V(0.06, 0.18, 0.05), V(-0.06, 0.88, 0.15), BLACK, METAL },
		{ "RearR", V(0.06, 0.18, 0.05), V(0.06, 0.88, 0.15), BLACK, METAL },
		{ "RearT", V(0.06, 0.06, 0.05), V(0, 0.94, 0.15), BLACK, METAL },
		{ "RearB", V(0.06, 0.06, 0.05), V(0, 0.82, 0.15), BLACK, METAL },
		-- Korn im Ringtunnel
		{ "FrontBase", V(0.11, 0.24, 0.1), V(0, 0.65, -2.65), BLACK, METAL },
		{ "FrontPost", V(0.028, 0.085, 0.028), V(0, 0.8125, -2.65), BLACK, METAL },
		{ "FrontDot", V(0.03, 0.025, 0.03), V(0, 0.8675, -2.65), DOT, METAL, { Neon = true } },
		{ "HoodL", V(0.022, 0.16, 0.08), V(-0.065, 0.85, -2.65), BLACK, METAL },
		{ "HoodR", V(0.022, 0.16, 0.08), V(0.065, 0.85, -2.65), BLACK, METAL },
		{ "HoodTop", V(0.152, 0.022, 0.08), V(0, 0.941, -2.65), BLACK, METAL },
	},
	LMG = {
		HANDLE,
		{ "Grip", V(0.25, 0.52, 0.3), V(0, -0.05, 0.05), BLACK, PLASTIC, { Rot = rot(-15) } },
		{ "Body", V(0.42, 0.5, 2.0), V(0, 0.4, -0.4), OLIVE, METAL, { Skin = true } },
		{ "Shroud", V(0.26, 0.26, 0.7), V(0, 0.48, -1.75), GRAY, METAL },
		{ "Barrel", V(0.18, 0.18, 0.6), V(0, 0.48, -2.4), BLACK, METAL },
		{ "Muzzle", V(0.22, 0.22, 0.2), V(0, 0.48, -2.78), BLACK, METAL },
		{ "Box", V(0.45, 0.5, 0.5), V(0.05, -0.05, -0.55), OLIVE, METAL, { Group = "Magazine", Skin = true } },
		{ "Belt", V(0.16, 0.08, 0.3), V(0.1, 0.24, -0.55), BRASS, METAL, { Group = "Magazine" } },
		{ "Cover", V(0.4, 0.06, 0.8), V(0, 0.68, -0.35), DARK, METAL, { Group = "Cover" } },
		{ "Stock", V(0.3, 0.5, 0.9), V(0, 0.35, 1.0), BLACK, METAL },
		{ "BipodL", V(0.08, 0.45, 0.08), V(-0.07, 0.2, -2.2), BLACK, METAL, { Rot = rot(0, 0, -10) } },
		{ "BipodR", V(0.08, 0.45, 0.08), V(0.07, 0.2, -2.2), BLACK, METAL, { Rot = rot(0, 0, 10) } },
		{ "Bolt", V(0.15, 0.07, 0.08), V(0.27, 0.45, -0.6), BLACK, METAL, { Group = "Bolt" } },
		-- Kimme: Kerbe hinter dem Deckel (Visierlinie y = 0.92)
		{ "RearBase", V(0.16, 0.18, 0.08), V(0, 0.74, 0.25), BLACK, METAL },
		{ "RearL", V(0.05, 0.11, 0.06), V(-0.055, 0.885, 0.25), BLACK, METAL },
		{ "RearR", V(0.05, 0.11, 0.06), V(0.055, 0.885, 0.25), BLACK, METAL },
		{ "FrontBase", V(0.11, 0.25, 0.1), V(0, 0.695, -2.45), BLACK, METAL },
		{ "FrontPost", V(0.03, 0.075, 0.03), V(0, 0.8575, -2.45), BLACK, METAL },
		{ "FrontDot", V(0.032, 0.025, 0.032), V(0, 0.9075, -2.45), DOT, METAL, { Neon = true } },
	},
	Pistol = {
		HANDLE,
		{ "Grip", V(0.22, 0.55, 0.3), V(0, -0.02, 0.04), BLACK, PLASTIC, { Rot = rot(-15) } },
		{ "Frame", V(0.21, 0.13, 0.75), V(0, 0.27, -0.27), BLACK, PLASTIC },
		{ "TriggerGuard", V(0.04, 0.12, 0.25), V(0, 0.15, -0.2), BLACK, PLASTIC },
		{ "Slide", V(0.25, 0.28, 0.95), V(0, 0.38, -0.25), GOLD, METAL, { Skin = true, Group = "Slide" } },
		{ "Barrel", V(0.12, 0.12, 0.08), V(0, 0.4, -0.75), BLACK, METAL },
		{ "Magazine", V(0.17, 0.53, 0.24), V(0, -0.06, 0.04), BLACK, METAL, { Group = "Magazine", Rot = rot(-15) } },
		-- 3-Punkt-Visier auf dem Schlitten (Visierlinie y = 0.6)
		{ "RearL", V(0.07, 0.08, 0.06), V(-0.065, 0.56, 0.17), BLACK, METAL, { Group = "Slide" } },
		{ "RearR", V(0.07, 0.08, 0.06), V(0.065, 0.56, 0.17), BLACK, METAL, { Group = "Slide" } },
		{ "RearDotL", V(0.025, 0.025, 0.01), V(-0.065, 0.565, 0.2005), WHITE, PLASTIC, { Group = "Slide" } },
		{ "RearDotR", V(0.025, 0.025, 0.01), V(0.065, 0.565, 0.2005), WHITE, PLASTIC, { Group = "Slide" } },
		{ "FrontPost", V(0.04, 0.055, 0.05), V(0, 0.5475, -0.66), BLACK, METAL, { Group = "Slide" } },
		{ "FrontDot", V(0.042, 0.025, 0.05), V(0, 0.5875, -0.66), DOT, METAL, { Neon = true, Group = "Slide" } },
	},
	Revolver = {
		HANDLE,
		{ "Grip", V(0.22, 0.55, 0.3), V(0, -0.02, 0.06), WOOD, WOODEN, { Rot = rot(-20) } },
		{ "Frame", V(0.25, 0.3, 0.6), V(0, 0.38, -0.15), DARK, METAL, { Skin = true } },
		{ "Cylinder", V(0.35, 0.32, 0.32), V(0, 0.38, -0.25), DARK, METAL,
			{ Skin = true, Group = "Cylinder", Shape = Enum.PartType.Cylinder, Rot = rot(0, 90, 0) } },
		{ "Barrel", V(0.14, 0.14, 0.75), V(0, 0.43, -0.8), BLACK, METAL },
		{ "Lug", V(0.12, 0.1, 0.6), V(0, 0.32, -0.75), DARK, METAL },
		{ "Hammer", V(0.06, 0.1, 0.1), V(0, 0.5, 0.15), BLACK, METAL, { Group = "Hammer" } }, -- unter der Visierlinie
		-- Kimme: Kerbe in der Rahmenoberseite, Korn: Leuchtpunkt (Visierlinie y = 0.6)
		{ "RearL", V(0.06, 0.07, 0.06), V(-0.055, 0.565, 0.08), BLACK, METAL },
		{ "RearR", V(0.06, 0.07, 0.06), V(0.055, 0.565, 0.08), BLACK, METAL },
		{ "FrontPost", V(0.035, 0.075, 0.12), V(0, 0.5375, -1.1), BLACK, METAL },
		{ "FrontDot", V(0.037, 0.025, 0.06), V(0, 0.5875, -1.08), DOT, METAL, { Neon = true } },
		-- Schnelllader beim Nachladen (sonst unsichtbar), sitzt hinter der ausgeschwenkten Trommel
		{ "Loader", V(0.12, 0.3, 0.3), V(-0.28, 0.28, -0.015), BLACK, METAL,
			{ Group = "Loader", Hidden = true, Shape = Enum.PartType.Cylinder, Rot = rot(0, 90, 0) } },
	},
}

-- Infos je Waffe (Modell-Einheiten, Griffpunkt = Ursprung):
-- SightHeight = Höhe der Visierlinie (Oberkante Korn bzw. roter Punkt), SightZ = Position der Kimme (beim
-- Rotpunkt: des Glases), EyeRelief = Abstand Auge - Kimme beim Zielen, Reflex = Rotpunktvisier,
-- Muzzle = Mündung, Eject = Hülsenauswurf, RightHand/LeftHand = Hände,
-- Stock = Ende der Schulterstütze (lange Waffen), Long = lange Waffe (Schulteranschlag),
-- LeftHandTP = linke Hand in der Third-Person (näher am Griff, damit die kürzeren Avatar-Arme hinkommen)
GunModels.Info = {
	-- Rotpunkt: SightZ = Glas, das Auge bleibt wie vorher 0.72 hinter dem Griff
	Rifle = { SightHeight = 0.92, SightZ = -0.36, EyeRelief = 1.08, Reflex = true, Muzzle = V(0, 0.48, -2.73),
		Eject = V(0.18, 0.47, -0.3), RightHand = V(0, -0.05, 0.05), LeftHand = V(-0.03, 0.27, -1.6), Stock = V(0, 0.35, 1.4),
		Long = true, LeftHandTP = V(-0.03, 0.2, -1.15) },
	SMG = { SightHeight = 0.76, SightZ = 0.3, EyeRelief = 0.55, Muzzle = V(0, 0.43, -1.355), Eject = V(0.16, 0.45, -0.25),
		RightHand = V(0, -0.05, 0.04), LeftHand = V(-0.03, 0.15, -0.68), Stock = V(0, 0.3, 1.02), Long = true,
		LeftHandTP = V(-0.03, 0.15, -0.68) },
	Shotgun = { SightHeight = 0.71, SightZ = 0.18, EyeRelief = 0.6, Muzzle = V(0, 0.52, -2.45), Eject = V(0.18, 0.42, -0.35),
		RightHand = V(0, -0.05, 0.06), LeftHand = V(-0.02, 0.2, -1.35), Stock = V(0, 0.3, 1.5), Long = true,
		LeftHandTP = V(-0.02, 0.2, -1.35) },
	DMR = { SightHeight = 0.88, SightZ = 0.15, EyeRelief = 0.65, Muzzle = V(0, 0.46, -3.075), Eject = V(0.17, 0.48, -0.25),
		RightHand = V(0, -0.05, 0.05), LeftHand = V(-0.03, 0.18, -1.2), Stock = V(0, 0.35, 1.5), Long = true,
		LeftHandTP = V(-0.03, 0.18, -1.2) },
	LMG = { SightHeight = 0.92, SightZ = 0.25, EyeRelief = 0.65, Muzzle = V(0, 0.48, -2.88), Eject = V(0.22, 0.42, -0.2),
		RightHand = V(0, -0.05, 0.05), LeftHand = V(-0.03, 0.33, -1.75), Stock = V(0, 0.35, 1.45), Long = true,
		LeftHandTP = V(-0.03, 0.33, -1.42) },
	Pistol = { SightHeight = 0.6, SightZ = 0.17, EyeRelief = 1.0, Muzzle = V(0, 0.4, -0.79), Eject = V(0.14, 0.45, -0.15),
		RightHand = V(0, -0.02, 0.04), LeftHand = V(-0.12, -0.1, 0.02), Long = false,
		LeftHandTP = V(-0.12, -0.1, 0.02) },
	Revolver = { SightHeight = 0.6, SightZ = 0.08, EyeRelief = 1.05, Muzzle = V(0, 0.43, -1.175), Eject = V(0, 0.38, -0.25),
		RightHand = V(0, -0.02, 0.06), LeftHand = V(-0.12, -0.1, 0.03), Long = false,
		LeftHandTP = V(-0.12, -0.1, 0.03) },
}

-- Ruheposition jedes Teils und Drehpunkt jeder Gruppe (erstes Teil der Gruppe)
local restOf = {}  -- [Waffe][Teilname] = CFrame
local groupOf = {} -- [Waffe][Teilname] = Gruppe
local pivots = {}  -- [Waffe][Gruppe] = CFrame des Hauptteils
for weaponName, defs in PARTS do
	restOf[weaponName], groupOf[weaponName], pivots[weaponName] = {}, {}, {}
	for _, def in defs do
		local options = def[6] or {}
		local cframe = CFrame.new(def[3]) * (options.Rot or CFrame.new())
		restOf[weaponName][def[1]] = cframe
		if options.Group then
			groupOf[weaponName][def[1]] = options.Group
			pivots[weaponName][options.Group] = pivots[weaponName][options.Group] or cframe
		end
	end
end

-- Ruhe-CFrame eines Teils im Waffenraum (nil, wenn es das Teil nicht gibt)
function GunModels.Rest(weaponName, partName)
	return restOf[weaponName] and restOf[weaponName][partName]
end

-- Animationsgruppe eines Teils (nil = bewegt sich nicht für sich)
function GunModels.GroupOf(weaponName, partName)
	return groupOf[weaponName] and groupOf[weaponName][partName]
end

-- Hauptteil einer Gruppe in Ruhe (z.B. das Magazin), nil wenn die Waffe die Gruppe nicht hat
function GunModels.GroupPivot(weaponName, group)
	return pivots[weaponName] and pivots[weaponName][group]
end

-- Bewegung einer Gruppe im Waffenraum: offset (Achsen der Waffe) um den Mittelpunkt des Hauptteils.
-- scale = Größe der Waffe (Tool/Viewmodel). Ergebnis * Ruhe-CFrame eines Teils = bewegtes Teil.
function GunModels.GroupTransform(weaponName, group, offset, scale)
	local pivot = GunModels.GroupPivot(weaponName, group)
	if not pivot or not offset then
		return CFrame.new()
	end
	scale = scale or 1
	local p = pivot.Position * scale
	return CFrame.new(p) * CFrame.new(offset.Position * scale) * offset.Rotation * CFrame.new(-p)
end

-- Kamera-Versatz beim Zielen über Kimme und Korn: legt die Visierlinie genau in die Bildmitte,
-- EyeRelief vor das Auge. Ergebnis gilt für ein Modell mit Größe 1 (für kleinere: Position * scale).
function GunModels.AimOffset(weaponName)
	local info = GunModels.Info[weaponName]
	return CFrame.new(0, -info.SightHeight, -info.EyeRelief - info.SightZ)
end

-- Weltposition eines Punkts der Waffe (z.B. Info.Muzzle) über den Griff
function GunModels.PointWorld(handle, point, scale)
	return (handle.CFrame * CFrame.new(point * (scale or 1))).Position
end

-- Alle Teile einer Animationsgruppe in einem Waffenmodell oder Tool
function GunModels.GroupParts(container, group)
	local list = {}
	for _, part in container:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Group") == group then
			table.insert(list, part)
		end
	end
	return list
end

-- Waffen-Aufsätze als Teile an das Modell bauen (Modell-Einheiten, Lauf zeigt nach -Z).
-- attachments = Liste der Aufsatz-Ids (AttachmentConfig), z.B. { "Compensator", "Laser" }
local ATTACH_DARK = Color3.fromRGB(32, 33, 36)
local function attachPart(model, name, size, cframe, color, material, group, neon)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color or ATTACH_DARK
	part.Material = neon and Enum.Material.Neon or (material or Enum.Material.Metal)
	if group then
		part:SetAttribute("Group", group)
	end
	part.Parent = model
	return part
end

local function addAttachments(model, weaponName, attachments)
	local info = GunModels.Info[weaponName]
	if not info or not attachments then
		return
	end
	local has = {}
	for _, id in attachments do
		has[id] = true
	end
	local muzzle = info.Muzzle
	local long = info.Long
	if has.Compensator then
		attachPart(model, "AttCompensator", V(0.26, 0.26, 0.34), CFrame.new(muzzle + V(0, 0, -0.17)))
		attachPart(model, "AttCompensatorPort", V(0.28, 0.06, 0.12), CFrame.new(muzzle + V(0, 0.1, -0.2)),
			Color3.fromRGB(70, 72, 76))
	elseif has.Suppressor then
		local can = attachPart(model, "AttSuppressor", V(0.62, 0.24, 0.24), CFrame.new(muzzle + V(0, 0, -0.31))
			* CFrame.Angles(0, math.rad(90), 0))
		can.Shape = Enum.PartType.Cylinder
		attachPart(model, "AttSuppressorBand", V(0.26, 0.26, 0.06), CFrame.new(muzzle + V(0, 0, -0.08)), Color3.fromRGB(70, 72, 76))
	elseif has.MuzzleBrake then
		attachPart(model, "AttBrake", V(0.32, 0.22, 0.3), CFrame.new(muzzle + V(0, 0, -0.15)))
		for k = 0, 1 do
			attachPart(model, "AttBrakeRib", V(0.36, 0.06, 0.05), CFrame.new(muzzle + V(0, 0, -0.08 - k * 0.12)),
				Color3.fromRGB(70, 72, 76))
		end
	end
	if long and has.LongBarrel then
		attachPart(model, "AttLongBarrel", V(0.13, 0.13, 0.55), CFrame.new(muzzle + V(0, 0, -0.27)))
	elseif long and has.HeavyBarrel then
		attachPart(model, "AttHeavyBarrel", V(0.24, 0.24, 0.9), CFrame.new(muzzle + V(0, 0, 0.4)), Color3.fromRGB(48, 50, 54))
		for k = 0, 2 do
			attachPart(model, "AttHeavyFin", V(0.28, 0.04, 0.06), CFrame.new(muzzle + V(0, 0.12, 0.15 + k * 0.25)),
				Color3.fromRGB(70, 72, 76))
		end
	elseif long and has.ShortBarrel then
		attachPart(model, "AttShroud", V(0.24, 0.24, 0.3), CFrame.new(muzzle + V(0, 0, 0.25)), Color3.fromRGB(55, 58, 62))
	end
	if long and info.LeftHand then
		local hand = info.LeftHand
		if has.VerticalGrip then
			attachPart(model, "AttGrip", V(0.15, 0.48, 0.17), CFrame.new(hand + V(0.03, -0.32, 0.12)))
		elseif has.AngledGrip then
			attachPart(model, "AttAngledGrip", V(0.14, 0.34, 0.42), CFrame.new(hand + V(0.03, -0.22, 0.05))
				* CFrame.Angles(math.rad(-35), 0, 0))
		elseif has.Laser then
			attachPart(model, "AttLaser", V(0.12, 0.12, 0.34), CFrame.new(hand + V(0.17, 0.08, -0.15)))
			attachPart(model, "AttLaserDot", V(0.06, 0.06, 0.02), CFrame.new(hand + V(0.17, 0.08, -0.33)),
				Color3.fromRGB(255, 50, 40), nil, nil, true)
		end
	end
	local mag = model:FindFirstChild("Magazine") or model:FindFirstChild("Box")
	if mag then
		if has.ExtendedMag then
			-- länger nach unten
			local extra = mag.Size.Y * 0.35
			mag.Size += V(0, extra, 0)
			mag.CFrame *= CFrame.new(0, -extra / 2, 0)
		elseif has.DrumMag then
			-- Trommel unter dem Magazinschacht
			local drum = attachPart(model, "AttDrum", V(mag.Size.X * 1.6, mag.Size.Y * 1.1, mag.Size.Y * 1.1),
				mag.CFrame * CFrame.new(0, -mag.Size.Y * 0.35, 0) * CFrame.Angles(0, 0, math.rad(90)), mag.Color, mag.Material,
				"Magazine")
			drum.Shape = Enum.PartType.Cylinder
			drum.Size = V(mag.Size.X * 1.6, mag.Size.Y * 1.1, mag.Size.Y * 1.1)
		elseif has.FastMag then
			-- zweites Magazin daneben geklebt (schneller Wechsel)
			local twin = attachPart(model, "AttTwinMag", mag.Size, mag.CFrame * CFrame.new(mag.Size.X + 0.02, 0, 0),
				mag.Color, mag.Material, "Magazine")
			attachPart(model, "AttTape", V(mag.Size.X * 2 + 0.06, 0.08, mag.Size.Z + 0.02),
				mag.CFrame * CFrame.new(mag.Size.X / 2, -mag.Size.Y * 0.15, 0), Color3.fromRGB(140, 120, 70),
				Enum.Material.Fabric, "Magazine")
			twin.Name = "AttTwinMag"
		end
	end
end

-- Liefert ein Model mit PrimaryPart "Handle" (Griffpunkt). Alle Parts sind verankert und ohne Kollision.
-- Teile haben das Attribut "Group" (Animationsgruppe) bzw. "Hidden" (nur in Animationen sichtbar).
-- attachments (optional) = ausgerüstete Aufsätze, werden als Teile angebaut.
function GunModels.Build(weaponName, skin, attachments)
	local model = Instance.new("Model")
	model.Name = weaponName
	for _, def in PARTS[weaponName] do
		local options = def[6] or {}
		local part = Instance.new("Part")
		part.Name = def[1]
		part.Size = def[2]
		part.CFrame = CFrame.new(def[3]) * (options.Rot or CFrame.new())
		part.Color = def[4]
		part.Material = options.Neon and Enum.Material.Neon or def[5]
		if options.Shape then
			part.Shape = options.Shape
		end
		if skin and options.Skin then
			part.Color = skin.Color
			part.Material = skin.Material
		end
		if options.Invisible then
			part.Transparency = 1
		end
		if options.Glass then
			part.Transparency = options.Glass
			part.Material = Enum.Material.Glass
		end
		if options.Hidden then
			part.Transparency = 1
			part:SetAttribute("Hidden", true)
		end
		if options.Group then
			part:SetAttribute("Group", options.Group)
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		if def[1] == "Handle" then
			model.PrimaryPart = part
		end
	end
	addAttachments(model, weaponName, attachments)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part:SetAttribute("Rest", part.CFrame) -- Ruhelage im Modell (auch für angebaute Aufsätze)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = false
		end
	end
	return model
end

-- Liefert ein Tool (für die Hand des Charakters), verkleinert auf ToolScale. Die Teile hängen über
-- Welds (Name "GunWeld") am Griff, damit Clients Magazin & Co. beim Nachladen bewegen können.
function GunModels.BuildTool(weaponName, displayName, skin, attachments)
	local model = GunModels.Build(weaponName, skin, attachments)
	model:ScaleTo(GunModels.ToolScale)
	local tool = Instance.new("Tool")
	tool.Name = displayName
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.RequiresHandle = true
	tool:SetAttribute("Weapon", weaponName)

	local handle = model.PrimaryPart
	for _, part in model:GetChildren() do
		part.Anchored = false
		if part ~= handle then
			local weld = Instance.new("Weld")
			weld.Name = "GunWeld"
			weld.Part0 = handle
			weld.Part1 = part
			weld.C0 = handle.CFrame:ToObjectSpace(part.CFrame)
			weld.Parent = part
		end
		part.Parent = tool
	end
	model:Destroy()
	return tool
end

return GunModels
