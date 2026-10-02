-- SideMenu (ModuleScript, nur Client)
-- Knopfleiste links im Hub (wie in Hypershot & Co.): SHOP, RUCKSACK, AGENTEN, AUFTRÄGE, TÄGLICH,
-- CODES, EINSTELLUNGEN, darüber der Münzstand. Jeder Knopf öffnet ein Fenster in der Mitte.
-- Kaufen/Ausrüsten prüft der Server (ShopService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local AgentConfig = require(Shared.AgentConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local GunModels = require(Shared.GunModels)
local AgentFigure = require(Shared.AgentFigure)
local Movement = require(Shared.Movement)
local GameMenu = require(Shared.GameMenu)
local UITheme = require(Shared.UITheme)
local TweenService = game:GetService("TweenService")
local QuestConfig = require(Shared.QuestConfig)
local PassConfig = require(Shared.PassConfig)
local RankConfig = require(Shared.RankConfig)
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local SideMenu = {}

-- Farben aus dem gemeinsamen Design (UITheme)
local ACCENT = UITheme.Colors.Accent
local PANEL = UITheme.Colors.Panel
local CARD = UITheme.Colors.Card
local BORDER = UITheme.Colors.Border
local GRAY = UITheme.Colors.Muted
local GREEN = UITheme.Colors.Good

local WEAPON_ORDER = { "Rifle", "SMG", "Shotgun", "DMR", "LMG", "Pistol", "Revolver" }

local gui, column, coinLabel, dailyDot, questDot
local panels = {}      -- [Name] = { Frame, Status, Refresh }
local openPanel = nil

-- ---------- Helfer ----------

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function text(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

local function button(props, parent, onClick)
	props.BorderSizePixel = 0
	props.Font = props.Font or Enum.Font.GothamBlack
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.AutoButtonColor = true
	local b = make("TextButton", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local formatted = string.reverse(string.gsub(string.reverse(s), "(%d%d%d)", "%1."))
	return (string.gsub(formatted, "^%.", ""))
end

local function coins()
	return player:GetAttribute("Coins") or 0
end

-- Vorschau einer Waffe mit Skin in einem ViewportFrame
local function showWeapon(viewport, weaponName, skin)
	viewport:ClearAllChildren()
	local model = GunModels.Build(weaponName, skin)
	model.Parent = viewport
	local camera = make("Camera", { FieldOfView = 30 }, viewport)
	camera.CFrame = CFrame.lookAt(Vector3.new(5.5, 1.2, -0.5), Vector3.new(0, 0.2, -0.5))
	viewport.CurrentCamera = camera
end

-- Vorschau eines Agenten mit Farben in einem ViewportFrame
local function showAgent(viewport, agent, primary, accent)
	viewport:ClearAllChildren()
	local figure = AgentFigure.Build(agent, primary, accent, Cosmetics.WeaponSkin(player, agent.Id, agent.Loadout[1]))
	figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.4, 0))
	figure.Parent = viewport
	local camera = make("Camera", { FieldOfView = 38 }, viewport)
	camera.CFrame = AgentFigure.CameraCFrame
	viewport.CurrentCamera = camera
end

local function viewportFrame(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Ambient = Color3.fromRGB(130, 135, 150)
	props.LightColor = Color3.fromRGB(255, 245, 235)
	props.LightDirection = Vector3.new(-0.5, -1, 0.6)
	return make("ViewportFrame", props, parent)
end

-- Tab-Leiste: names = { "A", "B" }, onSelect(name)
local function tabBar(parent, names, y, onSelect)
	local bar = make("Frame", { Position = UDim2.new(0, 24, 0, y), Size = UDim2.new(1, -48, 0, 34),
		BackgroundTransparency = 1 }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	local buttons = {}
	local function select(name)
		for n, b in buttons do
			b.BackgroundColor3 = n == name and ACCENT or CARD
			b.TextColor3 = n == name and Color3.fromRGB(20, 20, 20) or Color3.new(1, 1, 1)
		end
		onSelect(name)
	end
	for i, name in names do
		buttons[name] = button({ Size = UDim2.new(0, 200, 1, 0), Text = name, TextSize = 15, LayoutOrder = i,
			BackgroundColor3 = CARD }, bar, function()
			select(name)
		end)
	end
	return select
end

-- ---------- Fenster ----------

local function setPanel(name)
	for panelName, panel in panels do
		panel.Frame.Visible = panelName == name
	end
	openPanel = name
	UITheme.SetBlur("SideMenu", name ~= nil)
	if name and panels[name].Refresh then
		panels[name].Refresh()
	end
end

local function makePanel(name, title, width, height)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, width, 0, height), BackgroundColor3 = PANEL, Visible = false, Active = true }, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, frame)
	make("UIStroke", { Color = BORDER, Thickness = 1.5 }, frame)
	UITheme.Gradient(frame, Color3.fromRGB(28, 33, 50), PANEL)
	-- Farbige Kopfleiste
	local header = make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, header)
	local scale = make("UIScale", {}, frame)
	local function updateScale()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min((viewport.X - 280) / (width + 40), (viewport.Y - 60) / (height + 40)), 0.4, 1.15)
	end
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	text({ Position = UDim2.new(0, 24, 0, 14), Size = UDim2.new(1, -100, 0, 40), Text = title, TextSize = 30,
		Font = Enum.Font.GothamBlack, TextColor3 = ACCENT }, frame)
	button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.new(0, 40, 0, 40),
		Text = "✕", TextSize = 20, BackgroundColor3 = CARD }, frame, function()
		setPanel(nil)
	end)
	local status = text({ Position = UDim2.new(0, 24, 1, -36), Size = UDim2.new(1, -48, 0, 24), Text = "",
		TextSize = 16, TextColor3 = GRAY }, frame)
	panels[name] = { Frame = frame, Status = status }
	return frame
