-- AbilityClient (ModuleScript, nur Client)
-- Fähigkeit (Q / L1) und Gadget (G / R1) auslösen und unten rechts neben der Munition anzeigen, im Stil
-- von Rogue Company: zwei Rauten mit Symbol, Tastenhinweis für das aktuelle Gerät darüber, Name darunter.
-- Abklingzeit: Zahl in der Raute, die Füllung wächst von innen, bis die Fähigkeit wieder bereit ist.
-- Aufladungen des Gadgets als Zahl an der Raute. Auf Touch-Geräten unten mittig links neben der Munition.
-- Außerdem: Sprint-Stoß (Dash), Radar-Markierungen und Blend-Effekt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local C = UITheme.Colors
local make = UITheme.Make

local player = Players.LocalPlayer

local AbilityClient = {}

-- Symbole je Fähigkeits-, Gadget- und Passiv-Typ
local ICONS = {
	Boost = "⚡", Wall = "🛡", Heal = "✚", Reveal = "📡", Cloak = "👁", Dash = "💨", TeamHeal = "❤",
	Trap = "🕸", Turret = "🔫", Frag = "💣", Flash = "✴", Smoke = "☁", Sensor = "📍",
	Armor = "🛡", Cooldown = "⏱", ExtraGadget = "➕", KillSpeed = "🔥", MarkOnHit = "🎯", Regen = "♻",
	Reload = "🔄", Revive = "✚", SensorImmune = "👻",
}

-- Aktiver Agent dieses Lebens, sonst der gewählte
local function currentAgent()
	local character = player.Character
	return AgentConfig.Get(character and character:GetAttribute("Agent"))
		or AgentConfig.Get(player:GetAttribute("Agent"))
		or AgentConfig.Agents[1]
end

-- Ein Feld als Raute: Symbol, Tastenhinweis darüber, Name darunter, Füllung für die Abklingzeit.
-- Kinder einer gedrehten Raute drehen mit, darum liegen Texte als Geschwister darüber.
local function makeSlot(parent, size, order)
	local holder = make("Frame", { Size = UDim2.new(0, size + 34, 0, size + 46), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local center = UDim2.new(0.5, 0, 0, 22 + size / 2)
	local box = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.new(0, size * 0.72, 0, size * 0.72),
		Rotation = 45, BackgroundColor3 = C.Panel, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, holder)
	local stroke = UITheme.Stroke(box, C.Border, 2)
	-- Füllung: wächst von der Mitte, während die Fähigkeit lädt (voll = bereit)
	local fill = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = C.Accent, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, box)
	local icon = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.new(0, size, 0, size), Text = "",
		TextSize = math.floor(size * 0.42), Font = UITheme.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 }, holder)
	local timer = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.new(0, size, 0, size), Text = "",
		TextSize = math.floor(size * 0.46), Font = UITheme.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
		TextStrokeTransparency = 0.3 }, holder)
	-- Tastenhinweis über der Raute
	local key = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 30, 0, 18),
		Text = "", TextSize = 13, Font = UITheme.Fonts.Title, BackgroundTransparency = 0.1, BackgroundColor3 = C.Background,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 }, holder)
	UITheme.Corner(key, 3)
	UITheme.Stroke(key, C.Border, 1)
	-- Aufladungen (Gadget) rechts unten an der Raute
	local count = UITheme.Label({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, size * 0.32, 0, 22 + size * 0.86),
		Size = UDim2.new(0, 30, 0, 20), Text = "", TextSize = 18, Font = UITheme.Fonts.Title, ZIndex = 4,
		TextStrokeTransparency = 0.3 }, holder)
	local name = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 30, 0, 16),
		Text = "", TextSize = 13, Font = UITheme.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5 }, holder)
	local scale = make("UIScale", {}, holder)
	return { Holder = holder, Box = box, Stroke = stroke, Fill = fill, Icon = icon, Timer = timer, Key = key,
		Count = count, Name = name, Scale = scale }
end

