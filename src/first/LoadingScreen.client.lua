-- LoadingScreen (LocalScript in ReplicatedFirst)
-- Eigener Ladebildschirm im nüchternen Taktik-Look: Logo, dünner Lade-Balken, wechselnde Tipps.
-- Verschwindet erst, wenn Waffenmodelle und Skins vorgeladen sind, der Charakter im Camp auf festem Boden steht und
-- die Umgebung des Spawns geladen ist (jeder Schritt mit Frist, siehe unten). Danach startet z.B. das Tutorial.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local GRAPHITE = Color3.fromRGB(12, 14, 17)
local AMBER = Color3.fromRGB(212, 170, 80)

-- Tipps zur offenen Welt (Extinction); übersetzt werden sie wie alle Texte über LocaleStrings, sobald Locale läuft
local TIPS = {
	"Camp Phoenix ist eine Safe Zone: Dort nimmst du keinen Schaden. Draußen gilt nach 5 Sekunden PvP.",
	"Wer draußen stirbt, lässt seine Tasche fallen – Container und Lager bleiben dir.",
	"Wertvolles ins LAGERHAUS im Camp legen: Das Lager ist immer sicher.",
	"Das Tor in der MARKTHALLE führt aus dem Camp in den Markt.",
	"Einmal am Tag gratis drehen: das GLÜCKSRAD im Camp.",
	"Das Starter Kit gibt es gratis an der KIT-AUSGABE im Camp – alle 30 Minuten neu.",
	"Mit Rechtsklick zielst du genauer – die Streuung sinkt stark.",
	"Im Sprint STRG drücken: Slide!",
	"Z markiert Orte und Gegner für deinen Squad.",
	"Lade Freunde über SQUAD ein – kein Friendly Fire, gemeinsame Pings und Minimap.",
	"Mit T wechselst du zwischen Ego- und Schulterkamera, mit H die Schulter.",
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
	obj.Font = font or Enum.Font.BuilderSansExtraBold
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
label("TACTICAL OPERATIONS", 16, 0.53, AMBER, Enum.Font.BuilderSansBold)
local status = label("Lade Einsatzgebiet ...", 16, 0.72, Color3.fromRGB(134, 142, 152), Enum.Font.BuilderSansBold)
local tip = label(TIPS[math.random(#TIPS)], 17, 0.86, Color3.fromRGB(190, 194, 200), Enum.Font.BuilderSans)

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

-- Fortschritt: Spiel geladen -> Waffen/Skins vorgeladen -> Spieldaten -> Charakter steht im Camp -> Umgebung geladen.
-- Jeder Schritt hat eine Frist, damit ein hängendes Asset niemanden für immer hier festhält.
local function setBar(fraction, seconds)
	TweenService:Create(bar, TweenInfo.new(seconds or 0.3), { Size = UDim2.new(fraction, 0, 1, 0) }):Play()
end
local function waitUntil(condition, timeout)
	local started = os.clock()
	while not condition() and os.clock() - started < timeout do
		task.wait(0.1)
	end
	return condition()
end

setBar(0.12, 1.5)
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Waffenmodelle, Skins und Aufsätze vorladen: die 3D-Vorschauen in Inventar, Hotbar und Markt sind dann sofort da
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared", 20)
local preloadModule = Shared and Shared:WaitForChild("AssetPreload", 10)
local AssetPreload = preloadModule and require(preloadModule)
if AssetPreload then
	status.Text = "Lade Waffen und Skins ..."
	AssetPreload.Run(AssetPreload.AssetGroups(), function(done, total)
		status.Text = string.format("Lade Waffen und Skins ... %d/%d", done, total)
		setBar(0.12 + 0.38 * done / total)
	end, 25)
end
setBar(0.5)

status.Text = "Verbinde mit Camp Phoenix ..."
waitUntil(function()
	return player:GetAttribute("Mode") ~= nil
end, 15)
-- Kein Modus nach 15 s: der Server hängt (meist fehlen die Karten unter Workspace.Maps, z.B. Rojo nicht fertig
-- synchronisiert, oder der Spielstand lädt noch). Statt in eine leere Welt auszublenden, den Grund anzeigen und weiter warten.
if player:GetAttribute("Mode") == nil then
	local maps = workspace:FindFirstChild("Maps")
	if not maps or not maps:FindFirstChild("Extinction") then
		status.Text = "Karten fehlen im Workspace (Maps) – Rojo verbinden oder die gebaute Place-Datei öffnen"
	else
		status.Text = "Server antwortet nicht – Fehler im Output-Fenster prüfen"
	end
	status.TextColor3 = AMBER
	player:GetAttributeChangedSignal("Mode"):Wait()
	status.TextColor3 = Color3.fromRGB(134, 142, 152)
end
setBar(0.62)

-- Spawn: Charakter da und vom Server an seinen Spawnpunkt gesetzt (Attribut SafeZone am Charakter kommt erst nach dem
-- Versetzen, vorher steht er kurz am Ladepunkt von LoadCharacter), Avatar fertig, Streaming hält das Spiel nicht mehr
-- an, Boden unter den Füßen und die Stelle bleibt ruhig (kein Versetzen mehr)
status.Text = "Spawne im Camp ..."
local function root()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end
waitUntil(function()
	return root() ~= nil
end, 20)
waitUntil(function()
	local character = player.Character
	return character ~= nil and character:GetAttribute("SafeZone") == true and root() ~= nil
end, 15)
setBar(0.66)
waitUntil(function()
	local ok, loaded = pcall(player.HasAppearanceLoaded, player)
	return not ok or loaded
end, 8)
setBar(0.7)
local function grounded()
	local hrp = root()
	if not hrp then
		return false
	end
	local paused = false
	pcall(function()
		paused = player.GameplayPaused
	end)
	if paused then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	return workspace:Raycast(hrp.Position, Vector3.new(0, -60, 0), params) ~= nil
end
-- fest = auf dem Boden und seit einer halben Sekunde an derselben Stelle
local lastPos, stillSince = nil, os.clock()
waitUntil(function()
	local hrp = root()
	if not hrp or not grounded() then
		lastPos, stillSince = nil, os.clock()
		return false
	end
	if not lastPos or (hrp.Position - lastPos).Magnitude > 4 then
		lastPos, stillSince = hrp.Position, os.clock()
	end
	return os.clock() - stillSince >= 0.5
end, 15)
setBar(0.74)

-- Streaming: warten, bis um den Spawn keine neuen Teile mehr ankommen (eine Sekunde lang nichts Neues)
local maps = workspace:FindFirstChild("Maps")
do
	local lastAdd = os.clock()
	local added = (maps or workspace).DescendantAdded:Connect(function()
		lastAdd = os.clock()
	end)
	waitUntil(function()
		return os.clock() - lastAdd >= 1
	end, 10)
	added:Disconnect()
end
setBar(0.8)

-- Umgebung des Spawns (Gebäude, Stände, Texturen) und der eigene Avatar vorladen, damit beim Ausblenden nichts mehr aufploppt
local hrp = root()
if AssetPreload and hrp then
	status.Text = "Lade das Camp ..."
	local groups = AssetPreload.AreaGroups(maps or workspace, hrp.Position)
	if player.Character then
		table.insert(groups, 1, player.Character)
	end
	AssetPreload.Run(groups, function(done, total)
		status.Text = string.format("Lade das Camp ... %d/%d", done, total)
		setBar(0.8 + 0.16 * done / total)
	end, 15)
end

-- Kamera hängt am eigenen Charakter (Ego-Ansicht, Hände und HUD sind aufgebaut), dann kurz ruhen lassen
waitUntil(function()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return camera ~= nil and humanoid ~= nil and camera.CameraSubject == humanoid
end, 5)
setBar(0.97)
task.wait(0.8)

status.Text = "Bereit"
setBar(1, 0.4)
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
