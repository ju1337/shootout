-- HitFeedback (ModuleScript, nur Client)
-- Treffer-Rückmeldung beim Schießen in mehreren Stilen (Einstellungen „Hitmarker“ und „Schadenszahlen“):
--   Hitmarker      KLASSISCH  X um die Mitte, das kurz aufspringt
--                  IMPULS     vier Klingen schlagen von außen ein, dazu eine Druckwelle; Kopftreffer blitzen mit
--                             einer goldenen Raute, ein Kill zündet eine doppelte Welle, einen Blitz und vier Splitter
--                  PRÄZISION  Ring mit vier Strichen wie im Zielfernrohr; Kopftreffer mit innerem Ring, ein Kill
--                             sprengt den Ring in vier Bögen, die sich drehend nach außen lösen
--   Schadenszahlen STAPELN    eine Zahl pro Ziel zählt hoch, jeder Treffer fliegt als kleines „+X“ daneben weg,
--                             ein Kill färbt sie rot und streicht sie an
--                  EINZELN    jeder Treffer eine eigene Zahl, die im Bogen wegfliegt (abwechselnd links/rechts,
--                             Kopftreffer groß und gold mit Raute, Kill groß und rot mit Ruck)
--                  AUS
-- Farben je Treffer-Art: Körper weiß, Kopf gold, nur Rüstung blau, niedergeschlagen orange, ausgeschaltet rot.
-- Kombo: schnelle Treffer hintereinander am selben Ziel machen den Hitmarker größer und den Ton höher.
-- Jeder Hitmarker-Stil hat eigene Töne. HitFeedback.Preview baut dieselben Effekte als Vorschau (Seite OPTIONEN).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)
local PlayerSettings = require(Shared.PlayerSettings)

local HitFeedback = {}

HitFeedback.Colors = {
	Body = Color3.new(1, 1, 1),
	Head = Color3.fromRGB(255, 204, 72),
	Armor = Color3.fromRGB(92, 178, 255),
	Down = Color3.fromRGB(255, 152, 56),
	Kill = Color3.fromRGB(255, 58, 50),
}
local COLORS = HitFeedback.Colors
local BLACK = Color3.new(0, 0, 0)
local NUMBER_FONT = Enum.Font.BuilderSansExtraBold

local COMBO_WINDOW = 0.65 -- so lange nach einem Treffer zählt der nächste am selben Ziel zur Kombo
local MAX_BOOST = 6       -- ab so vielen Kombo-Treffern wächst nichts mehr
local STACK_TIME = 1.2    -- STAPELN: so lange zählt eine Zahl am selben Ziel weiter
local FLOAT_TIME = 0.85   -- EINZELN: Lebensdauer einer Zahl

local DIAGONALS = { Vector2.new(-1, -1).Unit, Vector2.new(1, -1).Unit, Vector2.new(1, 1).Unit, Vector2.new(-1, 1).Unit }
local CARDINALS = { Vector2.new(0, -1), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(-1, 0) }

local make = UITheme.Make

-- ---------- Treffer-Art und Töne ----------

-- "Kill", "Down", "Head", "Armor" (Schaden ging nur in die Rüstung) oder "Body"
function HitFeedback.KindOf(headshot, killed, downed, damage, armor)
	if killed then
		return "Kill"
	elseif downed then
		return "Down"
	elseif headshot then
		return "Head"
	elseif typeof(armor) == "number" and armor > 0 and (typeof(damage) == "number" and damage or 0) <= armor + 0.5 then
		return "Armor"
	end
	return "Body"
end

local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local THUD = "rbxasset://sounds/switch.wav"
-- Je Stil und Treffer-Art: { Klang, Tonhöhe, Lautstärke, Verzögerung (s) }
HitFeedback.Sounds = {
	Classic = {
		Body = { { PING, 1.95, 0.35 } },
		Head = { { PING, 2.5, 0.55 } },
		Armor = { { PING, 1.5, 0.35 } },
		Down = { { PING, 1.3, 0.6 }, { PING, 1.0, 0.45, 0.07 } },
		Kill = { { PING, 1.1, 0.7 }, { PING, 1.6, 0.55, 0.07 } },
	},
	-- satter Klick mit hellem Glanz; Kill: dumpfer Schlag und aufsteigender Dreiklang
	Impulse = {
		Body = { { CLICK, 1.7, 0.55 }, { PING, 2.7, 0.16 } },
		Head = { { PING, 3.0, 0.5 }, { CLICK, 2.3, 0.45 } },
		Armor = { { CLICK, 1.15, 0.5 }, { PING, 1.9, 0.12 } },
		Down = { { THUD, 0.8, 0.6 }, { PING, 1.6, 0.4, 0.05 } },
		Kill = { { THUD, 0.6, 0.8 }, { PING, 1.5, 0.5 }, { PING, 2.0, 0.42, 0.06 }, { PING, 3.0, 0.22, 0.12 } },
	},
	-- klare, leise Pings; Kill: zweistimmiger Glockenton
	Precision = {
		Body = { { PING, 2.2, 0.3 } },
		Head = { { PING, 2.9, 0.42 }, { PING, 3.6, 0.22, 0.045 } },
		Armor = { { PING, 1.6, 0.3 } },
		Down = { { PING, 1.4, 0.45 }, { PING, 1.9, 0.35, 0.06 } },
		Kill = { { PING, 1.8, 0.5 }, { PING, 2.4, 0.45, 0.08 }, { PING, 3.6, 0.18, 0.16 } },
	},
}
local COMBO_PITCH = 0.035 -- jeder weitere Kombo-Treffer klingt so viel höher

