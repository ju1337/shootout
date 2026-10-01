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
local QuestConfig = require(Shared.QuestConfig)
local PassConfig = require(Shared.PassConfig)

local player = Players.LocalPlayer

local SideMenu = {}

local ACCENT = Color3.fromRGB(255, 140, 40)
local PANEL = Color3.fromRGB(14, 17, 25)
local CARD = Color3.fromRGB(24, 28, 38)
local BORDER = Color3.fromRGB(50, 55, 70)
local GRAY = Color3.fromRGB(170, 175, 190)
local GREEN = Color3.fromRGB(70, 170, 90)

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
	if name and panels[name].Refresh then
		panels[name].Refresh()
	end
end

local function makePanel(name, title, width, height)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 40, 0.5, 0),
		Size = UDim2.new(0, width, 0, height), BackgroundColor3 = PANEL, Visible = false, Active = true }, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, frame)
	make("UIStroke", { Color = ACCENT, Thickness = 2 }, frame)
	local scale = make("UIScale", {}, frame)
	local function updateScale()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min((viewport.X - 160) / (width + 40), (viewport.Y - 40) / (height + 40)), 0.4, 1.2)
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

local function buildSettings()
	local frame = makePanel("Settings", "⚙  EINSTELLUNGEN", 560, 320)
	local function settingRow(y, label, getValue, change)
		text({ Position = UDim2.new(0, 24, 0, y), Size = UDim2.new(0, 260, 0, 44), Text = label, TextSize = 18 }, frame)
		local value = text({ Position = UDim2.new(0, 360, 0, y), Size = UDim2.new(0, 80, 0, 44), Text = "",
			TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center }, frame)
		local function refresh()
			value.Text = tostring(getValue())
		end
		button({ Position = UDim2.new(0, 304, 0, y), Size = UDim2.new(0, 48, 0, 44), Text = "−", TextSize = 22,
			BackgroundColor3 = CARD }, frame, function()
			change(-1)
			refresh()
		end)
		button({ Position = UDim2.new(0, 448, 0, y), Size = UDim2.new(0, 48, 0, 44), Text = "+", TextSize = 22,
			BackgroundColor3 = CARD }, frame, function()
			change(1)
			refresh()
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
end

-- ---------- Knopfleiste ----------

local function sideButton(icon, label, order, onClick)
	local b = make("TextButton", { Size = UDim2.new(0, 96, 0, 70), BackgroundColor3 = Color3.fromRGB(20, 24, 34),
		BackgroundTransparency = 0.1, BorderSizePixel = 0, Text = "", AutoButtonColor = true, LayoutOrder = order }, column)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
	make("UIStroke", { Color = ACCENT, Thickness = 1.5, Transparency = 0.3 }, b)
	text({ Position = UDim2.new(0, 0, 0, 4), Size = UDim2.new(1, 0, 0, 38), Text = icon, TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center }, b)
	text({ Position = UDim2.new(0, 0, 0, 42), Size = UDim2.new(1, 0, 0, 22), Text = label, TextSize = 12,
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
		{ "🎫", "PASS", function() togglePanel("Pass") end },
		{ "📋", "AUFTRÄGE", function() togglePanel("Quests") end },
		{ "🎁", "TÄGLICH", function() togglePanel("Daily") end },
		{ "🎟", "CODES", function() togglePanel("Codes") end },
		{ "⚙", "OPTIONEN", function() togglePanel("Settings") end },
	}
	local height = #entries * 70 + (#entries - 1) * 8
	column = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 24),
		Size = UDim2.new(0, 96, 0, height), BackgroundTransparency = 1 }, gui)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, column)
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
	buildPass()
	buildQuests()
	buildDaily()
	buildCodes()
	buildSettings()

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
			or name == "PassXP" then
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