end

-- ---------- SHOP ----------

local function buildShop()
	local frame = makePanel("Shop", "🛒  SHOP", 980, 620)
	local balance = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 20),
		Size = UDim2.new(0, 260, 0, 30), Text = "", TextSize = 22, TextColor3 = Color3.fromRGB(255, 210, 80),
		TextXAlignment = Enum.TextXAlignment.Right }, frame)
	local grid = make("ScrollingFrame", { Position = UDim2.new(0, 24, 0, 110), Size = UDim2.new(1, -48, 1, -156),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y }, frame)
	make("UIGridLayout", { CellSize = UDim2.new(0, 214, 0, 262), CellPadding = UDim2.new(0, 14, 0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)

	local currentType = "Weapon"
	local buyButtons = {} -- [itemId] = Button

	local function updateButtons()
		balance.Text = "💰 " .. formatNumber(coins())
		local owned = Cosmetics.GetOwned(player)
		for itemId, b in buyButtons do
			local item = Cosmetics.Get(itemId)
			if owned[itemId] then
				b.Text = "BESITZT ✓"
				b.BackgroundColor3 = Color3.fromRGB(55, 60, 75)
			else
				b.Text = "💰 " .. formatNumber(item.Price) .. "  KAUFEN"
				b.BackgroundColor3 = coins() >= item.Price and GREEN or Color3.fromRGB(90, 50, 50)
			end
		end
	end

	local function fill()
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		buyButtons = {}
		local shopItems = {}
		for _, item in Cosmetics.List(currentType) do
			if not item.Pass then
				table.insert(shopItems, item)
			end
		end
		for i, item in shopItems do
			local rarity = Cosmetics.Rarities[item.Rarity]
			local card = make("Frame", { BackgroundColor3 = CARD, LayoutOrder = i }, grid)
			make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
			make("UIStroke", { Color = rarity.Color, Thickness = 1.5 }, card)
			local stripe = make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = rarity.Color,
				BorderSizePixel = 0 }, card)
			make("UICorner", { CornerRadius = UDim.new(0, 10) }, stripe)
			local preview = viewportFrame({ Position = UDim2.new(0, 0, 0, 8), Size = UDim2.new(1, 0, 0, 130) }, card)
			if item.Type == "Weapon" then
				showWeapon(preview, "Rifle", item)
			else
				showAgent(preview, AgentConfig.Get(item.Agent), item.Primary, item.Accent)
			end
			text({ Position = UDim2.new(0, 12, 0, 142), Size = UDim2.new(1, -24, 0, 24), Text = item.Name,
				TextSize = 19 }, card)
			local sub = string.upper(rarity.Name)
			if item.Type == "Agent" then
				sub ..= "  ·  " .. AgentConfig.Get(item.Agent).Name
			end
			text({ Position = UDim2.new(0, 12, 0, 166), Size = UDim2.new(1, -24, 0, 18), Text = sub, TextSize = 13,
				TextColor3 = rarity.Color }, card)
			buyButtons[item.Id] = button({ Position = UDim2.new(0, 12, 1, -50), Size = UDim2.new(1, -24, 0, 38),
				TextSize = 15, Text = "" }, card, function()
				if not Cosmetics.GetOwned(player)[item.Id] then
					Remotes.ShopAction:FireServer("Buy", item.Id)
				end
			end)
		end
		updateButtons()
	end

	tabBar(frame, { "WAFFEN-SKINS", "AGENTEN-SKINS" }, 64, function(name)
		currentType = name == "WAFFEN-SKINS" and "Weapon" or "Agent"
		fill()
	end)("WAFFEN-SKINS")
	panels.Shop.Refresh = updateButtons
end

-- ---------- RUCKSACK ----------