local function playTone(tone, rise)
	local sound = Instance.new("Sound")
	sound.SoundId = tone[1]
	sound.PlaybackSpeed = tone[2] * rise
	sound.Volume = tone[3]
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 2)
end

function HitFeedback.PlaySound(style, kind, combo)
	local set = HitFeedback.Sounds[style] or HitFeedback.Sounds.Impulse
	local rise = 1
	if kind ~= "Kill" and kind ~= "Down" then
		rise += COMBO_PITCH * math.min((combo or 1) - 1, MAX_BOOST)
	end
	for _, tone in set[kind] or set.Body do
		if (tone[4] or 0) > 0 then
			task.delay(tone[4], playTone, tone, rise)
		else
			playTone(tone, rise)
		end
	end
end

-- ---------- Bausteine ----------

local function tween(object, time, goals, style, direction, delay)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0)
	local animation = TweenService:Create(object, info, goals)
	animation:Play()
	return animation
end

-- Strich (bzw. Fläche) mit dunklem Rand, Mitte als Bezugspunkt, zunächst unsichtbar
local function solid(parent, zIndex)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 2), BackgroundColor3 = COLORS.Body, BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = zIndex }, parent)
	local outline = make("UIStroke", { Color = BLACK, Thickness = 1, Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	return frame, outline
end

-- Kreis (nur der Rand), Mitte als Bezugspunkt, zunächst unsichtbar
local function circle(parent, zIndex)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, ZIndex = zIndex }, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
	local line = make("UIStroke", { Color = COLORS.Body, Thickness = 2, Transparency = 1 }, frame)
	return frame, line
end

local function at(direction, distance)
	return UDim2.new(0.5, direction.X * distance, 0.5, direction.Y * distance)
end

local function rotationOf(direction)
	return math.deg(math.atan2(direction.Y, direction.X)) + 90 -- Strich zeigt in Richtung direction
end

-- ---------- Hitmarker ----------
-- Jeder Stil baut seine Teile in root (Rahmen der Größe 0 in der Bildmitte) und gibt function(kind, combo) zurück.
local HITMARKERS = {}

-- KLASSISCH: X um die Mitte
function HITMARKERS.Classic(root)
	local scale = make("UIScale", {}, root)
	local lines = {}
	for i, direction in DIAGONALS do
		local line, outline = solid(root, 6)
		line.Rotation = rotationOf(direction)
		lines[i] = { Line = line, Outline = outline, Dir = direction }
	end
	local id = 0
	return function(kind, combo)
		id += 1
		local myId = id
		local big = kind == "Kill" or kind == "Down"
		local distance = big and 17 or 12.7
		for _, entry in lines do
			entry.Line.Position = at(entry.Dir, distance)
			entry.Line.Size = UDim2.fromOffset(big and 3 or 2.5, big and 15 or 11)
			entry.Line.BackgroundColor3 = COLORS[kind]
			entry.Line.BackgroundTransparency = 0
			entry.Outline.Transparency = 0.45
		end
		scale.Scale = (big and 1.6 or 1.35) + 0.04 * math.min(combo - 1, MAX_BOOST)
		tween(scale, 0.12, { Scale = 1 })
		task.delay(big and 0.4 or 0.16, function()
			if id ~= myId then
				return
			end
			for _, entry in lines do
				tween(entry.Line, 0.12, { BackgroundTransparency = 1 })
				tween(entry.Outline, 0.12, { Transparency = 1 })
			end
		end)
	end
end

-- IMPULS: Klingen schlagen ein, Druckwelle; Kopf: goldene Raute; Kill: Blitz, zweite Welle, Splitter
function HITMARKERS.Impulse(root)
	local flash = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30), BackgroundColor3 = COLORS.Kill, BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = 5 }, root)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, flash)
	local wave, waveLine = circle(root, 6)
	local wave2, wave2Line = circle(root, 6)
	local blades = {}
	for i, direction in DIAGONALS do
		local blade, outline = solid(root, 7)
		blade.Rotation = rotationOf(direction)
		-- innen voll, nach außen etwas durchsichtiger (wirkt wie eine Klinge)
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 0) }, blade)
		blades[i] = { Frame = blade, Outline = outline, Dir = direction }
	end
	local shards = {}
	for i, direction in CARDINALS do
		local shard, outline = solid(root, 7)
		shards[i] = { Frame = shard, Outline = outline, Dir = direction, Rotation = rotationOf(direction) }
	end
	local diamond, diamondOutline = solid(root, 8)
	diamond.Size = UDim2.fromOffset(8, 8)
	diamond.Rotation = 45
	local diamondScale = make("UIScale", { Scale = 0 }, diamond)

	local id, diamondId = 0, 0
	return function(kind, combo)
		id += 1
		local myId = id
		local color = COLORS[kind]
		local kill = kind == "Kill"
		local big = kill or kind == "Down"
		local boost = math.min(combo - 1, MAX_BOOST)
		-- Klingen: von außen auf die Mitte zu schlagen (Quint = schneller Einschlag), innen bleibt das Fadenkreuz frei
		local length = (kill and 17 or big and 15 or kind == "Head" and 14 or 12) + boost * 0.5
		local width = kill and 3.5 or (kind == "Head" or big) and 3 or 2.5
		local gap = kill and 9 or 7 -- Abstand des inneren Endes zur Mitte
		local from, to = gap + 8 + boost * 1.5 + length / 2, gap + length / 2
		for _, blade in blades do
			blade.Frame.Size = UDim2.fromOffset(width, length)
			blade.Frame.BackgroundColor3 = color
			blade.Frame.BackgroundTransparency = 0
			blade.Outline.Transparency = 0.35
			blade.Frame.Position = at(blade.Dir, from)
			tween(blade.Frame, 0.07, { Position = at(blade.Dir, to) }, Enum.EasingStyle.Quint)
		end
		-- Druckwelle (wächst mit der Kombo)
		local reach = kill and 42 or big and 32 or 17 + boost * 2.5
		wave.Size = UDim2.fromOffset(14, 14)
		waveLine.Color = color
		waveLine.Thickness = kill and 3 or big and 2.5 or 1.5 + boost * 0.15
		waveLine.Transparency = kind == "Body" and 0.35 or 0.1
		tween(wave, kill and 0.3 or 0.2, { Size = UDim2.fromOffset(reach * 2, reach * 2) })
		tween(waveLine, kill and 0.3 or 0.2, { Transparency = 1, Thickness = 0.5 })
		-- Kopftreffer: goldene Raute blitzt in der Mitte auf
		if kind == "Head" then
			diamondId += 1
			local myDiamond = diamondId -- eigener Zähler: der nächste Treffer darf die Raute nicht stehen lassen
			diamond.BackgroundColor3 = color
			diamond.BackgroundTransparency = 0
			diamondOutline.Transparency = 0.3
			diamondScale.Scale = 0.2
			tween(diamondScale, 0.07, { Scale = 1.3 }, Enum.EasingStyle.Back)
			task.delay(0.1, function()
				if diamondId == myDiamond then
					tween(diamondScale, 0.14, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					tween(diamond, 0.14, { BackgroundTransparency = 1 })
					tween(diamondOutline, 0.14, { Transparency = 1 })
				end
			end)
		end
		-- Kill: Blitz, zweite Welle und vier Splitter, die zwischen den Klingen davonfliegen
		if kill then
			flash.Size = UDim2.fromOffset(30, 30)
			flash.BackgroundColor3 = color
			flash.BackgroundTransparency = 0.45
			tween(flash, 0.22, { BackgroundTransparency = 1, Size = UDim2.fromOffset(48, 48) })
			wave2.Size = UDim2.fromOffset(10, 10)
			wave2Line.Color = color
			wave2Line.Thickness = 1.5
			wave2Line.Transparency = 0.2
			tween(wave2, 0.4, { Size = UDim2.fromOffset(118, 118) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.06)
			tween(wave2Line, 0.4, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.06)
			for _, shard in shards do
				shard.Frame.Size = UDim2.fromOffset(2.5, 8)
				shard.Frame.Rotation = shard.Rotation
				shard.Frame.BackgroundColor3 = color
				shard.Frame.BackgroundTransparency = 0
				shard.Outline.Transparency = 0.4
				shard.Frame.Position = at(shard.Dir, 12)
				tween(shard.Frame, 0.36, { Position = at(shard.Dir, 60), BackgroundTransparency = 1, Rotation = shard.Rotation + 120 })
				tween(shard.Outline, 0.36, { Transparency = 1 })
			end
		end
		-- Ausklingen: Klingen gleiten etwas nach außen und verblassen
		task.delay(kill and 0.32 or big and 0.25 or 0.1, function()
			if id ~= myId then
				return
			end
			for _, blade in blades do
				tween(blade.Frame, 0.16, { BackgroundTransparency = 1, Position = at(blade.Dir, to + 4) })
				tween(blade.Outline, 0.16, { Transparency = 1 })
			end
		end)
	end
end

-- Bogen: Kreis, von dem ein Verlauf nur das Viertel in Richtung angle (Grad) sichtbar lässt
local ARC_CUT = (1 + math.cos(math.rad(45))) / 2
local function arc(parent, angle, zIndex)
	local frame, line = circle(parent, zIndex)
	make("UIGradient", { Rotation = angle, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(ARC_CUT - 0.01, 1),
		NumberSequenceKeypoint.new(ARC_CUT + 0.01, 0), NumberSequenceKeypoint.new(1, 0) }) }, line)
	return frame, line
