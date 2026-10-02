-- AbilityClient (ModuleScript, nur Client)
-- Fähigkeit (Q / L1) und Gadget (G / R1) auslösen und unten mittig als klobige Knöpfe anzeigen (Design
-- "BLOCKOPS"): Taste groß in der Mitte, Name darunter, gelber Rand = bereit. Abklingzeit: dunkle Abdeckung
-- von unten (schrumpft, bis die Fähigkeit wieder bereit ist) und die Sekunden statt der Taste. Läuft die
-- Fähigkeit, leuchtet der Knopf in der Agentenfarbe. Aufladungen des Gadgets als Zahl oben rechts.
-- Daneben der runde ULT-Knopf (Ultimate "Überladung", Taste F / L1+R1): Ladung in Prozent als Füllung
-- von unten, voll = gelb, pulsierend und mit Taste.
-- Auf Touch-Geräten unten mittig links neben der Munition (Symbole statt Tasten).
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

-- Ein klobiger Knopf: Taste (bzw. Sekunden/Symbol), Name, Abdeckung für die Abklingzeit, Aufladungen
local function makeSlot(parent, size, order)
	local chunky = UITheme.Chunky({ Size = UDim2.new(0, size, 0, size), LayoutOrder = order, Color = C.Panel, StrokeColor = C.Border,
		StrokeThickness = 2, Text = "", Radius = UITheme.Radius.Large }, parent)
	local face = chunky.Face
	face.ClipsDescendants = true
	-- Abdeckung von unten: Anteil der verbleibenden Abklingzeit
	local cover = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = C.Background, BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 2 }, face)
	local key = UITheme.Label({ Position = UDim2.new(0, 0, 0, 4), Size = UDim2.new(1, 0, 0, size * 0.55), Text = "",
		TextSize = math.floor(size * 0.36), Font = UITheme.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, face)
	local name = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -8, 0, 12),
		Text = "", TextSize = 9, Font = UITheme.Fonts.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 }, face)
	-- Aufladungen (Gadget) oben rechts
	local count = UITheme.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.new(0, 16, 0, 14),
		Text = "", TextSize = 10, Font = UITheme.Fonts.Display, BackgroundTransparency = 0, BackgroundColor3 = C.Primary,
		TextColor3 = C.PrimaryText, TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 4 }, face)
	UITheme.Corner(count, 4)
	local scale = make("UIScale", {}, chunky.Button)
	return { Holder = chunky.Button, Chunky = chunky, Cover = cover, Key = key, Name = name, Count = count, Scale = scale }
end

