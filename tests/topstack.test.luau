-- Anzeigen oben in der Mitte (TopStack): Zonen-Anzeige, Spawnschutz, Tutorial, Ortsname und Banner liegen untereinander
-- statt übereinander. Reine Rechnung (Reihenfolge, Mindestlage, unsichtbare zählen nicht) und im Spiel: Spawnschutz
-- (CombatBarrier) und das Banner "Safe Zone verlassen" (Notifications) überdecken sich nicht.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local TopStack = require("TopStack")

-- Rechnung: alles frei -> Ortsname bei 0.2, Banner mittig bei 0.3 wie bisher
local layout = TopStack.Layout({
	{ Visible = true, Height = 30 },
	{ Visible = false, Height = 24 },
	{ Visible = true, Height = 62, MinY = 0.2 },
	{ Visible = true, Height = 130, MinY = 0.3, Anchor = 0.5 },
}, 900)
check(layout[1] == TopStack.Top, "Zone ganz oben")
check(layout[2] == nil, "Unsichtbares bekommt keinen Platz")
check(layout[3] == 180, "Ortsname bleibt bei 0.2, wenn darüber Platz ist: " .. tostring(layout[3]))
check(layout[4] - 65 >= layout[3] + 62, "Banner unter dem Ortsnamen: " .. tostring(layout[4]))

-- voll belegt (Tutorial-Tafel): alles rückt nach unten, keine Überlappung
local entries = {
	{ Visible = true, Height = 30 },
	{ Visible = true, Height = 30 },
	{ Visible = true, Height = 150 },
	{ Visible = true, Height = 62, MinY = 0.2 },
	{ Visible = true, Height = 130, MinY = 0.3, Anchor = 0.5 },
}
layout = TopStack.Layout(entries, 900)
local bottom = -math.huge
for i, entry in entries do
	local top = layout[i] - (entry.Anchor or 0) * entry.Height
	check(top >= bottom, "Eintrag " .. i .. " überdeckt den vorigen (" .. top .. " < " .. bottom .. ")")
	bottom = top + entry.Height
end

-- im Spiel: Spawnschutz-Leiste und Banner beim Verlassen der Safe Zone
local bob = SIM.Join("Bob")
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
bob:SetAttribute("Mode", "Extinction")
require("Remotes") -- legt der Server an
SIM.Advance(1, 20)

SIM.IsServer = false -- ab hier Client (RenderStepped läuft)
local CombatBarrier = require("CombatBarrier")
local Notifications = require("Notifications")
-- Zonen-Anzeige wie in ExtinctionClient (oben, 30 hoch)
local hud = Instance.new("ScreenGui", playerGui)
local zone = Instance.new("Frame", hud)
zone.AnchorPoint = Vector2.new(0.5, 0)
zone.Size = UDim2.fromOffset(400, 30)
TopStack.Register(zone, { Order = TopStack.Order.Zone })
CombatBarrier.Init()
Notifications.Init()
bob:SetAttribute("ProtectedUntil", workspace:GetServerTimeNow() + 4)
Notifications.Banner({ Caption = "Safe Zone verlassen", Title = "VORSICHT", Sub = "Zombies · PvP in 5 Sekunden", Style = "Warning" })
SIM.Advance(1, 20)

local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local barrier = playerGui:FindFirstChild("CombatBarrier")
local pill = barrier and find(barrier, "Combat")
local banner = find(playerGui:FindFirstChild("Notifications"), "Banner")
check(barrier ~= nil and barrier.Enabled, "Spawnschutz sichtbar")
check(pill ~= nil and banner ~= nil and banner.Visible, "Leiste und Banner angelegt")
if pill and banner then
	local pillBottom = pill.Position.Y.Offset + 30
	local bannerTop = banner.Position.Y.Offset - banner.Size.Y.Offset / 2
	check(pill.Position.Y.Offset >= TopStack.Top + 30, "Spawnschutz unter der Zonen-Anzeige: " .. pill.Position.Y.Offset)
	check(bannerTop >= pillBottom, "Banner überdeckt den Spawnschutz nicht (" .. bannerTop .. " < " .. pillBottom .. ")")
end

if failures > 0 then
	error(failures .. " Fehler")
end
print("TopStack ok")
