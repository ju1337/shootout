-- TradeClient (ModuleScript, nur Client)
-- Tauschen in den Safe Zones der offenen Welt und im Markt (Server: TradeService):
--   * Im Markt öffnet Taste T (oder Knopf TAUSCH in der Markt-Leiste) die Spielerliste (in der offenen Welt ist T die
--     Kamera): alle Spieler im selben Bereich mit
--     Entfernung und Inventarwert, TAUSCH ANFRAGEN schickt die Anfrage (nah genug heranlaufen, RapConfig.TradeRange).
--   * An anderen Spielern erscheint G (Controller △, Touch: Antippen): Tausch-Anfrage schicken.
--   * Anfragen erscheinen rechts als Karte mit ANNEHMEN / ABLEHNEN und einem ablaufenden Balken.
--   * Tausch-Fenster: links das eigene Angebot (Skins, RAP) und darunter die eigenen freien Skins zum Hinzufügen,
--     rechts das Angebot des anderen; der RAP-Wert beider Seiten steht darüber. BEREIT – sind beide bereit, läuft
--     ein Countdown, dann wird getauscht. Jede Änderung nimmt BEREIT bei beiden zurück (kein Austauschen im letzten
--     Moment). Nach dem Tausch erscheint eine Belohnungs-Karte.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local Cosmetics = require(Shared.Cosmetics)
local RapConfig = require(Shared.RapConfig)
local Modes = require(Shared.Modes)
local ItemPreview = require(Shared.ItemPreview)
local Notifications = require(Shared.Notifications)
local InputActions = require(Shared.InputActions)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper
local format = UITheme.FormatNumber

local TradeClient = {}

local WIN_W, WIN_H = 1120, 660
local PROMPT_NAME = "TradePrompt"

local gui, root, requestList, toast
local window = nil -- { Frame, State, EndsAt, ... }
local current = nil -- letzter Stand vom Server

local function sound(id, speed, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 2)
end

local function decode(raw)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "")
	return ok and type(data) == "table" and data or {}
end

-- RAP-Wert eines Angebots (Skins nach RAP-Wert + RAP)
local function offerValue(offer)
	local total = tonumber(offer.Rap) or 0
	for id, n in offer.Items or {} do
		total += (RapConfig.Value(id) or 0) * n
	end
	return total
end

local toastUntil = 0
local function showToast(text, success)
	toast.Text = tostring(text)
	toast.TextColor3 = success == false and C.Bad or (success and C.Good or C.Text)
	toast.Visible = true
	toastUntil = os.clock() + 4
	task.delay(4.05, function()
		if os.clock() >= toastUntil then
			toast.Visible = false
		end
	end)
end

-- ---------- Anfragen ----------

local function requestCard(data)
	local card = UITheme.Card({ Name = "Request" .. tostring(data.From), Size = UDim2.fromOffset(340, 104),
		BackgroundTransparency = 0.05 }, requestList)
	UITheme.AccentBar(card, C.Rap, { Side = "Left", Thickness = 4, ZIndex = 2 })
	label({ Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -30, 0, 16), Text = "TAUSCH-ANFRAGE", TextSize = 11,
		Font = F.Bold, TextColor3 = C.Rap, ZIndex = 2 }, card)
	label({ Position = UDim2.fromOffset(18, 26), Size = UDim2.new(1, -30, 0, 26), Text = upper(tostring(data.Name)) .. " MÖCHTE TAUSCHEN",
		TextSize = 21, Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 }, card)
	local function respond(accept)
		Remotes.TradeAction:FireServer("Respond", data.From, accept)
		card:Destroy()
	end
	UITheme.Chunky({ Position = UDim2.fromOffset(18, 58), Size = UDim2.fromOffset(150, 34), Color = C.Rap, Text = "ANNEHMEN",
		TextSize = 16, TextColor = C.PrimaryText, ZIndex = 2 }, card, function()
		respond(true)
	end)
	UITheme.Chunky({ Position = UDim2.fromOffset(176, 58), Size = UDim2.fromOffset(146, 34), Color = C.Card, StrokeColor = C.Border,
		Text = "ABLEHNEN", TextSize = 16, ZIndex = 2 }, card, function()
		respond(false)
	end)
	-- Balken läuft ab
	local track = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -4), Size = UDim2.new(1, -20, 0, 2),
		BackgroundColor3 = C.Background, BorderSizePixel = 0, ZIndex = 2 }, card)
	local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Rap, BorderSizePixel = 0, ZIndex = 2 }, track)
	local seconds = tonumber(data.Seconds) or RapConfig.TradeRequestTime
	local began = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local left = 1 - (os.clock() - began) / seconds
		if left <= 0 or not card.Parent then
			connection:Disconnect()
			if card.Parent then
				card:Destroy()
			end
			return
		end
		fill.Size = UDim2.fromScale(left, 1)
	end)
	sound("rbxasset://sounds/electronicpingshort.wav", 1.6, 0.35)
