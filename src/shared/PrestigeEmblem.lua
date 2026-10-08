-- PrestigeEmblem (ModuleScript, nur Client)
-- Abzeichen für Spielerlevel und Prestige, aus Formen gebaut (keine Bilder nötig), in der Prestige-Farbe:
--   Prestige 0     Raute mit Level
--   Prestige 1-3   + 1 bis 3 Winkel (Chevrons) darunter
--   Prestige 4-6   + Flügel, ab 5 Sterne darunter (★, ★★)
--   Prestige 7-9   + Flügel und Krone, ab 8 Sterne darunter
--   Prestige 10    alles in Regenbogen-Farben (drehender Verlauf) mit pulsierendem Leuchten
-- Benutzung: local emblem = PrestigeEmblem.new(parent, size); emblem:Set(level, prestige)

local RunService = game:GetService("RunService")

local Shared = script.Parent
local LevelConfig = require(Shared.LevelConfig)

local PrestigeEmblem = {}
PrestigeEmblem.__index = PrestigeEmblem

local LEGEND = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 130)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
})
local SHADE = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 165))
local DARK = Color3.fromRGB(14, 22, 36)

-- Alle Legenden-Verläufe drehen sich langsam, Leuchten pulsiert
local spinning = {}
local glows = {}
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for gradient in spinning do
		if gradient.Parent then
			gradient.Rotation = (gradient.Rotation + dt * 90) % 360
		else
			spinning[gradient] = nil
		end
	end
	for glow in glows do
		if glow.Parent then
			glow.BackgroundTransparency = 0.55 + math.sin(t * 3) * 0.2
		else
			glows[glow] = nil
		end
	end
end)

-- Rechteck (in Anteilen des Abzeichens), gedreht
local function bar(parent, x, y, w, h, rotation, z)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(x, 0, y, 0)
	frame.Size = UDim2.new(w, 0, h, 0)
	frame.Rotation = rotation or 0
	frame.BorderSizePixel = 0
	frame.ZIndex = z or 2
	frame.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = frame
	return frame
end

function PrestigeEmblem.new(parent, size)
	local self = setmetatable({}, PrestigeEmblem)
	local root = Instance.new("Frame")
	root.Name = "PrestigeEmblem"
	root.Size = UDim2.new(0, size, 0, size)
	root.BackgroundTransparency = 1
	root.Parent = parent
	self.Root = root
	self.Colored = {} -- alle Teile in Prestige-Farbe

	-- Leuchten hinter allem (nur Legende)
	local glow = bar(root, 0.5, 0.42, 0.95, 0.95, 0, 1)
	glow.BackgroundColor3 = Color3.fromRGB(255, 220, 140)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = glow
	self.Glow = glow

	-- Flügel: je Seite drei Federn, nach außen gefächert
	self.Wings = {}
	for side = -1, 1, 2 do
		for k = 0, 2 do
			local feather = bar(root, 0.5 + side * (0.27 + k * 0.035), 0.36 + k * 0.1, 0.3 - k * 0.05, 0.075,
				side * (-18 + k * 18), 2)
			table.insert(self.Wings, feather)
			table.insert(self.Colored, feather)
		end
	end

	-- Krone: drei kleine Rauten über dem Abzeichen
	self.Crown = {}
	for _, spec in { { 0.37, 0.12, 0.1 }, { 0.5, 0.06, 0.13 }, { 0.63, 0.12, 0.1 } } do
		local jewel = bar(root, spec[1], spec[2], spec[3], spec[3], 45, 3)
		table.insert(self.Crown, jewel)
		table.insert(self.Colored, jewel)
	end

	-- Raute mit Rand und dunkler Innenfläche
	local outer = bar(root, 0.5, 0.42, 0.46, 0.46, 45, 4)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = outer
	table.insert(self.Colored, outer)
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.new(0.5, 0, 0.5, 0)
	inner.Size = UDim2.new(0.68, 0, 0.68, 0)
	inner.BackgroundColor3 = DARK
	inner.BorderSizePixel = 0
	inner.ZIndex = 5
	inner.Parent = outer
	self.Outer = outer

	local level = Instance.new("TextLabel")
	level.AnchorPoint = Vector2.new(0.5, 0.5)
	level.Position = UDim2.new(0.5, 0, 0.42, 0)
	level.Size = UDim2.new(0.36, 0, 0.2, 0)
	level.BackgroundTransparency = 1
	level.Font = Enum.Font.BuilderSansExtraBold
	level.TextScaled = true
	level.TextColor3 = Color3.new(1, 1, 1)
	level.ZIndex = 6
	level.Parent = root
	self.Level = level

	-- Winkel (Chevrons) unter der Raute
	self.Chevrons = {}
	for i = 0, 2 do
		local y = 0.76 + i * 0.075
		local left = bar(root, 0.44, y, 0.16, 0.045, 28, 3)
		local right = bar(root, 0.56, y, 0.16, 0.045, -28, 3)
		table.insert(self.Chevrons, { left, right })
		table.insert(self.Colored, left)
		table.insert(self.Colored, right)
	end

	-- Sterne unter der Raute (ab Prestige 5 bzw. 8)
	local stars = Instance.new("TextLabel")
	stars.AnchorPoint = Vector2.new(0.5, 0)
	stars.Position = UDim2.new(0.5, 0, 0.74, 0)
	stars.Size = UDim2.new(0.7, 0, 0.22, 0)
	stars.BackgroundTransparency = 1
	stars.Font = Enum.Font.BuilderSansExtraBold
	stars.TextScaled = true
	stars.TextStrokeTransparency = 0.4
	stars.ZIndex = 3
	stars.Parent = root
	self.Stars = stars
	return self
end

function PrestigeEmblem:Set(level, prestige)
	prestige = math.clamp(prestige or 0, 0, LevelConfig.MaxPrestige)
	local legend = prestige >= LevelConfig.MaxPrestige
	local color = LevelConfig.PrestigeColors[prestige]
	self.Level.Text = tostring(level or 1)
	for _, part in self.Colored do
		local gradient = part:FindFirstChildOfClass("UIGradient")
		part.BackgroundColor3 = legend and Color3.new(1, 1, 1) or color
		gradient.Color = legend and LEGEND or SHADE
		spinning[gradient] = legend or nil
	end
	-- Welche Teile sind sichtbar?
	local chevrons = prestige >= 1 and prestige <= 3 and prestige or 0
	for i, pair in self.Chevrons do
		pair[1].Visible = i <= chevrons
		pair[2].Visible = i <= chevrons
	end
	local wings = prestige >= 4
	for _, feather in self.Wings do
		feather.Visible = wings
	end
	for _, jewel in self.Crown do
		jewel.Visible = prestige >= 7
	end
	local starCount = (prestige == 5 or prestige == 8) and 1 or ((prestige == 6 or prestige == 9) and 2 or 0)
	self.Stars.Visible = starCount > 0 or legend
	self.Stars.Text = legend and "LEGENDE" or string.rep("★", starCount)
	self.Stars.TextColor3 = legend and Color3.fromRGB(255, 225, 140) or color
	self.Glow.Visible = legend
	glows[self.Glow] = legend or nil
	-- Mit höherem Prestige wird die Raute etwas größer
	local size = 0.4 + math.min(prestige, 10) * 0.008
	self.Outer.Size = UDim2.new(size, 0, size, 0)
end

return PrestigeEmblem
