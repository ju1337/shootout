-- UITheme (ModuleScript, nur Client)
-- Einheitliches, cleanes Design für alle Menüs und das HUD: fast schwarzes Neutralgrau als Grund, ruhige Flächen
-- mit haarfeinem hellem Rand, Bernstein als einzige Signalfarbe (aktiv, Hauptknöpfe), Stahlblau für das eigene
-- Team, Rot für Gegner. Flach, knappe Rundungen, keine Schatten, keine Comic-Konturen. Schrift durchgehend
-- Builder Sans (die moderne Roblox-Schrift): Überschriften und Zahlen extra fett, Beschriftungen fett/mittel.
-- Sonderzeichen wie ✕ ✓ ★ ◆ → ∞ besser zeichnen (Cross, Diamond, Coin) – nicht jede Schrift hat sie.
-- Bausteine: Text, Überschrift, Knopf (Button, Chunky), Fläche (Panel, Card, HudPanel), Akzentstreifen (AccentBar),
-- Kontur, Schild (Tag), Raute, Münze, RAP-Symbol. Inhalte liegen auf einer "Leinwand" mit fester Größe in der
-- Bildschirmmitte, die als Ganzes skaliert wird (Canvas). So rutscht nichts nach links.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local UITheme = {}

-- Farben: neutrales, fast schwarzes Grau, klare Signalfarben (nichts Knalliges)
UITheme.Colors = {
	Background = Color3.fromRGB(10, 11, 13),   -- Grund
	Panel = Color3.fromRGB(16, 18, 21),        -- Flächen und Fenster
	Card = Color3.fromRGB(24, 27, 31),         -- Karten und Knöpfe in Flächen
	CardHover = Color3.fromRGB(32, 36, 41),    -- Hover, Spuren
	Secondary = Color3.fromRGB(32, 36, 41),
	MutedBack = Color3.fromRGB(27, 30, 35),
	Border = Color3.fromRGB(52, 57, 64),       -- Ränder (haarfein, siehe Stroke)
	Primary = Color3.fromRGB(236, 178, 70),    -- Bernstein: aktiv, Hauptknöpfe, Schilder
	PrimaryText = Color3.fromRGB(12, 13, 15),  -- dunkle Schrift auf Bernstein/Blau
	Accent = Color3.fromRGB(88, 164, 226),     -- Stahlblau: eigenes Team, Verbündete
	AccentDark = Color3.fromRGB(34, 72, 104),
	Play = Color3.fromRGB(236, 178, 70),       -- großer SPIELEN-Knopf
	Text = Color3.fromRGB(236, 238, 241),
	Muted = Color3.fromRGB(136, 144, 156),     -- gedämpfte Schrift
	Good = Color3.fromRGB(104, 194, 122),
	Bad = Color3.fromRGB(228, 76, 64),         -- Gegner, Warnungen
	Gold = Color3.fromRGB(214, 176, 96),
	Rap = Color3.fromRGB(86, 214, 170),        -- RAP (zweite Währung, RapConfig.Color)
	Shadow = Color3.new(0, 0, 0),
}
-- Farben im Menü der offenen Welt (halbtransparent, Rot als Akzent statt Bernstein): Seiten im Menü nehmen diese
-- Tabelle statt Colors; was hier fehlt, kommt aus Colors
UITheme.MenuColors = setmetatable({
	Primary = Color3.fromRGB(214, 58, 58),
	PrimaryText = Color3.fromRGB(255, 255, 255),
	Card = Color3.fromRGB(18, 19, 23),
	CardHover = Color3.fromRGB(30, 32, 37),
	Panel = Color3.fromRGB(26, 27, 31),
	MutedBack = Color3.fromRGB(26, 27, 31),
}, { __index = UITheme.Colors })
UITheme.Colors.Ally = UITheme.Colors.Accent
UITheme.Colors.Enemy = UITheme.Colors.Bad

UITheme.Fonts = {
	Display = Enum.Font.BuilderSansExtraBold, -- Überschriften, Zahlen und Knöpfe (Großbuchstaben)
	Title = Enum.Font.BuilderSansBold,
	Bold = Enum.Font.BuilderSansBold,         -- Beschriftungen
	Medium = Enum.Font.BuilderSansMedium,
	Body = Enum.Font.BuilderSans,
}

