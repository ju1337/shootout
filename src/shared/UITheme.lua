-- UITheme (ModuleScript, nur Client)
-- Einheitliches Design für alle Menüs: Farben, Schriften und Bausteine (Fläche, Knopf, Text).
-- Wichtig für saubere Zentrierung: Inhalte liegen auf einer "Leinwand" mit fester Größe in der
-- Bildschirmmitte, die als Ganzes skaliert wird (Canvas). So rutscht nichts nach links.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local UITheme = {}

UITheme.Colors = {
	Background = Color3.fromRGB(9, 11, 18),
	Panel = Color3.fromRGB(16, 19, 29),
	Card = Color3.fromRGB(24, 28, 41),
	CardHover = Color3.fromRGB(32, 37, 54),
	Border = Color3.fromRGB(52, 58, 80),
	Accent = Color3.fromRGB(255, 140, 40),
	AccentDark = Color3.fromRGB(210, 90, 20),
	Text = Color3.fromRGB(240, 242, 248),
	Muted = Color3.fromRGB(150, 158, 180),
	Good = Color3.fromRGB(90, 210, 120),
	Bad = Color3.fromRGB(240, 85, 85),
	Gold = Color3.fromRGB(255, 205, 80),
}

UITheme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.Gotham,
}

local C = UITheme.Colors

function UITheme.Make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end
local make = UITheme.Make

function UITheme.Corner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

function UITheme.Stroke(parent, color, thickness, transparency)
	return make("UIStroke", { Color = color or C.Border, Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

-- Senkrechter Verlauf (oben -> unten)
function UITheme.Gradient(parent, top, bottom, rotation)
	return make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 }, parent)
end

-- Text ohne Hintergrund
function UITheme.Label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or UITheme.Fonts.Bold
	props.TextColor3 = props.TextColor3 or C.Text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

-- Knopf mit abgerundeten Ecken, Verlauf und sanftem Hover-Effekt
function UITheme.Button(props, parent, onClick)
	local color = props.BackgroundColor3 or C.Card
	props.BackgroundColor3 = color
	props.BorderSizePixel = 0
	props.AutoButtonColor = false
	props.Font = props.Font or UITheme.Fonts.Title
	props.TextColor3 = props.TextColor3 or C.Text
	local button = make("TextButton", props, parent)
	UITheme.Corner(button, 10)
	UITheme.Gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 200))
	local scale = make("UIScale", {}, button)
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Fläche mit Rand (z.B. Karte oder Fenster)
function UITheme.Panel(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Panel
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	UITheme.Corner(frame, 14)
	UITheme.Stroke(frame, C.Border, 1)
	return frame
end

-- Zentrierte Leinwand mit fester Größe, die auf den Bildschirm skaliert wird
function UITheme.Canvas(parent, width, height)
	local canvas = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, width, 0, height), BackgroundTransparency = 1 }, parent)
	local scale = make("UIScale", {}, canvas)
	local function update()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(viewport.X / width, viewport.Y / height)
	end
	update()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return canvas
end

-- Hintergrund-Unschärfe, solange mindestens ein Menü offen ist
local blur = nil
local blurUsers = {}
function UITheme.SetBlur(user, on)
	blurUsers[user] = on or nil
	if not blur then
		blur = make("BlurEffect", { Name = "MenuBlur", Size = 0 }, Lighting)
	end
	local active = next(blurUsers) ~= nil
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = active and 16 or 0 }):Play()
end

return UITheme
