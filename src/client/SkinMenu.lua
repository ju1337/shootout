-- SkinMenu (ModuleScript, nur Client)
-- Reiter SKINS im Menü der offenen Welt (ExtinctionClient): den einen Agenten (AgentConfig.MainId) mit freigeschalteten
-- Agenten-Skins (Cosmetics, Type = "Agent") ausstatten.
--   links:  großer 3D-Agent mit dem angeklickten Skin (dreht sich langsam), Name, Seltenheit, Herkunft und ein Knopf:
--           AUSRÜSTEN / AUSGERÜSTET, gesperrte Skins IM SHOP · Preis (öffnet den SHOP) bzw. NUR FÜR CREATOR
--   rechts: alle Agenten-Skins als Kacheln im Stil des Inventars (STANDARD zuerst, dann freigeschaltete, dann gesperrte;
--           ausgerüstet grün umrandet, gesperrt abgedunkelt mit Schloss). Klick auf eine freigeschaltete Kachel rüstet
--           sie gleich aus, eine gesperrte zeigt nur die Vorschau.
-- Ausrüsten läuft über Remotes.ShopAction ("Equip" bzw. "Unequip" mit "Agent"); der Server zieht den Agenten sofort um.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local UITheme = require(Shared.UITheme)
local LobbyPages = require(Shared.LobbyPages)

local player = Players.LocalPlayer
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper

local SkinMenu = {}

local EQUIPPED = Color3.fromRGB(96, 200, 120) -- Rahmen und Schrift: ausgerüstet
local STANDARD = { Id = "Standard", Name = "Standard", Rarity = "Common" } -- Kachel ohne Skin (Standard-Look)

-- Herkunft eines gesperrten Skins (Zeile unter dem Namen)
local function sourceText(item)
	if item.Creator then
		return "NUR FÜR CREATOR"
	elseif Cosmetics.ForSale(item) then
		return "IM SHOP FÜR " .. UITheme.FormatNumber(item.Price) .. " MÜNZEN"
	end
	return "BELOHNUNG"
end

-- Kacheln in fester Reihenfolge: STANDARD, freigeschaltete, gesperrte (je nach Seltenheit, dann Preis)
local RARITY_ORDER = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
local function sortedSkins(owned)
	local list = Cosmetics.List("Agent")
	table.sort(list, function(a, b)
		local ownA, ownB = owned[a.Id] ~= nil, owned[b.Id] ~= nil
		if ownA ~= ownB then
			return ownA
		end
		if RARITY_ORDER[a.Rarity] ~= RARITY_ORDER[b.Rarity] then
			return RARITY_ORDER[a.Rarity] < RARITY_ORDER[b.Rarity]
		end
		return (a.Price or 0) < (b.Price or 0)
	end)
	table.insert(list, 1, STANDARD)
	return list
end

