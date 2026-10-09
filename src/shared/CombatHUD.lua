-- CombatHUD (ModuleScript, nur Client)
-- Kampf-Anzeigen rund um die Bildschirmmitte im Stil von Rogue Company:
--   * Fadenkreuz: vier dünne Striche und ein kleiner Punkt, der Abstand zeigt die echte Streuung der Waffe
--     (Bewegung, Sprung, Dauerfeuer). Beim Zielen in der Schulterkamera zieht es sich zu einem kleinen Kreuz zusammen,
--     in der Ego-Perspektive blendet es aus (man zielt über Kimme und Korn). Schrotflinte: Kreis.
--     Über Gegnern wird es rot.
--   * Hitmarker, Schadenszahlen und Treffer-Töne in mehreren Stilen: HitFeedback (Einstellungen „Hitmarker“ und
--     „Schadenszahlen“)
--   * Treffer-Richtung: rote Bögen um die Mitte zeigen zum Angreifer (stärker bei viel Schaden)
--   * Kill-Meldung (ELIMINIERT / NIEDERGESCHLAGEN) mit XP-Zeile darunter, mittig unter dem Fadenkreuz, Nachlade-Balken, Anzeige "Schuss blockiert"
--     (Schulterkamera: zwischen Waffe und Ziel ist etwas im Weg)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local WeaponConfig = require(Shared.WeaponConfig)
local Movement = require(Shared.Movement)
local TeamCheck = require(Shared.TeamCheck)
local PlayerSettings = require(Shared.PlayerSettings)
local HitFeedback = require(Shared.HitFeedback)

local player = Players.LocalPlayer

local CombatHUD = {}

local WHITE = Color3.new(1, 1, 1)
local ENEMY_RED = Color3.fromRGB(230, 70, 60)
local DOWN_ORANGE = Color3.fromRGB(226, 150, 64)
local KILL_RED = Color3.fromRGB(226, 56, 50)

local MIN_GAP = 2.5          -- kleinster Abstand der Striche zur Mitte (Design-Pixel)
local HIP_LENGTH = 10        -- Strichlänge aus der Hüfte ...
local AIM_LENGTH = 5         -- ... und beim Zielen (kleines Kreuz)
local THICKNESS = 2
local INDICATOR_TIME = 1.6   -- Sichtbarkeit der Treffer-Richtung
local INDICATOR_RADIUS = 150

local make = UITheme.Make

local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or Enum.Font.BuilderSansBold
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.4
	return make("TextLabel", props, parent)
end

-- Weißer Strich mit dünnem dunklen Rand (gut sichtbar auf jedem Hintergrund)
local function bar(parent)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, parent)
	local stroke = make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.45,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	return frame, stroke
end

-- Ist das Modell ein Gegner des Spielers (für das rote Fadenkreuz)?
local isEnemy = TeamCheck.IsEnemy