end

-- PRÄZISION: Ring mit vier Strichen; Kopf: innerer Ring und goldener Punkt; Kill: Ring zerfällt in vier Bögen
function HITMARKERS.Precision(root)
	local ring, ringLine = circle(root, 6)
	local inner, innerLine = circle(root, 6)
	local ticks = {}
	for i, direction in CARDINALS do
		local tick, outline = solid(root, 7)
		tick.Rotation = rotationOf(direction)
		ticks[i] = { Frame = tick, Outline = outline, Dir = direction }
	end
	local dot, dotOutline = solid(root, 8)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	local arcs = {}
	for i, direction in DIAGONALS do
		local frame, line = arc(root, math.deg(math.atan2(direction.Y, direction.X)), 6)
		arcs[i] = { Frame = frame, Line = line }
	end

	local id = 0
	return function(kind, combo)
		id += 1
		local myId = id
		local color = COLORS[kind]
		local kill = kind == "Kill"
		local boost = math.min(combo - 1, MAX_BOOST)
		local radius = kind == "Down" and 14 or 11
		if kill then
			-- Ring weg, stattdessen vier Bögen, die sich drehend lösen
			ringLine.Transparency = 1
			for _, entry in arcs do
				entry.Frame.Size = UDim2.fromOffset(radius * 2, radius * 2)
				entry.Frame.Rotation = 0
				entry.Line.Color = color
				entry.Line.Thickness = 2.5
				entry.Line.Transparency = 0
				tween(entry.Frame, 0.34, { Size = UDim2.fromOffset(64, 64), Rotation = 35 })
				tween(entry.Line, 0.34, { Transparency = 1, Thickness = 1 })
			end
		else
			ring.Size = UDim2.fromOffset(radius * 2.6, radius * 2.6)
			ringLine.Color = color
			ringLine.Thickness = 1.5 + boost * 0.25
			ringLine.Transparency = 0
			tween(ring, 0.08, { Size = UDim2.fromOffset(radius * 2, radius * 2) }, Enum.EasingStyle.Quint)
		end
		-- Striche: von außen an den Ring; beim Kill fliegen sie weg
		for _, entry in ticks do
			entry.Frame.Size = UDim2.fromOffset(2, 6)
			entry.Frame.BackgroundColor3 = color
			entry.Frame.BackgroundTransparency = 0
			entry.Outline.Transparency = 0.4
			entry.Frame.Position = at(entry.Dir, radius + 9)
			if kill then
				tween(entry.Frame, 0.34, { Position = at(entry.Dir, radius + 30), BackgroundTransparency = 1 })
				tween(entry.Outline, 0.34, { Transparency = 1 })
			else
				tween(entry.Frame, 0.08, { Position = at(entry.Dir, radius + 4) }, Enum.EasingStyle.Quint)
			end
		end
		-- Mitte: Kopf und Kill mit Punkt (Kill pulsiert), Kopf zusätzlich mit innerem Ring
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = (kind == "Head" or kill) and 0 or 1
		dotOutline.Transparency = (kind == "Head" or kill) and 0.4 or 1
		dot.Size = UDim2.fromOffset(4, 4)
		if kill then
			tween(dot, 0.3, { Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1 })
			tween(dotOutline, 0.3, { Transparency = 1 })
		end
		if kind == "Head" then
			inner.Size = UDim2.fromOffset(4, 4)
			innerLine.Color = color
			innerLine.Thickness = 1.5
			innerLine.Transparency = 0
			tween(inner, 0.12, { Size = UDim2.fromOffset(12, 12) })
		end
		task.delay(kill and 0.3 or 0.14, function()
			if id ~= myId then
				return
			end
			tween(ringLine, 0.16, { Transparency = 1 })
			tween(innerLine, 0.16, { Transparency = 1 })
			tween(dot, 0.16, { BackgroundTransparency = 1 })
			tween(dotOutline, 0.16, { Transparency = 1 })
			for _, entry in ticks do
				tween(entry.Frame, 0.16, { BackgroundTransparency = 1 })
				tween(entry.Outline, 0.16, { Transparency = 1 })
			end
		end)
	end
