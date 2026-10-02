-- HUD (ModuleScript, nur Client)
-- Bildschirm-Anzeige in den Kampfmodi: Schadens-Effekt, Countdown, XP neben dem Fadenkreuz, Geld,
-- Todesanzeige mit Todeskamera, Tastenzeile unten und VERLASSEN-Knopf unter der Minimap (zweimal klicken:
-- zurück in den Hub). Die Match-Anzeige (Punktestand, Killfeed, Leben, Munition, Zielmarker) baut MatchHUD,
-- die Minimap Minimap; Fadenkreuz, Hitmarker, Schadenszahlen, Treffer-Richtung und Kill-Meldung kommen aus
-- CombatHUD. Medaillen, Runden-Banner, Ziel- und Level-Meldungen zeigt Notifications.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local UITheme = require(Shared.UITheme)
local Movement = require(Shared.Movement)
local InputActions = require(Shared.InputActions)
local PlayerSettings = require(Shared.PlayerSettings)
local CombatHUD = require(Shared.CombatHUD)
local MatchHUD = require(Shared.MatchHUD)
local Minimap = require(Shared.Minimap)

local player = Players.LocalPlayer

local HUD = {}

local AMMO_SCALE = 1          -- Waffen-/Munitionsanzeige unten rechts: so groß wie die Lebensanzeige
local LEAVE_CONFIRM = 3       -- so lange wartet VERLASSEN auf den zweiten Klick

local screen -- ScreenGui (an/aus)
local gui    -- skalierte Vollbild-Ebene darin (alle HUD-Elemente)
local statusLabel

-- Kleiner Helfer: Instanz mit Eigenschaften erzeugen
local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

-- Weißer Text mit leichter dunkler Kante, ohne Hintergrund
local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextStrokeTransparency = 0.7
	return make("TextLabel", props, parent)
end

-- Text unter dem Fadenkreuz setzen (leerer Text = ausblenden), z.B. "Du schaust X zu"
function HUD.SetStatus(text: string)
	if statusLabel then
		statusLabel.Text = text
		statusLabel.Visible = text ~= ""
	end
end

