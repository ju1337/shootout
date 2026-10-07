-- CrateClient (ModuleScript, nur Client)
-- Kisten öffnen (Server: CrateService, Chancen und Preise: CrateConfig). In der Marktmitte stehen zwei Automaten, eine
-- Waffen-Kiste und eine Agenten-Kiste; E öffnet das Fenster:
--   * oben die Rolle (Skins ziehen vorbei und bleiben unter der Markierung stehen), darunter die Chancen je Seltenheit
--     und alle Skins, die in der Kiste stecken (mit RAP-Wert, falls handelbar),
--   * ÖFFNEN zieht Münzen ab (der Server würfelt, die Rolle zeigt nur das Ergebnis),
--   * danach eine Gewinn-Karte: neu, weiteres Stück (handelbar) oder Duplikat mit Münzen zurück.
-- Esc oder X schließt; der Gewinn ist dann schon im Inventar und kommt als Meldung.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local Cosmetics = require(Shared.Cosmetics)
local CrateConfig = require(Shared.CrateConfig)
local RapConfig = require(Shared.RapConfig)
local AgentConfig = require(Shared.AgentConfig)
local ItemPreview = require(Shared.ItemPreview)
local Notifications = require(Shared.Notifications)
local InputActions = require(Shared.InputActions)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper
local format = UITheme.FormatNumber

local CrateClient = {}

local WIN_W, WIN_H = 960, 660
local TILE_W, TILE_H, TILE_GAP = 124, 132, 8
local VIEW_W, VIEW_H = 880, 150
local SPIN_TIME = 6

local gui, root
local window = nil -- { Crate, Frame, Strip, Open (Knopf), Status, Coins, Spinning, Connection, Tween, Generation }

local function sound(id, speed, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 2)
end

local function coins()
	return tonumber(player:GetAttribute("Coins")) or 0
end

-- Gewinn als Karte melden (Fenster war schon zu, bevor die Rolle fertig war)
local function announce(result)
	local item = Cosmetics.Get(result.Item)
	if not item then
		return
	end
	local line = result.Status == "new" and "Neuer Skin" or (result.Status == "copy" and "Weiteres Stück" or ("Duplikat: +" .. format(result.Refund or 0) .. " Münzen"))
	Notifications.Reward({ Title = "KISTE GEÖFFNET", Lines = { item.Name, line }, Rarity = item.Rarity })
end

local function closeWindow()
	if window then
		if window.Result and not window.ResultShown then
			announce(window.Result)
		end
		window.Generation += 1
		if window.Tween then
			window.Tween:Cancel()
		end
		if window.Connection then
			window.Connection:Disconnect()
		end
		InputActions.Unfocus(window.Frame)
		window.Frame:Destroy()
		window = nil
		UITheme.SetBlur("Crate", false)
	end
end

-- Skin-Kachel für die Rolle: Farbfläche (Agenten zweifarbig), Name, Seltenheit
local function tile(parent, itemId, index)
	local item = Cosmetics.Get(itemId)
	local rarity = item and Cosmetics.Rarities[item.Rarity]
	local color = rarity and rarity.Color or C.Border
	local frame = make("Frame", { Name = "Tile" .. index, Position = UDim2.fromOffset((index - 1) * (TILE_W + TILE_GAP), 9),
		Size = UDim2.fromOffset(TILE_W, TILE_H), BackgroundColor3 = C.Card, BorderSizePixel = 0, ZIndex = 6 }, parent)
	UITheme.Corner(frame, UITheme.Radius.Large)
	UITheme.Stroke(frame, color, 1, 0.5)
	if item then
		local primary = item.Type == "Agent" and (item.Primary or color) or (item.Color or color)
		local accent = item.Type == "Agent" and (item.Accent or primary) or primary
		local left = make("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(0.5, -8, 0, 60), BackgroundColor3 = primary,
			BorderSizePixel = 0, ZIndex = 6 }, frame)
		UITheme.Corner(left, UITheme.Radius.Small)
		local right = make("Frame", { Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(0.5, -8, 0, 60), BackgroundColor3 = accent,
			BorderSizePixel = 0, ZIndex = 6 }, frame)
		UITheme.Corner(right, UITheme.Radius.Small)
		label({ Position = UDim2.fromOffset(6, 72), Size = UDim2.new(1, -12, 0, 28), Text = upper(item.Name), TextSize = 14, Font = F.Display,
			TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, frame)
		local kind = item.Type == "Agent" and upper((AgentConfig.Get(item.Agent) or { Name = "" }).Name) or "WAFFE"
		label({ Position = UDim2.fromOffset(6, 100), Size = UDim2.new(1, -12, 0, 14), Text = kind, TextSize = 10, Font = F.Bold,
			TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, frame)
	end
	make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = color,
		BorderSizePixel = 0, ZIndex = 7 }, frame)
	return frame