local function buildInventory()
	local frame = makePanel("Inventory", "🎒  RUCKSACK", 980, 620)
	local list = make("ScrollingFrame", { Position = UDim2.new(0, 24, 0, 110), Size = UDim2.new(0, 220, 1, -156),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y }, frame)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local previewBack = make("Frame", { Position = UDim2.new(0, 264, 0, 110), Size = UDim2.new(1, -288, 0, 230),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, previewBack)
	local preview = viewportFrame({ Size = UDim2.new(1, 0, 1, 0) }, previewBack)
	local previewTitle = text({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 28), Text = "",
		TextSize = 22 }, previewBack)
	local options = make("ScrollingFrame", { Position = UDim2.new(0, 264, 0, 354), Size = UDim2.new(1, -288, 1, -400),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y }, frame)
	make("UIGridLayout", { CellSize = UDim2.new(0, 160, 0, 56), CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder }, options)

	local mode = "Weapon"       -- "Weapon" oder "Agent"
	local selected = WEAPON_ORDER[1]

	local function fillOptions()
		for _, child in options:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local owned = Cosmetics.GetOwned(player)
		local equipped = Cosmetics.GetEquipped(player)
		local slot = (mode == "Weapon" and "W:" or "A:") .. selected
		local current = equipped[slot]
		if current and not owned[current] then
			current = nil
		end

		-- Standard + alle gekauften passenden Skins
		local entries = { { Id = nil, Name = "Standard", Color = GRAY } }
		local items = mode == "Weapon" and Cosmetics.List("Weapon") or Cosmetics.List("Agent", selected)
		for _, item in items do
			if owned[item.Id] then
				table.insert(entries, { Id = item.Id, Name = item.Name, Color = Cosmetics.Rarities[item.Rarity].Color })
			end
		end
		for i, entry in entries do
			local isOn = entry.Id == current
			local b = button({ LayoutOrder = i, Text = entry.Name, TextSize = 15, BackgroundColor3 = CARD,
				Font = Enum.Font.GothamBold }, options, function()
				if entry.Id then
					Remotes.ShopAction:FireServer("Equip", entry.Id, selected)
				else
					Remotes.ShopAction:FireServer("Unequip", slot)
				end
			end)
			make("UIStroke", { Color = isOn and ACCENT or entry.Color, Thickness = isOn and 3 or 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		end
		if #entries == 1 then
			panels.Inventory.Status.Text = "Noch keine Skins dafür – schau im SHOP vorbei."
		end

		-- Vorschau mit aktuellem Skin
		if mode == "Weapon" then
			previewTitle.Text = WeaponConfig.Get(selected).DisplayName
			showWeapon(preview, selected, Cosmetics.WeaponSkin(player, nil, selected))
		else
			local agent = AgentConfig.Get(selected)
			previewTitle.Text = agent.Name
			local primary, accent = Cosmetics.AgentColors(player, selected)
			showAgent(preview, agent, primary, accent)
		end
		preview.ZIndex = 1
		previewTitle.ZIndex = 2
	end

	local function fillList()
		for _, child in list:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local names = {}
		if mode == "Weapon" then
			names = WEAPON_ORDER
		else
			for _, agent in AgentConfig.Agents do
				table.insert(names, agent.Id)
			end
		end
		for i, name in names do
			local label = mode == "Weapon" and WeaponConfig.Get(name).DisplayName or AgentConfig.Get(name).Name
			button({ LayoutOrder = i, Size = UDim2.new(1, -6, 0, 44), Text = label, TextSize = 16,
				BackgroundColor3 = name == selected and ACCENT or CARD,
				TextColor3 = name == selected and Color3.fromRGB(20, 20, 20) or Color3.new(1, 1, 1) }, list, function()
				selected = name
				fillList()
				fillOptions()
			end)
		end
	end

	tabBar(frame, { "WAFFEN", "AGENTEN" }, 64, function(name)
		mode = name == "WAFFEN" and "Weapon" or "Agent"
		selected = mode == "Weapon" and WEAPON_ORDER[1] or AgentConfig.Agents[1].Id
		fillList()
		fillOptions()
	end)("WAFFEN")
	panels.Inventory.Refresh = fillOptions
end

-- ---------- AUFTRÄGE ----------

-- Gibt es einen fertigen, noch nicht abgeholten Auftrag?
local function questReady()
	local data = QuestConfig.Read(player)
	if not data or not data.Ids then
		return false
	end
	for _, id in data.Ids do
		local quest = QuestConfig.Get(id)
		if quest and not (data.Claimed or {})[id] and ((data.Progress or {})[id] or 0) >= quest.Goal then
			return true
		end
	end
	return false
end

local function buildQuests()
	local frame = makePanel("Quests", "📋  TÄGLICHE AUFTRÄGE", 640, 420)
	text({ Position = UDim2.new(0, 24, 0, 60), Size = UDim2.new(1, -48, 0, 22),
		Text = "Jeden Tag neue Aufträge – Belohnung in Münzen.", TextSize = 16, TextColor3 = GRAY }, frame)
	local list = make("Frame", { Position = UDim2.new(0, 24, 0, 96), Size = UDim2.new(1, -48, 1, -140),
		BackgroundTransparency = 1 }, frame)
	make("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	panels.Quests.Refresh = function()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local data = QuestConfig.Read(player)
		if not data or not data.Ids then
			return
		end
		for i, id in data.Ids do
			local quest = QuestConfig.Get(id)
			if quest then
				local progress = (data.Progress or {})[id] or 0
				local claimed = (data.Claimed or {})[id] == true
				local done = progress >= quest.Goal
				local row = make("Frame", { Size = UDim2.new(1, 0, 0, 80), BackgroundColor3 = CARD, LayoutOrder = i }, list)
				make("UICorner", { CornerRadius = UDim.new(0, 10) }, row)
				text({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -200, 0, 24), Text = quest.Text,
					TextSize = 19 }, row)
				text({ Position = UDim2.new(0, 16, 0, 36), Size = UDim2.new(1, -200, 0, 18),
					Text = progress .. " / " .. quest.Goal .. "   ·   💰 " .. quest.Reward, TextSize = 14,
					TextColor3 = GRAY }, row)
				local barBack = make("Frame", { Position = UDim2.new(0, 16, 0, 60), Size = UDim2.new(1, -200, 0, 8),
					BackgroundColor3 = BORDER, BorderSizePixel = 0 }, row)
				make("Frame", { Size = UDim2.new(progress / quest.Goal, 0, 1, 0), BorderSizePixel = 0,
					BackgroundColor3 = done and GREEN or ACCENT }, barBack)
				button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.new(0, 150, 0, 44),
					TextSize = 16, Text = claimed and "ABGEHOLT ✓" or (done and "ABHOLEN" or "OFFEN"),
					BackgroundColor3 = (done and not claimed) and GREEN or Color3.fromRGB(55, 60, 75) }, row, function()
					if done and not claimed then
						Remotes.ShopAction:FireServer("ClaimQuest", id)
					end
				end)
			end
		end
	end
end

local function decodeAttribute(target, name)
	local raw = target:GetAttribute(name)
	if type(raw) ~= "string" then
		return {}
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(data) == "table" and data or {}
end

-- ---------- SQUAD ----------

