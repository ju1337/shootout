-- HUD (ModuleScript, nur Client)
-- Leben, Munition, Kills, Fadenkreuz, Hitmarker, Schadenszahlen, Treffer-Sounds,
-- Schadens-Effekt, Killfeed, Modus-Info und Meldungen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local BuyConfig = require(Shared.BuyConfig)

local player = Players.LocalPlayer

local HUD = {}

local KILLFEED_MAX = 5        -- maximale Einträge im Killfeed
local KILLFEED_TIME = 5       -- Sekunden, die ein Eintrag sichtbar bleibt
local ANNOUNCE_TIME = 3       -- Sekunden für große Meldungen
-- Treffer-Sound (in Roblox eingebaut, keine Asset-ID nötig)
local HIT_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local gui
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

-- Weißer Text mit Umrandung, ohne Hintergrund
local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextStrokeTransparency = 0.5
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

	gui = make("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))

	-- Lebensbalken unten links
	local healthBack = make("Frame", {
		Position = UDim2.new(0, 20, 1, -50),
		Size = UDim2.new(0, 250, 0, 24),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, gui)
	local healthFill = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(80, 200, 100),
		BorderSizePixel = 0,
	}, healthBack)
	local healthText = label({ Size = UDim2.new(1, 0, 1, 0), Text = "100", TextSize = 18 }, healthBack)

	-- Rüstung (gekauft in Drop) als blauer Balken direkt über dem Leben
	local armorBack = make("Frame", {
		Position = UDim2.new(0, 20, 1, -58),
		Size = UDim2.new(0, 250, 0, 6),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	local armorFill = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(80, 160, 255),
		BorderSizePixel = 0,
	}, armorBack)

	-- Geld in Drop (über der Munition) und kurze Meldung "+200 $"
	local moneyText = label({
		Position = UDim2.new(1, -220, 1, -130),
		Size = UDim2.new(0, 200, 0, 30),
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(120, 230, 140),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	}, gui)

	-- Munition unten rechts
	local ammoText = label({
		Position = UDim2.new(1, -220, 1, -95),
		Size = UDim2.new(0, 200, 0, 45),
		Text = "",
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, gui)
	local weaponText = label({
		Position = UDim2.new(1, -220, 1, -50),
		Size = UDim2.new(0, 200, 0, 24),
		Text = "",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, gui)

	-- Eigene Kills oben links
	local killsText = label({
		Position = UDim2.new(0, 20, 0, 50),
		Size = UDim2.new(0, 200, 0, 30),
		Text = "Kills: 0",
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, gui)

	-- Modus-Info oben mittig (Text kommt vom Server als Spieler-Attribut "ModeText")
	local modeText = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.new(0, 700, 0, 30),
		Text = "",
		TextSize = 22,
	}, gui)

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

	-- Fadenkreuz und Hitmarker
	local crosshair = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 4, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, gui)
	local hitmarker = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 40, 0, 40),
		Text = "✕",
		TextSize = 26,
		Visible = false,
	}, gui)

	statusLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 60),
		Size = UDim2.new(0, 500, 0, 30),
		Text = "",
		TextSize = 22,
		Visible = false,
	}, gui)

	-- Große Meldung (Rundenstart, Sieger)
	local announce = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.new(0, 800, 0, 60),
		Text = "",
		TextSize = 44,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		Visible = false,
	}, gui)

	-- Killfeed oben rechts
	local killfeed = make("Frame", {
		Position = UDim2.new(1, -420, 0, 20),
		Size = UDim2.new(0, 400, 0, 200),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 4),
	}, killfeed)

	-- Leben: bei jedem Spawn neu verbinden
	local function trackCharacter(character)
		local humanoid = character:WaitForChild("Humanoid")
		local lastHealth = humanoid.Health
		local function update()
			local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			healthFill.Size = UDim2.new(ratio, 0, 1, 0)
			healthText.Text = tostring(math.max(0, math.ceil(humanoid.Health)))
			healthFill.BackgroundColor3 = ratio < 0.3 and Color3.fromRGB(230, 70, 60) or Color3.fromRGB(80, 200, 100)
			-- Getroffen: roter Rand blitzt auf, bei wenig Leben bleibt er leicht sichtbar
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

		local function updateArmor()
			local armor = character:GetAttribute("Armor") or 0
			armorBack.Visible = armor > 0
			armorFill.Size = UDim2.new(math.clamp(armor / BuyConfig.ArmorAmount, 0, 1), 0, 1, 0)
		end
		updateArmor()
		character:GetAttributeChangedSignal("Armor"):Connect(updateArmor)
	end
	player.CharacterAdded:Connect(trackCharacter)
	if player.Character then
		task.spawn(trackCharacter, player.Character)
	end

	-- Kills aus leaderstats
	task.spawn(function()
		local kills = player:WaitForChild("leaderstats"):WaitForChild("Kills")
		local function update()
			killsText.Text = "Kills: " .. kills.Value
		end
		update()
		kills.Changed:Connect(update)
	end)

	-- Modus-Text
	local function updateMode()
		modeText.Text = player:GetAttribute("ModeText") or ""
	end
	updateMode()
	player:GetAttributeChangedSignal("ModeText"):Connect(updateMode)

	-- Eroberungspunkt (Strikeout): Fortschritt beider Teams unter der Modus-Info
	local objective = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.new(0, 420, 0, 52),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local function objectiveBar(y, color, title)
		label({ Position = UDim2.new(0, 0, 0, y), Size = UDim2.new(0, 70, 0, 14), Text = title, TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left }, objective)
		local back = make("Frame", { Position = UDim2.new(0, 75, 0, y + 2), Size = UDim2.new(1, -75, 0, 10),
			BackgroundColor3 = Color3.fromRGB(30, 30, 35), BackgroundTransparency = 0.2, BorderSizePixel = 0 }, objective)
		return make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	end
	local mineBar = objectiveBar(0, Color3.fromRGB(80, 200, 255), "WIR")
	local enemyBar = objectiveBar(16, Color3.fromRGB(255, 80, 80), "GEGNER")
	local objectiveInfo = label({ Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 0, 20), Text = "",
		TextSize = 15 }, objective)
	local function updateObjective()
		local mine = player:GetAttribute("ObjMine")
		local info = player:GetAttribute("ObjInfo")
		objective.Visible = mine ~= nil or info ~= nil
		-- Balken nur mit Punkt-Fortschritt (Strikeout), sonst nur die Statuszeile (Demolition)
		for _, child in objective:GetChildren() do
			if child ~= objectiveInfo then
				child.Visible = mine ~= nil
			end
		end
		mineBar.Size = UDim2.new(mine or 0, 0, 1, 0)
		enemyBar.Size = UDim2.new(player:GetAttribute("ObjEnemy") or 0, 0, 1, 0)
		objectiveInfo.Text = info or ""
	end
	updateObjective()
	player:GetAttributeChangedSignal("ObjMine"):Connect(updateObjective)
	player:GetAttributeChangedSignal("ObjEnemy"):Connect(updateObjective)
	player:GetAttributeChangedSignal("ObjInfo"):Connect(updateObjective)

	-- HUD nur in Kampfmodi zeigen, nicht im Hub
	local function updateVisible()
		gui.Enabled = Modes.IsFighting(player)
	end
	updateVisible()
	player:GetAttributeChangedSignal("Mode"):Connect(updateVisible)

	-- Munition
	weaponClient.AmmoChanged:Connect(function(name, mag, reserve, reloading)
		ammoText.Text = mag .. " / " .. reserve
		local displayName = require(Shared.WeaponConfig).Get(name).DisplayName
		weaponText.Text = reloading and (displayName .. " · lädt nach...") or displayName
	end)

	-- Hitmarker: weiß = Körper, rot = Kopf, groß = Kill
	local hitId = 0
	local killId = 0
	local killNotice = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 30),
		Size = UDim2.new(0, 500, 0, 28),
		Text = "",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 90, 90),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, gui)
	weaponClient.Hit:Connect(function(headshot, killed, damage, position, victimName, downed)
		hitId += 1
		local myId = hitId
		hitmarker.TextColor3 = headshot and Color3.fromRGB(255, 70, 70) or Color3.new(1, 1, 1)
		hitmarker.TextSize = killed and 40 or 26
		hitmarker.Visible = true
		task.delay(0.15, function()
			if hitId == myId then
				hitmarker.Visible = false
			end
		end)

		-- Treffer-Sound (höher bei Kopfschuss, tiefer bei Kill)
		local sound = Instance.new("Sound")
		sound.SoundId = HIT_SOUND
		sound.Volume = killed and 0.8 or 0.5
		sound.PlaybackSpeed = killed and 0.7 or (headshot and 1.5 or 1.15)
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 2)

		-- Schadenszahl an der Trefferstelle, steigt auf und verblasst
		if damage and damage > 0 and typeof(position) == "Vector3" then
			local anchor = Instance.new("Attachment")
			anchor.WorldPosition = position
			anchor.Parent = workspace.Terrain
			local billboard = make("BillboardGui", { Adornee = anchor, Size = UDim2.new(0, 80, 0, 30),
				AlwaysOnTop = true, StudsOffset = Vector3.new(math.random(-10, 10) / 10, 1, 0) }, gui)
			local number = label({ Size = UDim2.new(1, 0, 1, 0), Text = tostring(math.floor(damage + 0.5)),
				TextSize = headshot and 26 or 20, TextColor3 = headshot and Color3.fromRGB(255, 210, 60)
					or Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center }, billboard)
			TweenService:Create(billboard, TweenInfo.new(0.8), { StudsOffset = billboard.StudsOffset + Vector3.new(0, 2, 0) }):Play()
			TweenService:Create(number, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			Debris:AddItem(billboard, 0.85)
			Debris:AddItem(anchor, 0.85)
		end

		-- Kill- bzw. Niederschlag-Meldung unter dem Fadenkreuz
		if (killed or downed) and victimName then
			killId += 1
			local myKill = killId
			killNotice.Text = (killed and "✕  ELIMINIERT  " or "⬇  NIEDERGESCHLAGEN  ") .. string.upper(victimName)
			killNotice.TextColor3 = killed and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 190, 80)
			killNotice.Visible = true
			task.delay(1.6, function()
				if killId == myKill then
					killNotice.Visible = false
				end
			end)
		end
	end)

	-- Fadenkreuz beim Zielen ausblenden (man schaut über das Visier)
	weaponClient.AimChanged:Connect(function(aiming)
		crosshair.Visible = not aiming
	end)

	-- Killfeed-Einträge
	local entryCount = 0
	Remotes.Killfeed.OnClientEvent:Connect(function(killerName, victimName, weaponName, headshot)
		entryCount += 1
		local text = killerName .. " hat " .. victimName .. " erledigt"
		if headshot then
			text ..= " (Kopfschuss)"
		end
		local involvesMe = killerName == player.Name or victimName == player.Name
		local entry = label({
			Size = UDim2.new(0, 400, 0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "  " .. text .. "  ",
			TextSize = 18,
			TextColor3 = involvesMe and Color3.fromRGB(255, 220, 90) or Color3.new(1, 1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			TextXAlignment = Enum.TextXAlignment.Right,
			LayoutOrder = entryCount,
		}, killfeed)
		-- Älteste Einträge entfernen
		local entries = {}
		for _, child in killfeed:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(entries, child)
			end
		end
		table.sort(entries, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #entries - KILLFEED_MAX do
			entries[i]:Destroy()
		end
		task.delay(KILLFEED_TIME, function()
			entry:Destroy()
		end)
	end)

	-- XP-Meldung über der Fähigkeits-Box ("+100 XP · Kill"), Level-Up groß
	local xpText = label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.new(0, 400, 0, 30),
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(120, 230, 140),
		Visible = false,
	}, gui)
	local xpId = 0
	Remotes.XPGain.OnClientEvent:Connect(function(amount, reason, agentId, levelUp, coins)
		xpId += 1
		local myId = xpId
		xpText.Text = "+" .. amount .. " XP" .. ((coins or 0) > 0 and ("  +" .. coins .. " 💰") or "") .. "  ·  " .. tostring(reason)
		xpText.Visible = true
		task.delay(2, function()
			if xpId == myId then
				xpText.Visible = false
			end
		end)
		local agent = AgentConfig.Get(agentId)
		if levelUp and agent then
			local level = AgentConfig.LevelFromXP(AgentConfig.GetXP(player, agentId))
			local skin = AgentConfig.SkinForLevel(level)
			local message = agent.Name .. " ist jetzt Level " .. level .. "!"
			if skin and skin.Level == level then
				message ..= "  " .. skin.Name .. "-Skin freigeschaltet!"
			end
			HUD.ShowAnnouncement(message)
		end
	end)

	-- Geld (nur während eines Drop-Matches)
	local function updateMoney()
		local money = player:GetAttribute("Money")
		moneyText.Visible = money ~= nil
		moneyText.Text = money and ("💵 " .. money .. " $") or ""
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
		BackgroundColor3 = Color3.fromRGB(20, 10, 12),
		BackgroundTransparency = 0.25,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, recap)
	make("UIStroke", { Color = Color3.fromRGB(220, 60, 60), Thickness = 1.5 }, recap)
	local recapTitle = label({ Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -32, 0, 28), Text = "",
		TextSize = 20, TextColor3 = Color3.fromRGB(255, 90, 90), TextXAlignment = Enum.TextXAlignment.Left }, recap)
	local recapInfo = label({ Position = UDim2.new(0, 16, 0, 40), Size = UDim2.new(1, -32, 0, 22), Text = "",
		TextSize = 15, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, recap)
	local recapId = 0
	Remotes.DeathRecap.OnClientEvent:Connect(function(killerName, weaponName, killerHealth, agentId)
		recapId += 1
		local myId = recapId
		local agent = agentId and AgentConfig.Get(agentId)
		recapTitle.Text = "AUSGESCHALTET VON " .. string.upper(tostring(killerName))
		recapInfo.Text = (agent and (agent.Name .. "  ·  ") or "") .. tostring(weaponName or "?")
			.. "  ·  hatte noch " .. tostring(killerHealth) .. " Leben"
		recap.Visible = true
		task.delay(4, function()
			if recapId == myId then
				recap.Visible = false
			end
		end)
	end)

	-- Große Meldungen
	local announceId = 0
	function HUD.ShowAnnouncement(text)
		announceId += 1
		local myId = announceId
		announce.Text = text
		announce.Visible = true
		task.delay(ANNOUNCE_TIME, function()
			if announceId == myId then
				announce.Visible = false
			end
		end)
	end
	Remotes.Announce.OnClientEvent:Connect(HUD.ShowAnnouncement)
end

return HUD
