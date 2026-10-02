-- UITheme (ModuleScript, nur Client)
-- Einheitliches Design für alle Menüs (Design "BLOCKOPS"): Stahl-Navy als Grund, Signalgelb als
-- Hauptfarbe (aktiv, Hauptknöpfe), Cyan für das eigene Team, Rot für Gegner. Klobige Knöpfe mit
-- Schatten darunter, die beim Drücken nach unten rutschen, Flächen mit runden Ecken, 2 px Rand und
-- Schatten, große Überschriften in schwerer Schrift mit Kontur in der Grundfarbe.
-- Bausteine: Text, Überschrift, Knopf (Button, Chunky), Fläche (Panel, Card), Kontur, Schild (Tag),
-- Raute. Inhalte liegen auf einer "Leinwand" mit fester Größe in der Bildschirmmitte, die als
-- Ganzes skaliert wird (Canvas). So rutscht nichts nach links.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local UITheme = {}

-- Farben aus dem Design (oklch-Werte in RGB umgerechnet)
UITheme.Colors = {
	Background = Color3.fromRGB(12, 22, 38),   -- Grund (Stahl-Navy)
	Panel = Color3.fromRGB(24, 36, 55),        -- Flächen und Fenster ("card")
	Card = Color3.fromRGB(31, 44, 66),         -- Karten und Knöpfe in Flächen
	CardHover = Color3.fromRGB(37, 51, 74),    -- "secondary": Hover, Spuren
	Secondary = Color3.fromRGB(37, 51, 74),
	MutedBack = Color3.fromRGB(34, 46, 66),
	Border = Color3.fromRGB(52, 67, 91),
	Primary = Color3.fromRGB(255, 195, 26),    -- Signalgelb: aktiv, Hauptknöpfe, Schilder
	PrimaryText = Color3.fromRGB(12, 22, 38),  -- dunkle Schrift auf Gelb/Cyan
	Accent = Color3.fromRGB(44, 204, 235),     -- Cyan: eigenes Team, Verbündete
	AccentDark = Color3.fromRGB(24, 104, 132),
	Play = Color3.fromRGB(255, 195, 26),       -- großer SPIELEN-Knopf
	Text = Color3.fromRGB(237, 242, 248),
	Muted = Color3.fromRGB(152, 166, 184),     -- gedämpfte Schrift
	Good = Color3.fromRGB(80, 210, 130),
	Bad = Color3.fromRGB(249, 65, 68),         -- Gegner, Warnungen
	Gold = Color3.fromRGB(255, 205, 80),
	Shadow = Color3.new(0, 0, 0),
}
UITheme.Colors.Ally = UITheme.Colors.Accent
UITheme.Colors.Enemy = UITheme.Colors.Bad

UITheme.Fonts = {
	Display = Enum.Font.GothamBlack, -- große, schwere Überschriften und Knöpfe
	Title = Enum.Font.Oswald,        -- schmale Zahlen und Zeilen (ältere Fenster)
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
}

-- Rundungen wie im Design (rem * 16)
UITheme.Radius = { Small = 6, Medium = 10, Large = 12, XL = 16, XXL = 22 }

local SHADOW = 5          -- Schatten unter klobigen Knöpfen (px)
local PANEL_SHADOW = 6    -- Schatten unter Flächen
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

-- Kontur um Schrift in der Grundfarbe (Design: "text-outline"), für große Namen auf Bildern
function UITheme.Outline(textObject, thickness, color)
	return make("UIStroke", { Color = color or C.Background, Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round }, textObject)
end

-- Text ohne Hintergrund
function UITheme.Label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or UITheme.Fonts.Bold
	props.TextColor3 = props.TextColor3 or C.Text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

-- Großbuchstaben inkl. Umlaute (string.upper kennt nur ASCII: "Sanitäter" -> "SANITäTER")
function UITheme.Upper(text)
	local upper = string.upper(text or "")
	upper = string.gsub(upper, "ä", "Ä")
	upper = string.gsub(upper, "ö", "Ö")
	upper = string.gsub(upper, "ü", "Ü")
	return upper
end

-- Überschrift in der schweren Schrift, Großbuchstaben (Text wird umgewandelt)
function UITheme.Heading(props, parent)
	props.Font = props.Font or UITheme.Fonts.Display
	props.Text = UITheme.Upper(props.Text)
	return UITheme.Label(props, parent)
end

-- Kleines Schild mit Hintergrund (Rolle, BEREIT, DUELS ...). Breite passt sich dem Text an.
function UITheme.Tag(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 0
	props.BackgroundColor3 = props.BackgroundColor3 or C.Primary
	props.TextColor3 = props.TextColor3 or C.PrimaryText
	props.Font = props.Font or UITheme.Fonts.Display
	props.TextSize = props.TextSize or 12
	props.Size = props.Size or UDim2.new(0, 0, 0, (props.TextSize or 12) + 10)
	props.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.X
	props.TextXAlignment = Enum.TextXAlignment.Center
	local tag = UITheme.Label(props, parent)
	UITheme.Corner(tag, UITheme.Radius.Small)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tag)
	return tag