local function buildSquad()
	local frame = makePanel("Squad", "👥  SQUAD", 760, 560)
	text({ Position = UDim2.new(0, 24, 0, 64), Size = UDim2.new(0.5, -30, 0, 20), Text = "DEIN SQUAD (max. 4)", TextSize = 14,
		TextColor3 = ACCENT }, frame)
	text({ Position = UDim2.new(0.5, 6, 0, 64), Size = UDim2.new(0.5, -30, 0, 20), Text = "SPIELER IM SERVER", TextSize = 14,
		TextColor3 = ACCENT }, frame)
	local function column(x)
		local list = make("ScrollingFrame", { Position = UDim2.new(x, x == 0 and 24 or 6, 0, 92), Size = UDim2.new(0.5, -30, 1, -180),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y }, frame)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		return list
	end
	local mine, others = column(0), column(0.5)
	button({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -48), Size = UDim2.new(0, 220, 0, 44),
		Text = "SQUAD VERLASSEN", TextSize = 16, BackgroundColor3 = Color3.fromRGB(140, 45, 50) }, frame, function()
		Remotes.PartyAction:FireServer("Leave")
	end)

	local function row(parent, order, name, buttonText, buttonColor, onClick)
		local entry = make("Frame", { Size = UDim2.new(1, -6, 0, 48), BackgroundColor3 = CARD, LayoutOrder = order }, parent)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, entry)
		text({ Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -150, 1, 0), Text = name, TextSize = 16 }, entry)
		if buttonText then
			button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 120, 0, 34),
				Text = buttonText, TextSize = 14, BackgroundColor3 = buttonColor }, entry, onClick)
		end
	end

	panels.Squad.Refresh = function()
		for _, list in { mine, others } do
			for _, child in list:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
		end
		local party = decodeAttribute(player, "Party")
		local inParty = {}
		local iAmLeader = party.Leader == nil or party.Leader == player.UserId
		if party.Members then
			for i, member in party.Members do
				inParty[member.UserId] = true
				local isLeader = member.UserId == party.Leader
				local kick = iAmLeader and member.UserId ~= player.UserId
				row(mine, i, (isLeader and "👑  " or "") .. member.Name, kick and "ENTFERNEN" or nil, Color3.fromRGB(140, 45, 50),
					function()
						Remotes.PartyAction:FireServer("Kick", member.UserId)
					end)
			end
		else
			row(mine, 1, "Du spielst allein – lade jemanden ein!")
		end
		local order = 0
		for _, other in Players:GetPlayers() do
			if other ~= player and not inParty[other.UserId] then
				order += 1
				row(others, order, other.Name, iAmLeader and "EINLADEN" or nil, GREEN, function()
					Remotes.PartyAction:FireServer("Invite", other.UserId)
				end)
			end
		end
		if order == 0 then
			row(others, 1, "Keine anderen Spieler im Server.")
		end
	end
	Players.PlayerAdded:Connect(function()
		if openPanel == "Squad" then
			panels.Squad.Refresh()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if openPanel == "Squad" then
				panels.Squad.Refresh()
			end
		end)
	end)

	-- Einladung (erscheint überall, auch außerhalb des Hubs)
	local inviteGui = make("ScreenGui", { Name = "PartyInvite", ResetOnSpawn = false, DisplayOrder = 30 }, player.PlayerGui)
	local popup = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -140), Size = UDim2.new(0, 360, 0, 120),
		BackgroundColor3 = PANEL, Visible = false }, inviteGui)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, popup)
	make("UIStroke", { Color = ACCENT, Thickness = 2 }, popup)
	local inviteText = text({ Position = UDim2.new(0, 16, 0, 12), Size = UDim2.new(1, -32, 0, 44), Text = "", TextSize = 16,
		TextWrapped = true }, popup)
	local inviter = nil
	local inviteId = 0
	button({ Position = UDim2.new(0, 16, 1, -52), Size = UDim2.new(0.5, -22, 0, 40), Text = "ANNEHMEN", TextSize = 15,
		BackgroundColor3 = GREEN }, popup, function()
		Remotes.PartyAction:FireServer("Accept", inviter)
		popup.Visible = false
	end)
	button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -52), Size = UDim2.new(0.5, -22, 0, 40), Text = "ABLEHNEN",
		TextSize = 15, BackgroundColor3 = CARD }, popup, function()
		Remotes.PartyAction:FireServer("Decline", inviter)
		popup.Visible = false
	end)
	Remotes.PartyInvite.OnClientEvent:Connect(function(name, userId)
		inviteId += 1
		local myId = inviteId
		inviter = userId
		inviteText.Text = "👥  " .. name .. " lädt dich in seinen Squad ein."
		popup.Visible = true
		task.delay(20, function()
			if inviteId == myId then
				popup.Visible = false
			end
		end)
	end)
end

-- ---------- STATS + RANKED ----------


local function ratio(a, b)
	return b > 0 and a / b or a
end

local function percent(a, b)
	return b > 0 and string.format("%d %%", math.floor(a / b * 100 + 0.5)) or "–"
end

