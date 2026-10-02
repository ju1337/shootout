-- UITheme (ModuleScript, nur Client)
-- Einheitliches Design für alle Menüs im nüchternen Taktik-Look: Graphit als Grund, gedecktes
-- Bernstein als einzige Signalfarbe (aktiv, Hauptknöpfe), Stahlblau für das eigene Team, Rot für
-- Gegner. Flache Knöpfe und Flächen mit kaum gerundeten Ecken und 1 px Rand, keine Schatten oder
-- Comic-Konturen. Überschriften, Zahlen und Knöpfe in der schmalen Oswald, kleine Beschriftungen in Gotham.
-- Achtung: Oswald kennt in Roblox nur lateinische Zeichen – Symbole wie ✕ ✓ ★ ◆ → ∞ erscheinen dort als
-- Kästchen. Solche Zeichen nur in Gotham-Texten verwenden oder zeichnen (Cross, Diamond, Coin).
-- Bausteine: Text, Überschrift, Knopf (Button, Chunky), Fläche (Panel, Card, HudPanel), Kontur,
-- Schild (Tag), Raute, Münze. Inhalte liegen auf einer "Leinwand" mit fester Größe in der
-- Bildschirmmitte, die als Ganzes skaliert wird (Canvas). So rutscht nichts nach links.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local UITheme = {}

-- Farben: dunkles Graphit, gedeckte Signalfarben (nichts Knalliges)
UITheme.Colors = {
	Background = Color3.fromRGB(12, 14, 17),   -- Grund (Graphit)
	Panel = Color3.fromRGB(19, 22, 26),        -- Flächen und Fenster
	Card = Color3.fromRGB(27, 31, 36),         -- Karten und Knöpfe in Flächen
	CardHover = Color3.fromRGB(35, 40, 46),    -- Hover, Spuren
	Secondary = Color3.fromRGB(35, 40, 46),
	MutedBack = Color3.fromRGB(30, 34, 40),
	Border = Color3.fromRGB(58, 64, 72),
	Primary = Color3.fromRGB(212, 170, 80),    -- gedecktes Bernstein: aktiv, Hauptknöpfe, Schilder
	PrimaryText = Color3.fromRGB(14, 16, 19),  -- dunkle Schrift auf Bernstein/Blau
	Accent = Color3.fromRGB(96, 164, 214),     -- Stahlblau: eigenes Team, Verbündete
	AccentDark = Color3.fromRGB(40, 78, 108),
	Play = Color3.fromRGB(212, 170, 80),       -- großer SPIELEN-Knopf
	Text = Color3.fromRGB(228, 231, 235),
	Muted = Color3.fromRGB(134, 142, 152),     -- gedämpfte Schrift
	Good = Color3.fromRGB(112, 178, 112),
	Bad = Color3.fromRGB(206, 70, 58),         -- Gegner, Warnungen
	Gold = Color3.fromRGB(200, 166, 92),
	Shadow = Color3.new(0, 0, 0),
}
UITheme.Colors.Ally = UITheme.Colors.Accent
UITheme.Colors.Enemy = UITheme.Colors.Bad

UITheme.Fonts = {
	Display = Enum.Font.Oswald,      -- schmale Überschriften, Zahlen und Knöpfe (Großbuchstaben)
	Title = Enum.Font.Oswald,
	Bold = Enum.Font.GothamBold,     -- kleine Beschriftungen
	Medium = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
}

-- Kaum gerundete Ecken (Namen bleiben, damit alle Fenster dieselben Stufen nutzen)
UITheme.Radius = { Small = 2, Medium = 3, Large = 3, XL = 4, XXL = 6 }

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

-- Dezente dunkle Kante um Schrift (lesbar auf hellen 3D-Bildern, aber keine dicke Comic-Kontur)
function UITheme.Outline(textObject, thickness, color)
	return make("UIStroke", { Color = color or C.Shadow, Thickness = math.min(thickness or 1, 1.5), Transparency = 0.55,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round }, textObject)
end