end

local function setOpenButton()
	if not window then
		return
	end
	local crate = window.Crate
	local button = window.Open
	if window.Spinning then
		button.SetText("ÖFFNET …")
		button.SetColor(C.MutedBack, C.Muted)
	elseif coins() < crate.Price then
		button.SetText("ZU WENIG MÜNZEN  ·  " .. format(crate.Price))
		button.SetColor(C.MutedBack, C.Bad)
	else
		button.SetText("ÖFFNEN  ·  " .. format(crate.Price) .. " MÜNZEN")
		button.SetColor(crate.Color, C.PrimaryText)
	end
	window.CoinsLabel.Text = "MÜNZEN  " .. format(coins())
end

-- Rolle mit Skins füllen (Gewinn an fester Stelle, sonst Platzhalter aus dem Pool)
local function fillStrip(ids)
	for _, child in window.Strip:GetChildren() do
		child:Destroy()
	end
	window.Strip.Size = UDim2.fromOffset(#ids * (TILE_W + TILE_GAP), VIEW_H)
	window.Tiles = {}
	for index, id in ids do
		window.Tiles[index] = tile(window.Strip, id, index)
	end
end

local function idleIds(crate)
	local pool = CrateConfig.Pool(crate)
	local ids = {}
	for index = 1, 12 do
		ids[index] = pool[(index - 1) % #pool + 1].Id
	end
	return ids
end

-- Gewinn-Karte nach der Rolle
local function showResult(result)
	if not window then
		return
	end
	local item = Cosmetics.Get(result.Item)
	if not item then
		return
	end
	window.ResultShown = true
	local rarity = Cosmetics.Rarities[item.Rarity]
	local color = rarity and rarity.Color or C.Border
	local overlay = make("Frame", { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background, BackgroundTransparency = 0.25,
		ZIndex = 9 }, window.Frame)
	local card = UITheme.Card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 420),
		ZIndex = 9 }, overlay)
	make("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 9 }, card)
	label({ Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 22), Text = upper(rarity and rarity.Name or ""), TextSize = 16,
		Font = F.Bold, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, card)
	label({ Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 44), Text = upper(item.Name), TextSize = 40, Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, card)
	local view = ItemPreview.New(card, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(300, 160),
		ZIndex = 9 })
	ItemPreview.Show(view, item, 300 / 160)
	local text, textColor
	if result.Status == "new" then
		text, textColor = "NEU FREIGESCHALTET", C.Good
	elseif result.Status == "copy" then
		text, textColor = "WEITERES STÜCK  ·  HANDELBAR IM MARKT (RAP-WERT " .. format(RapConfig.Value(item.Id) or 0) .. ")", C.Rap
	else
		text, textColor = "SCHON BESESSEN  ·  +" .. format(result.Refund or 0) .. " MÜNZEN ZURÜCK", C.Primary
	end
	label({ Position = UDim2.fromOffset(20, 262), Size = UDim2.new(1, -40, 0, 36), Text = text, TextSize = 16, Font = F.Bold, TextColor3 = textColor,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, card)
	local crate = window.Crate
	local again = UITheme.Chunky({ Position = UDim2.fromOffset(28, 330), Size = UDim2.fromOffset(300, 56), Color = crate.Color,
		Text = "NOCHMAL  ·  " .. format(crate.Price), TextSize = 20, TextColor = C.PrimaryText, ZIndex = 9 }, card, function()
		overlay:Destroy()
		CrateClient.Request()
	end)
	if coins() < crate.Price then
		again.SetColor(C.MutedBack, C.Bad)
		again.SetText("ZU WENIG MÜNZEN")
	end
	UITheme.Chunky({ Position = UDim2.fromOffset(344, 330), Size = UDim2.fromOffset(188, 56), Color = C.Card, StrokeColor = C.Border, Text = "OK",
		TextSize = 20, ZIndex = 9 }, card, function()
		overlay:Destroy()
	end)
	sound("rbxasset://sounds/electronicpingshort.wav", item.Rarity == "Legendary" and 0.8 or 1.2, 0.6)
end

-- Rolle abspielen: Skins ziehen vorbei, die Rolle bremst und bleibt auf dem Gewinn stehen
local function spin(result)
	local win = window
	win.Result = result
	win.Spinning = true
	setOpenButton()
	win.Status.Text = ""
	fillStrip(result.Reel)
	local random = Random.new()
	local center = (result.Index - 1) * (TILE_W + TILE_GAP) + TILE_W / 2 + random:NextInteger(-40, 40)
	local finalX = VIEW_W / 2 - center
	win.Strip.Position = UDim2.fromOffset(VIEW_W / 2 - TILE_W / 2, 0)
	local generation = win.Generation
	local lastIndex = 0
	win.Connection = RunService.RenderStepped:Connect(function()
		if not window or window ~= win then
			return
		end
		local x = win.Strip.Position.X.Offset
		local index = math.floor((VIEW_W / 2 - x) / (TILE_W + TILE_GAP)) + 1
		if index ~= lastIndex then
			lastIndex = index
			sound("rbxasset://sounds/clickfast.wav", 1 + (index % 3) * 0.08, 0.25)
		end
	end)
	local tween = TweenService:Create(win.Strip, TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(finalX, 0) })
	win.Tween = tween
	tween.Completed:Connect(function()
		if window ~= win or win.Generation ~= generation then
			return
		end
		if win.Connection then
			win.Connection:Disconnect()
			win.Connection = nil
		end
		local winner = win.Tiles[result.Index]
		if winner then
			local stroke = winner:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = C.Primary
				stroke.Thickness = 3
				stroke.Transparency = 0
			end
		end
		win.Spinning = false
		win.Tween = nil
		setOpenButton()
		task.delay(0.7, function()
			if window == win and win.Generation == generation then
				showResult(result)
			end
		end)
	end)
	tween:Play()