end

-- ---------- Tausch-Fenster ----------

local function closeWindow()
	if window then
		InputActions.Unfocus(window.Frame)
		window.Frame:Destroy()
		window = nil
		UITheme.SetBlur("Trade", false)
	end
end

-- Kachel für einen Skin im Angebot (Vorschau, Name, Stückzahl); onRemove = Knopf "−" (nur eigenes Angebot)
local function offerTile(parent, item, count, order, onRemove)
	local rarity = Cosmetics.Rarities[item.Rarity]
	local tile = make("Frame", { Size = UDim2.fromOffset(160, 118), BackgroundColor3 = C.Card, LayoutOrder = order, ZIndex = 5 }, parent)
	UITheme.Corner(tile, UITheme.Radius.Medium)
	UITheme.Stroke(tile, rarity and rarity.Color or C.Border, 1, 0.45)
	local view = ItemPreview.New(tile, { Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 70), ZIndex = 5 })
	ItemPreview.Show(view, item, 148 / 70)
	label({ Position = UDim2.fromOffset(8, 76), Size = UDim2.new(1, -16, 0, 20), Text = upper(item.Name), TextSize = 17, Font = F.Display,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, tile)
	label({ Position = UDim2.fromOffset(8, 96), Size = UDim2.new(1, -16, 0, 14), Text = format(RapConfig.Value(item.Id) or 0) .. " RAP",
		TextSize = 11, Font = F.Bold, TextColor3 = C.Rap, ZIndex = 5 }, tile)
	if count > 1 then
		UITheme.Tag({ Position = UDim2.fromOffset(6, 6), Text = "×" .. count, TextSize = 12, BackgroundColor3 = C.Secondary,
			TextColor3 = C.Text, ZIndex = 6 }, tile)
	end
	if onRemove then
		local minus = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(28, 28),
			Color = C.Background, StrokeColor = C.Bad, Text = "-", TextSize = 22, Font = F.Bold, TextColor = C.Bad, ZIndex = 6 }, tile, onRemove)
		minus.Button.ZIndex = 6
	end
	return tile
end

local function sideHeader(parent, title, value, ready)
	label({ Size = UDim2.new(1, -170, 0, 22), Text = title, TextSize = 13, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, parent)
	label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(170, 22),
		Text = "WERT " .. format(value) .. " RAP", TextSize = 13, Font = F.Bold, TextColor3 = C.Rap,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }, parent)
	local badge = UITheme.Tag({ Position = UDim2.fromOffset(0, 26), Text = ready and "BEREIT" or "NOCH NICHT BEREIT", TextSize = 12,
		BackgroundColor3 = ready and C.Rap or C.Secondary, TextColor3 = ready and C.PrimaryText or C.Muted, ZIndex = 5 }, parent)
	return badge
end

local function offerGrid(parent, offer, y, height, editable)
	local grid = make("ScrollingFrame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.35, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 5 }, parent)
	UITheme.Corner(grid, UITheme.Radius.Large)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, grid)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(160, 118), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local ids = {}
	for id in offer.Items or {} do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return (RapConfig.Value(a) or 0) > (RapConfig.Value(b) or 0)
	end)
	for order, id in ids do
		local item = Cosmetics.Get(id)
		if item then
			offerTile(grid, item, offer.Items[id], order, editable and function()
				Remotes.TradeAction:FireServer("RemoveItem", id)
			end or nil)
		end
	end
	if #ids == 0 then
		label({ Size = UDim2.fromOffset(400, 40), Text = editable and "Füge unten Skins hinzu (+)" or "Noch keine Skins", TextSize = 13,
			Font = F.Medium, TextColor3 = C.Muted, ZIndex = 5, LayoutOrder = 1 }, grid)
	end
	return grid