end

HitFeedback.HitmarkerStyles = { "Classic", "Impulse", "Precision" }

-- Hitmarker im Stil style in parent (Mitte von parent = Fadenkreuz). Gibt { Hit = function(kind, combo), Destroy } zurück.
function HitFeedback.NewHitmarker(parent, style)
	local root = make("Frame", { Name = "Hitmarker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 6 }, parent)
	local hit = (HITMARKERS[style] or HITMARKERS.Impulse)(root)
	return {
		Style = style,
		Hit = function(kind, combo)
			hit(kind, combo or 1)
		end,
		Destroy = function()
			root:Destroy()
		end,
	}
end

-- ---------- Schadenszahlen ----------
-- mount(anchor) liefert einen Rahmen (240 x 180, Mitte = Ziel), in dem eine Zahl spielt, und eine Abbau-Funktion:
-- im Spiel eine BillboardGui am Ziel, in der Vorschau ein Rahmen auf der Vorschaufläche.

local function numberLabel(parent, size, color)
	local text = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(160, size + 8), BackgroundTransparency = 1, Text = "", TextSize = size, Font = NUMBER_FONT,
		TextColor3 = color or COLORS.Body, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, parent)
	local outline = make("UIStroke", { Color = BLACK, Thickness = 2, Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, text) -- Kontur um die Ziffern
	return text, outline
end

local function fadeLabel(text, outline, time, goals)
	goals = goals or {}
	goals.TextTransparency = 1
	tween(text, time, goals)
	tween(outline, time, { Transparency = 1 })
end

local NUMBERS = {}

-- STAPELN: eine Zahl pro Ziel zählt hoch, jeder Treffer als „+X“ daneben
function NUMBERS.Stack(mount)
	local stacks = {}
	return function(key, anchor, damage, kind)
		local now = os.clock()
		local stack = stacks[key]
		if not stack or now - stack.Last > STACK_TIME or not stack.Frame.Parent then
			local frame, destroy = mount(anchor)
			local text, outline = numberLabel(frame, 30)
			local underline = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 22),
				Size = UDim2.fromOffset(0, 3), BackgroundColor3 = COLORS.Kill, BorderSizePixel = 0, ZIndex = 2 }, frame)
			stack = { Frame = frame, Destroy = destroy, Text = text, Outline = outline, Underline = underline,
				Scale = make("UIScale", {}, text), Total = 0, Last = now }
			stacks[key] = stack
		end
		local color = COLORS[kind]
		stack.Total += damage
		stack.Last = now
		stack.Text.Text = tostring(math.floor(stack.Total + 0.5))
		stack.Text.TextColor3 = color
		stack.Text.TextSize = kind == "Kill" and 38 or kind == "Head" and 34 or 30
		stack.Scale.Scale = kind == "Kill" and 1.8 or 1.45
		tween(stack.Scale, 0.18, { Scale = kind == "Kill" and 1.12 or 1 }, Enum.EasingStyle.Back)
		-- dieser Treffer als „+X“, das schräg nach oben wegfliegt
		local plus, plusOutline = numberLabel(stack.Frame, kind == "Head" and 19 or 16, color)
		plus.Text = "+" .. math.floor(damage + 0.5)
		plus.Position = UDim2.new(0.5, 50, 0.5, math.random(-8, 6))
		fadeLabel(plus, plusOutline, 0.55, { Position = UDim2.new(0.5, 66, 0.5, -32) })
		Debris:AddItem(plus, 0.6)
		if kind == "Kill" then
			-- Kill: rote Linie streicht die Zahl an
			stack.Underline.Size = UDim2.fromOffset(0, 3)
			tween(stack.Underline, 0.2, { Size = UDim2.fromOffset(74, 3) }, Enum.EasingStyle.Quint)
		end
		local myStack = stack
		task.delay(kind == "Kill" and 0.9 or STACK_TIME, function()
			if stacks[key] ~= myStack or (kind ~= "Kill" and os.clock() - myStack.Last < STACK_TIME - 0.02) then
				return
			end
			stacks[key] = nil
			fadeLabel(myStack.Text, myStack.Outline, 0.45, { Position = UDim2.new(0.5, 0, 0.5, -28) })
			tween(myStack.Underline, 0.45, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, -6) })
			task.delay(0.5, myStack.Destroy)
		end)
	end
