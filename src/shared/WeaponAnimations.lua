-- WeaponAnimations (ModuleScript)
-- Nachlade- und Schuss-Animationen aller Waffen als Keyframes. Dieselben Daten bewegen die Waffe vor der
-- eigenen Kamera (ViewModel) und die Waffe samt Armen der Charaktere in der Third-Person (CharacterPose).
--
-- Zeiten sind 0..1 (Anteil der Animationsdauer), Positionen in Modell-Einheiten der Waffe (Griffpunkt =
-- Ursprung, siehe GunModels). Spuren:
--   Gun    = Versatz der ganzen Waffe (dreht um den Griff)
--   Hand   = linke Hand im Waffenraum: CFrame oder { Gruppe, Versatz } (folgt dann z.B. dem Magazin)
--   Groups = Bewegung von Teilgruppen (Magazin, Schlitten, ...) in Achsen der Waffe um ihren Mittelpunkt
--   Hide   = Gruppe in diesen Zeiträumen unsichtbar, Show = sonst unsichtbare Gruppe sichtbar
--   Events = { Zeit, "Sound", Name } | { Zeit, "Drop", Gruppe } (fallende Kopie) | { Zeit, "Eject" } (Hülse)
--            | { Zeit, "Spill", Gruppe, Anzahl } (Hülsen fallen aus der Gruppe)
-- Keyframe: { Zeit, Wert, Übergang } – Übergang zum Keyframe: "In", "Out", "InOut" (sonst linear)

local Shared = script.Parent
local GunModels = require(Shared.GunModels)
local WeaponConfig = require(Shared.WeaponConfig)

local WeaponAnimations = {}

local I = CFrame.new()

-- Versatz und Drehung (Grad) als CFrame
local function cf(x, y, z, rx, ry, rz)
	return CFrame.new(x or 0, y or 0, z or 0) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

local function restHand(weaponName)
	return CFrame.new(GunModels.Info[weaponName].LeftHand)
end

-- ---------- Nachladen: Magazinwaffen ----------

-- Gemeinsamer Ablauf für Magazinwaffen: kippen, Magazin raus (fällt), neues rein, Schlag, Spannen.
-- p = Werte der Waffe
local function magazineReload(weaponName, p)
	local LH = restHand(weaponName)
	local GT, GT2 = p.Tilt, p.Tilt2
	local grab = { "Magazine", p.MagGrab }
	return {
		Gun = {
			{ 0.00, I },
			{ 0.12, GT, "Out" },
			{ 0.26, GT },
			{ 0.29, GT * cf(0, 0.03, 0), "Out" },
			{ 0.33, GT, "InOut" },
			{ 0.56, GT },
			{ 0.60, GT * cf(0, 0.07, -0.02, 4, 0, 0), "Out" },
			{ 0.66, GT, "InOut" },
			{ 0.74, GT2, "InOut" },
			{ 0.82, GT2 * cf(0, 0, 0.06, -3, 0, 0), "Out" },
			{ 0.88, GT2, "InOut" },
			{ 1.00, I, "InOut" },
		},
		Groups = {
			Magazine = {
				{ 0.16, I },
				{ 0.28, p.MagOut, "In" },
				{ 0.40, cf(-0.5, -1.4, 0.3, 0, 0, 20) },
				{ 0.50, p.MagOut * cf(0, -0.05, 0), "Out" },
				{ 0.58, I, "In" },
			},
			Bolt = {
				{ 0.76, I },
				{ 0.82, p.BoltPull, "Out" },
				{ 0.86, I, "In" },
			},
		},
		Hand = {
			{ 0.00, LH },
			{ 0.12, grab, "InOut" },
			{ 0.28, grab },
			{ 0.36, cf(-0.4, -1.3, 0.3), "In" },
			{ 0.42, grab, "Out" },
			{ 0.58, grab },
			{ 0.62, { "Magazine", p.MagGrab * cf(0, -0.15, 0) }, "Out" },
			{ 0.72, p.BoltReach, "InOut" },
			{ 0.76, { "Bolt", p.BoltGrab } },
			{ 0.82, { "Bolt", p.BoltGrab } },
			{ 0.88, p.BoltReach, "Out" },
			{ 1.00, LH, "InOut" },
		},
		Hide = { Magazine = { { 0.28, 0.40 } } },
		Events = {
			{ 0.24, "Sound", "MagOut" },
			{ 0.28, "Drop", "Magazine" },
			{ 0.57, "Sound", "MagIn" },
			{ 0.81, "Sound", "Bolt" },
		},
	}
end

local RELOADS = {}

