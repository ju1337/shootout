-- GunModels (ModuleScript)
-- Waffenmodelle: fertige 3D-Modelle aus ReplicatedStorage.Assets.Weapons (Blender, siehe unten und
-- docs/waffen-modelle.md) oder – solange es keins gibt – einfache Modelle aus Parts ("Quader-Waffen").
-- Lauf zeigt nach -Z, "Handle" ist der Griffpunkt (Ursprung).
-- Wird für die Waffe vor der eigenen Kamera (Client), in der Hand der Charaktere (Server, Tool) und für
-- Vorschauen benutzt. skin (aus AgentConfig.Skins / Cosmetics) färbt die markierten Teile um.
--
-- Jede Waffe hat eine echte Kimme (hinten) und ein Korn (vorne, mit Leuchtpunkt). Ihre Oberkante liegt
-- genau auf der Visierlinie (Info.SightHeight): Beim Zielen schaut die Kamera über Kimme und Korn.
-- Ausnahme Sturmgewehr: Rotpunktvisier (Info.Reflex) – beim Zielen liegt der rote Punkt in der Bildmitte.
-- Teile mit Group bewegen sich in Animationen gemeinsam (Magazin, Schlitten, Pumpe, Trommel, ...).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- ---------- Ruhelage, Animationsgruppen, Drehpunkte ----------
-- Für jede Waffe aus den Quadern bzw. aus dem 3D-Modell (siehe unten)
local restOf = {}    -- [Waffe][Teilname] = CFrame
local groupOf = {}   -- [Waffe][Teilname] = Gruppe
local pivots = {}    -- [Waffe][Gruppe] = CFrame des Drehpunkts (Hauptteil der Gruppe oder Marker Pivot_<Gruppe>)
local mainParts = {} -- [Waffe][Gruppe] = Name des Hauptteils (erstes Teil der Gruppe, z.B. das Magazin)

-- entries = { { Name, CFrame (Ruhelage), Group } } in Reihenfolge (erstes Teil einer Gruppe = Hauptteil),
-- pivotOverride = { [Gruppe] = CFrame } (optional, aus Markern)
local function indexParts(weaponName, entries, pivotOverride)
	restOf[weaponName], groupOf[weaponName], pivots[weaponName], mainParts[weaponName] = {}, {}, {}, {}
	for _, entry in entries do
		restOf[weaponName][entry.Name] = entry.CFrame
		if entry.Group then
			groupOf[weaponName][entry.Name] = entry.Group
			if not mainParts[weaponName][entry.Group] then
				mainParts[weaponName][entry.Group] = entry.Name
				pivots[weaponName][entry.Group] = entry.CFrame
			end
		end
	end
	for group, pivot in pivotOverride or {} do
		if pivots[weaponName][group] then
			pivots[weaponName][group] = pivot
		end
	end
end

-- Quader-Waffen: Gruppen (die Animationen bewegen genau diese) und Länge (Maßstab für 3D-Modelle)
local blockoutGroups = {} -- [Waffe] = { Gruppe, ... }
local blockoutLength = {} -- [Waffe] = Länge in Studs (Schulterstütze bis Mündung)
for weaponName, defs in PARTS do
	local entries, seen, minZ, maxZ = {}, {}, math.huge, -math.huge
	blockoutGroups[weaponName] = {}
	for _, def in defs do
		local options = def[6] or {}
		table.insert(entries, { Name = def[1], CFrame = CFrame.new(def[3]) * (options.Rot or CFrame.new()), Group = options.Group })
		if options.Group and not seen[options.Group] then
			seen[options.Group] = true
			table.insert(blockoutGroups[weaponName], options.Group)
		end
		if not options.Invisible then
			minZ = math.min(minZ, def[3].Z - def[2].Z / 2)
			maxZ = math.max(maxZ, def[3].Z + def[2].Z / 2)
		end
	end
	blockoutLength[weaponName] = maxZ - minZ
	indexParts(weaponName, entries)
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

-- Name des Hauptteils einer Gruppe (z.B. das Magazin, an dem die Magazin-Aufsätze sitzen)
function GunModels.GroupMainPart(weaponName, group)
	return mainParts[weaponName] and mainParts[weaponName][group]
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
	local magName = GunModels.GroupMainPart(weaponName, "Magazine")
	local mag = magName and model:FindFirstChild(magName)
	if mag and mag:IsA("BasePart") then
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

-- Quader-Waffe aus PARTS (ohne Aufsätze)
local function buildBlockout(weaponName, skin)
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
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		if def[1] == "Handle" then
			model.PrimaryPart = part
		end
	end
	return model
end