end

-- Farbe leicht aufhellen (Hover, Design: brightness 1.08)
local function brighten(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount or 0.08)
end
UITheme.Brighten = brighten

-- Knopf (gibt den TextButton zurück): runde Ecken, dunkle Unterkante als 3D-Lippe, die beim Drücken
-- flach wird. Für Knöpfe, deren Text/Farbe der Aufrufer direkt setzt.
function UITheme.Button(props, parent, onClick)
	local color = props.BackgroundColor3 or C.Card
	props.BackgroundColor3 = color
	props.BorderSizePixel = 0
	props.AutoButtonColor = false
	props.Font = props.Font or UITheme.Fonts.Display
	props.TextColor3 = props.TextColor3 or C.Text
	local button = make("TextButton", props, parent)
	UITheme.Corner(button, UITheme.Radius.Large)
	local lip = make("Frame", { Name = "Lip", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, SHADOW), BackgroundColor3 = C.Shadow, BackgroundTransparency = 0.65, BorderSizePixel = 0 }, button)
	UITheme.Corner(lip, UITheme.Radius.Large)
	-- Hover: leicht helle Schicht darüber (die Knopffarbe selbst bleibt beim Aufrufer)
	local glow = make("Frame", { Name = "Hover", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0 }, button)
	UITheme.Corner(glow, UITheme.Radius.Large)
	local function setPressed(pressed)
		lip.Size = UDim2.new(1, 0, 0, pressed and 1 or SHADOW)
	end
	button.MouseEnter:Connect(function()
		glow.BackgroundTransparency = 0.92
	end)
	button.MouseLeave:Connect(function()
		glow.BackgroundTransparency = 1
		setPressed(false)
	end)
	button.MouseButton1Down:Connect(function()
		setPressed(true)
	end)
	button.MouseButton1Up:Connect(function()
		setPressed(false)
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Klobiger Knopf wie im Design (.btn-chunky): Fläche mit Schatten (5 px) darunter, beim Drücken
-- rutscht die Fläche 4 px nach unten, beim Überfahren wird sie etwas heller.
-- props: Position, Size (Größe der Fläche), AnchorPoint, LayoutOrder, Visible, Name, ZIndex sowie
--   Color (Fläche), TextColor, Text, TextSize, Font, Radius, StrokeColor/StrokeThickness (Rand),
--   TextXAlignment.
-- Gibt ein Objekt zurück: { Button (TextButton, für Ereignisse/Layout), Face, Label, Stroke,
--   SetColor(color, textColor), SetText(text), SetStroke(color, thickness) }
function UITheme.Chunky(props, parent, onClick)
	local size = props.Size or UDim2.fromOffset(160, 48)
	local radius = props.Radius or UITheme.Radius.Large
	local button = make("TextButton", { Name = props.Name or "Chunky", AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(), Size = size + UDim2.fromOffset(0, SHADOW), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, LayoutOrder = props.LayoutOrder or 0, Visible = props.Visible ~= false,
		ZIndex = props.ZIndex or 1, Selectable = true }, parent)
	local shadow = make("Frame", { Name = "Shadow", Position = UDim2.fromOffset(0, SHADOW), Size = UDim2.new(1, 0, 1, -SHADOW),
		BackgroundColor3 = C.Shadow, BackgroundTransparency = 0.65, BorderSizePixel = 0, ZIndex = button.ZIndex }, button)
	UITheme.Corner(shadow, radius)
	local color = props.Color or C.Card
	local face = make("Frame", { Name = "Face", Size = UDim2.new(1, 0, 1, -SHADOW), BackgroundColor3 = color,
		BorderSizePixel = 0, ZIndex = button.ZIndex }, button)
	UITheme.Corner(face, radius)
	local stroke = nil
	if props.StrokeColor then
		stroke = UITheme.Stroke(face, props.StrokeColor, props.StrokeThickness or 2)
	end
	local label = UITheme.Label({ Name = "Label", Size = UDim2.fromScale(1, 1), Text = props.Text or "",
		TextSize = props.TextSize or 18, Font = props.Font or UITheme.Fonts.Display, TextColor3 = props.TextColor or C.Text,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center, ZIndex = button.ZIndex,
		TextWrapped = props.TextWrapped == true }, face)
	if label.TextXAlignment ~= Enum.TextXAlignment.Center then
		make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, label)
	end

	local chunky = { Button = button, Face = face, Label = label, Stroke = stroke, Shadow = shadow }
	local baseColor = color
	local hovering, pressing = false, false
	local function refresh()
		face.BackgroundColor3 = hovering and brighten(baseColor) or baseColor
		face.Position = UDim2.fromOffset(0, pressing and SHADOW - 1 or 0)
	end
	function chunky.SetColor(newColor, textColor)
		baseColor = newColor
		if textColor then
			label.TextColor3 = textColor
		end
		refresh()
	end
	function chunky.SetText(text)
		label.Text = text
	end
	function chunky.SetStroke(strokeColor, thickness)
		if not stroke then
			stroke = UITheme.Stroke(face, strokeColor, thickness or 2)
			chunky.Stroke = stroke
		end
		stroke.Color = strokeColor
		stroke.Thickness = thickness or stroke.Thickness
	end
	button.MouseEnter:Connect(function()
		hovering = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovering, pressing = false, false
		refresh()
	end)
	button.MouseButton1Down:Connect(function()
		pressing = true
		refresh()
	end)
	button.MouseButton1Up:Connect(function()
		pressing = false
		refresh()
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return chunky
end

-- Fläche mit Rand (z.B. Karte oder Fenster). Liegt sie in einem Layout, ohne Schatten.
function UITheme.Panel(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Panel
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	UITheme.Corner(frame, UITheme.Radius.XL)
	UITheme.Stroke(frame, C.Border, 2)
	return frame
end

-- Fläche wie im Design (.panel): runde Ecken, 2 px Rand, leicht durchsichtig, Schatten darunter.
-- Der Schatten ist ein Geschwister-Frame und folgt Position, Größe und Sichtbarkeit der Fläche –
-- darum nicht in UIListLayout/UIGridLayout verwenden (dort UITheme.Panel).
function UITheme.Card(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.12
	props.BorderSizePixel = 0
	props.ZIndex = props.ZIndex or 2
	local radius = props.Radius or UITheme.Radius.XL
	props.Radius = nil
	local shadow = make("Frame", { Name = (props.Name or "Card") .. "Shadow", BackgroundColor3 = C.Shadow,
		BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = props.ZIndex - 1 }, parent)
	UITheme.Corner(shadow, radius)
	local frame = make("Frame", props, parent)
	UITheme.Corner(frame, radius)
	UITheme.Stroke(frame, C.Border, 2)
	local function sync()
		shadow.AnchorPoint = frame.AnchorPoint
		shadow.Position = frame.Position + UDim2.fromOffset(0, PANEL_SHADOW)
		shadow.Size = frame.Size
		shadow.Visible = frame.Visible
	end
	sync()
	for _, property in { "Position", "Size", "AnchorPoint", "Visible" } do
		frame:GetPropertyChangedSignal(property):Connect(sync)
	end
	frame.Destroying:Connect(function()
		shadow:Destroy()
	end)
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

-- Vollbild-Ebene, die mit der Bildschirmgröße skaliert (HUD auf Handy kleiner, auf PC 1:1).
-- Kinder positioniert man wie gewohnt an den Rändern. Gibt den Frame zurück.
function UITheme.ScaledRoot(screenGui, designWidth, designHeight, minScale)
	designWidth, designHeight = designWidth or 1600, designHeight or 900
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0) }, screenGui)
	local scale = make("UIScale", {}, root)
	local function update()
		local viewport = workspace.CurrentCamera.ViewportSize
		local s = math.clamp(math.min(viewport.X / designWidth, viewport.Y / designHeight), minScale or 0.45, 1)
		scale.Scale = s
		-- Größe ausgleichen, damit die Ebene nach dem Skalieren wieder den ganzen Bildschirm füllt
		root.Size = UDim2.new(1 / s, 0, 1 / s, 0)
	end
	update()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return root
end

-- Raute (gedrehtes Quadrat) als Schmuckelement. Kinder würden mitgedreht,
-- darum Texte als Geschwister darüberlegen.
function UITheme.Diamond(parent, size, position, color, strokeColor)
	local diamond = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.new(0, size, 0, size),
		Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0 }, parent)
	if strokeColor then
		UITheme.Stroke(diamond, strokeColor, 2)
	end
	return diamond
end

-- Zahl mit Tausenderpunkten ("12.450")
function UITheme.FormatNumber(n)
	local s = tostring(math.floor(n or 0))
	local formatted = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1.")))
	return (string.gsub(formatted, "^%.", ""))
end

-- Hintergrund-Unschärfe, solange mindestens ein Menü offen ist
local blur = nil
local blurUsers = {}

-- Ist gerade ein Menü mit Unschärfe offen (Spielmenü, Seitenmenü)?
function UITheme.IsMenuOpen()
	return next(blurUsers) ~= nil
end
function UITheme.SetBlur(user, on)
	blurUsers[user] = on or nil
	if not blur then
		blur = make("BlurEffect", { Name = "MenuBlur", Size = 0 }, Lighting)
	end
	local active = next(blurUsers) ~= nil
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = active and 16 or 0 }):Play()
end

return UITheme
