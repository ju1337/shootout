-- ExtTutorial (ModuleScript, nur Client)
-- Geführtes Tutorial der offenen Welt für neue Spieler. Der Server setzt beim ersten Betreten das Spieler-Attribut
-- ExtTutorial (Profil ohne TutorialDone und ohne GuideHinted, siehe Extinction.AddPlayer). Dann erscheint eine Karte
-- WELCOME mit START TUTORIAL / SKIP (Maus frei), danach führt eine Tafel oben in der Mitte Schritt für Schritt:
-- Starter-Kit holen (Wegpunkt zum Kit-Händler), Inventar öffnen, Waffe in die Hand, Safe Zone verlassen, Zombie töten,
-- zum Schluss die wichtigsten Regeln. Jeder Schritt prüft selbst, ob er erledigt ist (Attribute ExtBag, ExtEquipped,
-- InSafeZone, ZombieKills, offenes Fenster); ist er es schon, geht es gleich weiter. Fertig oder übersprungen meldet
-- ExtAction "Tutorial" an den Server (Profil TutorialDone, danach nie wieder von selbst). Im GUIDE-Reiter startet oder
-- beendet ein Knopf das Tutorial jederzeit (ExtTutorial.Start / Stop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local TopStack = require(Shared.TopStack)
local InputActions = require(Shared.InputActions)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local KitConfig = require(Shared.KitConfig)
local Sfx = require(Shared.Sfx)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label

local ExtTutorial = {}

local RED = Color3.fromRGB(214, 58, 58) -- Akzent wie im Menü der offenen Welt
local READY_TIME = 12 -- Sekunden, die der letzte Schritt (nur Text) stehen bleibt
local CHECK_EVERY = 0.2

local hooks: { WindowKind: (() -> string?)? } = {} -- von ExtinctionClient: WindowKind() = Art des offenen Fensters oder nil
local gui, panel, stepText, titleText, bodyText, bar, intro, waypoint, waypointText
local state = {
	Active = false, -- Tafel läuft
	Step = 0,
	StepStart = 0,
	ResumedAt = 0, -- zuletzt TutorialEquip neu angefragt
	Kills = 0, -- ZombieKills beim Start des Zombie-Schritts
	Started = false, -- schon begonnen (nach Verlassen und Wiederkommen weiter, ohne neue Karte)
	Finished = false, -- fertig oder übersprungen (in dieser Sitzung nicht mehr von selbst)
}

-- Art des offenen Fensters der offenen Welt ("Inventory", "Kits" ...) oder nil
local function windowKind(): string?
	local get = hooks.WindowKind
	return get and get() or nil
end

local function inExtinction()
	return Modes.IsSurvival(player:GetAttribute("Mode"))
end

local function key(action, fallback)
	local hint = InputActions.Hint(action)
	return hint ~= "" and ("[" .. hint .. "]") or fallback
end

local function bagEntries()
	local ok, list = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("ExtBag") or "[]")
	return ok and type(list) == "table" and list or {}
end

-- Erster Hotbar-Platz mit einer Waffe (nil = keine Waffe in der Hotbar)
local function weaponSlot()
	local best = nil
	for _, entry in bagEntries() do
		local config = type(entry) == "table" and ExtinctionConfig.Get(entry.Id)
		if config and config.Kind == "Weapon" and type(entry.S) == "number" and entry.S <= ExtinctionConfig.HotbarSlots
			and (not best or entry.S < best) then
			best = entry.S
		end
	end
	return best
end

-- Startpaket gerade nicht abholbar (schon geholt, Wartezeit läuft): Schritt nicht daran hängen lassen
local function starterWaiting()
	local kit = KitConfig.Get("Starter")
	local ok, claimed = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Kits") or "{}")
	return kit ~= nil and KitConfig.Remaining(kit, ok and claimed or {}, workspace:GetServerTimeNow()) > 0
end

local function hasWeapon()
	for _, entry in bagEntries() do
		local config = type(entry) == "table" and ExtinctionConfig.Get(entry.Id)
		if config and config.Kind == "Weapon" then
			return true
		end
	end
	return false
end

local function rootPart()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

-- Nächster Stand dieses Namens in der Karte (Camp oder Safehouse)
local function nearestStand(name)
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	local stands = map and map:FindFirstChild("Stands")
	local root = rootPart()
	local best, bestDistance = nil, math.huge
	for _, part in stands and stands:GetChildren() or {} do
		if part.Name == name and part:IsA("BasePart") then
			local distance = root and (part.Position - root.Position).Magnitude or 0
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

