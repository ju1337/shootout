-- RankEmblem (ModuleScript, nur Client)
-- Abzeichen für den ELO-Rang, aus Formen gebaut (keine Bilder nötig), in der Rangfarbe:
--   Bronze    Sechseck
--   Silber    Sechseck + kleine Flügel
--   Gold      Sechseck + Flügel + Spitze oben
--   Platin    Sechseck + große Flügel + Spitze
--   Diamant   große Raute (Edelstein) + große Flügel + Spitze
--   Meister   Raute + Flügel + Krone, pulsierendes Leuchten
-- In der Mitte die Division (III, II, I), beim Meister ein Stern.
-- Benutzung: local emblem = RankEmblem.new(parent, size); emblem:Set(elo)  (oder emblem:SetRank(RankConfig.Get(elo)))

local RunService = game:GetService("RunService")

local Shared = script.Parent
local RankConfig = require(Shared.RankConfig)

local RankEmblem = {}
RankEmblem.__index = RankEmblem

local SHADE = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(140, 140, 155))
local DARK = Color3.fromRGB(14, 18, 26)

-- Leuchten (Meister) pulsiert
local glows = {}
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for glow in glows do
		if glow.Parent then
			glow.BackgroundTransparency = 0.6 + math.sin(t * 3) * 0.15
		else
			glows[glow] = nil
		end
	end
end)

-- Rechteck (in Anteilen des Abzeichens), gedreht; Verlauf zeigt immer nach unten
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
	gradient.Rotation = 90 - (rotation or 0)
	gradient.Color = SHADE
	gradient.Parent = frame
	return frame
end

-- Sechseck (Spitze oben) aus drei gedrehten Rechtecken; r = Umkreis-Radius
local function hexagon(parent, x, y, r, z)
	local parts = {}
	for _, rotation in { 0, 60, 120 } do
		table.insert(parts, bar(parent, x, y, r * 1.732, r, rotation, z))
	end
	return parts
end

function RankEmblem.new(parent, size)
	local self = setmetatable({}, RankEmblem)
	local root = Instance.new("Frame")
	root.Name = "RankEmblem"
	root.Size = UDim2.new(0, size, 0, size)
	root.BackgroundTransparency = 1
	root.Parent = parent
	self.Root = root
	self.Colored = {} -- Teile in Rangfarbe

	-- Leuchten (Meister)
	local glow = bar(root, 0.5, 0.5, 0.95, 0.95, 0, 1)
	glow:FindFirstChildOfClass("UIGradient"):Destroy()
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = glow
	self.Glow = glow

	-- Flügel: je Seite bis zu drei Federn
	self.Wings = {}
	for k = 1, 3 do
		for side = -1, 1, 2 do
			local feather = bar(root, 0.5 + side * (0.3 + k * 0.025), 0.4 + k * 0.085, 0.28 - k * 0.04, 0.07,
				side * (-26 + k * 16), 2)
			feather.Visible = false
			table.insert(self.Wings, { Frame = feather, Level = k })
			table.insert(self.Colored, feather)
		end
	end

	-- Spitze oben und Krone
	local spike = bar(root, 0.5, 0.1, 0.13, 0.13, 45, 3)
	table.insert(self.Colored, spike)
	self.Spike = spike
	self.Crown = {}
	for _, spec in { { 0.33, 0.13, 0.09 }, { 0.67, 0.13, 0.09 } } do
		local jewel = bar(root, spec[1], spec[2], spec[3], spec[3], 45, 3)
		table.insert(self.Crown, jewel)
		table.insert(self.Colored, jewel)
	end

	-- Grundform: Sechseck (Bronze bis Platin) oder Raute (Diamant, Meister), jeweils mit dunkler Innenfläche
	self.Hex = hexagon(root, 0.5, 0.52, 0.36, 4)
	self.HexInner = hexagon(root, 0.5, 0.52, 0.27, 5)
	for _, part in self.Hex do
		table.insert(self.Colored, part)
	end
	self.Gem = bar(root, 0.5, 0.52, 0.5, 0.5, 45, 4)
	table.insert(self.Colored, self.Gem)
	self.GemInner = bar(root, 0.5, 0.52, 0.36, 0.36, 45, 5)
	for _, part in { self.GemInner, table.unpack(self.HexInner) } do
		part.BackgroundColor3 = DARK
		part:FindFirstChildOfClass("UIGradient"):Destroy()
	end
	-- Facette im Edelstein: heller Streifen
	self.Facet = bar(root, 0.43, 0.45, 0.05, 0.22, 45, 6)
	self.Facet.BackgroundColor3 = Color3.new(1, 1, 1)
	self.Facet.BackgroundTransparency = 0.75

	local division = Instance.new("TextLabel")
	division.AnchorPoint = Vector2.new(0.5, 0.5)
	division.Position = UDim2.new(0.5, 0, 0.53, 0)
	division.Size = UDim2.new(0.34, 0, 0.22, 0)
	division.BackgroundTransparency = 1
	division.Font = Enum.Font.GothamBlack
	division.TextScaled = true
	division.ZIndex = 7
	division.Parent = root
	self.Division = division
	return self
end

-- rank = Ergebnis von RankConfig.Get
function RankEmblem:SetRank(rank)
	local tier = 1
	for i, entry in RankConfig.Tiers do
		if entry.Name == rank.Name then
			tier = i
		end
	end
	for _, part in self.Colored do
		part.BackgroundColor3 = rank.Color
	end
	local gem = tier >= 5
	for _, part in self.Hex do
		part.Visible = not gem
	end
	for _, part in self.HexInner do
		part.Visible = not gem
	end
	self.Gem.Visible = gem
	self.GemInner.Visible = gem
	self.Facet.Visible = gem
	local wingLevel = ({ 0, 1, 2, 3, 3, 3 })[tier] or 0
	for _, wing in self.Wings do
		wing.Frame.Visible = wing.Level <= wingLevel
	end
	self.Spike.Visible = tier >= 3
	for _, jewel in self.Crown do
		jewel.Visible = tier >= 6
	end
	local master = tier >= #RankConfig.Tiers
	self.Glow.Visible = master
	self.Glow.BackgroundColor3 = rank.Color
	glows[self.Glow] = master or nil
	self.Division.Text = master and "★" or (rank.Division ~= "" and rank.Division or "")
	self.Division.TextColor3 = rank.Color
end

function RankEmblem:Set(elo)
	self:SetRank(RankConfig.Get(elo))
end

return RankEmblem
