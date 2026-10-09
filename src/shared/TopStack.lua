-- TopStack (ModuleScript, nur Client)
-- Anzeigen oben in der Mitte liegen in fester Reihenfolge untereinander, statt jede für sich an einer festen Stelle:
-- Zonen-Anzeige, Anti-Zombie-Spritze, Spawnschutz / Im Kampf, Tutorial, Ortsname, Banner (Ereignisse, Safe Zone
-- verlassen, Rote Zone ...). Sind mehrere gleichzeitig sichtbar, rutschen die unteren nach unten, nichts überdeckt sich.
-- Alle Ebenen nutzen UITheme.ScaledRoot (1600 x 900), Höhen und Abstände hier sind in diesen Einheiten.
-- MinY: Anteil der Bildschirmhöhe, an dem der Ankerpunkt mindestens liegt (Ortsname 0.2, Banner 0.3 wie bisher); ist
-- darüber zu wenig Platz, rückt die Anzeige weiter nach unten.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local TopStack = {}

TopStack.Order = { Zone = 10, Shield = 20, Status = 30, Tutorial = 40, Place = 50, Banner = 60 }
TopStack.Top = 30 -- Oberkante der ersten Anzeige
TopStack.Gap = 6  -- Abstand zwischen zwei Anzeigen
local FOLLOW = 14 -- wie schnell eine Anzeige an ihren neuen Platz gleitet (pro Sekunde)

local items = {} -- { Element, Order, Height, MinY, Y }, nach Order sortiert
local connection = nil

-- Reine Rechnung (auch für Tests): entries = { { Visible, Height, MinY, Anchor } } in Reihenfolge, gibt für jede
-- sichtbare Anzeige die Lage ihres Ankerpunkts zurück (unsichtbare: nil)
function TopStack.Layout(entries, screenHeight)
	local y = TopStack.Top
	local result = {}
	for i, entry in entries do
		if entry.Visible then
			local anchor = entry.Anchor or 0
			local top = math.max(y, (entry.MinY or 0) * screenHeight - anchor * entry.Height)
			result[i] = top + anchor * entry.Height
			y = top + entry.Height + TopStack.Gap
		end
	end
	return result
end

local function shown(element)
	if not element.Parent or not element.Visible then
		return false
	end
	local gui = element:FindFirstAncestorWhichIsA("LayerCollector")
	return gui == nil or gui.Enabled
end

local function step(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local scale = UITheme.RootScale(camera.ViewportSize)
	local entries = {}
	for i, item in items do
		local visible = shown(item.Element)
		local height = 0
		if visible then
			local element = item.Element
			if item.Height then
				height = item.Height()
			elseif element.AutomaticSize == Enum.AutomaticSize.None then
				height = element.Size.Y.Offset
			else -- wächst mit dem Inhalt: tatsächliche Höhe, zurückgerechnet in Einheiten der Ebene
				height = element.AbsoluteSize.Y / scale
			end
		end
		entries[i] = { Visible = visible, Height = height, MinY = item.MinY, Anchor = item.Element.AnchorPoint.Y }
	end
	local layout = TopStack.Layout(entries, camera.ViewportSize.Y / scale)
	local blend = math.clamp((dt or 1) * FOLLOW, 0, 1)
	for i, item in items do
		local target = layout[i]
		if target then
			-- gerade erst erschienen: sofort an den Platz, sonst hinübergleiten
			item.Y = item.Y and (item.Y + (target - item.Y) * blend) or target
			if math.abs(item.Y - target) < 0.5 then
				item.Y = target
			end
			local position = item.Element.Position
			item.Element.Position = UDim2.new(position.X.Scale, position.X.Offset, 0, math.floor(item.Y + 0.5))
		else
			item.Y = nil
		end
	end
end

-- element: Anzeige (GuiObject in einer ScaledRoot-Ebene); options: { Order = TopStack.Order.X, Height = function?, MinY }
-- Ohne Height zählt Size.Y.Offset, bei AutomaticSize die tatsächliche Höhe.
function TopStack.Register(element, options)
	table.insert(items, { Element = element, Order = options.Order, Height = options.Height, MinY = options.MinY })
	table.sort(items, function(a, b)
		return a.Order < b.Order
	end)
	step(nil)
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

TopStack.Update = step

return TopStack