-- Schmale Display-Schrift nur für große Texte: klein ist Oswald schlecht lesbar, dort Gotham Bold
function UITheme.FontFor(font, textSize)
	if font == UITheme.Fonts.Display and (textSize or 14) < 16 then
		return UITheme.Fonts.Bold
	end
	return font
end

-- Text ohne Hintergrund
function UITheme.Label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = UITheme.FontFor(props.Font or UITheme.Fonts.Bold, props.TextSize)
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
	props.TextSize = props.TextSize or 12
	props.Font = UITheme.FontFor(props.Font or UITheme.Fonts.Display, props.TextSize)
	props.Size = props.Size or UDim2.new(0, 0, 0, (props.TextSize or 12) + 10)
	props.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.X
	props.TextXAlignment = Enum.TextXAlignment.Center
	local tag = UITheme.Label(props, parent)
	UITheme.Corner(tag, UITheme.Radius.Small)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tag)
	return tag
end

-- Farbe leicht aufhellen (Hover)
local function brighten(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount or 0.07)
end
UITheme.Brighten = brighten

-- Flacher Knopf (gibt den TextButton zurück): kaum gerundet, beim Überfahren eine helle Schicht,
-- beim Drücken eine dunkle. Für Knöpfe, deren Text/Farbe der Aufrufer direkt setzt.
function UITheme.Button(props, parent, onClick)
	local color = props.BackgroundColor3 or C.Card
	props.BackgroundColor3 = color
	props.BorderSizePixel = 0
	props.AutoButtonColor = false
	props.Font = UITheme.FontFor(props.Font or UITheme.Fonts.Display, props.TextSize)
	props.TextColor3 = props.TextColor3 or C.Text
	local button = make("TextButton", props, parent)
	UITheme.Corner(button, UITheme.Radius.Small)
	-- Hover/Drücken: Schicht darüber (die Knopffarbe selbst bleibt beim Aufrufer)
	local glow = make("Frame", { Name = "Hover", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0 }, button)
	UITheme.Corner(glow, UITheme.Radius.Small)
	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		glow.BackgroundColor3 = Color3.new(1, 1, 1)
		glow.BackgroundTransparency = 0.94
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		glow.BackgroundTransparency = 1
	end)
	button.MouseButton1Down:Connect(function()
		glow.BackgroundColor3 = Color3.new(0, 0, 0)
		glow.BackgroundTransparency = 0.85
	end)
	button.MouseButton1Up:Connect(function()
		glow.BackgroundColor3 = Color3.new(1, 1, 1)
		glow.BackgroundTransparency = hovering and 0.94 or 1
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Flache Schaltfläche (früher "klobiger Knopf", Name und Schnittstelle bleiben): Fläche mit 1 px Rand,
-- beim Überfahren etwas heller, beim Drücken etwas dunkler.
-- props: Position, Size (Größe der Fläche), AnchorPoint, LayoutOrder, Visible, Name, ZIndex sowie
--   Color (Fläche), TextColor, Text, TextSize, Font, Radius, StrokeColor/StrokeThickness (Rand),
--   TextXAlignment.
-- Gibt ein Objekt zurück: { Button (TextButton, für Ereignisse/Layout), Face, Label, Stroke,
--   SetColor(color, textColor), SetText(text), SetStroke(color, thickness) }
function UITheme.Chunky(props, parent, onClick)
	local size = props.Size or UDim2.fromOffset(160, 48)
	local radius = props.Radius or UITheme.Radius.Small
	local button = make("TextButton", { Name = props.Name or "Chunky", AnchorPoint = props.AnchorPoint or Vector2.zero,
		Position = props.Position or UDim2.new(), Size = size, BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, LayoutOrder = props.LayoutOrder or 0, Visible = props.Visible ~= false,
		ZIndex = props.ZIndex or 1, Selectable = true }, parent)
	local color = props.Color or C.Card
	local face = make("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color,
		BorderSizePixel = 0, ZIndex = button.ZIndex }, button)
	UITheme.Corner(face, radius)
	local stroke = nil
	if props.StrokeColor then
		stroke = UITheme.Stroke(face, props.StrokeColor, math.min(props.StrokeThickness or 1, 1))
	end
	local label = UITheme.Label({ Name = "Label", Size = UDim2.fromScale(1, 1), Text = props.Text or "",
		TextSize = props.TextSize or 18, Font = props.Font or UITheme.Fonts.Display, TextColor3 = props.TextColor or C.Text,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center, ZIndex = button.ZIndex,
		TextWrapped = props.TextWrapped == true }, face)
	if label.TextXAlignment ~= Enum.TextXAlignment.Center then
		make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, label)
	end

	local chunky = { Button = button, Face = face, Label = label, Stroke = stroke }
	local baseColor = color
	local hovering, pressing = false, false
	local function refresh()
		if pressing then
			face.BackgroundColor3 = baseColor:Lerp(Color3.new(0, 0, 0), 0.12)
		else
			face.BackgroundColor3 = hovering and brighten(baseColor) or baseColor
		end
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
	-- Rand: höchstens 2 px (Auswahl zeigt die Farbe, kein dicker Comic-Rahmen)
	function chunky.SetStroke(strokeColor, thickness)
		if not stroke then
			stroke = UITheme.Stroke(face, strokeColor, 1)
			chunky.Stroke = stroke
		end
		stroke.Color = strokeColor
		stroke.Thickness = math.min(thickness or stroke.Thickness, 2)
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

