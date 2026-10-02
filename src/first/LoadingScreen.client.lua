-- LoadingScreen (LocalScript in ReplicatedFirst)
-- Eigener Ladebildschirm im nüchternen Taktik-Look: Logo, dünner Lade-Balken, wechselnde Tipps.
-- Verschwindet, sobald das Spiel geladen ist und der Spieler im Hub angekommen ist.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local GRAPHITE = Color3.fromRGB(12, 14, 17)
local AMBER = Color3.fromRGB(212, 170, 80)

local TIPS = {
	"Halte E bei niedergeschlagenen Teamkollegen, um sie wiederzubeleben.",
	"Mit Rechtsklick zielst du genauer – die Streuung sinkt stark.",
	"Im Sprint STRG drücken: Slide!",
	"Z markiert Gegner für dein ganzes Team.",
	"Kaufe in der Agentenwahl Rüstung und Perks – das Geld gilt nur für das Match.",
	"Jeder Agent hat zwei Primärwaffen zur Auswahl.",
	"Mit V erledigst du niedergeschlagene Gegner sofort mit dem Messer.",
	"Lade Freunde über SQUAD ein – ihr landet im selben Team.",
	"Mit T wechselst du zwischen Ego- und Schulterkamera.",
}

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local background = Instance.new("Frame")
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = GRAPHITE
background.Parent = gui
local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new(Color3.fromRGB(30, 33, 38), Color3.fromRGB(6, 7, 9))
gradient.Parent = background

local function label(text, size, y, color, font)
	local obj = Instance.new("TextLabel")
	obj.AnchorPoint = Vector2.new(0.5, 0.5)
	obj.Position = UDim2.new(0.5, 0, y, 0)
	obj.Size = UDim2.new(0.9, 0, 0, size + 10)
	obj.BackgroundTransparency = 1
	obj.Font = font or Enum.Font.Oswald
	obj.TextSize = size
	obj.TextColor3 = color or Color3.new(1, 1, 1)
	obj.Text = text
	obj.Parent = background
	return obj
end

label("SHOOTOUT", 104, 0.42, Color3.fromRGB(228, 231, 235))
-- schmale Bernstein-Linie unter dem Logo
local line = Instance.new("Frame")
line.AnchorPoint = Vector2.new(0.5, 0.5)
line.Position = UDim2.new(0.5, 0, 0.495, 0)
line.Size = UDim2.new(0, 56, 0, 2)
line.BackgroundColor3 = AMBER
line.BorderSizePixel = 0
line.Parent = background
label("TACTICAL OPERATIONS", 16, 0.53, AMBER, Enum.Font.GothamBold)
local status = label("Lade Einsatzgebiet ...", 16, 0.72, Color3.fromRGB(134, 142, 152), Enum.Font.GothamBold)
local tip = label(TIPS[math.random(#TIPS)], 17, 0.86, Color3.fromRGB(190, 194, 200), Enum.Font.Gotham)

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.new(0.5, 0, 0.77, 0)
barBack.Size = UDim2.new(0, 420, 0, 3)
barBack.BackgroundColor3 = Color3.fromRGB(40, 44, 50)
barBack.BorderSizePixel = 0
barBack.Parent = background
local bar = Instance.new("Frame")
bar.Size = UDim2.new(0, 0, 1, 0)
bar.BackgroundColor3 = AMBER
bar.BorderSizePixel = 0
bar.Parent = barBack

-- Tipps wechseln
local running = true
task.spawn(function()
	while running do
		task.wait(4)
		tip.Text = TIPS[math.random(#TIPS)]
	end
end)

-- Fortschritt: geladen -> Spieldaten -> im Hub
TweenService:Create(bar, TweenInfo.new(1.5), { Size = UDim2.new(0.4, 0, 1, 0) }):Play()
if not game:IsLoaded() then
	game.Loaded:Wait()
end
status.Text = "Verbinde mit dem Hangar ..."
TweenService:Create(bar, TweenInfo.new(0.8), { Size = UDim2.new(0.75, 0, 1, 0) }):Play()
local started = os.clock()
while player:GetAttribute("Mode") == nil and os.clock() - started < 15 do
	task.wait(0.1)
end
status.Text = "Bereit"
TweenService:Create(bar, TweenInfo.new(0.4), { Size = UDim2.new(1, 0, 1, 0) }):Play()
task.wait(0.6)

-- Ausblenden
running = false
local fade = TweenInfo.new(0.6)
TweenService:Create(background, fade, { BackgroundTransparency = 1 }):Play()
for _, obj in background:GetDescendants() do
	if obj:IsA("TextLabel") then
		TweenService:Create(obj, fade, { TextTransparency = 1 }):Play()
	elseif obj:IsA("Frame") then
		TweenService:Create(obj, fade, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.7)
gui:Destroy()