RELOADS.Rifle = function()
	return magazineReload("Rifle", {
		Tilt = cf(0.05, -0.12, 0.1, 10, 20, -30),
		Tilt2 = cf(0.02, -0.06, 0.05, 6, 10, -12),
		MagOut = cf(0, -0.45, 0.04, -6, 0, 0),
		MagGrab = cf(0, -0.31, 0.02),
		BoltPull = cf(0, 0, 0.28),
		BoltGrab = cf(-0.12, 0.05, 0.02),
		BoltReach = cf(-0.15, 0.62, 0.4),
	})
end

RELOADS.SMG = function()
	local anim = magazineReload("SMG", {
		Tilt = cf(0.05, -0.1, 0.08, 8, 15, -25),
		Tilt2 = cf(0, -0.05, 0.05, 6, -10, 15), -- andersherum kippen: Spanngriff links vorne
		MagOut = cf(0, -0.5, 0.03, -4, 0, 0),
		MagGrab = cf(0, -0.37, 0),
		BoltPull = cf(0, 0, 0.22),
		BoltGrab = cf(-0.06, 0, 0.03),
		BoltReach = cf(-0.3, 0.45, -0.5),
	})
	-- "Schlag" auf den Spanngriff zum Schluss
	table.insert(anim.Events, { 0.86, "Sound", "Slide" })
	return anim
end

RELOADS.DMR = function()
	local anim = magazineReload("DMR", {
		Tilt = cf(0.05, -0.12, 0.1, 8, 18, -28),
		Tilt2 = cf(0, -0.05, 0.05, 5, 8, -15),
		MagOut = cf(0, -0.4, 0.03, -4, 0, 0),
		MagGrab = cf(0, -0.22, 0.02),
		BoltPull = cf(0, 0, 0.3),
		BoltGrab = cf(0.08, 0.04, 0),
		BoltReach = cf(0.1, 0.65, 0.2),
	})
	table.insert(anim.Events, { 0.86, "Sound", "Slide" })
	return anim
end

RELOADS.LMG = function()
	local LH = restHand("LMG")
	local GT = cf(0, -0.1, 0.1, 10, 12, -15)
	local GT2 = cf(0, -0.06, 0.05, 5, -6, 8)
	local OPEN = cf(0, 0, 0.4) * cf(0, 0, 0, 70, 0, 0) * cf(0, 0, -0.4) -- Deckel klappt um seine Hinterkante
	local box = { "Magazine", cf(-0.25, 0, 0) }
	local lid = { "Cover", cf(0, 0.06, -0.36) }
	local bolt = { "Bolt", cf(0.06, 0.02, 0) }
	return {
		Gun = {
			{ 0.00, I },
			{ 0.10, GT, "Out" },
			{ 0.34, GT },
			{ 0.36, GT * cf(0, 0.03, 0), "Out" },
			{ 0.40, GT },
			{ 0.62, GT },
			{ 0.65, GT * cf(0, 0.06, 0, 3, 0, 0), "Out" },
			{ 0.70, GT },
			{ 0.78, GT * cf(0, -0.03, 0, -2, 0, 0), "Out" },
			{ 0.82, GT2, "InOut" },
			{ 0.90, GT2 * cf(0, 0, 0.05), "Out" },
			{ 0.94, GT2 },
			{ 1.00, I, "InOut" },
		},
		Groups = {
			Cover = {
				{ 0.10, I },
				{ 0.18, OPEN, "Out" },
				{ 0.70, OPEN },
				{ 0.78, I, "In" },
			},
			Magazine = {
				{ 0.22, I },
				{ 0.34, cf(0.05, -0.55, 0.05, 0, 0, -10), "In" },
				{ 0.46, cf(-0.6, -1.5, 0.3) },
				{ 0.56, cf(0, -0.5, 0.05), "Out" },
				{ 0.64, I, "In" },
			},
			Bolt = {
				{ 0.82, I },
				{ 0.88, cf(0, 0, 0.3), "Out" },
				{ 0.92, I, "In" },
			},
		},
		Hand = {
			{ 0.00, LH },
			{ 0.08, lid, "InOut" },
			{ 0.18, lid },
			{ 0.24, box, "InOut" },
			{ 0.34, box },
			{ 0.40, cf(-0.5, -1.5, 0.3), "In" },
			{ 0.47, box, "Out" },
			{ 0.64, box },
			{ 0.68, lid, "InOut" },
			{ 0.78, lid },
			{ 0.82, bolt, "InOut" },
			{ 0.88, bolt },
			{ 0.94, cf(-0.1, 0.3, -1.0), "Out" },
			{ 1.00, LH, "InOut" },
		},
		Hide = { Magazine = { { 0.34, 0.46 } } },
		Events = {
			{ 0.17, "Sound", "Bolt" },
			{ 0.30, "Sound", "MagOut" },
			{ 0.34, "Drop", "Magazine" },
			{ 0.63, "Sound", "MagIn" },
			{ 0.77, "Sound", "Slide" },
			{ 0.87, "Sound", "Bolt" },
		},
	}
