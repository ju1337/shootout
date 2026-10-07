-- Akzentstreifen (UITheme.AccentBar) an abgerundeten Karten: Der Streifen liegt an der Kante an, ist an beiden Enden um
-- den Eckenradius der Karte eingerückt (ragt nie über die Rundung) und hat voll gerundete Enden. Oben (Standard),
-- unten, links und rechts; Radius aus dem UICorner der Karte, ohne Rundung UITheme.Radius.XL; Name und weitere
-- Eigenschaften werden übernommen
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local UITheme = require("UITheme")
local C = UITheme.Colors

local function udim(value, scale, offset)
	return value.Scale == scale and value.Offset == offset
end

-- Enden voll gerundet (UICorner mit Skala 1 = halbe Dicke)
local function roundEnds(bar)
	local corner = bar:FindFirstChildOfClass("UICorner")
	return corner ~= nil and udim(corner.CornerRadius, 1, 0)
end

-- Karte wie im Spiel (UITheme.Card: Radius XL = 14)
local holder = Instance.new("Frame")
local card = UITheme.Card({ Name = "Window", Size = UDim2.fromOffset(600, 400), ZIndex = 5 }, holder)
local radius = card:FindFirstChildOfClass("UICorner").CornerRadius.Offset
check(radius == UITheme.Radius.XL, "Karte mit Radius XL")

local top = UITheme.AccentBar(card, C.Rap)
check(top ~= nil and top.Parent == card and top:IsA("Frame"), "Streifen als Frame in der Karte")
check(top.Name == "Accent", "Standardname Accent")
check(top.BackgroundColor3 == C.Rap and top.BorderSizePixel == 0, "Farbe übernommen, kein Rahmen")
check(top.ZIndex == card.ZIndex, "ZIndex wie die Karte")
check(udim(top.Position.X, 0, radius) and udim(top.Position.Y, 0, 0), "oben: links um den Radius eingerückt, liegt oben an")
check(udim(top.Size.X, 1, -2 * radius) and udim(top.Size.Y, 0, 3), "oben: rechts ebenso eingerückt, 3 px dick")
check(top.AnchorPoint.X == 0 and top.AnchorPoint.Y == 0, "oben: Ankerpunkt oben links")
check(roundEnds(top), "oben: runde Enden")
-- in Pixeln: der Streifen beginnt erst dort, wo die obere Kante gerade wird
local barStart = top.Position.X.Offset
local barEnd = card.Size.X.Offset + top.Size.X.Offset + top.Position.X.Offset
check(barStart >= radius and barEnd <= card.Size.X.Offset - radius, "oben: Streifen bleibt innerhalb der Rundung")

-- Name, Dicke, ZIndex und weitere Eigenschaften
local named = UITheme.AccentBar(card, C.Primary, { Name = "Marker", Thickness = 4, ZIndex = 9, Visible = false,
	BackgroundTransparency = 0.5 })
check(named.Name == "Marker" and named.ZIndex == 9 and named.Visible == false and named.BackgroundTransparency == 0.5,
	"Name, ZIndex, Sichtbarkeit und Durchsichtigkeit übernommen")
check(udim(named.Size.Y, 0, 4), "Dicke 4 px")

-- größerer Abstand möglich, aber nie weniger als der Radius
local wide = UITheme.AccentBar(card, C.Primary, { Inset = 30 })
check(udim(wide.Position.X, 0, 30) and udim(wide.Size.X, 1, -60), "Inset größer als der Radius")
local tight = UITheme.AccentBar(card, C.Primary, { Inset = 2 })
check(udim(tight.Position.X, 0, radius) and udim(tight.Size.X, 1, -2 * radius), "Inset kleiner als der Radius: Radius gilt")

-- seitlich an einer Listenkarte mit kleinerem Radius
local row = Instance.new("Frame")
row.Size = UDim2.fromOffset(300, 46)
row.ZIndex = 3
UITheme.Corner(row, UITheme.Radius.Small)
local left = UITheme.AccentBar(row, C.Good, { Side = "Left", Thickness = 4 })
check(udim(left.Position.X, 0, 0) and udim(left.Position.Y, 0, UITheme.Radius.Small), "links: liegt links an, oben eingerückt")
check(udim(left.Size.X, 0, 4) and udim(left.Size.Y, 1, -2 * UITheme.Radius.Small), "links: unten eingerückt, 4 px breit")
check(left.ZIndex == 3 and roundEnds(left), "links: ZIndex der Karte, runde Enden")
local right = UITheme.AccentBar(row, C.Bad, { Side = "Right", Thickness = 2 })
check(right.AnchorPoint.X == 1 and right.AnchorPoint.Y == 0 and udim(right.Position.X, 1, 0)
	and udim(right.Position.Y, 0, UITheme.Radius.Small), "rechts: liegt rechts an, oben eingerückt")
check(udim(right.Size.X, 0, 2) and udim(right.Size.Y, 1, -2 * UITheme.Radius.Small) and roundEnds(right),
	"rechts: unten eingerückt, runde Enden")
local bottom = UITheme.AccentBar(row, C.Gold, { Side = "Bottom" })
check(bottom.AnchorPoint.Y == 1 and udim(bottom.Position.Y, 1, 0) and udim(bottom.Position.X, 0, UITheme.Radius.Small)
	and udim(bottom.Size.X, 1, -2 * UITheme.Radius.Small) and roundEnds(bottom), "unten: liegt unten an, eingerückt, runde Enden")

-- ohne festen Radius (kein UICorner oder Rundung in Skala): Radius XL
local plain = Instance.new("Frame")
local fallback = UITheme.AccentBar(plain)
check(udim(fallback.Position.X, 0, UITheme.Radius.XL) and udim(fallback.Size.X, 1, -2 * UITheme.Radius.XL),
	"ohne UICorner: um Radius XL eingerückt")
check(fallback.BackgroundColor3 == C.Primary, "ohne Farbe: Bernstein")
local pill = Instance.new("Frame")
local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0.5, 0)
pillCorner.Parent = pill
check(udim(UITheme.AccentBar(pill, C.Text).Position.X, 0, UITheme.Radius.XL), "Rundung in Skala: Radius XL")

if failures == 0 then
	print("Akzentstreifen: alles in Ordnung")
end