end

-- EINZELN: jeder Treffer eine eigene Zahl im Bogen (abwechselnd nach links und rechts)
function NUMBERS.Float(mount)
	local sides = setmetatable({}, { __mode = "k" })
	return function(key, anchor, damage, kind)
		local side = -(sides[key] or 1)
		sides[key] = side
		local frame, destroy = mount(anchor)
		-- außen: waagerecht gleichmäßig, innen: hoch und wieder etwas herunter = Bogen
		local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -14),
			Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, frame)
		local size = (kind == "Kill" and 38 or kind == "Head" and 32 or kind == "Down" and 30 or kind == "Armor" and 23 or 26)
			+ math.clamp(math.floor((damage - 30) / 15), 0, 6)
		local text, outline = numberLabel(holder, size, COLORS[kind])
		text.Position = UDim2.fromOffset(0, 0)
		text.Text = tostring(math.floor(damage + 0.5))
		if kind == "Kill" then
			outline.Thickness = 2.5
		end
		-- Kopftreffer: goldene Raute links neben der Zahl
		local diamond
		if kind == "Head" then
			diamond = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8), Rotation = 45,
				Position = UDim2.new(0.5, -(#text.Text * size * 0.27 + 12), 0.5, 1), BackgroundColor3 = COLORS.Head,
				BorderSizePixel = 0, ZIndex = 3 }, text)
			make("UIStroke", { Color = BLACK, Thickness = 1.5, Transparency = 0.2 }, diamond)
		end
		local scale = make("UIScale", { Scale = kind == "Kill" and 2.3 or 2 }, text)
		tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		if kind == "Kill" then
			text.Rotation = -12 * side
			tween(text, 0.32, { Rotation = 0 }, Enum.EasingStyle.Elastic)
		end
		local dx = side * (16 + math.random() * 24)
		tween(holder, FLOAT_TIME, { Position = UDim2.new(0.5, dx, 0.5, -14) }, Enum.EasingStyle.Linear)
		tween(text, 0.42, { Position = UDim2.fromOffset(0, -38) })
		task.delay(0.44, function()
			if text.Parent then
				fadeLabel(text, outline, FLOAT_TIME - 0.46, { Position = UDim2.fromOffset(0, -24) })
				if diamond then
					tween(diamond, FLOAT_TIME - 0.46, { BackgroundTransparency = 1 })
				end
			end
		end)
		task.delay(FLOAT_TIME, destroy)
	end