end

local function render()
	if not current then
		closeWindow()
		return
	end
	local state = current
	if not window then
		local frame = UITheme.Card({ Name = "TradeWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromOffset(WIN_W, WIN_H), BackgroundTransparency = 0.04, ZIndex = 5 }, root)
		window = { Frame = frame }
		UITheme.SetBlur("Trade", true)
	end
	-- Preisfeld nicht wegwerfen, während man tippt (danach neu bauen)
	local focused = UserInputService:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(window.Frame) then
		window.Pending = true
		return
	end
	window.Pending = false
	local frame = window.Frame
	for _, child in frame:GetChildren() do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	UITheme.AccentBar(frame, C.Rap, { ZIndex = 5 })
	label({ Position = UDim2.fromOffset(28, 18), Size = UDim2.new(1, -300, 0, 40), Text = "TAUSCH MIT " .. upper(state.Partner.Name),
		TextSize = 34, Font = F.Display, ZIndex = 5 }, frame)
	UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(150, 44), Color = C.Card,
		StrokeColor = C.Bad, Text = "ABBRECHEN", TextSize = 17, TextColor = C.Bad, ZIndex = 5 }, frame, function()
		Remotes.TradeAction:FireServer("Cancel")
	end)

	-- links: eigenes Angebot + eigene Skins
	local left = make("Frame", { Position = UDim2.fromOffset(28, 74), Size = UDim2.fromOffset(526, WIN_H - 170), BackgroundTransparency = 1,
		ZIndex = 5 }, frame)
	sideHeader(left, "DEIN ANGEBOT", offerValue(state.Mine), state.Mine.Ready)
	offerGrid(left, state.Mine, 56, 140, true)
	-- RAP ins Angebot
	label({ Position = UDim2.fromOffset(0, 206), Size = UDim2.fromOffset(120, 36), Text = "RAP DAZU", TextSize = 13, Font = F.Bold,
		TextColor3 = C.Muted, ZIndex = 5 }, left)
	local rapBox = make("TextBox", { Position = UDim2.fromOffset(110, 204), Size = UDim2.fromOffset(150, 38), Text = tostring(state.Mine.Rap or 0),
		ClearTextOnFocus = false, Font = F.Bold, TextSize = 16, TextColor3 = C.Text, BackgroundColor3 = C.Background, ZIndex = 5,
		PlaceholderText = "0", PlaceholderColor3 = C.Muted }, left)
	UITheme.Corner(rapBox, UITheme.Radius.Small)
	UITheme.Stroke(rapBox, C.Rap, 1, 0.5)
	rapBox:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = string.sub((string.gsub(rapBox.Text, "%D", "")), 1, 8)
		if digits ~= rapBox.Text then
			rapBox.Text = digits
		end
	end)
	local function setRap()
		Remotes.TradeAction:FireServer("SetRap", tonumber(rapBox.Text) or 0)
	end
	rapBox.FocusLost:Connect(function(enter)
		if enter then
			setRap()
		end
		if window and window.Pending then
			task.defer(render)
		end
	end)
	UITheme.Chunky({ Position = UDim2.fromOffset(268, 204), Size = UDim2.fromOffset(90, 38), Color = C.Rap, Text = "SETZEN", TextSize = 15,
		TextColor = C.PrimaryText, ZIndex = 5 }, left, setRap)
	label({ Position = UDim2.fromOffset(368, 204), Size = UDim2.fromOffset(158, 38), Text = "VON " .. format(player:GetAttribute("Rap") or 0),
		TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, left)
	-- eigene freie Skins
	label({ Position = UDim2.fromOffset(0, 254), Size = UDim2.new(1, 0, 0, 18), Text = "DEINE HANDELBAREN SKINS", TextSize = 12, Font = F.Bold,
		TextColor3 = C.Muted, ZIndex = 5 }, left)
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 276), Size = UDim2.new(1, 0, 1, -276), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 5 }, left)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(254, 52), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local owned = Cosmetics.GetOwned(player)
	local held = decode(player:GetAttribute("Reserved"))
	local entries = {}
	for id in owned do
		local item = Cosmetics.Get(id)
		local free = RapConfig.Count(owned, id) - (tonumber(held[id]) or 0)
		if item and RapConfig.Tradeable(id) and free > 0 then
			table.insert(entries, { Item = item, Free = free })
		end
	end
	table.sort(entries, function(a, b)
		return RapConfig.Value(a.Item.Id) > RapConfig.Value(b.Item.Id)
	end)
	for order, entry in entries do
		local rarity = Cosmetics.Rarities[entry.Item.Rarity]
		local row = make("Frame", { BackgroundColor3 = C.Card, LayoutOrder = order, ZIndex = 5 }, list)
		UITheme.Corner(row, UITheme.Radius.Small)
		UITheme.Stroke(row, rarity and rarity.Color or C.Border, 1, 0.6)
		local view = ItemPreview.New(row, { Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(62, 44), ZIndex = 5 })
		ItemPreview.Show(view, entry.Item, 62 / 44)
		label({ Position = UDim2.fromOffset(72, 6), Size = UDim2.fromOffset(136, 20), Text = upper(entry.Item.Name), TextSize = 16,
			Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, row)
		label({ Position = UDim2.fromOffset(72, 28), Size = UDim2.fromOffset(136, 14), Text = entry.Free .. " FREI  ·  "
			.. format(RapConfig.Value(entry.Item.Id)) .. " RAP", TextSize = 10, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, row)
		UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(38, 38), Color = C.Rap,
			Text = "+", TextSize = 22, Font = F.Bold, TextColor = C.PrimaryText, ZIndex = 5 }, row, function()
			Remotes.TradeAction:FireServer("AddItem", entry.Item.Id)
		end)
	end
	if #entries == 0 then
		label({ Size = UDim2.fromOffset(500, 40), Text = "Keine freien handelbaren Skins.", TextSize = 13, Font = F.Medium, TextColor3 = C.Muted,
			ZIndex = 5, LayoutOrder = 1 }, list)
	end

	-- rechts: Angebot des anderen
	local right = make("Frame", { Position = UDim2.fromOffset(WIN_W / 2 + 12, 74), Size = UDim2.fromOffset(526, WIN_H - 170),
		BackgroundTransparency = 1, ZIndex = 5 }, frame)
	make("Frame", { Position = UDim2.fromOffset(-14, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = C.Border, BorderSizePixel = 0,
		ZIndex = 5 }, right)
	sideHeader(right, "ANGEBOT VON " .. upper(state.Partner.Name), offerValue(state.Theirs), state.Theirs.Ready)
	offerGrid(right, state.Theirs, 56, 290, false)
	local theirRap = make("Frame", { Position = UDim2.fromOffset(0, 360), Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.35, ZIndex = 5 }, right)
	UITheme.Corner(theirRap, UITheme.Radius.Large)
	label({ Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(160, 56), Text = "RAP DAZU", TextSize = 13, Font = F.Bold,
		TextColor3 = C.Muted, ZIndex = 5 }, theirRap)
	local rapRow = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 5 }, theirRap)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, rapRow)
	UITheme.RapIcon(rapRow, 22, { LayoutOrder = 1, ZIndex = 5 })
	label({ Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Text = format(state.Theirs.Rap or 0) .. " RAP", TextSize = 28,
		Font = F.Display, TextColor3 = C.Rap, LayoutOrder = 2, ZIndex = 5 }, rapRow)

	-- unten: BEREIT und Zustand
	local ready = state.Mine.Ready
	UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(300, 52),
		Color = ready and C.Rap or C.Primary, Text = ready and "BEREIT  ·  ZURÜCKNEHMEN" or "BEREIT", TextSize = 22,
		TextColor = C.PrimaryText, ZIndex = 5 }, frame, function()
		Remotes.TradeAction:FireServer("Ready", not ready)
	end)
	window.Status = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -80), Size = UDim2.fromOffset(WIN_W - 60, 20),
		Text = "", TextSize = 14, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, frame)
	window.EndsAt = state.Countdown and (os.clock() + state.Countdown) or nil
	window.State = state
	InputActions.Refocus(frame) -- Controller: Auswahl bleibt, wo sie war, sonst in das Fenster