local function buildStats()
	local frame = makePanel("Stats", "📊  STATISTIK", 1040, 600)
	-- Linke Seite: Kacheln
	local grid = make("Frame", { Position = UDim2.new(0, 24, 0, 70), Size = UDim2.new(0, 620, 1, -110),
		BackgroundTransparency = 1 }, frame)
	make("UIGridLayout", { CellSize = UDim2.new(0, 145, 0, 84), CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local tiles = {}
	local order = { "KD", "Kills", "Deaths", "Assists", "WinRate", "Matches", "Wins", "Losses", "HSRate", "Accuracy",
		"AvgDamage", "Revives", "Plants", "Defuses", "RoundsWon", "Favorite" }
	local titles = { KD = "K/D", Kills = "KILLS", Deaths = "TODE", Assists = "ASSISTS", WinRate = "SIEGQUOTE",
		Matches = "MATCHES", Wins = "SIEGE", Losses = "NIEDERLAGEN", HSRate = "KOPFSCHUSS-QUOTE", Accuracy = "TREFFERQUOTE",
		AvgDamage = "Ø SCHADEN/MATCH", Revives = "WIEDERBELEBT", Plants = "BOMBEN GELEGT", Defuses = "ENTSCHÄRFT",
		RoundsWon = "RUNDEN GEWONNEN", Favorite = "LIEBLINGS-AGENT" }
	for i, key in order do
		local tile = make("Frame", { BackgroundColor3 = CARD, LayoutOrder = i }, grid)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, tile)
		make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = (key == "KD" or key == "WinRate") and ACCENT or BORDER,
			BorderSizePixel = 0 }, tile)
		text({ Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -20, 0, 16), Text = titles[key], TextSize = 11,
			TextColor3 = GRAY }, tile)
		tiles[key] = text({ Position = UDim2.new(0, 14, 0, 30), Size = UDim2.new(1, -20, 0, 40), Text = "–", TextSize = 30,
			Font = UITheme.Fonts.Title, TextScaled = false }, tile)
	end

	-- Rechte Seite: Ranked
	local rankedBox = make("Frame", { Position = UDim2.new(0, 668, 0, 70), Size = UDim2.new(1, -692, 0, 230),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 4) }, rankedBox)
	text({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 18), Text = "RANKED", TextSize = 13,
		TextColor3 = ACCENT }, rankedBox)
	local rankName = text({ Position = UDim2.new(0, 16, 0, 32), Size = UDim2.new(1, -32, 0, 50), Text = "", TextSize = 42,
		Font = UITheme.Fonts.Title }, rankedBox)
	local eloText = text({ Position = UDim2.new(0, 16, 0, 84), Size = UDim2.new(1, -32, 0, 24), Text = "", TextSize = 18 }, rankedBox)
	local barBack = make("Frame", { Position = UDim2.new(0, 16, 0, 116), Size = UDim2.new(1, -32, 0, 8),
		BackgroundColor3 = BORDER, BorderSizePixel = 0 }, rankedBox)
	local bar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, barBack)
	local rankedInfo = text({ Position = UDim2.new(0, 16, 0, 136), Size = UDim2.new(1, -32, 0, 84), Text = "", TextSize = 15,
		Font = UITheme.Fonts.Body, TextColor3 = GRAY, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, rankedBox)

	-- Bestenliste
	local board = make("Frame", { Position = UDim2.new(0, 668, 0, 312), Size = UDim2.new(1, -692, 1, -352),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 4) }, board)
	text({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 18), Text = "TOP 10 · ELO", TextSize = 13,
		TextColor3 = ACCENT }, board)
	local boardText = text({ Position = UDim2.new(0, 16, 0, 34), Size = UDim2.new(1, -32, 1, -44), Text = "", TextSize = 15,
		Font = UITheme.Fonts.Body, TextYAlignment = Enum.TextYAlignment.Top, RichText = true }, board)

	panels.Stats.Refresh = function()
		local stats = decodeAttribute(player, "Stats")
		local function get(key)
			return stats[key] or 0
		end
		tiles.KD.Text = string.format("%.2f", ratio(get("Kills"), get("Deaths")))
		tiles.Kills.Text = tostring(get("Kills"))
		tiles.Deaths.Text = tostring(get("Deaths"))
		tiles.Assists.Text = tostring(get("Assists"))
		tiles.WinRate.Text = percent(get("Wins"), get("Matches"))
		tiles.Matches.Text = tostring(get("Matches"))
		tiles.Wins.Text = tostring(get("Wins"))
		tiles.Losses.Text = tostring(get("Losses"))
		tiles.HSRate.Text = percent(get("Headshots"), get("Kills"))
		tiles.Accuracy.Text = percent(get("ShotsHit"), get("ShotsFired"))
		tiles.AvgDamage.Text = tostring(math.floor(ratio(get("Damage"), math.max(1, get("Matches")))))
		tiles.Revives.Text = tostring(get("Revives"))
		tiles.Plants.Text = tostring(get("Plants"))
		tiles.Defuses.Text = tostring(get("Defuses"))
		tiles.RoundsWon.Text = tostring(get("RoundsWon"))
		local favorite, most = nil, 0
		for _, agent in AgentConfig.Agents do
			if get("Kills_" .. agent.Id) > most then
				favorite, most = agent, get("Kills_" .. agent.Id)
			end
		end
		tiles.Favorite.Text = favorite and favorite.Name or "–"
		tiles.Favorite.TextColor3 = favorite and favorite.Color or Color3.new(1, 1, 1)

		local ranked = decodeAttribute(player, "RankedData")
		local elo = player:GetAttribute("Elo") or RankConfig.StartElo
		local rank = RankConfig.Get(elo)
		local matches = ranked.Matches or 0
		if matches < RankConfig.PlacementMatches then
			rankName.Text = "PLATZIERUNG"
			rankName.TextColor3 = GRAY
			rankedInfo.Text = "Noch " .. (RankConfig.PlacementMatches - matches) .. " Platzierungsspiele bis zu deinem Rang."
		else
			rankName.Text = rank.Display
			rankName.TextColor3 = rank.Color
			rankedInfo.Text = "Peak: " .. (ranked.Peak or elo) .. " ELO  ·  " .. RankConfig.Get(ranked.Peak or elo).Display
		end
		eloText.Text = elo .. " ELO"
		bar.Size = UDim2.new(rank.Progress, 0, 1, 0)
		bar.BackgroundColor3 = rank.Color
		rankedInfo.Text ..= "\nRanked: " .. (ranked.Wins or 0) .. " Siege · " .. (ranked.Losses or 0) .. " Niederlagen ("
			.. percent(ranked.Wins or 0, matches) .. ")"

		local lines = {}
		for i, entry in decodeAttribute(game:GetService("ReplicatedStorage"), "RankedLeaderboard") do
			local tier = RankConfig.Get(entry.Elo)
			local color = string.format("#%02X%02X%02X", tier.Color.R * 255, tier.Color.G * 255, tier.Color.B * 255)
			table.insert(lines, i .. ".  " .. tostring(entry.Name) .. '   <font color="' .. color .. '">' .. entry.Elo .. "</font>")
		end
		boardText.Text = #lines > 0 and table.concat(lines, "\n")
			or "Noch keine Einträge.\n(Die Bestenliste funktioniert im veröffentlichten Spiel.)"
	end