end

HitFeedback.NumberStyles = { "Stack", "Float" }

-- Schadenszahlen im Stil style (false/nil = aus). Gibt { Hit = function(key, anchor, damage, kind) } zurück.
function HitFeedback.NewNumbers(style, mount)
	local factory = NUMBERS[style]
	local hit = factory and factory(mount)
	return {
		Style = style,
		Hit = function(key, anchor, damage, kind)
			if hit and damage > 0 then
				hit(key, anchor, damage, kind)
			end
		end,
	}
end

-- ---------- Im Spiel ----------

local player = Players.LocalPlayer
local hitmarker, numbers
local combo, comboKey, comboTime = 0, nil, 0

-- BillboardGui am Ziel: anchor = { Part = BasePart } oder { Position = Vector3 }
local function worldMount(anchor)
	local adornee, attachment = anchor.Part, nil
	if not adornee then
		attachment = Instance.new("Attachment")
		attachment.WorldPosition = anchor.Position or Vector3.zero
		attachment.Parent = workspace.Terrain
		adornee = attachment
	end
	local billboard = make("BillboardGui", { Name = "DamageNumber", Adornee = adornee, Size = UDim2.fromOffset(240, 180),
		AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 1000, ResetOnSpawn = false, ClipsDescendants = false,
		StudsOffsetWorldSpace = anchor.Offset or Vector3.zero }, player:WaitForChild("PlayerGui"))
	return billboard, function()
		billboard:Destroy()
		if attachment then
			attachment:Destroy()
		end
	end
