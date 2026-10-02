-- AbilityClient (ModuleScript, nur Client)
-- Fähigkeit (Q / L1), Gadget (G / R1) und Ultimate (F / L1+R1) auslösen und anzeigen: drei schlanke Zeilen
-- unten rechts direkt links neben der Waffenanzeige (gleiche Höhe). Jede Zeile: Taste im Kästchen, Name,
-- rechts der Zustand (Sekunden der Abklingzeit, Aufladungen "×1", Ladung "64 %" bzw. BEREIT) und unten ein
-- dünner Balken – Bernstein = bereit, grau = lädt, blau = Fähigkeit läuft gerade. Wird etwas bereit, blitzt
-- die Zeile kurz auf. Auf Touch-Geräten ohne Tasten links neben der Munition unten mittig.
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

-- Drei Karten (Fähigkeit · Gadget · Ultimate) unten in der Mitte nebeneinander, zwischen Lebens- und Waffenanzeige;
-- darunter nur noch die dezente Tastenzeile, darüber die Medaillen (Notifications).
-- Touch: als Spalte unten mittig links neben der Munition (rechts liegen die Touch-Knöpfe).
local CARD_W, CARD_H, CARD_GAP = 236, 54, 8
local BOTTOM = 28

-- Aktiver Agent dieses Lebens, sonst der gewählte
local function currentAgent()
	local character = player.Character
	return AgentConfig.Get(character and character:GetAttribute("Agent"))
		or AgentConfig.Get(player:GetAttribute("Agent"))
		or AgentConfig.Agents[1]
end

-- Eine Karte: Taste im Kästchen, Name groß, darunter die Art klein, Zustand rechts, dünner Balken unten,
-- Fläche zum Aufblitzen
local function makeRow(parent, order, kind)
	local row = make("Frame", { Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = C.Background, BackgroundTransparency = 0.3,
		BorderSizePixel = 0, LayoutOrder = order, ClipsDescendants = true }, parent)
	UITheme.Corner(row, UITheme.Radius.Small)
	local key = UITheme.Label({ Position = UDim2.fromOffset(9, (CARD_H - 26) / 2), Size = UDim2.fromOffset(26, 26), Text = "", TextSize = 13,
		Font = UITheme.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Center }, row)
	UITheme.Corner(key, UITheme.Radius.Small)
	local keyStroke = UITheme.Stroke(key, C.Muted, 1, 0.4)
	-- lange Namen (SPLITTERGRANATE) werden etwas kleiner statt abgeschnitten
	local name = UITheme.Label({ Position = UDim2.fromOffset(45, 7), Size = UDim2.new(1, -118, 0, 22), Text = "", TextSize = 20,
		TextScaled = true, Font = UITheme.Fonts.Display }, row)
	make("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 14 }, name)
	local kindLabel = UITheme.Label({ Position = UDim2.fromOffset(45, 30), Size = UDim2.new(1, -118, 0, 14), Text = kind,
		TextSize = 11, Font = UITheme.Fonts.Bold, TextColor3 = C.Muted }, row)
	local status = UITheme.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0, 64, 1, -3),
		Text = "", TextSize = 22, Font = UITheme.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Right }, row)
	local track = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, BorderSizePixel = 0 }, row)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0 }, track)
	local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Primary, BackgroundTransparency = 1,
		BorderSizePixel = 0 }, row)
	UITheme.Corner(flash, UITheme.Radius.Small)
	return { Row = row, Key = key, KeyStroke = keyStroke, Name = name, Kind = kindLabel, Status = status, Fill = fill, Flash = flash }
end

-- Taste setzen (Controller-Kombis wie "L1+R1" brauchen ein breiteres Kästchen); Touch: ohne Taste
local function setKey(row, text, touch)
	row.Key.Visible = not touch and text ~= ""
	row.Key.Text = text
	local wide = #text > 2
	row.Key.Size = UDim2.fromOffset(wide and 44 or 26, 26)
	local x = row.Key.Visible and (wide and 63 or 45) or 12
	row.Name.Position = UDim2.fromOffset(x, 7)
	row.Kind.Position = UDim2.fromOffset(x, 30)
end

-- Balken unten: Anteil und Farbe
local function setFill(row, fraction, color)
	row.Fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	row.Fill.BackgroundColor3 = color
end