-- Die Schritte: Text (Funktion, damit Tasten zum Gerät passen), Done() = erledigt, Target = Stand mit Wegpunkt,
-- Duration = reiner Text-Schritt, der nach so vielen Sekunden weitergeht
ExtTutorial.Steps = {
	{ Id = "Kit", Title = "GRAB YOUR STARTER KIT", Target = KitConfig.Point, WaypointText = "KIT VENDOR",
		Text = function()
			return "Walk to the <b>kit vendor</b> (follow the marker) and press " .. key("Interact", "the button on screen")
				.. ", then click <b>COLLECT</b> on the free <b>STARTER KIT</b>: pistol, SMG, ammo, bandages, a vest and a bike."
		end,
		Done = function()
			return hasWeapon() or starterWaiting()
		end },
	{ Id = "Inventory", Title = "OPEN YOUR INVENTORY",
		Text = function()
			return "Press " .. key("Inventory", "the bag button") .. " to open your inventory. The first "
				.. ExtinctionConfig.HotbarSlots .. " slots of your bag are your <b>hotbar</b>."
		end,
		Done = function()
			return windowKind() == "Inventory"
		end },
	{ Id = "Equip", Title = "TAKE A WEAPON IN HAND",
		Text = function()
			local slot = weaponSlot()
			local hint = slot and InputActions.Hint("Hotbar" .. slot) or ""
			if InputActions.Device() == "Gamepad" then
				hint = InputActions.Hint("Gadget") .. " / " .. InputActions.Hint("Ability") -- Controller: Waffe wechseln mit R1/L1
			end
			return "Close the menu and press " .. (hint ~= "" and ("[" .. hint .. "]") or "a weapon in your hotbar")
				.. " to draw your gun. During the tutorial you can hold it in the safe zone – shooting only works outside."
		end,
		Done = function()
			-- ohne Waffe (Startpaket schon geholt und weg) gibt es nichts zu ziehen
			return (player:GetAttribute("ExtEquipped") or 0) > 0 or (not hasWeapon() and starterWaiting())
		end },
	{ Id = "Leave", Title = "LEAVE THE SAFE ZONE",
		Text = function()
			return "Walk out through one of the gates. Outside zombies roam and <b>PvP starts " .. ExtinctionConfig.PvPDelay
				.. " seconds</b> after you leave. The last safe zone you entered is your spawn point."
		end,
		Done = function()
			return player:GetAttribute("InSafeZone") == false
		end },
	{ Id = "Zombie", Title = "KILL A ZOMBIE",
		Text = function()
			return "Zombies drop <b>coins and loot</b>. Aim with " .. key("Aim", "the aim button") .. ", fire with "
				.. key("Fire", "the fire button") .. ". Hurt? Use a bandage from your hotbar."
		end,
		Start = function()
			state.Kills = player:GetAttribute("ZombieKills") or 0
		end,
		Done = function()
			return (player:GetAttribute("ZombieKills") or 0) > state.Kills
		end },
	{ Id = "Ready", Title = "YOU'RE READY", Duration = READY_TIME,
		Text = function()
			return "If you die outside, your <b>bag drops</b> where you died – your container and stash stay safe. "
				.. "Everything else: menu " .. key("Menu", "") .. " → <b>GUIDE</b>. Good luck out there."
		end },
}

local function setWaypoint(part, text)
	if not part then
		if waypoint then
			waypoint.Enabled = false
		end
		return
	end
	if not waypoint then
		waypoint = make("BillboardGui", { Name = "TutorialWaypoint", AlwaysOnTop = true, ResetOnSpawn = false, LightInfluence = 0,
			Size = UDim2.fromOffset(220, 56), StudsOffset = Vector3.new(0, 7, 0), MaxDistance = 2000 },
			player:FindFirstChild("PlayerGui"))
		make("Frame", { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromOffset(14, 14), Rotation = 45, BackgroundColor3 = RED, BorderSizePixel = 0 }, waypoint)
		waypointText = label({ Name = "Text", Size = UDim2.new(1, 0, 0, 36), Text = "", TextSize = 18, Font = F.Display,
			TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 }, waypoint)
	end
	waypoint.Adornee = part
	waypoint.Enabled = true
	local root = rootPart()
	local distance = root and math.floor((part.Position - root.Position).Magnitude) or nil
	waypointText.Text = text .. (distance and ("  ·  " .. distance .. " M") or "")
end

local function hidePanel()
	if panel then
		panel.Visible = false
	end
	setWaypoint(nil)
end