end

RELOADS.Pistol = function()
	local LH = restHand("Pistol")
	local GT = cf(0, -0.05, 0.1, 15, 15, -20)
	local GT2 = cf(0, -0.03, 0.05, 5, 5, -10)
	local mag = { "Magazine", cf(0, -0.27, 0.05) }
	local slide = { "Slide", cf(-0.1, 0.06, 0.32) }
	local out = cf(0, -0.42, 0.11)
	return {
		Gun = {
			{ 0.00, I },
			{ 0.10, GT, "Out" },
			{ 0.20, GT * cf(0, 0.02, 0), "Out" },
			{ 0.25, GT },
			{ 0.56, GT },
			{ 0.60, GT * cf(0, 0.05, 0, 3, 0, 0), "Out" },
			{ 0.64, GT },
			{ 0.68, GT2, "InOut" },
			{ 0.74, GT2 * cf(0, 0, 0.04), "Out" },
			{ 0.80, GT2 },
			{ 1.00, I, "InOut" },
		},
		Groups = {
			Magazine = {
				{ 0.12, I },
				{ 0.22, out, "In" },
				{ 0.36, cf(-0.4, -1.2, 0.3) },
				{ 0.48, out, "Out" },
				{ 0.58, I, "In" },
			},
			Slide = {
				{ 0.68, I },
				{ 0.73, cf(0, 0, 0.18), "Out" },
				{ 0.77, I, "In" },
			},
		},
		Hand = {
			{ 0.00, LH },
			{ 0.12, cf(-0.3, -0.7, 0.3), "InOut" },
			{ 0.36, mag, "Out" },
			{ 0.58, mag },
			{ 0.62, { "Magazine", cf(0, -0.37, 0.05) }, "Out" },
			{ 0.67, slide, "InOut" },
			{ 0.73, slide },
			{ 0.80, cf(-0.2, -0.1, 0.1), "Out" },
			{ 1.00, LH, "InOut" },
		},
		Hide = { Magazine = { { 0.22, 0.36 } } },
		Events = {
			{ 0.18, "Sound", "MagOut" },
			{ 0.22, "Drop", "Magazine" },
			{ 0.57, "Sound", "MagIn" },
			{ 0.73, "Sound", "Slide" },
		},
	}
end

RELOADS.Revolver = function()
	local LH = restHand("Revolver")
	local GT = cf(-0.05, 0, 0.1, 25, 20, -15)     -- Lauf hoch: Hülsen fallen heraus
	local GT2 = cf(-0.05, -0.05, 0.08, -10, 15, -25) -- Lauf runter: Schnelllader einsetzen
	local SWING = cf(-0.28, -0.1, 0, 0, 0, 25)     -- Trommel nach links ausgeschwenkt
	local cylinder = { "Cylinder", cf(-0.18, 0, 0) }
	local loader = { "Loader", cf(0, -0.05, 0.12) }
	return {
		Gun = {
			{ 0.00, I },
			{ 0.08, GT, "Out" },
			{ 0.24, GT * cf(0, 0.06, 0, 15, 0, 0), "Out" },
			{ 0.32, GT },
			{ 0.40, GT2, "InOut" },
			{ 0.72, GT2 },
			{ 0.78, GT, "InOut" },
			{ 0.86, GT * cf(0, 0.03, 0), "Out" },
			{ 0.90, GT },
			{ 1.00, I, "InOut" },
		},
		Groups = {
			Cylinder = {
				{ 0.08, I },
				{ 0.16, SWING, "Out" },
				{ 0.78, SWING },
				{ 0.86, I, "In" },
			},
			Loader = {
				{ 0.42, cf(-0.3, -1.2, 0.5) },
				{ 0.58, cf(0, 0, 0.1), "Out" },
				{ 0.66, I, "In" },
				{ 0.70, cf(-0.2, -0.6, 0.3), "In" },
				{ 1.00, I }, -- unsichtbar zurück in Ruhe
			},
		},
		Hand = {
			{ 0.00, LH },
			{ 0.08, cylinder, "InOut" },
			{ 0.16, cylinder },
			{ 0.24, { "Cylinder", cf(-0.1, -0.1, 0.25) } },
			{ 0.32, cf(-0.3, -0.9, 0.4), "InOut" },
			{ 0.42, loader, "Out" },
			{ 0.70, loader },
			{ 0.74, cylinder, "InOut" },
			{ 0.86, cylinder },
			{ 1.00, LH, "InOut" },
		},
		Show = { Loader = { { 0.42, 0.70 } } },
		Events = {
			{ 0.15, "Sound", "Cylinder" },
			{ 0.26, "Spill", "Cylinder", 6 },
			{ 0.26, "Sound", "MagOut" },
			{ 0.66, "Sound", "MagIn" },
			{ 0.86, "Sound", "Cylinder" },
		},
	}
