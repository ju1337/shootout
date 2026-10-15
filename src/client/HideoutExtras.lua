-- HideoutExtras (ModuleScript, nur Client)
-- Zwei Reiter im Versteck-Fenster (ExtinctionClient, openHideout), Werte in WorkshopConfig:
--   WERKBANK       oben was gerade hergestellt wird (Fortschritt, ABHOLEN), darunter alle Rezepte (Zutaten, Münzen, Zeit,
--                  HERSTELLEN; gesperrte Rezepte mit nötiger Versteckstufe)
--   FUNKAUFTRÄGE   die drei Aufträge des Tages nebeneinander: Aufgabe, Fortschritt, Belohnung, ABHOLEN
-- Jede Funktion baut in einen leeren Rahmen und gibt refresh(data, tier) zurück (data = HideoutConfig.Data(player)).
-- Aktionen gehen über send(...) (Remotes.ExtAction): "HideoutCraft", "HideoutCraftCollect", "HideoutContract".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)
local WorkshopConfig = require(Shared.WorkshopConfig)
local HideoutConfig = require(Shared.HideoutConfig)
local ExtinctionConfig = require(Shared.ExtinctionConfig)

local player = Players.LocalPlayer
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper

local HideoutExtras = {}

local function itemName(id)
	local config = ExtinctionConfig.Get(id)
	return config and config.Name or id
end

local function duration(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function ingredients(recipe)
	local parts = {}
	for _, need in recipe.Items do
		table.insert(parts, need[2] .. "× " .. itemName(need[1]))
	end
	if recipe.Coins > 0 then
		table.insert(parts, UITheme.FormatNumber(recipe.Coins) .. " Münzen")
	end
	return table.concat(parts, " + ")
end

-- ctx = { Colors, Accent, Raised, Send }
function HideoutExtras.Workbench(page, width, height, ctx)
	local C, accent = ctx.Colors, ctx.Accent
	-- oben: aktueller Auftrag der Werkbank
	local current = UITheme.Card({ Name = "Current", Size = UDim2.fromOffset(width, 92), BackgroundColor3 = ctx.Raised,
		BackgroundTransparency = 0, ZIndex = 6 }, page)
	UITheme.AccentBar(current, accent, { ZIndex = 7 })
	local title = label({ Name = "Title", Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -240, 0, 24), Text = "", TextSize = 20,
		Font = F.Display, ZIndex = 7 }, current)
	local sub = label({ Name = "Sub", Position = UDim2.fromOffset(20, 38), Size = UDim2.new(1, -240, 0, 16), Text = "", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted, ZIndex = 7 }, current)
	local track = make("Frame", { Name = "Track", Position = UDim2.fromOffset(20, 64), Size = UDim2.new(1, -240, 0, 8),
		BackgroundColor3 = C.Card, BorderSizePixel = 0, ZIndex = 7 }, current)
	UITheme.Corner(track, 4)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = accent, BorderSizePixel = 0, ZIndex = 8 },
		track)
	UITheme.Corner(fill, 4)
	local collect = UITheme.Chunky({ Name = "Collect", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(190, 44), Color = C.Card, StrokeColor = C.Border, Text = "", TextSize = 15, ZIndex = 7 }, current,
		function()
			ctx.Send("HideoutCraftCollect")
		end)

	-- darunter: Rezepte
	local list = make("ScrollingFrame", { Name = "Recipes", Position = UDim2.fromOffset(0, 104), Size = UDim2.fromOffset(width, height - 104),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Muted, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 6 }, page)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	for index, recipe in WorkshopConfig.Recipes do
		local row = make("Frame", { Name = "Recipe_" .. recipe.Id, Size = UDim2.new(1, -8, 0, 58), BackgroundColor3 = C.Card,
			BorderSizePixel = 0, LayoutOrder = index, ZIndex = 7 }, list)
		UITheme.Corner(row, UITheme.Radius.Medium)
		label({ Name = "Out", Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -200, 0, 22),
			Text = upper(recipe.Out[2] .. "× " .. itemName(recipe.Out[1])), TextSize = 18, Font = F.Display, ZIndex = 8 }, row)
		label({ Name = "Needs", Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -200, 0, 20), Text = ingredients(recipe),
			TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8 }, row)
		local button = UITheme.Chunky({ Name = "Craft", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(170, 40), Color = C.Card, StrokeColor = C.Border, Text = "", TextSize = 13, ZIndex = 8 }, row, function()
			ctx.Send("HideoutCraft", recipe.Id)
		end)
		rows[recipe.Id] = button
	end

	return function(data, tier)
		local craft = type(data.Craft) == "table" and data.Craft or nil
		local recipe = craft and WorkshopConfig.Recipe(craft.Id)
		local now = workspace:GetServerTimeNow()
		local level = HideoutConfig.Level(data, "Workbench")
		if recipe then
			local total = WorkshopConfig.CraftTime(recipe, level)
			local left = (tonumber(craft.Done) or now) - now
			title.Text = upper(recipe.Out[2] .. "× " .. itemName(recipe.Out[1]))
			sub.Text = left > 0 and ("IN ARBEIT  ·  NOCH " .. duration(left)) or "FERTIG  ·  ABHOLEN"
			fill.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
			collect.SetText(left > 0 and "IN ARBEIT" or "ABHOLEN")
			collect.SetColor(left > 0 and C.Card or C.Primary, left > 0 and C.Muted or C.PrimaryText)
		else
			title.Text = "WERKBANK FREI"
			sub.Text = level > 0 and ("WERKBANK STUFE " .. level .. "  ·  " .. math.min(60, level * WorkshopConfig.SpeedPerLevel)
				.. " % SCHNELLER") or "BAU DIE WERKBANK AUS, DANN GEHT ES SCHNELLER"
			fill.Size = UDim2.fromScale(0, 1)
			collect.SetText("NICHTS IN ARBEIT")
			collect.SetColor(C.Card, C.Muted)
		end
		for id, button in rows do
			local r = WorkshopConfig.Recipe(id)
			local locked = tier < r.Tier
			if locked then
				button.SetText("AB STUFE " .. r.Tier)
				button.SetColor(C.Card, C.Muted)
			elseif recipe then
				button.SetText(duration(WorkshopConfig.CraftTime(r, level)))
				button.SetColor(C.Card, C.Muted)
			else
				button.SetText("HERSTELLEN  ·  " .. duration(WorkshopConfig.CraftTime(r, level)))
				button.SetColor(C.Primary, C.PrimaryText)
			end
		end
	end