end

-- Kiste beim Server öffnen (der Server antwortet mit CrateResult)
function CrateClient.Request()
	if not window or window.Spinning or window.Waiting then
		return
	end
	local crate = window.Crate
	if coins() < crate.Price then
		window.Status.Text = "Nicht genug Münzen – " .. format(crate.Price) .. " nötig."
		window.Status.TextColor3 = C.Bad
		return
	end
	window.Waiting = true
	window.Status.Text = ""
	window.Open.SetText("ÖFFNET …")
	window.Open.SetColor(C.MutedBack, C.Muted)
	Remotes.CrateAction:FireServer("Open", crate.Id)
	-- Antwortet der Server nicht, nach einer Weile wieder freigeben (statt ewig auf ÖFFNET zu hängen)
	local win = window
	task.delay(8, function()
		if window == win and win.Waiting and not win.Spinning then
			win.Waiting = false
			win.Status.Text = "Keine Antwort vom Server – versuch es nochmal."
			win.Status.TextColor3 = C.Bad
			setOpenButton()
		end
	end)
end

local function build(crate)
	closeWindow()
	local frame = UITheme.Card({ Name = "CrateWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(WIN_W, WIN_H), BackgroundTransparency = 0.04, ZIndex = 5 }, root)
	make("Frame", { Name = "Accent", Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = crate.Color, BorderSizePixel = 0, ZIndex = 5 }, frame)
	label({ Position = UDim2.fromOffset(28, 16), Size = UDim2.new(1, -300, 0, 40), Text = crate.Name, TextSize = 34, Font = F.Display, ZIndex = 5 }, frame)
	label({ Position = UDim2.fromOffset(28, 54), Size = UDim2.new(1, -300, 0, 18), Text = crate.Sub .. "  ·  EIN SKIN PRO KISTE", TextSize = 12,
		Font = F.Bold, TextColor3 = crate.Color, ZIndex = 5 }, frame)
	local close = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(44, 44),
		Color = C.Card, StrokeColor = C.Border, Text = "", ZIndex = 5 }, frame, closeWindow)
	close.Button:SetAttribute("NoFocus", true) -- Controller: schließen mit ○
	UITheme.Cross(close.Face, 14, C.Text, 2).ZIndex = 5
	local coinsLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -76, 0, 28), Size = UDim2.fromOffset(220, 26), Text = "",
		TextSize = 20, Font = F.Display, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }, frame)

	-- Rolle
	local view = make("Frame", { Name = "Reel", Position = UDim2.fromOffset(40, 90), Size = UDim2.fromOffset(VIEW_W, VIEW_H), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.2, ClipsDescendants = true, ZIndex = 5 }, frame)
	UITheme.Corner(view, UITheme.Radius.Large)
	UITheme.Stroke(view, C.Border, 1, 0.3)
	local strip = make("Frame", { Name = "Strip", Size = UDim2.fromOffset(100, VIEW_H), BackgroundTransparency = 1, ZIndex = 6 }, view)
	make("Frame", { Name = "Marker", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = C.Primary, BorderSizePixel = 0, ZIndex = 8 }, view)
	for _, edge in { 0, 1 } do -- Abdunkeln an den Rändern
		local fade = make("Frame", { AnchorPoint = Vector2.new(edge, 0), Position = UDim2.new(edge, 0, 0, 0), Size = UDim2.new(0, 70, 1, 0),
			BackgroundColor3 = C.Background, BorderSizePixel = 0, ZIndex = 8 }, view)
		make("UIGradient", { Transparency = NumberSequence.new(edge == 0 and { NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }
			or { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) }) }, fade)
	end

	local status = label({ Position = UDim2.fromOffset(40, 248), Size = UDim2.fromOffset(VIEW_W, 20), Text = "", TextSize = 14, Font = F.Bold,
		TextColor3 = C.Bad, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, frame)

	-- Chancen
	label({ Position = UDim2.fromOffset(40, 272), Size = UDim2.fromOffset(300, 18), Text = "CHANCEN", TextSize = 13, Font = F.Bold, TextColor3 = C.Muted,
		ZIndex = 5 }, frame)
	local x = 40
	for _, entry in CrateConfig.Odds(crate) do
		local rarity = Cosmetics.Rarities[entry.Rarity]
		local chip = make("Frame", { Position = UDim2.fromOffset(x, 294), Size = UDim2.fromOffset(204, 34), BackgroundColor3 = C.Card, ZIndex = 5 }, frame)
		UITheme.Corner(chip, UITheme.Radius.Small)
		UITheme.Stroke(chip, rarity.Color, 1, 0.4)
		label({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -90, 1, 0), Text = upper(rarity.Name), TextSize = 13, Font = F.Bold,
			TextColor3 = rarity.Color, ZIndex = 5 }, chip)
		label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(80, 34),
			Text = string.format("%.1f %%", entry.Chance * 100), TextSize = 16, Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 5 }, chip)
		x += 212
	end

	-- Inhalt der Kiste
	label({ Position = UDim2.fromOffset(40, 340), Size = UDim2.fromOffset(400, 18), Text = "DAS STECKT DRIN", TextSize = 13, Font = F.Bold,
		TextColor3 = C.Muted, ZIndex = 5 }, frame)
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(40, 362), Size = UDim2.fromOffset(VIEW_W, 170), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 5 }, frame)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(204, 50), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local pool = CrateConfig.Pool(crate)
	local rank = {}
	for index, id in CrateConfig.RarityOrder do
		rank[id] = index
	end
	table.sort(pool, function(a, b)
		if a.Rarity ~= b.Rarity then
			return rank[a.Rarity] > rank[b.Rarity]
		end
		return a.Name < b.Name
	end)
	for index, item in pool do
		local rarity = Cosmetics.Rarities[item.Rarity]
		local cell = make("Frame", { LayoutOrder = index, BackgroundColor3 = C.Card, ZIndex = 5 }, list)
		UITheme.Corner(cell, UITheme.Radius.Small)
		make("Frame", { Size = UDim2.new(0, 4, 1, -12), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = rarity.Color, BorderSizePixel = 0,
			ZIndex = 5 }, cell)
		local kind = item.Type == "Agent" and upper((AgentConfig.Get(item.Agent) or { Name = "" }).Name) or "WAFFE"
		label({ Position = UDim2.fromOffset(14, 5), Size = UDim2.new(1, -20, 0, 22), Text = upper(item.Name), TextSize = 15, Font = F.Display,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, cell)
		local value = RapConfig.Value(item.Id)
		label({ Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -20, 0, 16), TextSize = 11, Font = F.Bold, TextColor3 = value and C.Rap or C.Muted,
			Text = kind .. (value and ("  ·  RAP " .. format(value)) or ""), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, cell)
	end

	local openButton = UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(420, 58),
		Color = crate.Color, Text = "ÖFFNEN", TextSize = 22, TextColor = C.PrimaryText, ZIndex = 5 }, frame, function()
		CrateClient.Request()
	end)
	window = { Crate = crate, Frame = frame, Strip = strip, Open = openButton, Status = status, CoinsLabel = coinsLabel, Spinning = false,
		Generation = 0, Tiles = {} }
	UITheme.SetBlur("Crate", true)
	fillStrip(idleIds(crate))
	strip.Position = UDim2.fromOffset(40, 0)
	setOpenButton()
	InputActions.Focus(frame, openButton.Button) -- Controller: gleich auf ÖFFNEN
	return window