end

-- ---------- Nachladen: Schrotflinte (Patrone für Patrone) ----------

-- start/per/finish = Sekunden zum Ansetzen, pro Patrone, zum Durchladen
local function shotgunReload(shells, start, per, finish)
	local total = start + shells * per + finish
	local LH = restHand("Shotgun")
	local GT = cf(0.05, -0.05, 0.1, 10, 15, -35)
	local GT3 = cf(0, -0.05, 0.05, 4, 5, -10)
	local FAR = cf(-0.2, -0.45, 0.15) -- Patrone kommt von unten links
	local IN = cf(0, 0.12, -0.25)     -- ins Gehäuse geschoben
	local shell = { "Shell", cf(-0.02, -0.08, 0.06) }
	local pump = { "Pump", cf(-0.02, -0.12, 0) }
	local gun = { { 0, I }, { start / total, GT, "Out" } }
	local shellTrack = {}
	local hand = { { 0, LH } }
	local show = {}
	local events = {}
	for i = 1, shells do
		local s = (start + (i - 1) * per) / total
		local p = per / total
		table.insert(gun, { s + 0.65 * p, GT * cf(0, 0.025, 0), "Out" })
		table.insert(gun, { s + p, GT, "InOut" })
		-- Patrone: von unten an die Ladeklappe, hineinschieben, dann (unsichtbar) zur nächsten
		table.insert(shellTrack, { s, FAR })
		table.insert(shellTrack, { s + 0.45 * p, I, "Out" })
		table.insert(shellTrack, { s + 0.7 * p, IN, "In" })
		table.insert(hand, { s, shell, "InOut" })
		table.insert(hand, { s + 0.7 * p, shell })
		table.insert(show, { s, s + 0.7 * p })
		table.insert(events, { s + 0.65 * p, "Sound", "Shell" })
	end
	table.insert(shellTrack, { 1, I })
	-- Zum Schluss einmal durchladen
	local f = finish / total
	table.insert(gun, { 1 - f * 0.6, GT3, "InOut" })
	table.insert(gun, { 1, I, "InOut" })
	table.insert(hand, { 1 - f * 0.85, pump, "InOut" })
	table.insert(hand, { 1, pump })
	table.insert(events, { 1 - f * 0.45, "Sound", "Pump" })
	table.insert(events, { 1 - f * 0.45, "Eject" })
	table.insert(events, { 1 - f * 0.15, "Sound", "Pump" })
	return {
		Gun = gun,
		Groups = {
			Shell = shellTrack,
			Pump = {
				{ 1 - f * 0.8, I },
				{ 1 - f * 0.45, cf(0, 0, 0.32), "Out" },
				{ 1 - f * 0.15, I, "In" },
			},
		},
		Hand = hand,
		Show = { Shell = show },
		Events = events,
	}, total
end

-- ---------- Schuss-Animationen ----------

local FIRES = {
	Pistol = {
		Duration = 0.13,
		Groups = { Slide = { { 0, I }, { 0.3, cf(0, 0, 0.2), "Out" }, { 1, I, "In" } } },
		Events = { { 0.3, "Eject" } },
	},
	DMR = {
		Duration = 0.15,
		Groups = { Bolt = { { 0, I }, { 0.35, cf(0, 0, 0.12), "Out" }, { 1, I } } },
		Events = { { 0.2, "Eject" } },
	},
	Shotgun = {
		Duration = WeaponConfig.Get("Shotgun").FireDelay * 0.85,
		Gun = {
			{ 0, I },
			{ 0.12, cf(0, 0, 0.03, 3, 0, 0), "Out" },
			{ 0.45, cf(0, -0.03, 0.03, -2, 0, 4), "InOut" },
			{ 0.75, I, "InOut" },
		},
		Groups = { Pump = { { 0.2, I }, { 0.45, cf(0, 0, 0.32), "Out" }, { 0.72, I, "In" } } },
		Hand = { { 0, { "Pump", cf(-0.02, -0.12, 0) } }, { 1, { "Pump", cf(-0.02, -0.12, 0) } } },
		Events = { { 0.45, "Sound", "Pump" }, { 0.45, "Eject" }, { 0.7, "Sound", "Pump" } },
	},
	Rifle = { Duration = 0.05, Events = { { 0, "Eject" } } },
	SMG = { Duration = 0.05, Events = { { 0, "Eject" } } },
	LMG = { Duration = 0.05, Events = { { 0, "Eject" } } },
}