end

local function rebuild(gui)
	if hitmarker then
		hitmarker.Destroy()
	end
	hitmarker = HitFeedback.NewHitmarker(gui, PlayerSettings.Get("HitmarkerStyle"))
	numbers = HitFeedback.NewNumbers(PlayerSettings.Get("DamageNumbers"), worldMount)
end

-- gui = skalierte Vollbild-Ebene des HUD (Mitte = Fadenkreuz)
function HitFeedback.Init(gui)
	rebuild(gui)
	PlayerSettings.Changed:Connect(function(key)
		if key == "HitmarkerStyle" or key == "DamageNumbers" then
			rebuild(gui)
		end
	end)
end

-- Treffer vom Server (WeaponClient.Hit, weitergereicht vom CombatHUD)
function HitFeedback.Hit(headshot, killed, damage, position, downed, armor, victimModel)
	if not hitmarker then
		return
	end
	damage = typeof(damage) == "number" and damage or 0
	local kind = HitFeedback.KindOf(headshot, killed, downed, damage, armor)
	local target = typeof(victimModel) == "Instance" and victimModel or nil
	local now = os.clock()
	local key = target or position
	if key ~= nil and key == comboKey and now - comboTime <= COMBO_WINDOW then
		combo += 1
	else
		combo = 1
	end
	comboKey, comboTime = key, now
	hitmarker.Hit(kind, combo)
	HitFeedback.PlaySound(hitmarker.Style, kind, combo)
	if numbers and damage > 0 then
		local head = target and target:FindFirstChild("Head")
		local point = typeof(position) == "Vector3" and position or nil
		local anchor
		if numbers.Style == "Stack" then
			-- über dem Kopf, leicht seitlich versetzt
			anchor = head and head:IsA("BasePart") and { Part = head, Offset = Vector3.new((math.random() - 0.5) * 1.2, 2.2, 0) }
				or { Position = point or Vector3.zero, Offset = Vector3.new(0, 2, 0) }
		else
			-- an der Trefferstelle, etwas darüber (die Zahl soll das Fadenkreuz nicht verdecken)
			anchor = { Position = point or (head and head.Position) or Vector3.zero, Offset = Vector3.new(0, 0.6, 0) }
		end
		numbers.Hit(key or "?", anchor, damage, kind)
	end
	if kind == "Kill" then
		combo = 0
	end
end

-- ---------- Vorschau (Seite OPTIONEN) ----------
-- Kleine Schießbahn: Puppe mit Fadenkreuz auf der Brust, darauf eine Trefferfolge (Körper, Kopf, Rüstung, Kill)
-- mit dem eingestellten Hitmarker und den eingestellten Schadenszahlen. Läuft leise in Schleife, solange die
-- Fläche zu sehen ist; Play(true) spielt sie sofort mit Ton (nach dem Umschalten eines Stils).

local SEQUENCE = {
	{ 0, "Body", 22, "Chest" }, { 0.22, "Body", 22, "Chest" }, { 0.44, "Head", 44, "Head" },
	{ 0.7, "Armor", 14, "Chest" }, { 0.94, "Body", 22, "Chest" }, { 1.24, "Kill", 31, "Head" },
}

local function shown(gui)
	local node = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