-- Kurzes Aufblitzen, wenn etwas bereit wird
local function pulse(row)
	row.Flash.BackgroundTransparency = 0.7
	TweenService:Create(row.Flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
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

	-- Karten unten in der Mitte: Fähigkeit · Gadget · Ultimate
	local bar = make("Frame", { Name = "Abilities", BackgroundTransparency = 1 }, root)
	local list = make("UIListLayout", { Padding = UDim.new(0, CARD_GAP), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center }, bar)
	local abilityRow = makeRow(bar, 1, "FÄHIGKEIT")
	local gadgetRow = makeRow(bar, 2, "GADGET")
	local ultimateRow = makeRow(bar, 3, "ULTIMATE")

	-- PC/Controller: Reihe unten mittig; Touch: Spalte links neben der Munition (rechts liegen die Touch-Knöpfe)
	local function layout()
		if InputActions.IsTouch() then
			list.FillDirection = Enum.FillDirection.Vertical
			bar.AnchorPoint = Vector2.new(1, 1)
			bar.Position = UDim2.new(0.5, -12, 1, -14)
			bar.Size = UDim2.fromOffset(CARD_W, CARD_H * 3 + CARD_GAP * 2)
		else
			list.FillDirection = Enum.FillDirection.Horizontal
			bar.AnchorPoint = Vector2.new(0.5, 1)
			bar.Position = UDim2.new(0.5, 0, 1, -BOTTOM)
			bar.Size = UDim2.fromOffset(CARD_W * 3 + CARD_GAP * 2, CARD_H)
		end
	end
	layout()
	InputActions.DeviceChanged:Connect(layout)

	-- Gesamtdauer der aktuellen Abklingzeit bzw. Wirkdauer (für den Balken)
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
		local touch = InputActions.IsTouch()
		setKey(abilityRow, InputActions.Hint("Ability"), touch)
		setKey(gadgetRow, InputActions.Hint("Gadget"), touch)
		setKey(ultimateRow, InputActions.Hint("Ultimate"), touch)

		-- Fähigkeit: läuft (blau, Balken schrumpft), lädt (grau, Sekunden) oder bereit (Bernstein)
		abilityRow.Name.Text = UITheme.Upper(agent.Ability.Name)
		local activeLeft = (player:GetAttribute("AbilityActiveUntil") or 0) - now
		local cooldownLeft = (player:GetAttribute("AbilityReadyAt") or 0) - now
		local ready = activeLeft <= 0 and cooldownLeft <= 0
		if activeLeft > 0 then
			setFill(abilityRow, activeLeft / activeTotal, C.Accent)
			abilityRow.Status.Text = string.format("%.0f s", math.ceil(activeLeft))
			abilityRow.Status.TextColor3 = C.Accent
			abilityRow.Name.TextColor3 = C.Text
		elseif cooldownLeft > 0 then
			setFill(abilityRow, 1 - cooldownLeft / cooldownTotal, C.Muted)
			abilityRow.Status.Text = tostring(math.ceil(cooldownLeft))
			abilityRow.Status.TextColor3 = C.Muted
			abilityRow.Name.TextColor3 = C.Muted
		else
			setFill(abilityRow, 1, C.Primary)
			abilityRow.Status.Text = ""
			abilityRow.Name.TextColor3 = C.Text
		end
		abilityRow.Key.TextColor3 = ready and C.Text or C.Muted
		if ready and not wasReady then
			pulse(abilityRow)
		end
		wasReady = ready

		-- Gadget mit Aufladungen
		local charges = player:GetAttribute("Gadgets") or 0
		gadgetRow.Name.Text = UITheme.Upper(agent.Gadget.Name)
		gadgetRow.Name.TextColor3 = charges > 0 and C.Text or C.Muted
		gadgetRow.Key.TextColor3 = charges > 0 and C.Text or C.Muted
		gadgetRow.Status.Text = "×" .. charges
		gadgetRow.Status.TextColor3 = charges > 0 and C.Text or C.Bad
		setFill(gadgetRow, charges > 0 and 1 or 0, C.Primary)
		if charges > 0 and not hadCharges then
			pulse(gadgetRow)
		end
		hadCharges = charges > 0

		-- Ultimate: Ladung in Prozent, voll = BEREIT (Taste und Balken leuchten leicht)
		local charge = math.clamp((player:GetAttribute("UltCharge") or 0) / 100, 0, 1)
		local ultReady = charge >= 1
		ultimateRow.Name.Text = UITheme.Upper(AgentConfig.Ultimate.Name)
		if ultReady then
			local glow = 0.5 + 0.5 * math.sin(os.clock() * 5)
			setFill(ultimateRow, 1, C.Primary:Lerp(Color3.new(1, 1, 1), glow * 0.3))
			ultimateRow.Status.Text = "BEREIT"
			ultimateRow.Status.TextColor3 = C.Primary
			ultimateRow.Name.TextColor3 = C.Text
			ultimateRow.Key.TextColor3 = C.Primary
			ultimateRow.KeyStroke.Color = C.Primary
			ultimateRow.KeyStroke.Transparency = 0.2 + glow * 0.4
		else
			setFill(ultimateRow, charge, C.Muted)
			ultimateRow.Status.Text = math.floor(charge * 100) .. " %"
			ultimateRow.Status.TextColor3 = C.Muted
			ultimateRow.Name.TextColor3 = C.Muted
			ultimateRow.Key.TextColor3 = C.Muted
			ultimateRow.KeyStroke.Color = C.Muted
			ultimateRow.KeyStroke.Transparency = 0.4
		end
		if ultReady and not ultWasReady then
			pulse(ultimateRow)
		end
		ultWasReady = ultReady
	end)
end

return AbilityClient