-- Baut die Seite in body (width x height). style = { Tile, Red, Glass, OpenShop = function() }.
-- Gibt { Refresh = function() } zurück (bei Änderung von Owned/Equipped aufrufen).
function SkinMenu.Build(body, width, height, style)
	local C = UITheme.MenuColors
	local previewW, gap = 380, 22
	local gridX = previewW + gap
	local gridW = width - gridX

	-- ---------- links: Vorschau ----------
	local preview = make("Frame", { Name = "SkinPreview", Size = UDim2.fromOffset(previewW, height), BackgroundColor3 = style.Tile,
		BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 6 }, body)
	UITheme.Corner(preview, 3)
	local view = make("ViewportFrame", { Name = "Figure", Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 1, -200),
		BackgroundTransparency = 1, Ambient = Color3.fromRGB(130, 135, 150), LightColor = Color3.fromRGB(255, 245, 235),
		LightDirection = Vector3.new(-0.5, -1, 0.6), ZIndex = 7 }, preview)
	local nameLabel = label({ Name = "SkinName", Position = UDim2.new(0, 20, 1, -184), Size = UDim2.new(1, -40, 0, 34), Text = "",
		TextSize = 30, Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 }, preview)
	local rarityLabel = label({ Name = "Rarity", Position = UDim2.new(0, 20, 1, -146), Size = UDim2.new(1, -40, 0, 16), Text = "",
		TextSize = 12, Font = F.Bold, ZIndex = 7 }, preview)
	local infoLabel = label({ Name = "Info", Position = UDim2.new(0, 20, 1, -124), Size = UDim2.new(1, -40, 0, 36), Text = "",
		TextSize = 12, Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 7 }, preview)
	local action = make("TextButton", { Name = "Action", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(1, -40, 0, 46), AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = style.Red, Text = "",
		Font = F.Bold, TextSize = 16, TextColor3 = C.Text, ZIndex = 7 }, preview)
	UITheme.Corner(action, 3)

	-- ---------- rechts: Kacheln ----------
	label({ Name = "GridTitle", Size = UDim2.fromOffset(300, 20), Position = UDim2.fromOffset(gridX, 0), Text = "AGENTEN-SKINS",
		TextSize = 13, Font = F.Display, ZIndex = 6 }, body)
	local countLabel = label({ Name = "Count", Position = UDim2.fromOffset(gridX + gridW - 300, 0), Size = UDim2.fromOffset(300, 20),
		Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 }, body)
	local scroll = make("ScrollingFrame", { Name = "Skins", Position = UDim2.fromOffset(gridX, 30), Size = UDim2.fromOffset(gridW, height - 30),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Muted, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 6 }, body)
	local cols, cellGap = 5, 10
	local cellW = math.floor((gridW - 8 - cellGap * (cols - 1)) / cols)
	local cellH = math.floor(cellW * 1.25)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(cellW, cellH), CellPadding = UDim2.fromOffset(cellGap, cellGap),
		SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	local selected = nil -- angeklickter Skin (Item oder STANDARD); nil = der ausgerüstete
	local tiles = {}     -- [Id] = { Frame, Stroke, Dim, Lock, State }
	local shownKey = nil
	local figure = nil

	local function equippedEntry()
		return Cosmetics.AgentSkin(player) or STANDARD
	end
	local function isOwned(entry)
		return entry == STANDARD or Cosmetics.GetOwned(player)[entry.Id] ~= nil
	end

	local function equip(entry)
		if entry == STANDARD then
			Remotes.ShopAction:FireServer("Unequip", "Agent")
		else
			Remotes.ShopAction:FireServer("Equip", entry.Id)
		end
	end

	local refresh
	local function tile(entry)
		local rarity = Cosmetics.Rarities[entry.Rarity]
		local frame = make("TextButton", { Name = "Skin_" .. entry.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = style.Tile,
			BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 7 }, scroll)
		UITheme.Corner(frame, 3)
		local stroke = make("UIStroke", { Color = EQUIPPED, Thickness = 2, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			frame)
		local small = make("ViewportFrame", { Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Ambient = Color3.fromRGB(130, 135, 150),
			LightColor = Color3.fromRGB(255, 245, 235), LightDirection = Vector3.new(-0.5, -1, 0.6), ZIndex = 8 }, frame)
		LobbyPages.ShowAgent(small, entry ~= STANDARD and entry or nil)
		label({ Name = "Name", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -20), Size = UDim2.new(1, -16, 0, 16),
			Text = upper(entry.Name), TextSize = 13, Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9 }, frame)
		local state = label({ Name = "State", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -5), Size = UDim2.new(1, -16, 0, 13),
			Text = "", TextSize = 10, Font = F.Bold, TextColor3 = rarity.Color, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9 }, frame)
		-- Seltenheit: farbiger Strich unten (wie im Inventar)
		make("Frame", { Name = "Rarity", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = rarity.Color, BorderSizePixel = 0, ZIndex = 9 }, frame)
		local dim = make("Frame", { Name = "Dim", Size = UDim2.new(1, 0, 1, -40), BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false, ZIndex = 10 }, frame)
		UITheme.Corner(dim, 3)
		local lock = label({ Name = "Lock", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(120, 18), Text = "GESPERRT", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11 }, dim)
		frame.MouseEnter:Connect(function()
			frame.BackgroundColor3 = Color3.fromRGB(30, 32, 37)
		end)
		frame.MouseLeave:Connect(function()
			frame.BackgroundColor3 = style.Tile
		end)
		frame.Activated:Connect(function()
			selected = entry
			if isOwned(entry) and entry ~= equippedEntry() then
				equip(entry)
			end
			refresh()
		end)
		tiles[entry.Id] = { Frame = frame, Stroke = stroke, Dim = dim, Lock = lock, State = state }
	end

	action.Activated:Connect(function()
		local entry = selected or equippedEntry()
		if isOwned(entry) then
			if entry ~= equippedEntry() then
				equip(entry)
			end
		elseif Cosmetics.ForSale(entry) and style.OpenShop then
			style.OpenShop()
		end
	end)

	local order = nil
	refresh = function()
		local owned = Cosmetics.GetOwned(player)
		local list = sortedSkins(owned)
		-- Kacheln einmal bauen, danach nur umsortieren
		local key = ""
		for _, entry in list do
			key ..= entry.Id .. ","
		end
		if key ~= order then
			order = key
			for index, entry in list do
				if not tiles[entry.Id] then
					tile(entry)
				end
				tiles[entry.Id].Frame.LayoutOrder = index
			end
		end
		local equipped = equippedEntry()
		local unlocked = 0
		for _, entry in list do
			local view = tiles[entry.Id]
			local own = isOwned(entry)
			if own and entry ~= STANDARD then
				unlocked += 1
			end
			view.Stroke.Enabled = entry == equipped
			view.Stroke.Color = EQUIPPED
			view.Dim.Visible = not own
			view.Frame.BackgroundTransparency = entry == selected and 0.2 or 0.5
			view.State.Text = entry == equipped and "AUSGERÜSTET"
				or (own and upper(Cosmetics.Rarities[entry.Rarity].Name))
				or (entry.Creator and "CREATOR" or (Cosmetics.ForSale(entry) and UITheme.FormatNumber(entry.Price) .. " MÜNZEN") or "BELOHNUNG")
			view.State.TextColor3 = entry == equipped and EQUIPPED or Cosmetics.Rarities[entry.Rarity].Color
		end
		countLabel.Text = unlocked .. " / " .. (#list - 1) .. " FREIGESCHALTET"

		-- Vorschau links
		local shown = selected or equipped
		if shownKey ~= shown.Id then
			shownKey = shown.Id
			figure = LobbyPages.ShowAgent(view, shown ~= STANDARD and shown or nil)
		end
		local rarity = Cosmetics.Rarities[shown.Rarity]
		nameLabel.Text = upper(shown.Name)
		rarityLabel.Text = shown == STANDARD and "STANDARD-LOOK" or upper(rarity.Name)
		rarityLabel.TextColor3 = shown == STANDARD and C.Muted or rarity.Color
		local own = isOwned(shown)
		if shown == STANDARD then
			infoLabel.Text = "Der Look deines Agenten ohne Skin."
		elseif own then
			infoLabel.Text = "Freigeschaltet. Dein Agent trägt den Skin überall, sobald du ihn ausrüstest."
		else
			infoLabel.Text = sourceText(shown)
		end
		if shown == equipped then
			action.Text = "AUSGERÜSTET"
			action.BackgroundColor3 = Color3.fromRGB(30, 46, 34)
			action.TextColor3 = EQUIPPED
		elseif own then
			action.Text = "AUSRÜSTEN"
			action.BackgroundColor3 = style.Red
			action.TextColor3 = C.Text
		elseif Cosmetics.ForSale(shown) then
			action.Text = "IM SHOP  ·  " .. UITheme.FormatNumber(shown.Price)
			action.BackgroundColor3 = Color3.fromRGB(40, 42, 48)
			action.TextColor3 = C.Gold
		else
			action.Text = shown.Creator and "NUR FÜR CREATOR" or "GESPERRT"
			action.BackgroundColor3 = Color3.fromRGB(40, 42, 48)
			action.TextColor3 = C.Muted
		end
	end

	-- Figur dreht sich langsam hin und her, solange die Seite offen ist
	local spin
	spin = RunService.RenderStepped:Connect(function()
		if not body.Parent then
			spin:Disconnect()
			return
		end
		if figure and figure.Parent then
			local angle = math.sin(os.clock() * 0.5) * 0.5 + 0.35
			figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, angle, 0))
		end
	end)

	refresh()
	return { Refresh = refresh }
end

return SkinMenu