function HitFeedback.Preview(surface)
	surface.ClipsDescendants = true
	local C = UITheme.Colors
	local h = surface.Size.Y.Offset
	-- Puppe (Silhouette) in der Mitte, Fadenkreuz auf der Brust; darüber Platz für die aufsteigenden Zahlen
	local dummy = make("Frame", { Name = "Dummy", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(70, math.clamp(h - 85, 60, 150)), BackgroundTransparency = 1 }, surface)
	local dummyScale = make("UIScale", {}, dummy)
	local parts = {}
	local function piece(x, y, pw, ph)
		local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, y), Size = UDim2.fromOffset(pw, ph),
			BackgroundColor3 = C.Card, BorderSizePixel = 0 }, dummy)
		make("UICorner", { CornerRadius = UDim.new(0, 3) }, frame)
		make("UIStroke", { Color = C.Border, Thickness = 1, Transparency = 0.2 }, frame)
		table.insert(parts, frame)
		return frame
	end
	local scaleY = dummy.Size.Y.Offset / 150
	piece(0, 0, 26 * scaleY, 26 * scaleY)                         -- Kopf
	piece(0, 30 * scaleY, 40 * scaleY, 50 * scaleY)               -- Oberkörper
	piece(-28 * scaleY, 31 * scaleY, 13 * scaleY, 46 * scaleY)    -- Arme
	piece(28 * scaleY, 31 * scaleY, 13 * scaleY, 46 * scaleY)
	piece(-10 * scaleY, 84 * scaleY, 17 * scaleY, 64 * scaleY)    -- Beine
	piece(10 * scaleY, 84 * scaleY, 17 * scaleY, 64 * scaleY)
	local headPoint = Vector2.new(0, -dummy.Size.Y.Offset + 13 * scaleY)
	local chestPoint = Vector2.new(0, -dummy.Size.Y.Offset + 55 * scaleY)
	local base = UDim2.new(0.5, 0, 1, -12)
	local function point(offset, jitter)
		local j = jitter and Vector2.new(math.random(-8, 8), math.random(-6, 6)) or Vector2.zero
		return UDim2.new(base.X.Scale, base.X.Offset + offset.X + j.X, base.Y.Scale, base.Y.Offset + offset.Y + j.Y)
	end
	-- Fadenkreuz auf der Brust (vier Striche und Punkt wie im Spiel)
	local cross = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = point(chestPoint), Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1, ZIndex = 5 }, surface)
	for _, direction in CARDINALS do
		local line, outline = solid(cross, 5)
		line.Size = direction.X == 0 and UDim2.fromOffset(2, 8) or UDim2.fromOffset(8, 2)
		line.Position = at(direction, 9)
		line.BackgroundTransparency = 0
		outline.Transparency = 0.45
	end
	local centerDot, centerOutline = solid(cross, 5)
	centerDot.BackgroundTransparency = 0
	centerOutline.Transparency = 0.45

	-- Zahlen erscheinen auf der Fläche (Mitte = Kopf bzw. Trefferstelle)
	local function previewMount(anchor)
		local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = anchor.Point, Size = UDim2.fromOffset(240, 180),
			BackgroundTransparency = 1, ZIndex = 6 }, surface)
		return frame, function()
			frame:Destroy()
		end
	end

	local preview = { Playing = false }
	local marker, markerStyle = nil, nil
	local runId = 0
	local lastEnd = -math.huge
	function preview.Play(withSound)
		runId += 1
		local myRun = runId
		local style = PlayerSettings.Get("HitmarkerStyle")
		if style ~= markerStyle then
			if marker then
				marker.Destroy()
			end
			marker, markerStyle = HitFeedback.NewHitmarker(cross, style), style
		end
		local numberStyle = PlayerSettings.Get("DamageNumbers")
		local numberSet = HitFeedback.NewNumbers(numberStyle, previewMount)
		for _, frame in parts do
			frame.BackgroundColor3 = C.Card
		end
		dummy.Rotation = 0
		dummyScale.Scale = 1
		preview.Playing = true
		local started = os.clock()
		task.spawn(function()
			for i, step in SEQUENCE do
				local wait = step[1] - (os.clock() - started)
				if wait > 0 then
					task.wait(wait)
				end
				if runId ~= myRun then
					return
				end
				local kind, damage = step[2], step[3]
				marker.Hit(kind, i)
				if withSound then
					HitFeedback.PlaySound(style, kind, i)
				end
				local spot = step[4] == "Head" and headPoint or chestPoint
				local anchor = { Point = numberStyle == "Stack" and point(headPoint + Vector2.new(0, -26)) or point(spot, true) }
				numberSet.Hit("Puppe", anchor, damage, kind)
				-- Puppe zuckt bei jedem Treffer, beim Kill kippt sie und färbt sich rot
				dummyScale.Scale = 0.97
				tween(dummyScale, 0.12, { Scale = 1 })
				if kind == "Kill" then
					for _, frame in parts do
						frame.BackgroundColor3 = COLORS.Kill:Lerp(C.Card, 0.55)
					end
					tween(dummy, 0.35, { Rotation = 9 }, Enum.EasingStyle.Back)
				end
			end
			task.wait(1.1)
			if runId == myRun then
				preview.Playing = false
				lastEnd = os.clock()
				tween(dummy, 0.25, { Rotation = 0 })
				for _, frame in parts do
					tween(frame, 0.25, { BackgroundColor3 = C.Card })
				end
			end
		end)
	end
	-- leise Schleife, solange die Vorschau zu sehen ist (startet gleich beim Öffnen, dann mit kurzer Pause)
	task.spawn(function()
		while surface.Parent do
			if not preview.Playing and shown(surface) and os.clock() - lastEnd > 1.2 then
				preview.Play(false)
			end
			task.wait(0.3)
		end
	end)
	return preview
end

return HitFeedback