local reloadCache = {}

-- Nachlade-Animation. duration = Nachladezeit (mit Upgrades), shells = Patronen (nur Schrotflinte).
-- Gibt (Animation, tatsächliche Dauer in Sekunden) zurück.
function WeaponAnimations.Reload(weaponName, duration, shells)
	local cfg = WeaponConfig.Get(weaponName)
	if cfg and cfg.ShellReload then
		local start, per, finish = WeaponConfig.ShellTiming(cfg, duration)
		shells = math.max(1, shells or cfg.MagazineSize)
		return shotgunReload(shells, start, per, finish)
	end
	local anim = reloadCache[weaponName]
	if not anim and RELOADS[weaponName] then
		anim = RELOADS[weaponName]()
		reloadCache[weaponName] = anim
	end
	return anim, duration
end

-- Schuss-Animation (oder nil). Dauer steht in anim.Duration (Sekunden).
function WeaponAnimations.Fire(weaponName)
	return FIRES[weaponName]
end

-- ---------- Abspielen ----------

local function ease(alpha, style)
	if style == "Out" then
		return math.sin(alpha * math.pi / 2)
	elseif style == "In" then
		return 1 - math.cos(alpha * math.pi / 2)
	elseif style == "InOut" then
		return (1 - math.cos(alpha * math.pi)) / 2
	end
	return alpha
end

-- Wert einer Spur zur Zeit t. resolve wandelt Keyframe-Werte in CFrames um (für Hand-Anhänge).
local function sample(track, t, resolve)
	local count = #track
	if count == 0 then
		return nil
	end
	if t <= track[1][1] then
		return resolve(track[1][2])
	end
	if t >= track[count][1] then
		return resolve(track[count][2])
	end
	for i = 1, count - 1 do
		local a, b = track[i], track[i + 1]
		if t < b[1] then
			local alpha = (t - a[1]) / math.max(b[1] - a[1], 1e-6)
			return resolve(a[2]):Lerp(resolve(b[2]), ease(alpha, b[3]))
		end
	end
	return resolve(track[count][2])
end

local function identity(value)
	return value
end

local function inside(intervals, t)
	for _, range in intervals do
		if t >= range[1] and t < range[2] then
			return true
		end
	end
	return false
end

-- Pose der Animation zur Zeit t (0..1) für eine Waffe:
-- { Gun = CFrame, Hand = CFrame oder nil (linke Hand im Waffenraum), Groups = { [Gruppe] = Versatz },
--   Visible = { [Gruppe] = true/false } } – alles in Modell-Einheiten
function WeaponAnimations.Sample(anim, weaponName, t)
	local pose = { Gun = I, Groups = {}, Visible = {} }
	if anim.Gun then
		pose.Gun = sample(anim.Gun, t, identity)
	end
	for group, track in anim.Groups or {} do
		pose.Groups[group] = sample(track, t, identity)
	end
	if anim.Hand then
		pose.Hand = sample(anim.Hand, t, function(value)
			if typeof(value) == "CFrame" then
				return value
			end
			-- An einer Gruppe: Hauptteil der Gruppe (bewegt) * Griff-Versatz, Achsen der Waffe
			local group, offset = value[1], value[2]
			local pivot = GunModels.GroupPivot(weaponName, group)
			if not pivot then
				return restHand(weaponName)
			end
			return GunModels.GroupTransform(weaponName, group, pose.Groups[group], 1) * CFrame.new(pivot.Position) * offset
		end)
	end
	for group, intervals in anim.Hide or {} do
		pose.Visible[group] = not inside(intervals, t)
	end
	for group, intervals in anim.Show or {} do
		pose.Visible[group] = inside(intervals, t)
	end
	return pose
end

-- Ereignisse mit Zeit in (from, to] (from < 0 = auch die bei 0), in zeitlicher Reihenfolge
function WeaponAnimations.Events(anim, from, to)
	local list = {}
	for _, event in anim.Events or {} do
		if event[1] > from and event[1] <= to then
			table.insert(list, event)
		end
	end
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	return list
end

return WeaponAnimations