-- ---------- Fertige 3D-Modelle (Blender) ----------
-- Liegt in ReplicatedStorage.Assets.Weapons ein Modell mit dem Namen einer Waffe (z.B. "Rifle"), wird es statt der
-- Quader benutzt – überall: Ego-Waffe, Hand, Rücken, Vorschauen, Symbole. Fehlt etwas Wichtiges, bleibt die
-- Quader-Waffe, und Studio schreibt beim Spielstart ins Output, was fehlt. Aufbau: docs/waffen-modelle.md. Kurz:
--   Marker (kleine Teile, kommen nicht ins Spiel): Point_Grip (rechte Hand, wird zum Ursprung), Point_SightRear
--   und Point_SightFront (beide genau auf der Visierlinie: legen Richtung und Höhe fest), Point_Muzzle,
--   Point_Eject, Point_LeftHand, Point_Stock (lange Waffen), optional Point_LeftHandTP und Pivot_<Gruppe>
--   (Drehpunkt einer Animationsgruppe). Statt Marker-Teilen gehen auch Attachments mit diesen Namen.
--   Die Ausrichtung kommt nur aus den Markern – wie das Modell beim Import gedreht oder verschoben ist, ist egal.
--   Teilnamen bestehen aus Wörtern mit "_" dazwischen (Blender-Endungen wie ".001" sind egal): eine
--   Animationsgruppe (Magazine, Bolt, Slide, Pump, Cylinder, Hammer, Cover, Shell, Loader) bewegt das Teil mit
--   der Gruppe, "Skin" = Skin-Zone (bekommt die Skin-Farbe), "Neon" = leuchtet, "Glass" = Glas, "Reticle" =
--   roter Punkt des Rotpunktvisiers (fehlt er, wird einer auf Point_SightRear gesetzt).
--   Textur-Skins (episch/legendär): Ordner "Skins" im Modell, darin je Skin ein Ordner mit der Skin-Id (z.B.
--   "W_Lava") mit SurfaceAppearances, benannt wie die Teile, die sie bekommen. Ohne Textur bleibt die Skin-Farbe.
local ANIMATION_GROUPS = { Magazine = true, Bolt = true, Slide = true, Pump = true, Cylinder = true, Hammer = true,
	Cover = true, Shell = true, Loader = true }
local HIDDEN_GROUPS = { Shell = true, Loader = true } -- nur während der Animation sichtbar
local POINTS = { Grip = true, SightRear = true, SightFront = true, Muzzle = true, Eject = true, LeftHand = true,
	LeftHandTP = true, Stock = true }
local REQUIRED_POINTS = { "Grip", "SightRear", "SightFront", "Muzzle", "Eject", "LeftHand" }
local GLASS_TRANSPARENCY = 0.82
local MAX_PARTS = 40 -- mehr Einzelteile kosten Leistung (vor allem auf Handys)

local assetData = {}   -- [Waffe] = { Template = Model in Ruhelage (Griff = Ursprung), Skins = Ordner oder nil }
local assetReport = {} -- [Waffe] = { Loaded = bool, Errors = { Text }, Warnings = { Text } }

-- Blender hängt an Kopien ".001" an – das zählt nicht zum Namen
local function cleanName(name)
	return (string.gsub(name, "%.%d+$", ""))
end

local function wordsOf(name)
	local list = {}
	for word in string.gmatch(name, "[^_%.%s]+") do
		table.insert(list, word)
	end
	return list
end

local function markerPosition(obj)
	if obj:IsA("BasePart") then
		return obj.Position
	end
	local parent = obj.Parent
	if obj:IsA("Attachment") and parent and parent:IsA("BasePart") then
		return (parent.CFrame * obj.CFrame).Position
	end
	return nil
end

-- Vorder- und Hinterkante eines Teils entlang des Laufs (Z im Waffenraum)
local function extentZ(cframe, size)
	local minZ, maxZ = math.huge, -math.huge
	for _, x in { -0.5, 0.5 } do
		for _, y in { -0.5, 0.5 } do
			for _, z in { -0.5, 0.5 } do
				local p = cframe * Vector3.new(size.X * x, size.Y * y, size.Z * z)
				minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
			end
		end
	end
	return minZ, maxZ
end