end

-- Zustandszeile (Countdown läuft ohne neue Nachricht vom Server)
local function updateStatus()
	if not window or not window.Status or not window.State then
		return
	end
	local state = window.State
	if window.EndsAt then
		local left = math.max(0, math.ceil(window.EndsAt - os.clock()))
		window.Status.Text = "BEIDE BEREIT – TAUSCH IN " .. left .. " …"
		window.Status.TextColor3 = C.Rap
	elseif state.Mine.Ready then
		window.Status.Text = "WARTE AUF " .. upper(state.Partner.Name) .. " …"
		window.Status.TextColor3 = C.Text
	elseif state.Theirs.Ready then
		window.Status.Text = upper(state.Partner.Name) .. " IST BEREIT – PRÜFE SEIN ANGEBOT UND DRÜCKE BEREIT"
		window.Status.TextColor3 = C.Primary
	else
		window.Status.Text = "JEDE ÄNDERUNG NIMMT BEREIT ZURÜCK – PRÜFE BEIDE ANGEBOTE GENAU"
		window.Status.TextColor3 = C.Muted
	end
end

-- Text für erhaltene bzw. gegebene Dinge ("Lava ×2, 300 RAP")
local function describe(offer)
	local parts = {}
	for id, n in (offer and offer.Items) or {} do
		local item = Cosmetics.Get(id)
		table.insert(parts, (item and item.Name or id) .. (n > 1 and (" ×" .. n) or ""))
	end
	if offer and (offer.Rap or 0) > 0 then
		table.insert(parts, format(offer.Rap) .. " RAP")
	end
	return #parts > 0 and table.concat(parts, ", ") or "nichts"