-- Kurzer "Bereit"-Puls
local function pulse(slot)
	slot.Scale.Scale = 1.15
	TweenService:Create(slot.Scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

function AbilityClient.Init()
	local gui = make("ScreenGui", { Name = "Ability", ResetOnSpawn = false, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(gui)

	-- Nur in Kampfmodi sichtbar
	local function updateVisible()
		gui.Enabled = Modes.IsFighting(player)
	end
	updateVisible()
	player:GetAttributeChangedSignal("Mode"):Connect(updateVisible)

	-- Rauten unten rechts links neben der Munition: Fähigkeit · Gadget
	local bar = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -396, 1, -16),
		Size = UDim2.new(0, 200, 0, 110), BackgroundTransparency = 1 }, root)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	local abilitySlot = makeSlot(bar, 62, 1)
	local gadgetSlot = makeSlot(bar, 52, 2)

	-- Touch: unten mittig links neben der Munition (rechts liegen die Touch-Knöpfe)
	local function layout()
		if InputActions.IsTouch() then
			bar.AnchorPoint = Vector2.new(1, 1)
			bar.Position = UDim2.new(0.5, -12, 1, -10)
		else
			bar.AnchorPoint = Vector2.new(1, 1)
			bar.Position = UDim2.new(1, -396, 1, -16) -- links neben der Munition (320 breit, 110 %)
		end
	end
	layout()
	InputActions.DeviceChanged:Connect(layout)

	-- Gesamtdauer der aktuellen Abklingzeit bzw. Wirkdauer (für Abdeckung und Balken)
	local cooldownTotal = 1
	player:GetAttributeChangedSignal("AbilityReadyAt"):Connect(function()
		cooldownTotal = math.max(1, (player:GetAttribute("AbilityReadyAt") or 0) - workspace:GetServerTimeNow())
	end)
	local activeTotal = 1
	player:GetAttributeChangedSignal("AbilityActiveUntil"):Connect(function()
		activeTotal = math.max(0.1, (player:GetAttribute("AbilityActiveUntil") or 0) - workspace:GetServerTimeNow())
	end)

	-- Sprint-Stoß: kurzer Schub in Laufrichtung (bzw. Blickrichtung, wenn man steht)
	Remotes.AbilityEffect.OnClientEvent:Connect(function(effect, speed, duration)
		if effect ~= "Dash" then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not rootPart then
			return
		end
		local direction = humanoid.MoveDirection
		if direction.Magnitude < 0.1 then
			local look = workspace.CurrentCamera.CFrame.LookVector
			direction = Vector3.new(look.X, 0, look.Z)
		end
		direction = direction.Unit
		local started = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			if os.clock() - started > duration or not rootPart.Parent then
				connection:Disconnect()
				return
			end
			rootPart.AssemblyLinearVelocity = Vector3.new(direction.X * speed, math.max(rootPart.AssemblyLinearVelocity.Y, 2),
				direction.Z * speed)
		end)
	end)

	-- Radar-Puls: markierte Gegner rot durch Wände anzeigen (nur für uns sichtbar)
	Remotes.Reveal.OnClientEvent:Connect(function(characters, duration)
		for _, character in characters do
			if typeof(character) == "Instance" and character.Parent then
				local highlight = Instance.new("Highlight")
				highlight.FillColor = Color3.fromRGB(255, 60, 60)
				highlight.FillTransparency = 0.5
				highlight.OutlineColor = Color3.fromRGB(255, 60, 60)
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.Parent = character
				Debris:AddItem(highlight, duration)
			end
		end
	end)

	-- Weißer Blitz beim Geblendet-werden
	local flash = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
		ZIndex = 10 }, gui)
	Remotes.Flash.OnClientEvent:Connect(function(duration)
		flash.BackgroundTransparency = 0
		-- Erst voll weiß halten, dann langsam ausblenden
		task.delay(duration * 0.4, function()
			TweenService:Create(flash, TweenInfo.new(duration * 0.6), { BackgroundTransparency = 1 }):Play()
		end)
	end)

	-- Auslösen über InputActions (Tastatur, Controller, Touch-Knöpfe)
	InputActions.Bind("Ability", function(began)
		if began and Modes.IsFighting(player) then
			Remotes.UseAbility:FireServer()
		end
	end)
	InputActions.Bind("Gadget", function(began)
		if began and Modes.IsFighting(player) then
			Remotes.UseGadget:FireServer(workspace.CurrentCamera.CFrame.LookVector)
		end
	end)

	-- Anzeige laufend aktualisieren
	local wasReady, hadCharges = true, true
	RunService.Heartbeat:Connect(function()
		if not gui.Enabled then
			return
		end
		local agent = currentAgent()
		local now = workspace:GetServerTimeNow()

		-- Tastenhinweise passend zum Gerät (auf Touch ausgeblendet, dort gibt es eigene Knöpfe)
		local touch = InputActions.IsTouch()
		abilitySlot.Key.Text = InputActions.Hint("Ability")
		gadgetSlot.Key.Text = InputActions.Hint("Gadget")
		abilitySlot.Key.Visible = not touch
		gadgetSlot.Key.Visible = not touch

		-- Fähigkeit
		abilitySlot.Icon.Text = ICONS[agent.Ability.Type] or "★"
		abilitySlot.Name.Text = string.upper(agent.Ability.Name)
		abilitySlot.Name.TextColor3 = agent.Color
		local activeLeft = (player:GetAttribute("AbilityActiveUntil") or 0) - now
		local cooldownLeft = (player:GetAttribute("AbilityReadyAt") or 0) - now
		local ready = activeLeft <= 0 and cooldownLeft <= 0
		if activeLeft > 0 then
			-- läuft: Füllung in Agentenfarbe schrumpft mit der Restdauer
			local left = math.clamp(activeLeft / activeTotal, 0, 1)
			abilitySlot.Fill.Size = UDim2.new(left, 0, left, 0)
			abilitySlot.Fill.BackgroundColor3 = agent.Color
			abilitySlot.Timer.Text = ""
			abilitySlot.Icon.TextTransparency = 0
			abilitySlot.Stroke.Color = agent.Color
			abilitySlot.Stroke.Thickness = 3
		elseif cooldownLeft > 0 then
			-- lädt: Zahl, Füllung wächst bis "bereit"
			local done = 1 - math.clamp(cooldownLeft / cooldownTotal, 0, 1)
			abilitySlot.Fill.Size = UDim2.new(done, 0, done, 0)
			abilitySlot.Fill.BackgroundColor3 = C.Muted
			abilitySlot.Timer.Text = tostring(math.ceil(cooldownLeft))
			abilitySlot.Icon.TextTransparency = 0.75
			abilitySlot.Stroke.Color = C.Border
			abilitySlot.Stroke.Thickness = 2
		else
			abilitySlot.Fill.Size = UDim2.new(1, 0, 1, 0)
			abilitySlot.Fill.BackgroundColor3 = C.Accent
			abilitySlot.Timer.Text = ""
			abilitySlot.Icon.TextTransparency = 0
			abilitySlot.Stroke.Color = C.Accent
			abilitySlot.Stroke.Thickness = 2
		end
		if ready and not wasReady then
			pulse(abilitySlot)
		end
		wasReady = ready

		-- Gadget mit Aufladungen
		local charges = player:GetAttribute("Gadgets") or 0
		gadgetSlot.Icon.Text = ICONS[agent.Gadget.Type] or "◈"
		gadgetSlot.Icon.TextTransparency = charges > 0 and 0 or 0.7
		gadgetSlot.Name.Text = string.upper(agent.Gadget.Name)
		gadgetSlot.Count.Text = tostring(charges)
		gadgetSlot.Count.TextColor3 = charges > 0 and C.Text or C.Bad
		gadgetSlot.Fill.Size = charges > 0 and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 0, 0)
		gadgetSlot.Fill.BackgroundColor3 = C.Accent
		gadgetSlot.Stroke.Color = charges > 0 and C.Accent or C.Bad
		if charges > 0 and not hadCharges then
			pulse(gadgetSlot)
		end
		hadCharges = charges > 0
	end)
end

return AbilityClient