end

local function rewardText(reward)
	local parts = {}
	if reward.Coins then
		table.insert(parts, UITheme.FormatNumber(reward.Coins) .. " Münzen")
	end
	if reward.RedPoints then
		table.insert(parts, reward.RedPoints .. " RZ")
	end
	for _, item in reward.Items or {} do
		table.insert(parts, item[2] .. "× " .. itemName(item[1]))
	end
	if reward.XP then
		table.insert(parts, reward.XP .. " XP")
	end
	return table.concat(parts, " · ")
end

function HideoutExtras.Contracts(page, width, height, ctx)
	local C, accent = ctx.Colors, ctx.Accent
	local n = WorkshopConfig.ContractsPerDay
	local gap = 16
	local cardW = math.floor((width - gap * (n - 1)) / n)
	local cards = {}
	for i = 1, n do
		local card = UITheme.Card({ Name = "Contract" .. i, Position = UDim2.fromOffset((i - 1) * (cardW + gap), 0),
			Size = UDim2.fromOffset(cardW, height), BackgroundColor3 = ctx.Raised, BackgroundTransparency = 0, ZIndex = 6 }, page)
		UITheme.AccentBar(card, accent, { ZIndex = 7 })
		label({ Position = UDim2.fromOffset(18, 16), Size = UDim2.new(1, -36, 0, 14), Text = "FUNKAUFTRAG " .. i, TextSize = 12,
			Font = F.Bold, TextColor3 = accent, ZIndex = 7 }, card)
		local task = label({ Name = "Task", Position = UDim2.fromOffset(18, 36), Size = UDim2.new(1, -36, 0, 60), Text = "", TextSize = 20,
			Font = F.Display, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7 }, card)
		local track = make("Frame", { Position = UDim2.fromOffset(18, 108), Size = UDim2.new(1, -36, 0, 10), BackgroundColor3 = C.Card,
			BorderSizePixel = 0, ZIndex = 7 }, card)
		UITheme.Corner(track, 5)
		local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = accent, BorderSizePixel = 0, ZIndex = 8 },
			track)
		UITheme.Corner(fill, 5)
		local count = label({ Name = "Count", Position = UDim2.fromOffset(18, 126), Size = UDim2.new(1, -36, 0, 24), Text = "", TextSize = 22,
			Font = F.Display, TextColor3 = accent, ZIndex = 7 }, card)
		label({ Position = UDim2.fromOffset(18, 162), Size = UDim2.new(1, -36, 0, 14), Text = "BELOHNUNG", TextSize = 11, Font = F.Bold,
			TextColor3 = C.Muted, ZIndex = 7 }, card)
		local reward = label({ Name = "Reward", Position = UDim2.fromOffset(18, 178), Size = UDim2.new(1, -36, 0, 60), Text = "", TextSize = 14,
			Font = F.Bold, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7 }, card)
		local claim = UITheme.Chunky({ Name = "Claim", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18),
			Size = UDim2.new(1, -36, 0, 44), Color = C.Card, StrokeColor = C.Border, Text = "", TextSize = 14, ZIndex = 7 }, card, function()
			ctx.Send("HideoutContract", i)
		end)
		cards[i] = { Task = task, Fill = fill, Count = count, Reward = reward, Claim = claim }
	end
	local function stats()
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Stats") or "{}")
		return ok and type(decoded) == "table" and decoded or {}
	end

	return function(data, tier)
		local day = WorkshopConfig.Day()
		local state = type(data.Contracts) == "table" and data.Contracts.Day == day and data.Contracts or nil
		local values = stats()
		local open = tier >= WorkshopConfig.ContractTier
		for i, contract in WorkshopConfig.ContractsFor(day) do
			local view = cards[i]
			if view then
				local entry = state and state.List and state.List[i]
				local have = entry and math.clamp((values[contract.Stat] or 0) - (tonumber(entry.Base) or 0), 0, contract.Need) or 0
				view.Task.Text = (string.gsub(contract.Text, "{1}", tostring(contract.Need)))
				view.Fill.Size = UDim2.fromScale(have / contract.Need, 1)
				view.Count.Text = have .. " / " .. contract.Need
				view.Reward.Text = rewardText(contract.Reward)
				local claimed = entry and entry.Claimed == true
				local done = open and have >= contract.Need and not claimed
				view.Claim.SetText(not open and ("AB VERSTECKSTUFE " .. WorkshopConfig.ContractTier) or claimed and "ABGEHOLT · MORGEN NEU"
					or done and "BELOHNUNG ABHOLEN" or "NOCH NICHT ERLEDIGT")
				view.Claim.SetColor(done and C.Primary or C.Card, done and C.PrimaryText or C.Muted)
			end
		end
	end
end

return HideoutExtras