local function showStep()
	local step = ExtTutorial.Steps[state.Step]
	if not step or not panel then
		return
	end
	stepText.Text = "TUTORIAL  ·  STEP " .. state.Step .. "/" .. #ExtTutorial.Steps
	titleText.Text = step.Title
	bodyText.Text = step.Text()
	bar.Size = UDim2.fromScale(state.Step / #ExtTutorial.Steps, 1)
	panel.Visible = inExtinction()
end

local function finish(result)
	state.Active = false
	state.Finished = true
	state.Step = 0
	hidePanel()
	Remotes.ExtAction:FireServer("Tutorial", result)
end

local function enterStep(index)
	state.Step = index
	state.StepStart = os.clock()
	local step = ExtTutorial.Steps[index]
	if not step then
		finish("Done")
		Sfx.UI("StingGood")
		return
	end
	Remotes.ExtAction:FireServer("Tutorial", "Step", index, step.Id) -- nur für die Analyse (Onboarding-Trichter)
	if step.Start then
		step.Start()
	end
	showStep()
end

local function closeIntro()
	if intro then
		intro:Destroy()
		intro = nil
	end
	RunService:UnbindFromRenderStep("ExtTutorialMouse")
	UITheme.HoldCamera("ExtTutorial", false)
end

-- Tutorial starten (withIntro = erst die Karte WELCOME mit START / SKIP)
function ExtTutorial.Start(withIntro)
	if not gui then
		return
	end
	closeIntro()
	state.Finished = false
	if not withIntro then
		state.Active = true
		state.Started = true
		if player:GetAttribute("ExtTutorial") ~= true then
			Remotes.ExtAction:FireServer("Tutorial", "Start") -- Wiederholung: der Server erlaubt dann wieder das Waffe-Ziehen im Camp
		end
		enterStep(1)
		return
	end
	local C2 = UITheme.MenuColors
	intro = make("Frame", { Name = "Intro", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), -- unter dem Banner der täglichen Kiste
		Size = UDim2.fromOffset(560, 250), BackgroundColor3 = C2.Card, BackgroundTransparency = 0.08, BorderSizePixel = 0,
		ZIndex = 20 }, gui)
	UITheme.Corner(intro, UITheme.Radius.Medium)
	make("Frame", { Name = "Accent", Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 21 }, intro)
	label({ Name = "Caption", Position = UDim2.fromOffset(28, 24), Size = UDim2.new(1, -56, 0, 18), Text = "WELCOME, SURVIVOR",
		TextSize = 14, Font = F.Bold, TextColor3 = RED, ZIndex = 21 }, intro)
	label({ Name = "Title", Position = UDim2.fromOffset(28, 44), Size = UDim2.new(1, -56, 0, 40), Text = "NEW TO EXTINCTION?",
		TextSize = 34, Font = F.Display, TextColor3 = C2.Text, ZIndex = 21 }, intro)
	label({ Name = "Text", Position = UDim2.fromOffset(28, 92), Size = UDim2.new(1, -56, 0, 60), Text = "A short tutorial shows "
		.. "you the basics: starter kit, inventory, leaving the safe zone and your first zombie. You can skip it any time "
		.. "in the menu under GUIDE.", TextSize = 17, Font = F.Medium, TextColor3 = C2.Text, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 21 }, intro)
	local buttons = make("Frame", { Name = "Buttons", Position = UDim2.new(0, 28, 1, -76), Size = UDim2.new(1, -56, 0, 52),
		BackgroundTransparency = 1, ZIndex = 21 }, intro)
	UITheme.Chunky({ Name = "Start", Size = UDim2.new(0.62, -6, 1, 0), Color = RED, StrokeColor = RED, Text = "START TUTORIAL",
		TextSize = 20, ZIndex = 22 }, buttons, function()
		closeIntro()
		Sfx.UI("StingInfo")
		ExtTutorial.Start(false)
	end)
	UITheme.Chunky({ Name = "Skip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.38, -6, 1, 0), Color = C2.Panel, StrokeColor = C2.Border, Text = "SKIP", TextSize = 20, ZIndex = 22 },
		buttons, function()
		closeIntro()
		finish("Skip")
	end)
	state.Started = true
	UITheme.HoldCamera("ExtTutorial", true) -- Blickrichtung nach dem Schließen wie vorher
	RunService:BindToRenderStep("ExtTutorialMouse", Enum.RenderPriority.Camera.Value + 2, function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
	InputActions.Focus(buttons)
	Sfx.UI("StingInfo")
end

-- Tutorial beenden (Knopf im GUIDE): zählt als übersprungen
function ExtTutorial.Stop()
	if state.Active or intro then
		closeIntro()
		finish("Skip")
	end
end

function ExtTutorial.IsActive()
	return state.Active or intro ~= nil
end

function ExtTutorial.CurrentStep()
	local step = state.Active and ExtTutorial.Steps[state.Step]
	return step and step.Id or nil
end

-- Schritt prüfen (alle CHECK_EVERY Sekunden): erledigt -> nächster, Wegpunkt nachführen
local function tick()
	if intro and not inExtinction() then
		closeIntro() -- beim nächsten Betreten kommt die Karte wieder (Attribut)
		state.Started = false
	end
	-- Controller: Auswahl ging verloren (Menü kurz offen): wieder auf die Karte
	if intro and windowKind() == nil and InputActions.Device() == "Gamepad" then
		local selected = game:GetService("GuiService").SelectedObject
		if not (selected and selected:IsDescendantOf(intro)) then
			InputActions.Focus(intro)
		end
	end
	if not state.Active then
		return
	end
	if not inExtinction() then
		hidePanel()
		return
	end
	local step = ExtTutorial.Steps[state.Step]
	if not step then
		return
	end
	-- Waffe ziehen in der Safe Zone erlaubt der Server nur mit TutorialEquip; das fällt beim Verlassen der Zone und beim
	-- Moduswechsel weg: wieder anfragen
	if (step.Id == "Equip" or step.Id == "Leave") and player:GetAttribute("TutorialEquip") ~= true
		and player:GetAttribute("InSafeZone") == true and os.clock() - state.ResumedAt > 2 then
		state.ResumedAt = os.clock()
		if player:GetAttribute("ExtTutorial") ~= true then
			Remotes.ExtAction:FireServer("Tutorial", "Start") -- Wiederholung nach Markt/Moduswechsel: Server weiß es nicht mehr
		end
		Remotes.ExtAction:FireServer("Tutorial", "Resume", state.Step, step.Id)
	end
	local done
	if step.Duration then
		done = os.clock() - state.StepStart >= step.Duration
	else
		done = step.Done()
	end
	if done then
		if not step.Duration then
			Sfx.UI("StingInfo")
		end
		enterStep(state.Step + 1)
		return
	end
	-- Fenster offen: Tafel aus (das Menü liegt ohnehin darüber), Text neu (Tasten können sich ändern)
	local windowOpen = windowKind() ~= nil or UITheme.IsMenuOpen() -- auch Weltkarte (N) und andere Vollbild-Menüs
	panel.Visible = not windowOpen
	bodyText.Text = step.Text()
	local target = step.Target and not windowOpen and nearestStand(step.Target) or nil
	setWaypoint(target, step.WaypointText or "")
end

-- Vom Server: Attribut ExtTutorial = true -> Karte zeigen (oder weitermachen, wenn schon begonnen)
local function onAttribute()
	if player:GetAttribute("ExtTutorial") ~= true or state.Finished or state.Active or intro then
		return
	end
	if state.Started then
		state.Active = true
		showStep()
		return
	end
	-- erst, wenn kein Fenster offen ist (die Karte liegt unter den Fenstern) und der Spieler da ist
	task.spawn(function()
		local waited = 0
		while waited < 600 and (not inExtinction() or windowKind() ~= nil) do
			waited += task.wait(0.5)
		end
		if player:GetAttribute("ExtTutorial") == true and not state.Finished and not state.Active and not intro and inExtinction()
			and windowKind() == nil then
			ExtTutorial.Start(true)
		end
	end)
end

function ExtTutorial.Init(options: { WindowKind: (() -> string?)? }?)
	hooks = options or {}
	gui = make("ScreenGui", { Name = "ExtTutorial", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	local canvas = UITheme.ScaledRoot(gui, 1600, 900)
	panel = UITheme.HudPanel({ Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(520, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.2, Visible = false },
		canvas)
	-- unter Zone und Spawnschutz, über Ortsname und Banner (TopStack: nichts liegt übereinander)
	TopStack.Register(panel, { Order = TopStack.Order.Tutorial })
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16) }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	stepText = label({ Name = "Step", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 16), Text = "", TextSize = 12, Font = F.Bold,
		TextColor3 = RED }, panel)
	titleText = label({ Name = "Title", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 26), Text = "", TextSize = 22,
		Font = F.Display, TextColor3 = C.Text }, panel)
	bodyText = label({ Name = "Text", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Text = "", RichText = true, TextWrapped = true, TextSize = 16, Font = F.Medium, TextColor3 = C.Text,
		TextYAlignment = Enum.TextYAlignment.Top }, panel)
	local track = make("Frame", { Name = "Progress", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = C.Card,
		BorderSizePixel = 0 }, panel)
	bar = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, track)
	label({ Name = "SkipHint", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 14), Text = "SKIP: MENU → GUIDE → SKIP TUTORIAL",
		TextSize = 11, Font = F.Bold, TextColor3 = C.Muted }, panel)

	player:GetAttributeChangedSignal("ExtTutorial"):Connect(onAttribute)
	onAttribute()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= CHECK_EVERY then
			elapsed = 0
			tick()
		end
	end)
end

return ExtTutorial