end

-- ---------- Prompts an anderen Spielern ----------

local function updatePrompts()
	local myMode = player:GetAttribute("Mode")
	local social = myMode ~= nil and Modes.InLounge(player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local character = other.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local prompt = rootPart:FindFirstChild(PROMPT_NAME)
				if not prompt then
					prompt = Instance.new("ProximityPrompt")
					prompt.Name = PROMPT_NAME
					prompt.ActionText = "Handeln"
					prompt.KeyboardKeyCode = Enum.KeyCode.G
					prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
					prompt.HoldDuration = 0.25
					prompt.MaxActivationDistance = 10
					prompt.RequiresLineOfSight = false
					prompt.UIOffset = Vector2.new(0, 40)
					prompt.Parent = rootPart
					prompt.Triggered:Connect(function()
						Remotes.TradeAction:FireServer("Request", other.UserId)
					end)
				end
				prompt.ObjectText = other.Name
				prompt.Enabled = social and other:GetAttribute("Mode") == myMode and Modes.InLounge(other) and current == nil
			end
		end
	end
end

-- ---------- Spielerliste: Tausch anfragen ohne G ----------

local listWindow = nil -- { Frame, List, Alive }
local hint = nil

local function closeList()
	if listWindow then
		listWindow.Alive = false
		InputActions.Unfocus(listWindow.Frame)
		listWindow.Frame:Destroy()
		listWindow = nil
		UITheme.SetBlur("TradeList", false)
	end
end

local function distanceTo(other)
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local theirs = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
	if not mine or not theirs then
		return nil
	end
	return (mine.Position - theirs.Position).Magnitude
end

local function fillList()
	local win = listWindow
	if not win then
		return
	end
	for _, child in win.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local myMode = player:GetAttribute("Mode")
	local others = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("Mode") == myMode then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		local da, db = distanceTo(a) or math.huge, distanceTo(b) or math.huge
		if da ~= db then
			return da < db
		end
		return a.Name < b.Name
	end)
	for index, other in others do
		local meters = distanceTo(other)
		local near = meters ~= nil and meters <= RapConfig.TradeRange
		local row = make("Frame", { Name = "Player" .. other.UserId, Size = UDim2.new(1, -12, 0, 66), BackgroundColor3 = C.Card, BackgroundTransparency = 0.05,
			LayoutOrder = index, ZIndex = 5 }, win.List)
		UITheme.Corner(row, UITheme.Radius.Large)
		UITheme.Stroke(row, near and C.Rap or C.Border, 1, 0.55)
		label({ Position = UDim2.fromOffset(18, 8), Size = UDim2.fromOffset(300, 28), Text = upper(other.Name), TextSize = 22, Font = F.Display,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, row)
		label({ Position = UDim2.fromOffset(18, 38), Size = UDim2.fromOffset(300, 18), Text = "INVENTAR  " .. format(tonumber(other:GetAttribute("RapValue")) or 0) .. " RAP",
			TextSize = 12, Font = F.Bold, TextColor3 = C.Rap, ZIndex = 5 }, row)
		label({ Position = UDim2.fromOffset(340, 20), Size = UDim2.fromOffset(150, 26), TextSize = 16, Font = F.Bold, ZIndex = 5,
			Text = meters and (math.floor(meters + 0.5) .. " M") or "–", TextColor3 = near and C.Good or C.Muted }, row)
		local busy = current ~= nil
		local text = busy and "DU TAUSCHST" or (near and "TAUSCH ANFRAGEN" or ("ZU WEIT  ·  GEH NÄHER"))
		local button = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(250, 46),
			Color = (near and not busy) and C.Rap or C.MutedBack, TextColor = (near and not busy) and C.PrimaryText or C.Muted, Text = text, TextSize = 16,
			ZIndex = 5 }, row, function()
			if busy or not near then
				return
			end
			Remotes.TradeAction:FireServer("Request", other.UserId)
		end)
		button.Button.Name = "RequestButton"
	end
	if #others == 0 then
		label({ Size = UDim2.new(1, -12, 0, 80), Text = "Gerade ist sonst niemand hier.", TextSize = 16, Font = F.Medium, TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, win.List)
	end
	InputActions.Refocus(win.Frame)
end

function TradeClient.OpenPlayers()
	local myMode = player:GetAttribute("Mode")
	if not myMode or not Modes.InLounge(player) then
		showToast("Tauschen geht nur in einer Safe Zone oder im Markt.", false)
		return
	end
	closeList()
	local frame = UITheme.Card({ Name = "TradeListWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(760, 560), BackgroundTransparency = 0.04, ZIndex = 5 }, root)
	UITheme.AccentBar(frame, C.Rap, { ZIndex = 5 })
	label({ Position = UDim2.fromOffset(28, 16), Size = UDim2.new(1, -120, 0, 40), Text = "TAUSCHEN", TextSize = 34, Font = F.Display, ZIndex = 5 }, frame)
	label({ Position = UDim2.fromOffset(28, 54), Size = UDim2.new(1, -120, 0, 18), Text = "SPIELER IN DEINEM BEREICH  ·  NAH GENUG HERANGEHEN, DANN ANFRAGEN",
		TextSize = 12, Font = F.Bold, TextColor3 = C.Rap, ZIndex = 5 }, frame)
	local close = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(44, 44),
		Color = C.Card, StrokeColor = C.Border, Text = "", ZIndex = 5 }, frame, closeList)
	close.Button:SetAttribute("NoFocus", true) -- Controller: schließen mit ○
	UITheme.Cross(close.Face, 14, C.Text, 2).ZIndex = 5
	local list = make("ScrollingFrame", { Name = "List", Position = UDim2.fromOffset(28, 90), Size = UDim2.new(1, -56, 1, -150), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 5 }, frame)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 28, 1, -16), Size = UDim2.new(1, -56, 0, 36), TextWrapped = true, TextSize = 12, Font = F.Medium,
		TextColor3 = C.Muted, ZIndex = 5,
		Text = "Der andere bekommt eine Anfrage und nimmt an oder lehnt ab. Im Tausch legt ihr beide Skins und RAP hinein; erst wenn beide BEREIT sind, wird getauscht. "
			.. "Geht auch ohne Fenster: G an einem Spieler halten." }, frame)
	listWindow = { Frame = frame, List = list, Alive = true }
	UITheme.SetBlur("TradeList", true)
	fillList()
	InputActions.Focus(frame)
	local win = listWindow
	task.spawn(function()
		while listWindow == win and win.Alive do
			task.wait(1)
			if listWindow == win then
				fillList()
			end
		end
	end)
