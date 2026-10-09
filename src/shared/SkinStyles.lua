-- SkinStyles (ModuleScript)
-- Daten der Effekt-Skins mit eigenen Partikeln, Leuchtspur, Einschlag und Kill-Finisher (SkinEffects baut daraus
-- die Effekte). Werte 1:1 aus dem Skin-Paket (art/sources/Skins/<Name>/Werte.md).
--
-- Emitter: Image = Bild (Attribut FX_<Image> am Skin-Ordner der Waffe, sonst Roblox-Standardbild Fallback),
--   Rate/Emit = Zahl oder { TP, FP } (TP = Third-Person/andere, FP = eigene Waffe vor der Kamera; ADS = beim Zielen),
--   Kurven als { { Zeit, Wert }, ... }, Farben als { { Zeit, { R, G, B } }, ... }, Bereiche als { Min, Max }.

local SkinStyles = {}

local WHITE = { 230, 250, 255 } -- Eisweiß (Glühkern)
local CYAN = { 70, 220, 255 }
local SAPPHIRE = { 52, 110, 245 }
local VIOLET = { 140, 90, 240 }
local MAGENTA = { 235, 80, 200 }
local ROSE = { 255, 140, 200 }
local LIGHT = { 110, 170, 255 }

SkinStyles.Splitterlicht = {
	-- Glühen der Adern (SurfaceAppearance.EmissiveStrength) und Waffenlicht atmen gemeinsam (Sinus, kein Flackern)
	Glow = { Tint = { 255, 255, 255 }, Min = 1.6, Max = 2.4, Period = 3 },
	Light = { Color = LIGHT, TP = { 0.6, 1, Range = 5 }, FP = { 0.35, 0.55, Range = 3 } },
	-- unsichtbare Box unter dem Verschlussgehäuse (Griff bis Magazinschacht), Oberkante unter der Visierlinie:
	-- nur hier entstehen die Dauer-Partikel – nie auf der Schiene, im Visier oder in der Bildmitte
	Box = { Size = { 0.3, 0.3, 1.5 }, Offset = { 0, 0.22, -0.45 } },
	Weapon = {
		{ -- E1 Kristallglitzer
			Image = "Glitzer", Rate = { 4, 2 }, Lifetime = { 0.35, 0.6 }, Speed = { 0, 0 }, Spread = { 0, 0 },
			Direction = "Top", Size = { { 0, 0 }, { 0.25, 0.22 }, { 1, 0 } },
			Transparency = { { 0, 0.1 }, { 0.6, 0.2 }, { 1, 1 } }, Color = { { 0, WHITE }, { 0.5, CYAN }, { 1, ROSE } },
			LightEmission = 1, LightInfluence = 0, Brightness = 2.5, Shape = "Box", Rotation = { 0, 45 },
			Locked = true, ZOffset = 0.1,
		},
		{ -- E2 Prismensplitter
			Image = "Splitter", Rate = { 2.5, 1.2 }, Lifetime = { 1.2, 1.8 }, Speed = { 0.15, 0.35 }, Spread = { 60, 60 },
			Direction = "Bottom", Size = { { 0, 0 }, { 0.15, 0.09 }, { 0.8, 0.08 }, { 1, 0 } },
			Transparency = { { 0, 0.3 }, { 0.2, 0.1 }, { 0.75, 0.25 }, { 1, 1 } },
			Color = { { 0, CYAN }, { 0.5, VIOLET }, { 1, ROSE } }, LightEmission = 0.6, LightInfluence = 0.4,
			Brightness = 1.5, Drag = 0.8, Acceleration = { 0, -0.25, 0 }, Shape = "Box", Rotation = { 0, 360 },
			RotSpeed = { -90, 90 },
		},
		{ -- E3 Prismenstaub
			Image = "Staub", Rate = { 5, 2.5 }, Lifetime = { 1, 1.6 }, Speed = { 0.05, 0.15 }, Spread = { 180, 180 },
			Direction = "Bottom", Size = { { 0, 0 }, { 0.2, 0.04 }, { 1, 0 } },
			Transparency = { { 0, 0.4 }, { 0.3, 0.2 }, { 1, 1 } }, Color = { { 0, WHITE }, { 0.5, CYAN }, { 1, VIOLET } },
			LightEmission = 1, LightInfluence = 0, Brightness = 2, Drag = 1, Acceleration = { 0, -0.05, 0 },
			Shape = "Box",
		},
	},
	-- pro Schuss an der Mündung (kein Licht-Blitz: flackert sonst bei Dauerfeuer); ersetzt das normale Mündungsfeuer
	Muzzle = {
		{ -- S1 Mündungsblitz
			Image = "Muendungsblitz", Emit = { 2, 1 }, Lifetime = { 0.05, 0.08 }, Speed = { 0, 0 }, Direction = "Front",
			Size = { { 0, 0.35 }, { 0.4, 0.6 }, { 1, 0.3 } }, SizeFP = { { 0, 0.2 }, { 0.4, 0.35 }, { 1, 0.17 } },
			Transparency = { { 0, 0 }, { 0.6, 0.3 }, { 1, 1 } }, TransparencyFP = { { 0, 0.3 }, { 0.6, 0.5 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 0.4, CYAN }, { 1, MAGENTA } }, LightEmission = 1, LightInfluence = 0,
			Brightness = { 3, 2 }, Rotation = { 0, 360 }, Locked = true,
		},
		{ -- S2a Prismaring (Ego: nur jeder 2. Schuss)
			Image = "Prismaring", Emit = { 1, 1 }, EveryFP = 2, Lifetime = { 0.12, 0.12 }, Speed = { 3, 3 },
			Direction = "Front", Size = { { 0, 0.15 }, { 1, 0.55 } }, SizeFP = { { 0, 0.1 }, { 1, 0.33 } },
			Transparency = { { 0, 0.1 }, { 0.5, 0.4 }, { 1, 1 } }, TransparencyFP = { { 0, 0.35 }, { 0.5, 0.6 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 0.5, VIOLET }, { 1, ROSE } }, LightEmission = 1, LightInfluence = 0,
			Brightness = { 2, 1.5 }, Drag = 4, Rotation = { 0, 60 }, Orientation = "VelocityPerpendicular",
		},
		{ -- S2b Kristallfunken
			Image = "Staub", Emit = { 4, 2 }, Lifetime = { 0.08, 0.14 }, Speed = { 6, 10 }, Spread = { 18, 18 },
			Direction = "Front", Size = { { 0, 0.05 }, { 1, 0 } }, SizeFP = { { 0, 0.04 }, { 1, 0 } },
			Transparency = { { 0, 0 }, { 1, 1 } }, TransparencyFP = { { 0, 0.2 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 1, ROSE } }, LightEmission = 1, LightInfluence = 0, Brightness = { 2.5, 2 },
			Drag = 6, Orientation = "VelocityParallel",
		},
	},
	-- S6 mit Schalldämpfer: Gegner sehen nichts, man selbst nur einen Kristallhauch
	Silenced = {
		{
			Image = "Staub", Emit = { 2, 2 }, Lifetime = { 0.06, 0.1 }, Speed = { 1, 2 }, Spread = { 25, 25 },
			Direction = "Front", Size = { { 0, 0.04 }, { 1, 0 } }, Transparency = { { 0, 0.2 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 1, CYAN } }, LightEmission = 1, LightInfluence = 0, Brightness = 1.5, Drag = 2,
		},
	},
	-- S3 Leuchtspur (Beam von der Mündung zum Treffer); ersetzt die normale Leuchtspur
	Tracer = {
		Image = "Leuchtspur",
		Color = { { 0, WHITE }, { 0.25, CYAN }, { 0.7, VIOLET }, { 1, ROSE } },
		TP = { Transparency = { { 0, 0.1 }, { 0.6, 0.25 }, { 1, 0.55 } }, Width = { 0.1, 0.04 }, Hold = 0.06, Fade = 0.08 },
		FP = { Transparency = { { 0, 0.35 }, { 0.7, 0.6 }, { 1, 1 } }, Width = { 0.06, 0.02 }, Hold = 0.04, Fade = 0.06 },
		Brightness = 2,
	},
	-- S4 Einschlag (max. 0.4 s), zusätzlich zum normalen Einschlag
	Impact = {
		{ -- S4a Blitz
			Image = "Einschlag", Emit = 1, Lifetime = { 0.1, 0.14 }, Speed = { 0, 0 }, Direction = "Top",
			Size = { { 0, 0.3 }, { 0.3, 0.7 }, { 1, 0.5 } }, Transparency = { { 0, 0 }, { 0.5, 0.3 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 0.5, CYAN }, { 1, VIOLET } }, LightEmission = 1, LightInfluence = 0,
			Brightness = 2.5, Rotation = { 0, 360 }, Locked = true,
		},
		{ -- S4b Splitter
			Image = "Splitter", Emit = 6, Lifetime = { 0.25, 0.4 }, Speed = { 4, 8 }, Spread = { 55, 55 },
			Direction = "Top", Size = { { 0, 0.12 }, { 1, 0.04 } }, Transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } },
			Color = { { 0, CYAN }, { 0.5, VIOLET }, { 1, ROSE } }, LightEmission = 0.7, LightInfluence = 0.3,
			Brightness = 1.8, Drag = 5, Acceleration = { 0, -12, 0 }, Rotation = { 0, 360 }, RotSpeed = { -360, 360 },
		},
		{ -- S4c Glitzer
			Image = "Glitzer", Emit = 2, Lifetime = { 0.2, 0.3 }, Speed = { 1, 2 }, Spread = { 40, 40 },
			Direction = "Top", Size = { { 0, 0 }, { 0.3, 0.2 }, { 1, 0 } }, Transparency = { { 0, 0 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 1, ROSE } }, LightEmission = 1, LightInfluence = 0, Brightness = 2.5,
			Rotation = { 0, 45 },
		},
	},
	-- S5 Laufglühen bei Dauerfeuer
	Heat = { PerShot = 0.06, Delay = 0.25, Cool = 0.5, Smooth = 8, Cold = LIGHT, Hot = ROSE, Glow = 3,
		Brightness = { 0.2, 1.2 }, FPFactor = 0.6, Range = { 3, 2 } },
	-- K Kill-Finisher „Kristallbruch“ (1.5 s, nur an der Stelle des Gegners)
	Finisher = {
		Highlight = { Fill = LIGHT, Outline = WHITE, OutlineTransparency = 0.35 },
		Light = { Color = LIGHT, Brightness = 1.5, Range = 8 },
		Ring = { -- K2 ab 0 s an den Füßen
			Image = "Prismaring", Emit = 1, Lifetime = { 0.8, 0.8 }, Speed = { 0.01, 0.01 }, Direction = "Top",
			Size = { { 0, 1 }, { 1, 6 } }, Transparency = { { 0, 0.25 }, { 0.6, 0.5 }, { 1, 1 } },
			Color = { { 0, CYAN }, { 1, VIOLET } }, LightEmission = 1, LightInfluence = 0, Brightness = 1.5,
			Rotation = { 0, 60 }, Orientation = "VelocityPerpendicular", Locked = true,
		},
		Shine = { -- K4 ab 0.1 s im Körper
			Image = "Glitzer", Emit = 10, Lifetime = { 0.3, 0.5 }, Speed = { 0, 0 }, Direction = "Top",
			Size = { { 0, 0 }, { 0.3, 0.35 }, { 1, 0 } }, Transparency = { { 0, 0 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 1, CYAN } }, LightEmission = 1, LightInfluence = 0, Brightness = 2.5,
			Shape = "Box", Rotation = { 0, 45 }, Locked = true,
		},
		Shatter = { -- K6 ab 0.35 s
			Image = "Splitter", Emit = 24, EmitLow = 12, Lifetime = { 0.6, 1 }, Speed = { 4, 7 }, Spread = { 180, 180 },
			Direction = "Top", Size = { { 0, 0.25 }, { 0.7, 0.2 }, { 1, 0 } },
			Transparency = { { 0, 0 }, { 0.6, 0.2 }, { 1, 1 } }, Color = { { 0, CYAN }, { 0.5, VIOLET }, { 1, ROSE } },
			LightEmission = 0.6, LightInfluence = 0.3, Brightness = 2, Drag = 3.5, Acceleration = { 0, 1.5, 0 },
			Shape = "Box", Rotation = { 0, 360 }, RotSpeed = { -240, 240 },
		},
		Core = { -- K7 ab 0.35 s an der Brust
			Image = "Einschlag", Emit = 1, Lifetime = { 0.25, 0.25 }, Speed = { 0, 0 }, Direction = "Top",
			Size = { { 0, 1.5 }, { 0.4, 3 }, { 1, 2.5 } }, Transparency = { { 0, 0.3 }, { 0.5, 0.6 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 1, VIOLET } }, LightEmission = 1, LightInfluence = 0, Brightness = 1.5,
			Rotation = { 0, 360 }, Locked = true,
		},
		Emblem = { -- K8 ab 0.6 s, steigt auf
			Image = "Emblem", Emit = 1, Lifetime = { 0.9, 0.9 }, Speed = { 1.5, 1.5 }, Direction = "Top",
			Size = { { 0, 0.5 }, { 0.25, 2.2 }, { 0.8, 2.2 }, { 1, 2.6 } },
			Transparency = { { 0, 1 }, { 0.2, 0.1 }, { 0.75, 0.3 }, { 1, 1 } },
			Color = { { 0, { 255, 255, 255 } }, { 1, { 255, 255, 255 } } }, LightEmission = 0.8, LightInfluence = 0,
			Brightness = 1.6, Drag = 1, Orientation = "FacingCameraWorldUp",
		},
		Dust = { -- K9 ab 0.6 s
			Image = "Staub", Emit = 14, EmitLow = 7, Lifetime = { 0.6, 0.9 }, Speed = { 0.5, 1.5 }, Spread = { 25, 25 },
			Direction = "Top", Size = { { 0, 0.08 }, { 1, 0 } }, Transparency = { { 0, 0.2 }, { 1, 1 } },
			Color = { { 0, WHITE }, { 0.5, CYAN }, { 1, ROSE } }, LightEmission = 1, LightInfluence = 0, Brightness = 2,
			Drag = 0.5, Shape = "Box",
		},
	},
}

-- Fallback-Bilder, solange im Skin-Ordner keine eigenen Bilder (Attribute FX_...) eingetragen sind
SkinStyles.Fallback = {
	Glitzer = "rbxasset://textures/particles/sparkles_main.dds",
	Splitter = "rbxasset://textures/particles/sparkles_main.dds",
	Staub = "rbxasset://textures/particles/sparkles_main.dds",
	Muendungsblitz = "rbxasset://textures/particles/sparkles_main.dds",
	Prismaring = "rbxasset://textures/particles/sparkles_main.dds",
	Einschlag = "rbxasset://textures/particles/sparkles_main.dds",
	Emblem = "rbxasset://textures/particles/sparkles_main.dds",
	Leuchtspur = "",
}

return SkinStyles