-- Knappe, präzise Rundungen. Alle Fenster nutzen dieselben Stufen.
UITheme.Radius = { Small = 4, Medium = 6, Large = 8, XL = 10, XXL = 12 }
UITheme.MinRadius = 3 -- auch fest eingetragene kleine Rundungen werden mindestens so weich
UITheme.MaxRadius = 12 -- fest eingetragene große Rundungen höchstens so rund (Pillen mit Rundung in Skala bleiben)

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
	local r = radius or UITheme.Radius.Medium
	-- sehr große Werte sind Kreise/Pillen (z.B. Corner(frame, size)): die bleiben rund
	if r < 40 then
		r = math.clamp(r, UITheme.MinRadius, UITheme.MaxRadius)
	end
	return make("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

-- Rand: der Standardrand (ohne Farbe) ist eine haarfeine helle Linie, die auf jedem Grund ruhig wirkt
function UITheme.Stroke(parent, color, thickness, transparency)
	local hairline = color == nil or color == C.Border
	return make("UIStroke", { Color = hairline and Color3.new(1, 1, 1) or color, Thickness = thickness or 1,
		Transparency = hairline and 0.9 + (transparency or 0) * 0.1 or (transparency or 0),
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

-- Extra fette Display-Schrift nur für große Texte: klein wirkt sie gedrungen, dort Bold
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

-- Fläche für Fenster und Kästen: leicht durchsichtig, 1 px Rand, weich gerundet, ohne Schatten.
-- props.Radius (optional) überschreibt die Rundung.
function UITheme.Card(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.06
	props.BorderSizePixel = 0
	props.ZIndex = props.ZIndex or 2
	local radius = math.min(props.Radius or UITheme.Radius.XL, UITheme.Radius.XL)
	props.Radius = nil
	local frame = make("Frame", props, parent)
	UITheme.Corner(frame, radius)
	UITheme.Stroke(frame, C.Border, 1)
	return frame
end

-- Farbiger Akzentstreifen an der Kante einer abgerundeten Karte (Standard oben). Ein eckiger Streifen über die volle
-- Breite ragt an den gerundeten Ecken über die Karte hinaus; dieser liegt an der Kante an, ist an beiden Enden um den
-- Eckenradius der Karte eingerückt (bleibt also auf der geraden Kante) und hat voll gerundete Enden.
-- Radius aus dem UICorner der Karte (ohne festen Radius: UITheme.Radius.XL).
-- props (optional): Side ("Top", "Bottom", "Left", "Right"), Thickness (Standard 3 px), Inset (Abstand der Enden von
--   den Ecken, mindestens der Radius) sowie Eigenschaften des Frames (Name, ZIndex, Visible, BackgroundTransparency ...).
-- Gibt den Frame zurück.
function UITheme.AccentBar(parent, color, props)
	local options = props or {}
	local side = options.Side or "Top"
	local thickness = options.Thickness or 3
	local radius = UITheme.Radius.XL
	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner and corner.CornerRadius.Scale == 0 then
		radius = corner.CornerRadius.Offset
	end
	local inset = math.max(options.Inset or 0, radius)
	local frameProps = { Name = "Accent", BackgroundColor3 = color or C.Primary, BorderSizePixel = 0,
		ZIndex = parent:IsA("GuiObject") and parent.ZIndex or 1 }
	for key, value in options do
		if key ~= "Side" and key ~= "Thickness" and key ~= "Inset" then
			frameProps[key] = value
		end
	end
	if side == "Left" or side == "Right" then
		frameProps.AnchorPoint = Vector2.new(side == "Right" and 1 or 0, 0)
		frameProps.Position = UDim2.new(side == "Right" and 1 or 0, 0, 0, inset)
		frameProps.Size = UDim2.new(0, thickness, 1, -2 * inset)
	else
		frameProps.AnchorPoint = Vector2.new(0, side == "Bottom" and 1 or 0)
		frameProps.Position = UDim2.new(0, inset, side == "Bottom" and 1 or 0, 0)
		frameProps.Size = UDim2.new(1, -2 * inset, 0, thickness)
	end
	local bar = make("Frame", frameProps, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, bar) -- runde Enden (Roblox begrenzt auf die halbe Dicke)
	return bar
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

-- Schließen-Kreuz aus zwei Strichen (unabhängig von der Schrift)
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

-- RAP als kleines Symbol (statt Text): mintgrüne Raute mit dunklem Kern. Beide Rauten sind Geschwister im Halter
-- (Kinder gedrehter Rahmen würden mitgedreht).
function UITheme.RapIcon(parent, size, props)
	props = props or {}
	props.Size = UDim2.fromOffset(size, size)
	props.BackgroundTransparency = 1
	local holder = make("Frame", props, parent)
	local outer = make("Frame", { Name = "Outer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72), Rotation = 45, BackgroundColor3 = C.Rap, BorderSizePixel = 0,
		ZIndex = holder.ZIndex }, holder)
	make("UICorner", { CornerRadius = UDim.new(0, math.max(1, math.floor(size / 8))) }, outer)
	make("Frame", { Name = "Core", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.3), Rotation = 45, BackgroundColor3 = C.Rap:Lerp(C.Shadow, 0.55), BorderSizePixel = 0,
		ZIndex = holder.ZIndex }, holder)
	return holder
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

-- Hat user (z.B. "Market", "Trade") gerade ein Fenster mit Unschärfe offen?
function UITheme.IsMenuOpenBy(user)
	return blurUsers[user] == true
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