-- Fläche mit 1 px Rand (z.B. Karte oder Fenster, auch in Layouts)
function UITheme.Panel(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Panel
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	UITheme.Corner(frame, UITheme.Radius.XL)
	UITheme.Stroke(frame, C.Border, 1)
	return frame
end

-- Fläche für Fenster und Kästen: leicht durchsichtig, 1 px Rand, kaum gerundet, ohne Schatten.
-- props.Radius (optional) überschreibt die Rundung.
function UITheme.Card(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.12
	props.BorderSizePixel = 0
	props.ZIndex = props.ZIndex or 2
	local radius = math.min(props.Radius or UITheme.Radius.XL, UITheme.Radius.XL)
	props.Radius = nil
	local frame = make("Frame", props, parent)
	UITheme.Corner(frame, radius)
	UITheme.Stroke(frame, C.Border, 1, 0.25)
	return frame
end

-- HUD-Fläche über der 3D-Welt: dunkel und durchsichtig, zur Bildmitte hin auslaufend
-- (fadeTo = "Right" oder "Left": diese Seite wird durchsichtiger), ohne Rand.
function UITheme.HudPanel(props, parent, fadeTo)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Background
	props.BackgroundTransparency = props.BackgroundTransparency or 0.3
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	UITheme.Corner(frame, UITheme.Radius.Small)
	if fadeTo then
		local fade = fadeTo == "Right" and { 0, 0.55 } or { 0.55, 0 }
		make("UIGradient", { Transparency = NumberSequence.new(fade[1], fade[2]) }, frame)
	end
	return frame
end

-- Schließen-Kreuz aus zwei Strichen (unabhängig von der Schrift: Oswald hat kein "✕")
function UITheme.Cross(parent, size, color, thickness)
	local holder = make("Frame", { Name = "Cross", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, parent)
	for _, rotation in { 45, -45 } do
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1.3, 0, 0, thickness or 2), Rotation = rotation, BackgroundColor3 = color or C.Text,
			BorderSizePixel = 0 }, holder)
	end
	return holder
end

-- Münze als kleines Symbol (statt Emoji): Bernstein-Scheibe mit dunklem Innenring
function UITheme.Coin(parent, size, props)
	props = props or {}
	props.Size = UDim2.fromOffset(size, size)
	props.BackgroundColor3 = C.Gold
	props.BorderSizePixel = 0
	local coin = make("Frame", props, parent)
	UITheme.Corner(coin, size)
	local inner = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56), BackgroundTransparency = 1, ZIndex = coin.ZIndex }, coin)
	UITheme.Corner(inner, size)
	UITheme.Stroke(inner, C.Gold:Lerp(C.Shadow, 0.45), 1)
	return coin
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
		UITheme.Stroke(diamond, strokeColor, 1)
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
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = active and 14 or 0 }):Play()
end

return UITheme
