-- LoadingScreen (LocalScript in ReplicatedFirst)
-- Eigener Ladebildschirm im Rogue-Company-Stil: Logo, Lade-Balken, wechselnde Tipps.
-- Verschwindet, sobald das Spiel geladen ist und der Spieler im Hub angekommen ist.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local NAVY = Color3.fromRGB(8, 14, 24)
local CYAN = Color3.fromRGB(40, 210, 230)

local TIPS = {
	"Halte E bei niedergeschlagenen Teamkollegen, um sie wiederzubeleben.",
	"Mit Rechtsklick zielst du genauer – die Streuung sinkt stark.",
	"Im Sprint STRG drücken: Slide!",
	"Z markiert Gegner für dein ganzes Team.",
	"Kaufe in der Agentenwahl Rüstung und Perks – das Geld gilt nur für das Match.",
	"Jeder Agent hat zwei Primärwaffen zur Auswahl.",
	"Mit V erledigst du niedergeschlagene Gegner sofort mit dem Messer.",
	"Lade Freunde über SQUAD ein – ihr landet im selben Team.",
}

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local background = Instance.new("Frame")
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = NAVY
background.Parent = gui
local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Color = ColorSequence.new(Color3.fromRGB(25, 50, 70), Color3.fromRGB(4, 8, 14))
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

-- Raute über dem Logo
local diamond = Instance.new("Frame")
diamond.AnchorPoint = Vector2.new(0.5, 0.5)
diamond.Position = UDim2.new(0.5, 0, 0.3, 0)
diamond.Size = UDim2.new(0, 46, 0, 46)
diamond.Rotation = 45
diamond.BackgroundColor3 = CYAN
diamond.BorderSizePixel = 0
diamond.Parent = background

label("SHOOTOUT", 96, 0.42)
label("TACTICAL OPERATIONS", 22, 0.5, CYAN, Enum.Font.GothamBold)
local status = label("Lade Einsatzgebiet ...", 18, 0.72, Color3.fromRGB(150, 165, 185), Enum.Font.GothamBold)
local tip = label(TIPS[math.random(#TIPS)], 18, 0.86, Color3.fromRGB(190, 200, 215), Enum.Font.Gotham)

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.new(0.5, 0, 0.77, 0)
barBack.Size = UDim2.new(0, 420, 0, 4)
barBack.BackgroundColor3 = Color3.fromRGB(30, 45, 60)
barBack.BorderSizePixel = 0
barBack.Parent = background
local bar = Instance.new("Frame")
bar.Size = UDim2.new(0, 0, 1, 0)
bar.BackgroundColor3 = CYAN
bar.BorderSizePixel = 0
bar.Parent = barBack

-- Raute dreht sich, Tipps wechseln
local running = true
task.spawn(function()
	while running do
		diamond.Rotation += 3
		task.wait(1 / 30)
	end
end)
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