-- Ein Modell aus Assets.Weapons prüfen und in die Ruhelage bringen. Gibt (Daten oder nil, Bericht) zurück.
local function loadAsset(weaponName, source)
	local report = { Loaded = false, Errors = {}, Warnings = {} }
	local function problem(text)
		table.insert(report.Errors, text)
	end
	local function hint(text)
		table.insert(report.Warnings, text)
	end
	local info = GunModels.Info[weaponName]
	local skins = source:FindFirstChild("Skins")

	-- Marker und sichtbare Teile einsammeln
	local points, pivotPoints, parts = {}, {}, {}
	for _, obj in source:GetDescendants() do
		if skins and (obj == skins or obj:IsDescendantOf(skins)) then
			continue
		end
		local name = cleanName(obj.Name)
		local point = string.match(name, "^Point_(.+)$")
		local pivotGroup = string.match(name, "^Pivot_(.+)$")
		local isMarker = (obj:IsA("BasePart") and (point or pivotGroup))
			or (obj:IsA("Attachment") and (point or pivotGroup or POINTS[name]))
		if isMarker then
			local position = markerPosition(obj)
			if pivotGroup then
				if ANIMATION_GROUPS[pivotGroup] then
					pivotPoints[pivotGroup] = position
				else
					hint("Unbekannter Drehpunkt " .. obj.Name)
				end
			elseif POINTS[point or name] then
				points[point or name] = position
			else
				hint("Unbekannter Marker " .. obj.Name)
			end
		elseif obj:IsA("BasePart") then
			table.insert(parts, obj)
		end
	end
	for _, key in REQUIRED_POINTS do
		if not points[key] then
			problem("Marker Point_" .. key .. " fehlt")
		end
	end
	if info.Long and not points.Stock then
		problem("Marker Point_Stock fehlt (lange Waffe: hinteres Ende der Schulterstütze)")
	end
	if #parts == 0 then
		problem("keine sichtbaren Teile im Modell")
	end
	if #report.Errors > 0 then
		return nil, report
	end

	-- Ausrichtung aus den Markern: Ursprung = Griff, -Z = entlang der Visierlinie nach vorn, +Y = vom Griff
	-- hoch zur Visierlinie
	local grip, rear, front = points.Grip, points.SightRear, points.SightFront
	if (front - rear).Magnitude < 0.05 then
		problem("Point_SightRear und Point_SightFront liegen aufeinander – zusammen legen sie die Visierlinie fest")
		return nil, report
	end
	local forward = (front - rear).Unit
	local toRear = rear - grip
	local upward = toRear - forward * toRear:Dot(forward)
	if upward.Magnitude < 0.05 then
		problem("Point_Grip liegt auf der Visierlinie – der Griff muss unter Kimme und Korn liegen")
		return nil, report
	end
	local up, back = upward.Unit, -forward
	local toWeapon = CFrame.fromMatrix(grip, up:Cross(back), up, back):Inverse()

	local sightRear = toWeapon * rear
	local geometry = {
		SightHeight = sightRear.Y,
		SightZ = sightRear.Z,
		SightFrontZ = (toWeapon * front).Z,
		Muzzle = toWeapon * points.Muzzle,
		Eject = toWeapon * points.Eject,
		RightHand = Vector3.zero,
		LeftHand = toWeapon * points.LeftHand,
	}
	geometry.LeftHandTP = points.LeftHandTP and toWeapon * points.LeftHandTP or geometry.LeftHand
	geometry.Stock = points.Stock and toWeapon * points.Stock or nil

	-- Plausibel?
	if geometry.Muzzle.Z >= geometry.SightZ then
		problem("Mündung liegt hinter der Kimme – sind Point_SightRear und Point_SightFront vertauscht?")
	end
	if geometry.Stock and geometry.Stock.Z <= 0 then
		problem("Point_Stock liegt vor dem Griff – er gehört ans hintere Ende der Schulterstütze")
	end
	if math.abs(geometry.Muzzle.X) > 0.3 then
		hint("Point_Muzzle liegt seitlich neben der Visierlinie")
	end
	if info.Long and geometry.LeftHand.Z >= 0 then
		hint("Point_LeftHand liegt hinter dem Griff – bei langen Waffen hält die linke Hand vorne den Handschutz")
	end
	local minZ, maxZ = math.huge, -math.huge
	for _, part in parts do
		local a, b = extentZ(toWeapon * part.CFrame, part.Size)
		minZ, maxZ = math.min(minZ, a), math.max(maxZ, b)
	end
	local length, expected = maxZ - minZ, blockoutLength[weaponName]
	local lengthText = string.format("%.2f Studs lang, vorgesehen sind etwa %.2f", length, expected)
	if length > expected * 2.5 or length < expected * 0.4 then
		problem("Waffe ist " .. lengthText .. " – stimmt die Einheit beim Import (1 Blender-Einheit = 1 Stud)?")
	elseif length > expected * 1.35 or length < expected * 0.7 then
		hint("Waffe ist " .. lengthText)
	end
	if #parts > MAX_PARTS then
		hint(#parts .. " Einzelteile – Teile ohne eigene Bewegung oder Skin-Zone in Blender zusammenfügen (spart Leistung)")
	end
	if #report.Errors > 0 then
		return nil, report
	end

	-- Vorlage in Ruhelage: flach (alle Teile direkt im Modell), Griff = Ursprung, Attribute wie bei den Quadern
	local template = Instance.new("Model")
	template.Name = weaponName
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.CFrame = CFrame.new()
	handle.Transparency = 1
	handle.Parent = template
	template.PrimaryPart = handle
	local used, entries, groupsFound, hasReticle = { Handle = true }, {}, {}, false
	for _, original in parts do
		local part = original:Clone()
		if not part then
			hint(original.Name .. " lässt sich nicht kopieren (Archivable ist aus)")
			continue
		end
		for _, child in part:GetDescendants() do
			if child:IsA("BasePart") then
				child:Destroy() -- verschachtelte Teile kommen einzeln dran
			end
		end
		local name = cleanName(original.Name)
		local unique, count = name, 1
		while used[unique] do
			count += 1
			unique = name .. "_" .. count
		end
		used[unique] = true
		part.Name = unique
		local rest = toWeapon * original.CFrame
		part.CFrame = rest
		local group, skin, neon, glass, reticle = nil, false, false, false, false
		for _, word in wordsOf(name) do
			if not group and ANIMATION_GROUPS[word] then
				group = word
			end
			skin = skin or word == "Skin"
			neon = neon or word == "Neon"
			glass = glass or word == "Glass"
			reticle = reticle or word == "Reticle"
		end
		if group then
			part:SetAttribute("Group", group)
			groupsFound[group] = true
			if HIDDEN_GROUPS[group] then
				part.Transparency = 1
				part:SetAttribute("Hidden", true)
			end
		end
		if skin then
			part:SetAttribute("Skin", true)
			-- importierte Meshes sind ohne eigene Farbe weiß: dunkle Grundfarbe, bis ein Skin sie überschreibt
			if part:IsA("MeshPart") and part.Color == Color3.new(1, 1, 1) and not part:FindFirstChildOfClass("SurfaceAppearance") then
				part.Color = Color3.fromRGB(42, 42, 46)
			end
		end
		if neon or reticle then
			part.Material = Enum.Material.Neon
		end
		if glass then
			part.Material = Enum.Material.Glass
			if part.Transparency == 0 then
				part.Transparency = GLASS_TRANSPARENCY
			end
		end
		hasReticle = hasReticle or reticle
		part.Parent = template
		table.insert(entries, { Name = unique, CFrame = rest, Group = group, Volume = part.Size.X * part.Size.Y * part.Size.Z })
	end
	if info.Reflex and not hasReticle then
		local dot = Instance.new("Part")
		dot.Name = "Neon_Reticle"
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.new(0.012, 0.012, 0.012)
		dot.Color = RETICLE
		dot.Material = Enum.Material.Neon
		dot.CFrame = CFrame.new(0, geometry.SightHeight, geometry.SightZ)
		dot.Parent = template
		table.insert(entries, { Name = dot.Name, CFrame = dot.CFrame })
	end
	for _, part in template:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = false
			part:SetAttribute("Rest", part.CFrame)
		end
	end
	-- Hauptteil einer Gruppe: das Teil, das genau wie die Gruppe heißt, sonst das größte (z.B. der Kasten des MG,
	-- nicht der Gurt daneben) – an ihm sitzen die Magazin-Aufsätze, ohne Pivot-Marker dreht die Gruppe um seine Mitte
	table.sort(entries, function(a, b)
		local aMain, bMain = a.Name == a.Group, b.Name == b.Group
		if aMain ~= bMain then
			return aMain
		end
		local aVolume, bVolume = a.Volume or 0, b.Volume or 0
		if aVolume ~= bVolume then
			return aVolume > bVolume
		end
		return a.Name < b.Name
	end)
	for _, group in blockoutGroups[weaponName] do
		if not groupsFound[group] then
			hint("Animationsgruppe " .. group .. " fehlt (ein Teil mit dem Wort " .. group .. " im Namen) – die Nachlade-Animation braucht sie")
		end
	end
	local pivotOverride = {}
	for group, position in pivotPoints do
		pivotOverride[group] = CFrame.new(toWeapon * position)
		if not groupsFound[group] then
			hint("Pivot_" .. group .. ": kein Teil dieser Gruppe")
		end
	end
	for _, folder in skins and skins:GetChildren() or {} do
		for _, appearance in folder:GetChildren() do
			if appearance:IsA("SurfaceAppearance") and not template:FindFirstChild(cleanName(appearance.Name)) then
				hint("Skins/" .. folder.Name .. "/" .. appearance.Name .. ": kein Teil mit diesem Namen")
			end
		end
	end
	report.Loaded = true
	return { Template = template, Skins = skins, Geometry = geometry, Entries = entries, Pivots = pivotOverride }, report
end

-- Ordner mit den Modellen: Rojo legt ReplicatedStorage.Assets.Weapons an, die Modelle selbst liegen im Place
local function weaponAssetFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets and RunService:IsClient() then
		assets = ReplicatedStorage:WaitForChild("Assets", 5)
	end
	local weapons = assets and assets:FindFirstChild("Weapons")
	if assets and not weapons and RunService:IsClient() then
		weapons = assets:WaitForChild("Weapons", 5)
	end
	return weapons
end

do
	local folder = weaponAssetFolder()
	for _, source in folder and folder:GetChildren() or {} do
		local weaponName = source.Name
		if not PARTS[weaponName] then
			local names = {}
			for name in PARTS do
				table.insert(names, name)
			end
			table.sort(names)
			assetReport[weaponName] = { Loaded = false, Warnings = {},
				Errors = { "unbekannter Name – Modelle heißen wie die Waffe: " .. table.concat(names, ", ") } }
			continue
		end
		local ok, asset, report = pcall(loadAsset, weaponName, source)
		if not ok then
			asset, report = nil, { Loaded = false, Warnings = {}, Errors = { "Fehler beim Laden: " .. tostring(asset) } }
		end
		assetReport[weaponName] = report
		if asset then
			assetData[weaponName] = { Template = asset.Template, Skins = asset.Skins }
			local info = GunModels.Info[weaponName]
			for key, value in asset.Geometry do
				info[key] = value
			end
			if not asset.Geometry.Stock then
				info.Stock = nil
			end
			indexParts(weaponName, asset.Entries, asset.Pivots)
		end
	end
	-- In Studio steht im Output, was mit jedem Modell los ist
	if RunService:IsStudio() and RunService:IsServer() then
		for weaponName, report in assetReport do
			if report.Loaded then
				print("[Waffenmodelle] " .. weaponName .. ": 3D-Modell geladen")
			else
				warn("[Waffenmodelle] " .. weaponName .. ": 3D-Modell NICHT geladen, es bleibt die Quader-Waffe:\n  - "
					.. table.concat(report.Errors, "\n  - "))
			end
			if #report.Warnings > 0 then
				warn("[Waffenmodelle] " .. weaponName .. ": Hinweise:\n  - " .. table.concat(report.Warnings, "\n  - "))
			end
		end
	end
end

-- Hat die Waffe ein fertiges 3D-Modell (statt der Quader)?
function GunModels.HasAsset(weaponName)
	return assetData[weaponName] ~= nil
end

-- Prüfbericht aller Modelle in Assets.Weapons: [Name] = { Loaded, Errors = { Text }, Warnings = { Text } }
function GunModels.AssetReport()
	return assetReport
end

-- 3D-Modell: Kopie der Vorlage. Skin: Farbe (und ohne Textur auch Material) auf die Skin-Zonen; gibt es im Modell
-- Texturen für diesen Skin (Skins/<Id>), ersetzen sie die SurfaceAppearance der genannten Teile.
local function buildFromAsset(asset, skin)
	local model = asset.Template:Clone()
	if not skin then
		return model
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Skin") then
			part.Color = skin.Color
			if not part:FindFirstChildOfClass("SurfaceAppearance") then
				part.Material = skin.Material
			end
		end
	end
	local textures = asset.Skins and skin.Id and asset.Skins:FindFirstChild(skin.Id)
	for _, appearance in textures and textures:GetChildren() or {} do
		local part = appearance:IsA("SurfaceAppearance") and model:FindFirstChild(cleanName(appearance.Name))
		if part and part:IsA("BasePart") then
			for _, old in part:GetChildren() do
				if old:IsA("SurfaceAppearance") then
					old:Destroy()
				end
			end
			appearance:Clone().Parent = part
		end
	end
	return model
end

-- Liefert ein Model mit PrimaryPart "Handle" (Griffpunkt). Alle Parts sind verankert und ohne Kollision.
-- Teile haben das Attribut "Group" (Animationsgruppe) bzw. "Hidden" (nur in Animationen sichtbar).
-- attachments (optional) = ausgerüstete Aufsätze, werden als Teile angebaut.
function GunModels.Build(weaponName, skin, attachments)
	local asset = assetData[weaponName]
	local model = asset and buildFromAsset(asset, skin) or buildBlockout(weaponName, skin)
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