-- gui = skalierte Vollbild-Ebene des HUD, weaponClient = WeaponClient-Modul
function CombatHUD.Init(gui, weaponClient)
	-- Kein Mauszeiger über dem Fadenkreuz: ausgeblendet, solange die Maus zum Zielen in der Bildmitte gesperrt
	-- ist (Ego- und Schulterkamera). Menüs geben die Maus vorher frei (Default) – dann ist er wieder da.
	RunService:BindToRenderStep("HideCursor", Enum.RenderPriority.Camera.Value + 10, function()
		UserInputService.MouseIconEnabled = UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
	end)

	local uiScale = gui:FindFirstChildOfClass("UIScale")
	local function scale()
		return uiScale and uiScale.Scale or 1
	end

	-- ---------- Fadenkreuz ----------
	local cross = make("Frame", { Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, ZIndex = 5 }, gui)
	local dot, dotStroke = bar(cross)
	dot.Size = UDim2.new(0, 2, 0, 2) -- kleiner weißer Punkt
	dot.Position = UDim2.new(0.5, 0, 0.5, 0)
	local bars = {}
	for _, dir in { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) } do
		local frame, stroke = bar(cross)
		table.insert(bars, { Frame = frame, Stroke = stroke, Dir = dir })
	end
	-- Schrotflinte: Kreis statt Strichen
	local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundTransparency = 1, Visible = false }, cross)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	local ringStroke = make("UIStroke", { Color = WHITE, Thickness = 1.5, Transparency = 0.15 }, ring)
	local ringShadow = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 2, 1, 2), BackgroundTransparency = 1 }, ring)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, ringShadow)
	local ringShadowStroke = make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.6 }, ringShadow)

	-- "Schuss blockiert" (Schulterkamera): Kreis an der Stelle, die zwischen Waffe und Ziel liegt
	local blocked = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 14, 0, 14),
		BackgroundTransparency = 1, Visible = false, ZIndex = 5 }, gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, blocked)
	make("UIStroke", { Color = ENEMY_RED, Thickness = 2, Transparency = 0.1 }, blocked)
	local blockedSlash = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 2, 0, 14), Rotation = 45, BackgroundColor3 = ENEMY_RED, BorderSizePixel = 0 }, blocked)
	blockedSlash.ZIndex = 5

	-- Nachlade-Balken unter dem Fadenkreuz
	local reloadBack = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 30),
		Size = UDim2.new(0, 70, 0, 3), BackgroundColor3 = UITheme.Colors.Background, BackgroundTransparency = 0.3,
		BorderSizePixel = 0, Visible = false }, gui)
	local reloadFill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = UITheme.Colors.Primary,
		BorderSizePixel = 0 }, reloadBack)
	local reloadText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3), Size = UDim2.new(0, 120, 0, 14),
		Text = "NACHLADEN", TextSize = 10, Font = UITheme.Fonts.Bold, TextColor3 = UITheme.Colors.Primary }, reloadBack)
	reloadText.TextXAlignment = Enum.TextXAlignment.Center

	local kick = 0       -- kurzes Aufspringen des Fadenkreuzes beim Schuss
	local hoverEnemy = false
	local lastHoverCheck = 0
	weaponClient.Fired:Connect(function()
		kick = math.min(kick + 6, 14)
	end)

	local function raycastParams()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local list = { workspace.CurrentCamera }
		if player.Character then
			table.insert(list, player.Character)
		end
		local effects = workspace:FindFirstChild("WeaponEffects")
		if effects then
			table.insert(list, effects)
		end
		params.FilterDescendantsInstances = list
		return params
	end

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local head = character and character:FindFirstChild("Head")
		local weapon = weaponClient.GetWeapon()
		local cfg = weapon and WeaponConfig.Get(weapon)
		local alive = humanoid ~= nil and humanoid.Health > 0 and Modes.IsFighting(player) and not character:GetAttribute("Downed")
		local camera = workspace.CurrentCamera
		local spectating = humanoid ~= nil and camera.CameraSubject ~= humanoid
		if not alive or not cfg or spectating then
			cross.Visible = false
			blocked.Visible = false
			reloadBack.Visible = false
			return
		end
		cross.Visible = true
		kick *= math.exp(-14 * dt)

		local aim = weaponClient.GetAimBlend()
		local firstPerson = weaponClient.IsFirstPerson()
		local s = scale()
		-- Streuung (Grad) in Bildschirm-Abstand umrechnen: tan(Streuung) / tan(halbes Sichtfeld) * halbe Höhe
		local spread = weaponClient.GetSpread()
		local halfFov = math.rad(camera.FieldOfView / 2)
		local radius = math.tan(math.rad(spread)) / math.tan(halfFov) * camera.ViewportSize.Y / 2 / s
		local gap = math.max(MIN_GAP, radius) + kick * (1 - aim * 0.6)
		local length = HIP_LENGTH + (AIM_LENGTH - HIP_LENGTH) * aim

		-- Sichtbarkeit: Ego beim Zielen aus (Kimme und Korn), beim Sprinten und Nachladen schwächer
		local alpha = 1
		if firstPerson then
			alpha = 1 - math.clamp(aim * 1.6, 0, 1)
		end
		if Movement.IsSprinting() then
			alpha *= 0.3
		end
		if weaponClient.GetReloadProgress() then
			alpha *= 0.5
		end

		-- Gegner unter dem Fadenkreuz? (nicht jedes Bild prüfen)
		local now = os.clock()
		if now - lastHoverCheck > 0.05 then
			lastHoverCheck = now
			local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * math.min(cfg.Range + 15, 900),
				raycastParams())
			hoverEnemy = result ~= nil and isEnemy(result.Instance:FindFirstAncestorOfClass("Model"))
		end
		-- Farbe aus den Einstellungen; über einem Gegner immer rot
		local color = hoverEnemy and ENEMY_RED
			or (PlayerSettings.CrosshairColors[PlayerSettings.Get("CrosshairColor")] or WHITE)
		local transparency = 1 - alpha

		local useRing = cfg.Pellets ~= nil and cfg.Pellets > 1
		ring.Visible = useRing
		if useRing then
			ring.Size = UDim2.new(0, gap * 2, 0, gap * 2)
			ringStroke.Color = color
			ringStroke.Transparency = 0.15 + transparency * 0.85
			ringShadowStroke.Transparency = 0.6 + transparency * 0.4
		end
		for _, entry in bars do
			local frame = entry.Frame
			frame.Visible = not useRing
			local offset = gap + length / 2
			frame.Position = UDim2.new(0.5, entry.Dir.X * offset, 0.5, entry.Dir.Y * offset)
			frame.Size = entry.Dir.X == 0 and UDim2.new(0, THICKNESS, 0, length) or UDim2.new(0, length, 0, THICKNESS)
			frame.BackgroundColor3 = color
			frame.BackgroundTransparency = transparency
			entry.Stroke.Transparency = 0.45 + transparency * 0.55
		end
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = transparency
		dotStroke.Transparency = 0.45 + transparency * 0.55

		-- Nachladen
		local progress = weaponClient.GetReloadProgress()
		reloadBack.Visible = progress ~= nil
		if progress then
			reloadFill.Size = UDim2.new(progress, 0, 1, 0)
		end

		-- Schulterkamera: Ist zwischen Kopf (dort startet der Schuss) und dem Ziel unter dem Fadenkreuz etwas?
		local showBlocked = false
		if not firstPerson and head then
			local params = raycastParams()
			local origin, look = camera.CFrame.Position, camera.CFrame.LookVector
			local skip = math.max(0, (head.Position - origin):Dot(look))
			local aimHit = workspace:Raycast(origin + look * skip, look * cfg.Range, params)
			local aimPoint = aimHit and aimHit.Position or (origin + look * (skip + cfg.Range))
			local toAim = aimPoint - head.Position
			local block = toAim.Magnitude > 2 and workspace:Raycast(head.Position, toAim, params)
			if block and (block.Position - aimPoint).Magnitude > 1.5 and (block.Position - head.Position).Magnitude > 1.5 then
				local screen, onScreen = camera:WorldToViewportPoint(block.Position)
				if onScreen then
					showBlocked = true
					blocked.Position = UDim2.new(0, screen.X / s, 0, screen.Y / s)
				end
			end
		end
		blocked.Visible = showBlocked
	end)

	-- ---------- Kill-Meldung und XP ----------
	-- Ein gemeinsamer Block mittig unter dem Fadenkreuz, weit genug unten, dass er das Ziel nicht verdeckt:
	-- oben die Kill-Karte (farbiges Schild ELIMINIERT / NIEDERGESCHLAGEN + Name, Akzentstrich in derselben Farbe,
	-- im Stil der Hotbar-Kacheln), darunter die XP-Zeile ("+100 XP · KILL", Münzen in Gold). Medaillen-XP kommen leise
	-- (quiet), die zeigt die Medaille selbst. Level-Aufstiege meldet Notifications.
	local feed = make("Frame", { Name = "KillFeedback", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 150),
		Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1 }, gui)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, feed)

	local killNotice = make("Frame", { Name = "Kill", Size = UDim2.new(0, 0, 0, 38), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = UITheme.Colors.Background, BackgroundTransparency = 0.25, BorderSizePixel = 0, Visible = false,
		LayoutOrder = 1 }, feed)
	UITheme.Corner(killNotice, UITheme.Radius.Small)
	UITheme.Stroke(killNotice)
	local killAccent = UITheme.AccentBar(killNotice, KILL_RED, { Side = "Bottom", Thickness = 2 })
	local killRow = make("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1 }, killNotice)
	make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 16) }, killRow)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, killRow)
	local killTag = make("Frame", { Size = UDim2.new(0, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = KILL_RED, BorderSizePixel = 0, LayoutOrder = 1 }, killRow)
	UITheme.Corner(killTag, 3)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, killTag)
	local killTitle = label({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 14,
		Font = Enum.Font.BuilderSansExtraBold, TextStrokeTransparency = 1 }, killTag)
	local killName = label({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 22,
		Font = Enum.Font.BuilderSansExtraBold, TextStrokeTransparency = 0.7, LayoutOrder = 2 }, killRow)

	local xpRow = make("Frame", { Name = "XP", Size = UDim2.new(0, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, Visible = false, LayoutOrder = 2 }, feed)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, xpRow)
	local function xpLabel(order, size, color)
		return label({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = size,
			Font = Enum.Font.BuilderSansExtraBold, TextColor3 = color, LayoutOrder = order }, xpRow)
	end
	local xpAmount = xpLabel(1, 20, UITheme.Colors.Primary)
	local xpCoins = xpLabel(2, 17, UITheme.Colors.Gold)
	local xpDot = xpLabel(3, 17, UITheme.Colors.Muted)
	xpDot.Text = "·"
	local xpReason = xpLabel(4, 17, UITheme.Colors.Text)

	-- kurzes Aufploppen
	local function pop(object, from)
		local s = object:FindFirstChildOfClass("UIScale") or make("UIScale", {}, object)
		s.Scale = from
		TweenService:Create(s, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	local killId = 0
	local function showKill(killed, name)
		killId += 1
		local myId = killId
		local color = killed and KILL_RED or DOWN_ORANGE
		killTitle.Text = killed and "ELIMINIERT" or "NIEDERGESCHLAGEN"
		killTag.BackgroundColor3 = color
		killAccent.BackgroundColor3 = color
		killName.Text = UITheme.Upper(tostring(name))
		killNotice.Visible = true
		pop(killNotice, 1.12)
		task.delay(2.2, function()
			if killId == myId then
				killNotice.Visible = false
			end
		end)
	end

	local xpId = 0
	Remotes.XPGain.OnClientEvent:Connect(function(amount, reason, _, _, coins, quiet)
		if quiet then
			return
		end
		xpId += 1
		local myId = xpId
		xpAmount.Text = "+" .. amount .. " XP"
		xpCoins.Visible = (coins or 0) > 0
		xpCoins.Text = xpCoins.Visible and ("+" .. coins .. " MÜNZEN") or ""
		local why = reason and UITheme.Upper(tostring(reason)) or ""
		xpReason.Text = why
		xpReason.Visible = why ~= ""
		xpDot.Visible = why ~= ""
		xpRow.Visible = true
		pop(xpRow, 1.2)
		task.delay(2.2, function()
			if xpId == myId then
				xpRow.Visible = false
			end
		end)
	end)

	-- Treffer: Hitmarker, Schadenszahl und Ton (HitFeedback), dazu die Kill-Meldung
	HitFeedback.Init(gui)
	weaponClient.Hit:Connect(function(headshot, killed, damage, position, victimName, downed, armor, victimModel)
		HitFeedback.Hit(headshot, killed, damage, position, downed, armor, victimModel)
		if (killed or downed) and victimName then
			showKill(killed, victimName)
		end
	end)

	-- ---------- Treffer-Richtung ----------
	local indicators = {} -- { Holder, Segments, Position, Until, Strength }
	local function newIndicator()
		local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, ZIndex = 4 }, gui)
		local segments = {}
		for k = -3, 3 do
			local angle = math.rad(k * 7)
			local segment = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.sin(angle) * INDICATOR_RADIUS, 0.5, -math.cos(angle) * INDICATOR_RADIUS),
				Size = UDim2.new(0, 19, 0, k == 0 and 7 or 5), Rotation = k * 7, BackgroundColor3 = KILL_RED,
				BorderSizePixel = 0, ZIndex = 4 }, holder)
			table.insert(segments, { Frame = segment, Edge = math.abs(k) / 3 })
		end
		return holder, segments
	end
	Remotes.DamageFrom.OnClientEvent:Connect(function(position, amount)
		if typeof(position) ~= "Vector3" then
			return
		end
		local strength = math.clamp((typeof(amount) == "number" and amount or 20) / 40, 0.35, 1)
		-- Gleicher Angreifer kurz hintereinander: vorhandenen Bogen auffrischen
		for _, entry in indicators do
			if (entry.Position - position).Magnitude < 6 then
				entry.Position = position
				entry.Until = os.clock() + INDICATOR_TIME
				entry.Strength = math.max(entry.Strength, strength)
				return
			end
		end
		local holder, segments = newIndicator()
		table.insert(indicators, { Holder = holder, Segments = segments, Position = position,
			Until = os.clock() + INDICATOR_TIME, Strength = strength })
	end)
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		local now = os.clock()
		for i = #indicators, 1, -1 do
			local entry = indicators[i]
			if now > entry.Until then
				entry.Holder:Destroy()
				table.remove(indicators, i)
			else
				-- Winkel zwischen Blickrichtung und Richtung zum Angreifer (von oben gesehen)
				local look = camera.CFrame.LookVector
				local toAttacker = entry.Position - camera.CFrame.Position
				local angle = math.atan2(toAttacker.X, toAttacker.Z) - math.atan2(look.X, look.Z)
				entry.Holder.Rotation = -math.deg(angle)
				local life = math.clamp((entry.Until - now) / INDICATOR_TIME, 0, 1)
				for _, segment in entry.Segments do
					segment.Frame.BackgroundTransparency = 1 - life * entry.Strength * (1 - segment.Edge * 0.6)
				end
			end
		end
	end)
end

return CombatHUD