end

-- ---------- BATTLE PASS ----------

local function buildPass()
	local frame = makePanel("Pass", "🎫  BATTLE PASS", 980, 470)
	local season = text({ Position = UDim2.new(0, 24, 0, 60), Size = UDim2.new(1, -48, 0, 24),
		Text = PassConfig.SeasonName, TextSize = 18, TextColor3 = GRAY }, frame)
	local tierLabel = text({ Position = UDim2.new(0, 24, 0, 90), Size = UDim2.new(0, 400, 0, 34), Text = "",
		TextSize = 28, Font = Enum.Font.GothamBlack }, frame)
	local barBack = make("Frame", { Position = UDim2.new(0, 24, 0, 130), Size = UDim2.new(1, -48, 0, 12),
		BackgroundColor3 = BORDER, BorderSizePixel = 0 }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, barBack)
	local bar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, barBack)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, bar)
	local xpLabel = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 98), Size = UDim2.new(0, 300, 0, 24),
		Text = "", TextSize = 16, TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Right }, frame)

	-- Stufen nebeneinander (waagerecht scrollbar)
	local strip = make("ScrollingFrame", { Position = UDim2.new(0, 24, 0, 160), Size = UDim2.new(1, -48, 0, 250),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.new(0, #PassConfig.Tiers * 134, 0, 0) }, frame)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder }, strip)
	local cards = {}
	for tier, reward in PassConfig.Tiers do
		local item = reward.Item and Cosmetics.Get(reward.Item)
		local rarity = item and Cosmetics.Rarities[item.Rarity]
		local card = make("Frame", { Size = UDim2.new(0, 124, 0, 230), BackgroundColor3 = CARD, LayoutOrder = tier }, strip)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		local stroke = make("UIStroke", { Color = rarity and rarity.Color or BORDER, Thickness = item and 2 or 1 }, card)
		text({ Size = UDim2.new(1, 0, 0, 30), Text = "STUFE " .. tier, TextSize = 14, TextColor3 = GRAY,
			TextXAlignment = Enum.TextXAlignment.Center }, card)
		if item then
			local preview = viewportFrame({ Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 120) }, card)
			if item.Type == "Weapon" then
				showWeapon(preview, "Rifle", item)
			else
				showAgent(preview, AgentConfig.Get(item.Agent), item.Primary, item.Accent)
			end
			text({ Position = UDim2.new(0, 6, 0, 152), Size = UDim2.new(1, -12, 0, 40), Text = item.Name, TextSize = 15,
				TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center }, card)
		else
			text({ Position = UDim2.new(0, 0, 0, 60), Size = UDim2.new(1, 0, 0, 60), Text = "💰", TextSize = 40,
				TextXAlignment = Enum.TextXAlignment.Center }, card)
			text({ Position = UDim2.new(0, 0, 0, 130), Size = UDim2.new(1, 0, 0, 30), Text = reward.Coins .. " Münzen",
				TextSize = 16, TextColor3 = Color3.fromRGB(255, 210, 80), TextXAlignment = Enum.TextXAlignment.Center }, card)
		end
		local state = text({ Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 26), Text = "",
			TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center }, card)
		cards[tier] = { Stroke = stroke, State = state, Card = card }
	end

	panels.Pass.Refresh = function()
		local xp = player:GetAttribute("PassXP") or 0
		local tier, progress = PassConfig.TierFromXP(xp)
		tierLabel.Text = "STUFE " .. tier .. " / " .. #PassConfig.Tiers
		bar.Size = UDim2.new(progress, 0, 1, 0)
		xpLabel.Text = tier >= #PassConfig.Tiers and "Pass abgeschlossen!"
			or (math.floor(progress * PassConfig.XPPerTier) .. " / " .. PassConfig.XPPerTier .. " XP bis Stufe " .. tier + 1)
		for t, entry in cards do
			local reached = t <= tier
			entry.State.Text = reached and "FREIGESCHALTET ✓" or "GESPERRT"
			entry.State.TextColor3 = reached and GREEN or GRAY
			entry.Card.BackgroundColor3 = reached and Color3.fromRGB(28, 40, 34) or CARD
		end
	end
	season.Text = PassConfig.SeasonName .. "   ·   Pass-XP gibt es für alle XP und für Aufträge"
end

-- ---------- TÄGLICH ----------

local function dailyLeft()
	return (player:GetAttribute("LastDaily") or 0) + Cosmetics.DailyCooldown - os.time()
end

local function buildDaily()
	local frame = makePanel("Daily", "🎁  TÄGLICHE BELOHNUNG", 560, 330)
	text({ Position = UDim2.new(0, 24, 0, 80), Size = UDim2.new(1, -48, 0, 60),
		Text = "💰 " .. Cosmetics.DailyReward .. " Münzen", TextSize = 44, Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 210, 80), TextXAlignment = Enum.TextXAlignment.Center }, frame)
	text({ Position = UDim2.new(0, 24, 0, 144), Size = UDim2.new(1, -48, 0, 24),
		Text = "Jeden Tag kostenlos abholen!", TextSize = 17, TextColor3 = GRAY,
		TextXAlignment = Enum.TextXAlignment.Center }, frame)
	local claim = button({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 196),
		Size = UDim2.new(0, 300, 0, 56), TextSize = 22, Text = "" }, frame, function()
		Remotes.ShopAction:FireServer("ClaimDaily")
	end)
	panels.Daily.Refresh = function()
		local left = dailyLeft()
		if left <= 0 then
			claim.Text = "ABHOLEN"
			claim.BackgroundColor3 = GREEN
		else
			claim.Text = string.format("IN %d h %02d min", left // 3600, (left % 3600) // 60)
			claim.BackgroundColor3 = Color3.fromRGB(55, 60, 75)
		end
	end
end

-- ---------- CODES ----------

local function buildCodes()
	local frame = makePanel("Codes", "🎟  CODES", 560, 300)
	text({ Position = UDim2.new(0, 24, 0, 70), Size = UDim2.new(1, -48, 0, 24),
		Text = "Code eingeben und Belohnung abholen:", TextSize = 17, TextColor3 = GRAY }, frame)
	local box = make("TextBox", { Position = UDim2.new(0, 24, 0, 104), Size = UDim2.new(1, -48, 0, 50),
		BackgroundColor3 = CARD, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1), PlaceholderText = "CODE", PlaceholderColor3 = GRAY, Text = "",
		ClearTextOnFocus = false }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
	button({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.new(0, 260, 0, 52),
		TextSize = 20, Text = "EINLÖSEN", BackgroundColor3 = GREEN }, frame, function()
		Remotes.ShopAction:FireServer("RedeemCode", box.Text)
	end)
end

-- ---------- EINSTELLUNGEN ----------

-- Einstellungen im Profil speichern (kurz verzögert, damit nicht jeder Klick gesendet wird)
local saveToken = 0
local function saveSettings()
	saveToken += 1
	local myToken = saveToken
	task.delay(1, function()
		if myToken == saveToken then
			Remotes.ShopAction:FireServer("SaveSettings", {
				Fov = Movement.GetFov(),
				Sensitivity = Movement.GetSensitivity(),
				ThirdPerson = Movement.GetThirdPersonSetting(),
			})
		end
	end)
end

-- Gespeicherte Einstellungen einmal beim Laden übernehmen
local function loadSettings()
	local raw = player:GetAttribute("ClientSettings")
	if type(raw) ~= "string" then
		return false
	end
	local ok, data = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), raw)
	if not ok or type(data) ~= "table" or next(data) == nil then
		return false
	end
	Movement.SetFov(data.Fov or 70)
	Movement.SetSensitivity(data.Sensitivity or 1)
	Movement.SetThirdPerson(data.ThirdPerson == true)
	return true