end

function TradeClient.TogglePlayers()
	if listWindow then
		closeList()
	else
		TradeClient.OpenPlayers()
	end
end

local function updateHint()
	if hint then
		local mode = player:GetAttribute("Mode")
		hint.Visible = mode ~= nil and Modes.IsSocial(mode) and window == nil and listWindow == nil
	end
end

-- ---------- Start ----------

function TradeClient.Init()
	-- über dem Fenster der offenen Welt (ExtinctionWindow, DisplayOrder 20), das Menü blendet es nicht aus (KeepOverMenu)
	gui = make("ScreenGui", { Name = "Trade", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 21,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	gui:SetAttribute("KeepOverMenu", true)
	root = UITheme.ScaledRoot(gui, nil, nil, 0.55)
	requestList = make("Frame", { Name = "Requests", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 210),
		Size = UDim2.fromOffset(340, 340), BackgroundTransparency = 1 }, root)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, requestList)
	toast = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(820, 26), Text = "",
		TextSize = 16, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5, Visible = false }, root)
	hint = label({ Name = "TradeHint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(360, 22),
		Text = "T  ·  TAUSCHEN MIT SPIELERN", TextSize = 13, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6, Visible = false }, root)
	local function onPlaceChanged()
		if listWindow and not Modes.InLounge(player) then
			closeList()
		end
		updateHint()
	end
	player:GetAttributeChangedSignal("Mode"):Connect(onPlaceChanged)
	player:GetAttributeChangedSignal("InSafeZone"):Connect(onPlaceChanged)
	UserInputService.InputBegan:Connect(function(input, processed)
		-- ○ schließt auch, wenn gerade ein Knopf im Fenster ausgewählt ist (dann meldet Roblox die Taste als verarbeitet)
		if listWindow and (input.KeyCode == Enum.KeyCode.ButtonB or (input.KeyCode == Enum.KeyCode.Escape and not processed)) then
			closeList()
			updateHint()
			return
		end
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.T and window == nil and Modes.IsSocial(player:GetAttribute("Mode")) then
			TradeClient.TogglePlayers()
			updateHint()
		end
	end)
	updateHint()

	Remotes.TradeUpdate.OnClientEvent:Connect(function(kind, data)
		data = type(data) == "table" and data or {}
		if kind == "Request" then
			local old = requestList:FindFirstChild("Request" .. tostring(data.From))
			if old then
				old:Destroy()
			end
			requestCard(data)
		elseif kind == "State" then
			local fresh = current == nil
			current = data
			for _, card in requestList:GetChildren() do
				if card:IsA("GuiObject") then
					card:Destroy()
				end
			end
			render()
			if fresh then
				sound("rbxasset://sounds/electronicpingshort.wav", 1.2, 0.4)
			end
		elseif kind == "Closed" then
			current = nil
			closeWindow()
			showToast(data.Reason or "Tausch beendet.", false)
		elseif kind == "Done" then
			current = nil
			closeWindow()
			sound("rbxasset://sounds/electronicpingshort.wav", 1.5, 0.6)
			Notifications.Reward({ Title = "TAUSCH MIT " .. upper(tostring(data.Partner or "")),
				Lines = { "Erhalten: " .. describe(data.Received), "Gegeben: " .. describe(data.Gave) }, Rarity = "Epic" })
		elseif kind == "Status" then
			showToast(data.Text or "", data.Success)
		end
	end)
	-- Eigene Skins oder RAP geändert: Liste im Fenster neu
	for _, attribute in { "Owned", "Reserved", "Rap" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if current then
				render()
			end
		end)
	end
	RunService.Heartbeat:Connect(updateStatus)
	task.spawn(function()
		while true do
			local ok, err = pcall(updatePrompts)
			if not ok then
				warn("TradeClient: " .. tostring(err))
			end
			task.wait(0.5)
		end
	end)
end

-- Für die Tests: Fenster mit einem Stand öffnen
function TradeClient.ShowState(state)
	current = state
	render()
	updateStatus()
end

return TradeClient