-- Runder ULT-Knopf (Design: Ladung als Füllung von unten, voll = gelb mit Taste)
local function makeUltimate(parent, size, order)
	local holder = make("Frame", { Size = UDim2.new(0, size, 0, size + 5), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local shadow = make("Frame", { Position = UDim2.new(0, 0, 0, 5), Size = UDim2.new(0, size, 0, size), BackgroundColor3 = C.Shadow,
		BackgroundTransparency = 0.65, BorderSizePixel = 0 }, holder)
	UITheme.Corner(shadow, size / 2)
	local circle = make("Frame", { Size = UDim2.new(0, size, 0, size), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 },
		holder)
	UITheme.Corner(circle, size / 2)
	local stroke = UITheme.Stroke(circle, C.Border, 3)
	-- Füllung von unten: harte Kante im Verlauf (oben Kartenfarbe, unten Gelb)
	local fill = make("UIGradient", { Rotation = 90 }, circle)
	local value = UITheme.Label({ Position = UDim2.new(0, 0, 0, size * 0.18), Size = UDim2.new(1, 0, 0, size * 0.4), Text = "",
		TextSize = math.floor(size * 0.27), Font = UITheme.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center }, circle)
	UITheme.Outline(value, 2)
	local caption = UITheme.Label({ Position = UDim2.new(0, 0, 0, size * 0.58), Size = UDim2.new(1, 0, 0, 12), Text = "ULT",
		TextSize = 10, Font = UITheme.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center }, circle)
	UITheme.Outline(caption, 2)
	local scale = make("UIScale", {}, holder)
	return { Holder = holder, Circle = circle, Stroke = stroke, Fill = fill, Value = value, Caption = caption, Scale = scale }
end

-- Füllung des ULT-Knopfs (0..1): oben dunkel, unten Signalgelb
local function setUltimateFill(slot, charge)
	local edge = math.clamp(1 - charge, 0.001, 0.998)
	slot.Fill.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.Panel),
		ColorSequenceKeypoint.new(edge, C.Panel),
		ColorSequenceKeypoint.new(math.min(edge + 0.001, 0.999), C.Primary:Lerp(C.Panel, 0.35)),
		ColorSequenceKeypoint.new(1, C.Primary:Lerp(C.Panel, 0.35)),
	})
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

	-- Knöpfe unten mittig: Fähigkeit · Gadget
	local bar = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(0, 250, 0, 82), BackgroundTransparency = 1 }, root)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	local abilitySlot = makeSlot(bar, 66, 1)
	local gadgetSlot = makeSlot(bar, 66, 2)
	local ultimateSlot = makeUltimate(bar, 76, 3)

	-- Touch: unten mittig links neben der Munition (rechts liegen die Touch-Knöpfe)
	local function layout()
		if InputActions.IsTouch() then
			bar.AnchorPoint = Vector2.new(1, 1)
			bar.Position = UDim2.new(0.5, -12, 1, -10)
		else
			bar.AnchorPoint = Vector2.new(0.5, 1)
			bar.Position = UDim2.new(0.5, 0, 1, -30) -- über der Tastenzeile ganz unten
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
	InputActions.Bind("Ultimate", function(began)
		if began and Modes.IsFighting(player) and (player:GetAttribute("UltCharge") or 0) >= 100 then
			Remotes.UseUltimate:FireServer()
		end
	end)

	-- Anzeige laufend aktualisieren
	local wasReady, hadCharges, ultWasReady = true, true, false
	RunService.Heartbeat:Connect(function()
		if not gui.Enabled then
			return
		end
		local agent = currentAgent()
		local now = workspace:GetServerTimeNow()

		-- Taste für das aktuelle Gerät (Touch: Symbol, dort gibt es eigene Knöpfe)
		local touch = InputActions.IsTouch()
		local abilityKey = touch and (ICONS[agent.Ability.Type] or "★") or InputActions.Hint("Ability")
		local gadgetKey = touch and (ICONS[agent.Gadget.Type] or "◈") or InputActions.Hint("Gadget")

		-- Fähigkeit
		abilitySlot.Name.Text = UITheme.Upper(agent.Ability.Name)
		local activeLeft = (player:GetAttribute("AbilityActiveUntil") or 0) - now
		local cooldownLeft = (player:GetAttribute("AbilityReadyAt") or 0) - now
		local ready = activeLeft <= 0 and cooldownLeft <= 0
		if activeLeft > 0 then
			-- läuft: Knopf in Agentenfarbe, Abdeckung wächst mit der abgelaufenen Wirkdauer
			abilitySlot.Chunky.SetColor(agent.Color:Lerp(C.Panel, 0.45), C.Text)
			abilitySlot.Chunky.SetStroke(agent.Color, 3)
			abilitySlot.Cover.Size = UDim2.new(1, 0, 1 - math.clamp(activeLeft / activeTotal, 0, 1), 0)
			abilitySlot.Key.Text = ICONS[agent.Ability.Type] or abilityKey
			abilitySlot.Name.TextColor3 = C.Text
		elseif cooldownLeft > 0 then
			-- lädt: Sekunden statt Taste, Abdeckung schrumpft bis "bereit"
			abilitySlot.Chunky.SetColor(C.Panel, C.Text)
			abilitySlot.Chunky.SetStroke(C.Border, 2)
			abilitySlot.Cover.Size = UDim2.new(1, 0, math.clamp(cooldownLeft / cooldownTotal, 0, 1), 0)
			abilitySlot.Key.Text = tostring(math.ceil(cooldownLeft))
			abilitySlot.Name.TextColor3 = C.Muted
		else
			abilitySlot.Chunky.SetColor(C.Panel, C.Text)
			abilitySlot.Chunky.SetStroke(C.Primary, 2)
			abilitySlot.Cover.Size = UDim2.new(1, 0, 0, 0)
			abilitySlot.Key.Text = abilityKey
			abilitySlot.Name.TextColor3 = C.Muted
		end
		abilitySlot.Key.TextColor3 = ready and C.Text or C.Muted
		if ready and not wasReady then
			pulse(abilitySlot)
		end
		wasReady = ready

		-- Gadget mit Aufladungen
		local charges = player:GetAttribute("Gadgets") or 0
		gadgetSlot.Name.Text = UITheme.Upper(agent.Gadget.Name)
		gadgetSlot.Key.Text = gadgetKey
		gadgetSlot.Key.TextColor3 = charges > 0 and C.Text or C.Muted
		gadgetSlot.Count.Visible = true
		gadgetSlot.Count.Text = tostring(charges)
		gadgetSlot.Count.BackgroundColor3 = charges > 0 and C.Primary or C.Bad
		gadgetSlot.Count.TextColor3 = charges > 0 and C.PrimaryText or C.Text
		gadgetSlot.Cover.Size = charges > 0 and UDim2.new(1, 0, 0, 0) or UDim2.new(1, 0, 1, 0)
		gadgetSlot.Chunky.SetStroke(charges > 0 and C.Primary or C.Border, 2)
		if charges > 0 and not hadCharges then
			pulse(gadgetSlot)
		end

		-- Ultimate: Ladung in Prozent, voll = gelb mit Taste und pulsierend
		local charge = math.clamp((player:GetAttribute("UltCharge") or 0) / 100, 0, 1)
		local ultReady = charge >= 1
		if ultReady then
			local glow = 0.5 + 0.5 * math.sin(os.clock() * 6)
			ultimateSlot.Fill.Color = ColorSequence.new(C.Primary:Lerp(Color3.new(1, 1, 1), glow * 0.25))
			ultimateSlot.Value.Text = touch and "✦" or InputActions.Hint("Ultimate")
			ultimateSlot.Stroke.Color = C.Primary
			ultimateSlot.Value.TextColor3 = C.PrimaryText
			ultimateSlot.Caption.TextColor3 = C.PrimaryText
		else
			setUltimateFill(ultimateSlot, charge)
			ultimateSlot.Value.Text = math.floor(charge * 100) .. "%"
			ultimateSlot.Stroke.Color = C.Border
			ultimateSlot.Value.TextColor3 = C.Text
			ultimateSlot.Caption.TextColor3 = C.Muted
		end
		if ultReady and not ultWasReady then
			pulse(ultimateSlot)
		end
		ultWasReady = ultReady
		hadCharges = charges > 0
	end)
end

return AbilityClient