end

local function buildSettings()
	local frame = makePanel("Settings", "⚙  EINSTELLUNGEN", 560, 380)
	local refreshers = {}
	local function settingRow(y, label, getValue, change)
		text({ Position = UDim2.new(0, 24, 0, y), Size = UDim2.new(0, 260, 0, 44), Text = label, TextSize = 18 }, frame)
		local value = text({ Position = UDim2.new(0, 360, 0, y), Size = UDim2.new(0, 80, 0, 44), Text = "",
			TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center }, frame)
		local function refresh()
			value.Text = tostring(getValue())
		end
		table.insert(refreshers, refresh)
		button({ Position = UDim2.new(0, 304, 0, y), Size = UDim2.new(0, 48, 0, 44), Text = "−", TextSize = 22,
			BackgroundColor3 = CARD }, frame, function()
			change(-1)
			refresh()
			saveSettings()
		end)
		button({ Position = UDim2.new(0, 448, 0, y), Size = UDim2.new(0, 48, 0, 44), Text = "+", TextSize = 22,
			BackgroundColor3 = CARD }, frame, function()
			change(1)
			refresh()
			saveSettings()
		end)
		refresh()
	end
	settingRow(90, "Sichtfeld (FOV)", function()
		return Movement.GetFov()
	end, function(direction)
		Movement.SetFov(math.clamp(Movement.GetFov() + direction * 5, 60, 100))
	end)
	settingRow(150, "Maus-Empfindlichkeit", function()
		return string.format("%.1f", Movement.GetSensitivity())
	end, function(direction)
		Movement.SetSensitivity(math.clamp(Movement.GetSensitivity() + direction * 0.1, 0.1, 3))
	end)
	settingRow(210, "Kamera (Kampf)", function()
		return Movement.GetThirdPersonSetting() and "Schulter" or "Ego"
	end, function()
		Movement.SetThirdPerson(not Movement.GetThirdPersonSetting())
	end)
	panels.Settings.Refresh = function()
		for _, refresh in refreshers do
			refresh()
		end
	end
end

-- ---------- Knopfleiste ----------

local function sideButton(icon, label, order, onClick)
	local b = make("TextButton", { Size = UDim2.new(0, 96, 0, 62), BackgroundColor3 = Color3.fromRGB(22, 26, 40),
		BackgroundTransparency = 0.08, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = order }, column)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, b)
	local stroke = make("UIStroke", { Color = BORDER, Thickness = 1.5 }, b)
	UITheme.Gradient(b, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 175, 195))
	local scale = make("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.07 }):Play()
		stroke.Color = ACCENT
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		stroke.Color = BORDER
	end)
	text({ Position = UDim2.new(0, 0, 0, 3), Size = UDim2.new(1, 0, 0, 34), Text = icon, TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center }, b)
	text({ Position = UDim2.new(0, 0, 0, 37), Size = UDim2.new(1, 0, 0, 20), Text = label, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center }, b)
	b.Activated:Connect(onClick)
	return b