function HUD.Init(weaponClient)
	-- Roblox-Standard-UI ausblenden, die wir selbst ersetzen
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	screen = make("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))
	gui = UITheme.ScaledRoot(screen) -- auf Handys kleiner

	-- Roter Bildschirm-Effekt bei Schaden (ganz unten, damit er nichts verdeckt)
	local damageFlash = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(200, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 0,
	}, gui)
	make("UIGradient", {
		-- Mitte durchsichtig, Ränder rot
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.85),
			NumberSequenceKeypoint.new(0.7, 0.85),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, damageFlash)

	-- Match-Anzeige im RC-Stil (Teamleiste, Killfeed, Leben, Munition, Zielmarker) und Minimap
	local match = MatchHUD.Init(gui, weaponClient)
	make("UIScale", { Scale = AMMO_SCALE }, match.Ammo)
	local minimap = Minimap.Init(gui)
	local minimapScale = make("UIScale", {}, minimap)

	-- Fadenkreuz, Hitmarker, Schadenszahlen, Treffer-Richtung, Kill-Meldung, Nachlade-Balken
	CombatHUD.Init(gui, weaponClient)

	statusLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 60),
		Size = UDim2.new(0, 500, 0, 30),
		Text = "",
		TextSize = 22,
		Visible = false,
	}, gui)

	-- Hinweis bei fast leerem Magazin (unter dem Fadenkreuz)
	local reloadHint = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 90),
		Size = UDim2.new(0, 300, 0, 24), Text = "", TextSize = 20, Font = Enum.Font.Oswald,
		TextColor3 = UITheme.Colors.Bad, TextXAlignment = Enum.TextXAlignment.Center, Visible = false }, gui)

	-- Geld in Team-Modi (über der Munition) und kurze Meldung "+200 $"
	local moneyText = label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -124),
		Size = UDim2.new(0, 260, 0, 28), Text = "", TextSize = 24, Font = UITheme.Fonts.Display,
		TextColor3 = UITheme.Colors.Good, TextXAlignment = Enum.TextXAlignment.Right, Visible = false }, gui)

	-- Tastenzeile ganz unten mittig ("LMB SCHIESSEN · R NACHLADEN · ..."), dezent, nur mit Tastatur
	local keyHints = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(0, 900, 0, 14),
		Text = "", TextSize = 10, Font = UITheme.Fonts.Bold, TextColor3 = UITheme.Colors.Text, TextTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center }, gui)
	local function updateKeyHints()
		keyHints.Visible = not InputActions.IsTouch() and PlayerSettings.Get("KeyHints") == true
		local parts = {}
		for _, entry in { { "Fire", "SCHIESSEN" }, { "Reload", "NACHLADEN" }, { "Ability", "FÄHIGKEIT" }, { "Gadget", "GADGET" },
			{ "Ultimate", "ULTIMATE" }, { "Weapon1", "WAFFE 1" }, { "Weapon2", "WAFFE 2" }, { "Scoreboard", "PUNKTE" } } do
			local key = InputActions.Hint(entry[1])
			if key ~= "" then
				table.insert(parts, key .. " " .. entry[2])
			end
		end
		keyHints.Text = table.concat(parts, "  ·  ")
	end
	updateKeyHints()
	InputActions.DeviceChanged:Connect(updateKeyHints)
	PlayerSettings.Changed:Connect(function(key)
		if key == "KeyHints" then
			updateKeyHints()
		end
	end)

	-- VERLASSEN-Knopf unter der Minimap: erster Klick fragt nach (rot), zweiter Klick innerhalb von
	-- LEAVE_CONFIRM Sekunden bringt einen zurück in den Hub
	local leaveButton = UITheme.Chunky({ Name = "LeaveButton", Size = UDim2.new(0, 152, 0, 30), Color = UITheme.Colors.Background,
		StrokeColor = UITheme.Colors.Border, Text = "VERLASSEN", TextSize = 17 }, gui)
	leaveButton.Face.BackgroundTransparency = 0.3
	local confirmLeaveUntil = 0
	local leaveClicks = 0 -- zählt Klicks, damit verspätete Rücksetzer nur den eigenen Zustand zurücksetzen
	local function resetLeave()
		confirmLeaveUntil = 0
		leaveButton.SetText("VERLASSEN")
		leaveButton.SetColor(UITheme.Colors.Background, UITheme.Colors.Text)
		leaveButton.SetStroke(UITheme.Colors.Border, 1)
	end
	leaveButton.Button.Activated:Connect(function()
		leaveClicks += 1
		local click = leaveClicks
		if os.clock() < confirmLeaveUntil then
			confirmLeaveUntil = 0
			leaveButton.SetText("VERLASSE ...")
			Remotes.JoinMode:FireServer(Modes.Hub.Id)
			-- Falls der Wechsel ausbleibt, nach kurzer Zeit wieder bedienbar machen
			task.delay(5, function()
				if leaveClicks == click then
					resetLeave()
				end
			end)
			return
		end
		confirmLeaveUntil = os.clock() + LEAVE_CONFIRM
		leaveButton.SetText("WIRKLICH VERLASSEN?")
		leaveButton.SetColor(UITheme.Colors.Bad, UITheme.Colors.Text)
		leaveButton.SetStroke(UITheme.Colors.Bad, 1)
		task.delay(LEAVE_CONFIRM, function()
			if leaveClicks == click and confirmLeaveUntil ~= 0 then
				resetLeave()
			end
		end)
	end)
	player:GetAttributeChangedSignal("Mode"):Connect(resetLeave)

	-- Schaden: roter Rand blitzt auf, bei wenig Leben bleibt er leicht sichtbar (bei jedem Spawn neu verbinden)
	local function trackCharacter(character)
		local humanoid = character:WaitForChild("Humanoid")
		local lastHealth = humanoid.Health
		local function update()
			local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			local resting = ratio < 0.3 and humanoid.Health > 0 and 0.75 or 1
			if humanoid.Health < lastHealth then
				damageFlash.BackgroundTransparency = 0.45
				TweenService:Create(damageFlash, TweenInfo.new(0.5), { BackgroundTransparency = resting }):Play()
			else
				damageFlash.BackgroundTransparency = resting
			end
			lastHealth = humanoid.Health
		end
		update()
		humanoid.HealthChanged:Connect(update)
	end
	player.CharacterAdded:Connect(trackCharacter)
	if player.Character then
		task.spawn(trackCharacter, player.Character)
	end

	-- ---------- Großer Countdown vor Rundenbeginn (3, 2, 1, LOS!) ----------
	local countdown = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 300, 0, 160), Text = "", TextSize = 130, Font = Enum.Font.Oswald,
		TextColor3 = UITheme.Colors.Text, TextXAlignment = Enum.TextXAlignment.Center, Visible = false }, gui)
	local countdownScale = make("UIScale", {}, countdown)
	local lastShown = nil
	RunService.Heartbeat:Connect(function()
		local finish = player:GetAttribute("CountdownEnd")
		local phase = player:GetAttribute("RoundPhase")
		if not finish or not Modes.IsTeamMode(player:GetAttribute("Mode")) then
			countdown.Visible = false
			return
		end
		local left = finish - workspace:GetServerTimeNow()
		local text
		if phase == "Countdown" and left > 0 then
			text = tostring(math.ceil(left))
		elseif phase == "Round" and left > -1 then
			text = "LOS!"
		end
		countdown.Visible = text ~= nil
		if text and text ~= lastShown then
			lastShown = text
			countdown.Text = text
			countdown.TextColor3 = text == "LOS!" and UITheme.Colors.Primary or UITheme.Colors.Text
			-- leichter Puls bei jeder neuen Zahl
			countdownScale.Scale = 1.12
			TweenService:Create(countdownScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		end
	end)

	-- Oberkante unter der Roblox-Leiste (Menü, Chat), in Design-Einheiten: Die Leiste ist immer gleich
	-- hoch (Pixel), das HUD wird aber je nach Bildschirm verkleinert – darum hier umrechnen.
	local rootScale = gui:FindFirstChildOfClass("UIScale")
	local function belowTopbar(minimum, gap)
		local inset = GuiService:GetGuiInset()
		local scale = rootScale and rootScale.Scale or 1
		return math.max(minimum, math.ceil((inset.Y + gap) / scale))
	end

	-- Touch-Geräte: links unten liegt der Steuerknüppel, rechts die Knöpfe. Darum Minimap kleiner,
	-- VERLASSEN rechts daneben, Leben darunter nach oben links und Munition unten in die Mitte (Fähigkeiten
	-- links daneben).
	local function layoutForDevice()
		match.Killfeed.Position = UDim2.new(1, -24, 0, belowTopbar(96, 14))
		if InputActions.IsTouch() then
			local top = belowTopbar(58, 8)
			minimap.Position = UDim2.new(0, 16, 0, top)
			minimapScale.Scale = 0.8
			leaveButton.Button.Position = UDim2.new(0, 16 + 160 + 12, 0, top)
			match.Vitals.AnchorPoint = Vector2.new(0, 0)
			match.Vitals.Position = UDim2.new(0, 16, 0, top + 172)
			match.Ammo.AnchorPoint = Vector2.new(0, 1)
			match.Ammo.Position = UDim2.new(0.5, 12, 1, -14)
			moneyText.AnchorPoint = Vector2.new(0, 1)
			moneyText.Position = UDim2.new(0.5, 12, 1, -116)
			moneyText.TextXAlignment = Enum.TextXAlignment.Left
		else
			local minimapTop = belowTopbar(66, 10)
			minimap.Position = UDim2.new(0, 24, 0, minimapTop)
			minimapScale.Scale = 1
			leaveButton.Button.Position = UDim2.new(0, 24 + 24, 0, minimapTop + 210)
			match.Vitals.AnchorPoint = Vector2.new(0, 1)
			match.Vitals.Position = UDim2.new(0, 24, 1, -24)
			match.Ammo.AnchorPoint = Vector2.new(1, 1)
			match.Ammo.Position = UDim2.new(1, -24, 1, -24)
			moneyText.AnchorPoint = Vector2.new(1, 1)
			moneyText.Position = UDim2.new(1, -24, 1, -124)
			moneyText.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
	layoutForDevice()
	InputActions.DeviceChanged:Connect(layoutForDevice)
	-- Fenstergröße geändert: neu ausrichten, nachdem die HUD-Skalierung angepasst wurde
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		task.defer(layoutForDevice)
	end)

	-- HUD nur in Kampfmodi zeigen, nicht im Hub
	local function updateVisible()
		screen.Enabled = Modes.IsFighting(player)
	end
	updateVisible()
	player:GetAttributeChangedSignal("Mode"):Connect(updateVisible)

	-- Nachladen-Hinweis bei fast leerem Magazin (mit Taste des aktuellen Geräts)
	weaponClient.AmmoChanged:Connect(function(name, mag, reserve, reloading, magSize, infinite)
		local config = WeaponConfig.Get(name)
		local size = magSize or (config and config.MagazineSize) or math.max(mag, 1)
		local ratio = math.clamp(mag / math.max(size, mag, 1), 0, 1)
		local key = InputActions.Hint("Reload")
		local prefix = key ~= "" and ("[" .. key .. "] ") or ""
		reloadHint.Visible = not reloading and ratio <= 0.25 and (reserve > 0 or infinite == true)
		reloadHint.Text = prefix .. (mag == 0 and "NACHLADEN" or "WENIG MUNITION")
	end)

	-- XP rechts neben dem Fadenkreuz wie die Punkte bei CoD ("+100 XP · KILL"). Medaillen-XP kommen leise
	-- (quiet), die zeigt die Medaille selbst. Level-Aufstiege meldet Notifications.
	local xpText = label({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 46, 0.5, 0),
		Size = UDim2.new(0, 360, 0, 26),
		Text = "",
		TextSize = 20,
		Font = Enum.Font.Oswald,
		TextColor3 = UITheme.Colors.Primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	}, gui)
	local xpScale = make("UIScale", {}, xpText)
	local xpId = 0
	Remotes.XPGain.OnClientEvent:Connect(function(amount, reason, _, _, coins, quiet)
		if quiet then
			return
		end
		xpId += 1
		local myId = xpId
		xpText.Text = "+" .. amount .. " XP" .. ((coins or 0) > 0 and ("  +" .. coins .. " MÜNZEN") or "") .. "  ·  "
			.. UITheme.Upper(tostring(reason))
		xpText.Visible = true
		xpScale.Scale = 1.2
		TweenService:Create(xpScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		task.delay(2, function()
			if xpId == myId then
				xpText.Visible = false
			end
		end)
	end)

	-- Geld (nur während eines Drop-Matches)
	local function updateMoney()
		local money = player:GetAttribute("Money")
		moneyText.Visible = money ~= nil
		moneyText.Text = money and (UITheme.FormatNumber(money) .. " $") or ""
	end
	updateMoney()
	player:GetAttributeChangedSignal("Money"):Connect(updateMoney)
	local moneyId = 0
	Remotes.MoneyGain.OnClientEvent:Connect(function(amount, reason)
		moneyId += 1
		local myId = moneyId
		moneyText.Text = "+" .. amount .. " $  ·  " .. tostring(reason)
		task.delay(1.5, function()
			if moneyId == myId then
				updateMoney()
			end
		end)
	end)

	-- Todesanzeige: wer hat dich ausgeschaltet
	local recap = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.7, 0),
		Size = UDim2.new(0, 440, 0, 74),
		BackgroundColor3 = UITheme.Colors.Background,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, UITheme.Radius.Small) }, recap)
	make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = UITheme.Colors.Bad, BorderSizePixel = 0 }, recap)
	local recapTitle = label({ Position = UDim2.new(0, 18, 0, 8), Size = UDim2.new(1, -34, 0, 30), Text = "",
		TextSize = 26, Font = Enum.Font.Oswald, TextColor3 = UITheme.Colors.Bad, TextXAlignment = Enum.TextXAlignment.Left }, recap)
	local recapInfo = label({ Position = UDim2.new(0, 18, 0, 42), Size = UDim2.new(1, -34, 0, 22), Text = "",
		TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = UITheme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left }, recap)
	local recapId = 0
	Remotes.DeathRecap.OnClientEvent:Connect(function(killerName, weaponName, killerHealth, agentId, killerModel)
		-- Todeskamera: 3 Sekunden auf den Killer schauen (Zuschauen übernimmt danach)
		local killerHumanoid = typeof(killerModel) == "Instance" and killerModel:FindFirstChildOfClass("Humanoid")
		if killerHumanoid then
			local camera = workspace.CurrentCamera
			camera:SetAttribute("KillCam", true)
			player.CameraMode = Enum.CameraMode.Classic
			player.CameraMinZoomDistance = 14
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = killerHumanoid
			task.delay(3, function()
				camera:SetAttribute("KillCam", nil)
				player.CameraMinZoomDistance = 0.5
				-- Schon wieder gespawnt: zurück zur eigenen Kamera
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					camera.CameraSubject = humanoid
					Movement.ApplyCamera()
				end
			end)
		end
		recapId += 1
		local myId = recapId
		local agent = agentId and AgentConfig.Get(agentId)
		recapTitle.Text = "AUSGESCHALTET VON " .. UITheme.Upper(tostring(killerName))
		recapInfo.Text = (agent and (agent.Name .. "  ·  ") or "") .. tostring(weaponName or "?")
			.. "  ·  hatte noch " .. tostring(killerHealth) .. " Leben"
		recap.Visible = true
		task.delay(4, function()
			if recapId == myId then
				recap.Visible = false
			end
		end)
	end)

end

return HUD