end

function CrateClient.Open(crateId)
	local crate = CrateConfig.Get(crateId)
	if crate then
		build(crate)
	end
end

function CrateClient.Init()
	gui = make("ScreenGui", { Name = "Crates", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 13,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	root = UITheme.ScaledRoot(gui, nil, nil, 0.55)

	-- Automaten in der Marktmitte: Parts "CrateWeapon" und "CrateAgent"
	local map = workspace:WaitForChild("Maps"):WaitForChild("Market", 30)
	if map then
		for _, crate in CrateConfig.Crates do
			local machine = map:FindFirstChild("Crate" .. crate.Id, true) -- liegt in einem Unterordner der Map
			if machine then
				local prompt = Instance.new("ProximityPrompt")
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
				prompt.ActionText = "Kiste öffnen"
				prompt.ObjectText = crate.Name .. "  ·  " .. crate.Price .. " Münzen"
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Parent = machine
				prompt.Triggered:Connect(function()
					CrateClient.Open(crate.Id)
				end)
			end
		end
	end

	Remotes.CrateResult.OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		if window then
			window.Waiting = false
		end
		if not result.Ok then
			if window then
				window.Status.Text = tostring(result.Message or "Das hat nicht geklappt.")
				window.Status.TextColor3 = C.Bad
				setOpenButton()
			end
			return
		end
		if window and window.Crate.Id == result.Crate then
			spin(result)
		else
			announce(result)
		end
	end)
	player:GetAttributeChangedSignal("Coins"):Connect(setOpenButton)
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		if window and player:GetAttribute("Mode") ~= "Market" and player:GetAttribute("Mode") ~= "Hub" then
			closeWindow()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if window and (input.KeyCode == Enum.KeyCode.ButtonB or (input.KeyCode == Enum.KeyCode.Escape and not processed)) then
			closeWindow()
		end
	end)
end

return CrateClient