end

local function togglePanel(name)
	setPanel(openPanel ~= name and name or nil)
end

local function buildColumn()
	local entries = {
		{ "🛒", "SHOP", function() togglePanel("Shop") end },
		{ "🎒", "RUCKSACK", function() togglePanel("Inventory") end },
		{ "🦸", "AGENTEN", function()
			setPanel(nil)
			GameMenu.Open("Agents")
		end },
		{ "👥", "SQUAD", function() togglePanel("Squad") end },
		{ "📊", "STATS", function() togglePanel("Stats") end },
		{ "🎫", "PASS", function() togglePanel("Pass") end },
		{ "📋", "AUFTRÄGE", function() togglePanel("Quests") end },
		{ "🎁", "TÄGLICH", function() togglePanel("Daily") end },
		{ "🎟", "CODES", function() togglePanel("Codes") end },
		{ "⚙", "OPTIONEN", function() togglePanel("Settings") end },
	}
	local height = #entries * 62 + (#entries - 1) * 6
	column = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 24),
		Size = UDim2.new(0, 96, 0, height), BackgroundTransparency = 1 }, gui)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, column)
	-- Auf kleinen Bildschirmen die ganze Leiste verkleinern
	local columnScale = make("UIScale", {}, column)
	local function updateColumnScale()
		columnScale.Scale = math.clamp((workspace.CurrentCamera.ViewportSize.Y - 140) / height, 0.55, 1)
	end
	updateColumnScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateColumnScale)
	local daily, quests
	for i, entry in entries do
		local b = sideButton(entry[1], entry[2], i, entry[3])
		if entry[2] == "TÄGLICH" then
			daily = b
		elseif entry[2] == "AUFTRÄGE" then
			quests = b
		end
	end
	-- Roter Punkt, wenn ein Auftrag abgeholt werden kann
	questDot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 16, 0, 16), BackgroundColor3 = Color3.fromRGB(230, 50, 50), BorderSizePixel = 0 }, quests)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, questDot)
	-- Roter Punkt, wenn die tägliche Belohnung bereit ist
	dailyDot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 16, 0, 16), BackgroundColor3 = Color3.fromRGB(230, 50, 50), BorderSizePixel = 0 }, daily)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, dailyDot)

	-- Münzstand über der Leiste
	local pill = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 0, -10),
		Size = UDim2.new(0, 150, 0, 40), BackgroundColor3 = Color3.fromRGB(20, 24, 34) }, column)
	make("UICorner", { CornerRadius = UDim.new(0, 20) }, pill)
	make("UIStroke", { Color = Color3.fromRGB(255, 210, 80), Thickness = 1.5 }, pill)
	coinLabel = text({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 20, TextColor3 = Color3.fromRGB(255, 210, 80),
		TextXAlignment = Enum.TextXAlignment.Center }, pill)
	-- UIListLayout würde die Münzanzeige einreihen: darum außerhalb der Liste platzieren
	pill.Parent = gui
	pill.AnchorPoint = Vector2.new(0, 1)
	pill.Position = UDim2.new(0, 16, 0.5, 24 - height / 2 - 10)
	column:GetPropertyChangedSignal("Visible"):Connect(function()
		pill.Visible = column.Visible
	end)
end

-- ---------- Start ----------

function SideMenu.Init()
	gui = make("ScreenGui", { Name = "SideMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	buildColumn()
	buildShop()
	buildInventory()
	buildSquad()
	buildStats()
	buildPass()
	buildQuests()
	buildDaily()
	buildCodes()
	buildSettings()

	-- Gespeicherte Einstellungen übernehmen, sobald das Profil geladen ist
	if not loadSettings() then
		local connection
		connection = player:GetAttributeChangedSignal("ClientSettings"):Connect(function()
			if loadSettings() then
				connection:Disconnect()
			end
		end)
	end

	-- Rückmeldung vom Server in das offene Fenster
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		for _, panel in panels do
			panel.Status.Text = message
			panel.Status.TextColor3 = success and Color3.fromRGB(120, 230, 140) or Color3.fromRGB(255, 120, 120)
		end
	end)
	-- Münzen, Besitz, Ausrüstung geändert: offenes Fenster aktualisieren
	player.AttributeChanged:Connect(function(name)
		if name == "Coins" or name == "Owned" or name == "Equipped" or name == "LastDaily" or name == "Quests"
			or name == "PassXP" or name == "Stats" or name == "Elo" or name == "RankedData" or name == "Party" then
			coinLabel.Text = "💰 " .. formatNumber(coins())
			if openPanel and panels[openPanel].Refresh then
				panels[openPanel].Refresh()
			end
		end
	end)
	coinLabel.Text = "💰 " .. formatNumber(coins())

	-- Nur im Hub sichtbar und nur, wenn das Hauptmenü zu ist
	task.spawn(function()
		while true do
			local visible = player:GetAttribute("Mode") == "Hub" and not GameMenu.IsOpen()
			column.Visible = visible
			if not visible and openPanel then
				setPanel(nil)
			end
			dailyDot.Visible = dailyLeft() <= 0
			questDot.Visible = questReady()
			if openPanel == "Daily" then
				panels.Daily.Refresh()
			end
			task.wait(0.25)
		end
	end)
end

return SideMenu
