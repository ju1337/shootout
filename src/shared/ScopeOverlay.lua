-- Zielfernrohr-Ansicht (nur Client): beim Zielen mit einer Waffe mit Zielfernrohr (GunModels.HasScope) liegt ein
-- runder Durchblick mit Fadenkreuz über dem Bild, außen schwarz. Die Ego-Waffe ist dann ausgeblendet (WeaponClient),
-- das Sichtfeld kommt aus WeaponConfig (ScopeFov). Ein echtes Fernrohr-Mesh vergrößert nicht – durch das Modell
-- hindurch sähe man nur einen kleinen Kreis.
--
-- ScopeOverlay.Update(shown) – jedes Bild aufrufen; baut die Oberfläche beim ersten Mal.

local Players = game:GetService("Players")

local ScopeOverlay = {}

local CIRCLE = 0.94           -- Durchmesser des Durchblicks (Anteil der Bildhöhe)
local LINE = 2                -- Fadenkreuz: dünne Linien in der Mitte (Pixel)
local POST = 6                -- dicke Balken außen
local POST_GAP = 0.28         -- dicke Balken beginnen so weit von der Mitte (Anteil des Radius)
local BLACK = Color3.new(0, 0, 0)
local DOT = Color3.fromRGB(255, 45, 40)

local gui, circle

local function frame(parent, name, size, position, color, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function build()
	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "ScopeOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1 -- unter dem HUD (Munition, Leben bleiben lesbar)
	gui.Enabled = false
	gui.Parent = playerGui

	-- Durchblick: quadratischer Rahmen in der Bildmitte, rund durch UICorner; der dicke schwarze Rand (UIStroke liegt
	-- außen) deckt den Rest des Bildschirms ab
	circle = frame(gui, "View", UDim2.fromScale(CIRCLE, CIRCLE), UDim2.fromScale(0.5, 0.5), BLACK, 1)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = circle
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outside"
	stroke.Color = BLACK
	stroke.Thickness = 4000
	stroke.Parent = circle
	-- dunkler Rand innen (Linsenrand)
	local rim = frame(circle, "Rim", UDim2.new(1, -24, 1, -24), UDim2.fromScale(0.5, 0.5), BLACK, 1)
	local rimCorner = Instance.new("UICorner")
	rimCorner.CornerRadius = UDim.new(0.5, 0)
	rimCorner.Parent = rim
	local rimStroke = Instance.new("UIStroke")
	rimStroke.Color = BLACK
	rimStroke.Thickness = 12
	rimStroke.Transparency = 0.45
	rimStroke.Parent = rim

	-- Fadenkreuz: dünne Linien durch die Mitte, außen dicke Balken (Duplex)
	frame(circle, "LineH", UDim2.new(1, 0, 0, LINE), UDim2.fromScale(0.5, 0.5), BLACK)
	frame(circle, "LineV", UDim2.new(0, LINE, 1, 0), UDim2.fromScale(0.5, 0.5), BLACK)
	local length = (1 - POST_GAP) / 2
	local offset = POST_GAP / 2 + length / 2
	frame(circle, "PostL", UDim2.new(length, 0, 0, POST), UDim2.fromScale(0.5 - offset, 0.5), BLACK)
	frame(circle, "PostR", UDim2.new(length, 0, 0, POST), UDim2.fromScale(0.5 + offset, 0.5), BLACK)
	frame(circle, "PostB", UDim2.new(0, POST, length, 0), UDim2.fromScale(0.5, 0.5 + offset), BLACK)
	local dot = frame(circle, "Dot", UDim2.fromOffset(4, 4), UDim2.fromScale(0.5, 0.5), DOT)
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = dot
	return true
end

function ScopeOverlay.Update(shown)
	if not gui and (not shown or not build()) then
		return
	end
	if gui.Enabled ~= shown then
		gui.Enabled = shown
	end
end

function ScopeOverlay.IsShown()
	return gui ~= nil and gui.Enabled
end

return ScopeOverlay
