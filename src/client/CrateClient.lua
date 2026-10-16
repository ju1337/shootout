-- CrateClient (ModuleScript, nur Client)
-- Kisten öffnen (Server: CrateService, Chancen und Preise: CrateConfig). Im Camp Phoenix (Teil "CrateWeapon" der Gruppe
-- Zentrale) steht der Automat der Waffen-Kiste; E öffnet das Fenster:
--   * oben links eine 3D-Kiste (KitCrate, wackelt während der Rolle, springt beim Gewinn), rechts Münzen und QUICKSPIN,
--   * die Rolle: Kacheln mit der Waffe im Skin (3D-Vorschau), Schein und Leiste in der Seltenheitsfarbe; die Kachel unter
--     der roten Markierung wird größer, das Klacken wird mit der Rolle langsamer und tiefer,
--   * darunter die Chancen je Seltenheit und alle Skins der Kiste mit ihrer Chance (Roblox-Pflicht, PaidRandom) und RAP,
--   * wo Roblox bezahlte Zufallsitems verbietet (Attribut PaidRandomOk = false), bleibt ÖFFNEN gesperrt,
--   * ÖFFNEN zieht Münzen ab (der Server würfelt, die Rolle zeigt nur das Ergebnis),
--   * Gewinn-Show nach Seltenheit (RANK): Gewinn-Kachel leuchtet und wächst, die anderen werden dunkel, Blitz über der
--     Rolle; ab Episch kurz Spannung (Rauschen, Fenster bebt); dann die Gewinn-Karte mit Strahlenkranz, Funken (ab
--     Selten), Glanz über dem Namen (Legendär) und Klang je Seltenheit. Die Karte sagt: neu, weiteres Stück (handelbar)
--     oder Duplikat mit Münzen zurück,
--   * oben rechts QUICKSPIN: mit dem Gamepass läuft die Rolle in gut 1 s, ohne führt der Knopf zum Kauf.
-- Der Automat in der Welt klappt bei jedem Gewinn (von wem auch immer) den Deckel auf und leuchtet in der
-- Seltenheitsfarbe (Attribute OpenCount/OpenRarity an CrateWeapon setzt der Server, wenn die Rolle steht).
-- Esc oder X schließt; der Gewinn ist dann schon im Inventar und kommt als Meldung.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local Cosmetics = require(Shared.Cosmetics)
local CrateConfig = require(Shared.CrateConfig)
local RapConfig = require(Shared.RapConfig)
local ItemPreview = require(Shared.ItemPreview)
local Notifications = require(Shared.Notifications)
local InputActions = require(Shared.InputActions)
local PaidRandom = require(Shared.PaidRandom)
local RobuxConfig = require(Shared.RobuxConfig)
local Zentrale = require(Shared.Zentrale)
local Sfx = require(Shared.Sfx)
local LoginConfig = require(Shared.LoginConfig)
local KitCrate = require(script.Parent.KitCrate)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper
local format = UITheme.FormatNumber

local CrateClient = {}

local WIN_W, WIN_H = 980, 680
CrateClient.TileW, CrateClient.TileGap, CrateClient.ViewW = 140, 10, 900
local TILE_W, TILE_H, TILE_GAP = CrateClient.TileW, 148, CrateClient.TileGap
local VIEW_W, VIEW_H = CrateClient.ViewW, 180
local REEL_X, REEL_Y = (WIN_W - CrateClient.ViewW) / 2, 108
local STEP = TILE_W + TILE_GAP

-- Seltenheit -> Stufe der Show (1 gewöhnlich … 4 legendär)
local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
CrateClient.Rank = RANK

local gui, root
local resetReel
local window = nil -- { Crate, Frame, Strip, Reel, Open, Quick, Status, CoinsLabel, Crate3D, Spinning, Connection, Tween, Generation, Tiles }

local function coins()
	return tonumber(player:GetAttribute("Coins")) or 0
end

local function rarityOf(item)
	return item and Cosmetics.Rarities[item.Rarity]
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

-- Weicher Schein: Fläche in einer Farbe, nach oben (rotation 90: nach unten) durchsichtig auslaufend
local function glow(parent, color, props, strongest, rotation)
	props.BackgroundColor3 = color
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	make("UIGradient", { Rotation = rotation or -90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, strongest),
		NumberSequenceKeypoint.new(1, 1) }) }, frame)
	return frame
end

-- Skin-Kachel für die Rolle: Schein in der Seltenheitsfarbe, Waffe im Skin (3D, sonst Farbfläche), Name, Seltenheit.
-- preview = false: nur die Farbfläche (Kacheln, die nur schnell vorbeiziehen)
local function tile(parent, itemId, index, preview)
	local item = Cosmetics.Get(itemId)
	local rarity = rarityOf(item)
	local color = rarity and rarity.Color or C.Border
	local frame = make("Frame", { Name = "Tile" .. index, Position = UDim2.fromOffset((index - 1) * STEP, (VIEW_H - TILE_H) / 2),
		Size = UDim2.fromOffset(TILE_W, TILE_H), BackgroundColor3 = C.Card, BorderSizePixel = 0, ZIndex = 6 }, parent)
	UITheme.Corner(frame, UITheme.Radius.Large)
	UITheme.Stroke(frame, color, 1, 0.45)
	local shine = glow(frame, color, { Name = "Shine", Size = UDim2.fromScale(1, 1), ZIndex = 6 }, 0.55)
	UITheme.Corner(shine, UITheme.Radius.Large)
	if item then
		if preview then
			local view = ItemPreview.New(frame, { Name = "Preview", Position = UDim2.fromOffset(6, 10), Size = UDim2.new(1, -12, 0, 78),
				ZIndex = 7 })
			ItemPreview.Show(view, item, (TILE_W - 12) / 78)
		else
			local swatch = make("Frame", { Name = "Swatch", Position = UDim2.fromOffset(16, 24), Size = UDim2.new(1, -32, 0, 48),
				BackgroundColor3 = item.Color or color, BorderSizePixel = 0, ZIndex = 7 }, frame)
			UITheme.Corner(swatch, UITheme.Radius.Medium)
		end
		label({ Position = UDim2.fromOffset(6, 96), Size = UDim2.new(1, -12, 0, 24), Text = upper(item.Name), TextSize = 16, Font = F.Display,
			TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 }, frame)
		label({ Position = UDim2.fromOffset(6, 120), Size = UDim2.new(1, -12, 0, 14), Text = upper(rarity and rarity.Name or ""), TextSize = 11,
			Font = F.Bold, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 }, frame)
	end
	UITheme.AccentBar(frame, color, { Side = "Bottom", Thickness = 5, ZIndex = 8 }) -- Seltenheit unten, innerhalb der Rundung
	-- Abdunkeln nach dem Stillstand (alle außer dem Gewinn)
	local dim = make("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background, BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 9 }, frame)
	UITheme.Corner(dim, UITheme.Radius.Large)
	return frame
end

-- Preis als Text: Münzen oder Robux (Robux-Kiste)
local function priceText(crate)
	if crate.Product then
		local product = RobuxConfig.Product(crate.Product)
		return "R$ " .. (product and product.Robux or 0)
	end
	return format(crate.Price) .. " MÜNZEN"
end

local function affordable(crate)
	return crate.Product ~= nil or coins() >= crate.Price
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
	elseif not PaidRandom.ShowRandom(player) then
		button.SetText("IN DEINEM LAND NICHT VERFÜGBAR")
		button.SetColor(C.MutedBack, C.Muted)
	elseif not affordable(crate) then
		button.SetText("ZU WENIG MÜNZEN  ·  " .. format(crate.Price))
		button.SetColor(C.MutedBack, C.Bad)
	else
		button.SetText("ÖFFNEN  ·  " .. priceText(crate))
		button.SetColor(crate.Color, C.OnLight)
	end
	window.CoinsLabel.Text = "MÜNZEN  " .. format(coins())
	local ready = not window.Spinning and PaidRandom.ShowRandom(player) and affordable(crate)
	window.Crate3D.SetState(ready and "Ready" or "Wait")
	local quick = window.Quick
	if CrateConfig.Quick(player) then
		quick.SetText("QUICKSPIN AKTIV")
		quick.SetColor(C.Card, crate.Color)
	else
		local pass = RobuxConfig.Pass(CrateConfig.QuickSpinPass)
		quick.SetText("QUICKSPIN  ·  R$ " .. (pass and pass.Robux or 0))
		quick.SetColor(crate.Color, C.OnLight)
	end
end

-- QUICKSPIN kaufen (Gamepass; solange die ID 0 ist, nur ein Hinweis)
local function buyQuickSpin()
	if not window or CrateConfig.Quick(player) then
		return
	end
	local pass = RobuxConfig.Pass(CrateConfig.QuickSpinPass)
	if pass and pass.PassId ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
	else
		window.Status.Text = "QUICKSPIN kommt bald in den Robux-Shop."
		window.Status.TextColor3 = C.Muted
	end
end

-- Rolle mit Skins füllen. winner: Platz des Gewinns (3D-Vorschau nur am Anfang und rund um den Gewinn, dazwischen zieht
-- die Rolle zu schnell vorbei, um mehr als die Farbe zu sehen)
local function fillStrip(ids, winner)
	for _, child in window.Strip:GetChildren() do
		child:Destroy()
	end
	window.Strip.Size = UDim2.fromOffset(#ids * STEP, VIEW_H)
	window.Tiles = {}
	for index, id in ids do
		local preview = winner == nil or index <= 8 or math.abs(index - winner) <= 6
		window.Tiles[index] = tile(window.Strip, id, index, preview)
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

-- Fenster beben lassen (ab Episch)
local function shake(frame, seconds, strength)
	local base = frame.Position
	local began = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if t >= seconds or not frame.Parent then
			connection:Disconnect()
			if frame.Parent then
				frame.Position = base
			end
			return
		end
		local k = strength * (1 - t / seconds)
		frame.Position = base + UDim2.fromOffset(math.random(-100, 100) / 100 * k, math.random(-100, 100) / 100 * k)
	end)
end

-- Funken: kleine Splitter fliegen aus der Mitte von parent nach außen, drehen sich und verblassen
local function burst(parent, color, count, zIndex)
	local random = Random.new()
	for _ = 1, count do
		local white = random:NextNumber() < 0.3
		local bit = make("Frame", { Name = "Spark", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(random:NextInteger(5, 9), random:NextInteger(10, 18)), Rotation = random:NextInteger(0, 360),
			BackgroundColor3 = white and Color3.new(1, 1, 1) or color, BorderSizePixel = 0, ZIndex = zIndex }, parent)
		local angle = random:NextNumber() * math.pi * 2
		local distance = random:NextNumber(220, 460)
		local time = random:NextNumber(0.9, 1.6)
		TweenService:Create(bit, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance * 0.75),
			Rotation = bit.Rotation + random:NextInteger(-540, 540), BackgroundTransparency = 1 }):Play()
		task.delay(time + 0.1, function()
			bit:Destroy()
		end)
	end
end

-- Klang je Seltenheit (gleiche Aufnahmen wie die Show am Glücksrad)
local function winSound(rank)
	Sfx.UI("CrateWin", { Pitch = rank >= 3 and 0.9 or 1.15 })
	if rank >= 2 then
		Sfx.UI("CrateCoins")
	end
	if rank >= 3 then
		Sfx.UI("CrateBoom")
		task.delay(0.25, Sfx.UI, "CrateWinBig")
	end
	if rank >= 4 then
		task.delay(0.5, Sfx.UI, "CrateWin", { Pitch = 1.25 })
		task.delay(0.8, Sfx.UI, "CrateWinBig", { Pitch = 1.2 })
	end
end

-- Gewinn-Karte nach der Rolle: Strahlenkranz, Funken, Karte springt auf
local function showResult(result)
	if not window then
		return
	end
	local item = Cosmetics.Get(result.Item)
	if not item then
		return
	end
	window.ResultShown = true
	local rarity = rarityOf(item)
	local color = rarity and rarity.Color or C.Border
	local rank = RANK[item.Rarity] or 1
	-- Active: fängt Klicks ab (sonst kauft ein Klick/A auf das ÖFFNEN darunter gleich die nächste Kiste)
	local overlay = make("Frame", { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background, BackgroundTransparency = 1,
		ZIndex = 20, Active = true, ClipsDescendants = true }, window.Frame)
	UITheme.Corner(overlay, UITheme.Radius.XL)
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.12 }):Play()

	-- Lichthof und Strahlen hinter der Karte (drehen sich, je seltener desto mehr und schneller)
	local halo = make("Frame", { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 760), BackgroundColor3 = color, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 20 }, overlay)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, halo)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5,
		({ 0.9, 0.82, 0.74, 0.62 })[rank]), NumberSequenceKeypoint.new(1, 1) }) }, halo)
	local rays = make("Frame", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1100, 1100), BackgroundTransparency = 1, ZIndex = 20 }, overlay)
	local rayCount = ({ 8, 10, 14, 18 })[rank]
	for k = 1, rayCount do
		local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, Rotation = (k - 1) * 180 / rayCount, ZIndex = 20 }, rays)
		local ray = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, ({ 22, 30, 40, 52 })[rank], 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 20 }, holder)
		make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, ({ 0.9, 0.84, 0.78, 0.7 })[rank]), NumberSequenceKeypoint.new(1, 1) }) }, ray)
	end
	local raySpeed = ({ 6, 8, 11, 16 })[rank]
	local spin = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation = (rays.Rotation + dt * raySpeed) % 360
	end)
	overlay.Destroying:Connect(function()
		spin:Disconnect()
	end)
	if rank >= 2 then
		burst(overlay, color, ({ 0, 22, 40, 64 })[rank], 22)
	end
	if rank >= 4 then
		task.delay(0.45, function()
			if overlay.Parent then
				burst(overlay, Color3.new(1, 1, 1):Lerp(color, 0.5), 40, 22)
			end
		end)
	end

	local card = UITheme.Card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 460),
		ZIndex = 21 }, overlay)
	UITheme.Stroke(card, color, rank >= 3 and 2 or 1, rank >= 2 and 0.1 or 0.5)
	UITheme.AccentBar(card, color, { Thickness = 5, ZIndex = 22 })
	UITheme.Corner(glow(card, color, { Name = "CardGlow", Size = UDim2.new(1, 0, 0, 260), ZIndex = 21 }, ({ 0.92, 0.85, 0.78, 0.7 })[rank], 90),
		UITheme.Radius.XL)
	local scale = make("UIScale", { Scale = 0.4 }, card)
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	label({ Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 20), Text = upper(rarity and rarity.Name or ""), TextSize = 17,
		Font = F.Bold, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 }, card)
	local name = label({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 50), Text = upper(item.Name), TextSize = 46,
		Font = F.Display, TextColor3 = rank >= 2 and color:Lerp(Color3.new(1, 1, 1), 0.25) or C.Text,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 }, card)
	if rank >= 4 then
		-- Glanz läuft immer wieder über den Namen
		local shimmer = make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 244, 200)),
			ColorSequenceKeypoint.new(0.55, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)) }),
			Offset = Vector2.new(-1, 0) }, name)
		TweenService:Create(shimmer, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.6),
			{ Offset = Vector2.new(1, 0) }):Play()
	end
	local view = ItemPreview.New(card, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 98), Size = UDim2.fromOffset(440, 180),
		ZIndex = 22 })
	ItemPreview.Show(view, item, 440 / 180)
	local text, textColor
	if result.Status == "new" then
		text, textColor = "NEU FREIGESCHALTET", C.Good
	elseif result.Status == "copy" then
		text, textColor = "WEITERES STÜCK  ·  HANDELBAR IM MARKT (RAP-WERT " .. format(RapConfig.Value(item.Id) or 0) .. ")", C.Rap
	else
		text, textColor = "SCHON BESESSEN  ·  +" .. format(result.Refund or 0) .. " MÜNZEN ZURÜCK", C.Primary
	end
	label({ Position = UDim2.fromOffset(20, 290), Size = UDim2.new(1, -40, 0, 40), Text = text, TextSize = 17, Font = F.Bold, TextColor3 = textColor,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 }, card)
	local crate = window.Crate
	local again = UITheme.Chunky({ Position = UDim2.fromOffset(28, 372), Size = UDim2.fromOffset(330, 60), Color = crate.Color,
		Text = "NOCHMAL  ·  " .. (crate.Product and priceText(crate) or format(crate.Price)), TextSize = 21, TextColor = C.OnLight, ZIndex = 22 }, card, function()
		overlay:Destroy()
		CrateClient.Request()
	end)
	if not affordable(crate) then
		again.SetColor(C.MutedBack, C.Bad)
		again.SetText("ZU WENIG MÜNZEN")
	end
	local frame = window.Frame
	local ok = UITheme.Chunky({ Position = UDim2.fromOffset(374, 372), Size = UDim2.fromOffset(198, 60), Color = C.Card,
		StrokeColor = C.Border, Text = "OK", TextSize = 21, ZIndex = 22 }, card, function()
		overlay:Destroy()
		InputActions.Refocus(frame) -- Controller: zurück auf ÖFFNEN
	end)
	InputActions.Focus(overlay, ok.Button) -- Controller: A schließt die Karte statt neu zu kaufen
	window.Crate3D.Pop()
	winSound(rank)
end

-- Rolle abspielen: Skins ziehen vorbei, die Rolle bremst und bleibt auf dem Gewinn stehen, dann die Show
local function spin(result)
	local win = window
	-- ein zweites Ergebnis (spät nach „Keine Antwort“): die alte Rolle sauber beenden
	if win.Connection then
		win.Connection:Disconnect()
		win.Connection = nil
	end
	if win.Tween then
		win.Tween:Cancel()
		win.Tween = nil
	end
	win.Generation += 1
	if win.Result and not win.ResultShown then -- noch nicht gezeigter Gewinn (spätes Ergebnis): nicht stillschweigend verlieren
		announce(win.Result)
	end
	win.Result = result
	win.ResultShown = false -- sonst meldet Schließen während NOCHMAL den neuen Gewinn nicht
	win.Spinning = true
	setOpenButton()
	win.Status.Text = ""
	fillStrip(result.Reel, result.Index)
	Sfx.UI("CrateRoll")
	local random = Random.new()
	local center = (result.Index - 1) * STEP + TILE_W / 2 + random:NextInteger(-math.floor(TILE_W * 0.32), math.floor(TILE_W * 0.32))
	local finalX = VIEW_W / 2 - center
	win.Strip.Position = UDim2.fromOffset(VIEW_W / 2 - TILE_W / 2, 0)
	local generation = win.Generation
	local quick = CrateConfig.Quick(player)
	local spinTime = quick and CrateConfig.QuickSpinTime or CrateConfig.SpinTime
	local lastIndex, lastX, focus = 0, win.Strip.Position.X.Offset, nil
	local crateFrame = win.Crate3D.Frame
	win.Connection = RunService.RenderStepped:Connect(function(dt)
		if not window or window ~= win then
			return
		end
		local x = win.Strip.Position.X.Offset
		local speed = math.abs(x - lastX) / math.max(dt, 1 / 240) -- Pixel pro Sekunde
		lastX = x
		local index = math.floor((VIEW_W / 2 - x) / STEP) + 1
		if index ~= lastIndex then
			lastIndex = index
			-- Klacken: schnell hell, zum Schluss tiefer und lauter
			Sfx.UI("CrateTick", { Pitch = 0.8 + math.min(speed / 4000, 1) * 0.6, Volume = 0.7 + (1 - math.min(speed / 4000, 1)) * 0.5 })
			-- Kachel unter der Markierung hebt sich ab (heller Rand; nicht größer, sonst ragt sie über die Nachbarn)
			if focus then
				focus.UIStroke.Transparency = 0.45
			end
			focus = win.Tiles[index]
			if focus then
				focus.UIStroke.Transparency = 0
			end
		end
		crateFrame.Rotation = math.sin(os.clock() * 38) * math.min(speed / 1500, 1) * 6 -- Kiste rüttelt, solange es schnell geht
	end)
	local tween = TweenService:Create(win.Strip, TweenInfo.new(spinTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(finalX, 0) })
	win.Tween = tween
	tween.Completed:Connect(function(state)
		if state ~= Enum.PlaybackState.Completed or window ~= win or win.Generation ~= generation then
			return
		end
		if win.Connection then
			win.Connection:Disconnect()
			win.Connection = nil
		end
		crateFrame.Rotation = 0
		local item = Cosmetics.Get(result.Item)
		local rank = item and RANK[item.Rarity] or 1
		local color = item and rarityOf(item) and rarityOf(item).Color or C.Primary
		Sfx.UI("CrateStop")
		-- Gewinn leuchtet, die anderen werden dunkel, die Markierung blendet aus (lief sonst mitten durch den Gewinn),
		-- Blitz über der Rolle
		TweenService:Create(win.Marker, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		for index, other in win.Tiles do
			if index ~= result.Index then
				other.UIStroke.Transparency = 0.45
				TweenService:Create(other.Dim, TweenInfo.new(0.35), { BackgroundTransparency = 0.45 }):Play()
			end
		end
		local winner = win.Tiles[result.Index]
		if winner then
			local stroke = winner:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = color
				stroke.Thickness = 3
				stroke.Transparency = 0
			end
			local shine = winner:FindFirstChild("Shine")
			local gradient = shine and shine:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.85) })
			end
		end
		local flash = make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 0.3,
			BorderSizePixel = 0, ZIndex = 10 }, win.Reel)
		TweenService:Create(flash, TweenInfo.new(0.5 + rank * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
		task.delay(1.4, function()
			flash:Destroy()
		end)
		win.ReelGlow.BackgroundColor3 = color
		TweenService:Create(win.ReelGlow, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
		local delay = quick and CrateConfig.QuickResultDelay or CrateConfig.ResultDelay
		if rank >= 3 then -- Spannung: Rauschen, das Fenster bebt kurz
			Sfx.UI("CrateRise", { Pitch = rank >= 4 and 0.6 or 0.75 })
			shake(win.Frame, 0.45, rank >= 4 and 7 or 4)
			delay += quick and 0.2 or 0.5
		end
		win.Spinning = false
		win.Tween = nil
		setOpenButton()
		task.delay(delay, function()
			if window == win and win.Generation == generation then
				showResult(result)
			end
		end)
	end)
	tween:Play()
end

-- Rolle zurück in den Ruhezustand (Schein vom letzten Gewinn weg, Markierung wieder da)
resetReel = function()
	TweenService:Create(window.ReelGlow, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	window.Marker.BackgroundTransparency = 0
end

-- Kiste beim Server öffnen (der Server antwortet mit CrateResult)
function CrateClient.Request()
	if not window or window.Spinning or window.Waiting or window.Frame:FindFirstChild("Result") then
		return -- (Ergebniskarte offen: erst schließen; NOCHMAL entfernt sie vorher)
	end
	local crate = window.Crate
	if not PaidRandom.ShowRandom(player) then
		window.Status.Text = "Kisten gibt es in deinem Land nicht. Skins kannst du im Shop direkt kaufen."
		window.Status.TextColor3 = C.Bad
		return
	end
	if crate.Product then
		-- Robux-Kiste: Kauf bei Roblox, das Ergebnis schickt der Server nach dem Kauf (RobuxService); Admins in Studio gratis
		local product = RobuxConfig.Product(crate.Product)
		if product and product.ProductId ~= 0 and PaidRandom.OfferRandom(player) then
			resetReel()
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
			return
		elseif not LoginConfig.AdminFreeSpins(player, RunService:IsStudio()) then
			window.Status.Text = "Die ROBUX-KISTE kommt bald."
			window.Status.TextColor3 = C.Muted
			return
		end
	elseif coins() < crate.Price then
		window.Status.Text = "Nicht genug Münzen – " .. format(crate.Price) .. " nötig."
		window.Status.TextColor3 = C.Bad
		return
	end
	window.Waiting = true
	window.Status.Text = ""
	window.Open.SetText("ÖFFNET …")
	window.Open.SetColor(C.MutedBack, C.Muted)
	resetReel()
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
		Size = UDim2.fromOffset(WIN_W, WIN_H), BackgroundTransparency = 0.02, ZIndex = 5 }, root)
	UITheme.PhoneFit(frame, WIN_W, WIN_H, 0.55)
	UITheme.AccentBar(frame, crate.Color, { ZIndex = 6 })
	-- Schein der Kistenfarbe oben im Fenster
	local sheen = glow(frame, crate.Color, { Name = "Sheen", Size = UDim2.new(1, 0, 0, 240), ZIndex = 5 }, 0.84, 90)
	UITheme.Corner(sheen, UITheme.Radius.XL)

	-- Kopf: 3D-Kiste, Name, Münzen, QUICKSPIN, schließen
	local crate3d = KitCrate.View(frame, { Color = crate.Color, Style = "Gold", ZIndex = 6, Size = UDim2.fromOffset(100, 96),
		Position = UDim2.fromOffset(16, 6) })
	label({ Position = UDim2.fromOffset(122, 18), Size = UDim2.new(1, -420, 0, 42), Text = crate.Name, TextSize = 38, Font = F.Display, ZIndex = 6 }, frame)
	label({ Position = UDim2.fromOffset(122, 60), Size = UDim2.new(1, -420, 0, 18), Text = crate.Sub .. "  ·  EIN SKIN PRO KISTE", TextSize = 13,
		Font = F.Bold, TextColor3 = crate.Color, ZIndex = 6 }, frame)
	local close = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(44, 44),
		Color = C.Card, StrokeColor = C.Border, Text = "", ZIndex = 6 }, frame, closeWindow)
	close.Button:SetAttribute("NoFocus", true) -- Controller: schließen mit ○
	UITheme.Cross(close.Face, 14, C.Text, 2).ZIndex = 6
	local coinsLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -76, 0, 22), Size = UDim2.fromOffset(240, 26), Text = "",
		TextSize = 21, Font = F.Display, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 }, frame)
	local quick = UITheme.Chunky({ Name = "QuickSpin", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -76, 0, 54),
		Size = UDim2.fromOffset(240, 30), Color = crate.Color, Text = "QUICKSPIN", TextSize = 13, TextColor = C.OnLight, ZIndex = 6 },
		frame, buyQuickSpin)
	quick.Button:SetAttribute("NoFocus", true)

	-- Rolle: dunkle Bahn, Schein in der Mitte, rote Markierung mit Spitzen oben und unten, Ränder abgedunkelt
	local reel = make("Frame", { Name = "Reel", Position = UDim2.fromOffset(REEL_X, REEL_Y), Size = UDim2.fromOffset(VIEW_W, VIEW_H),
		BackgroundColor3 = C.Background, BackgroundTransparency = 0.05, ClipsDescendants = true, ZIndex = 5 }, frame)
	UITheme.Corner(reel, UITheme.Radius.Large)
	UITheme.Stroke(reel, crate.Color, 1, 0.55)
	local reelGlow = make("Frame", { Name = "ReelGlow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 360, 1, 0), BackgroundColor3 = crate.Color, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, reel)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.72),
		NumberSequenceKeypoint.new(1, 1) }) }, reelGlow)
	local strip = make("Frame", { Name = "Strip", Size = UDim2.fromOffset(100, VIEW_H), BackgroundTransparency = 1, ZIndex = 6 }, reel)
	local marker = make("Frame", { Name = "Marker", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = C.Primary, BorderSizePixel = 0, ZIndex = 12 }, reel)
	for _, edge in { 0, 1 } do
		UITheme.Diamond(reel, 14, UDim2.new(0.5, 0, edge, 0), C.Primary).ZIndex = 12 -- halbe Raute = Spitze
		local fade = make("Frame", { AnchorPoint = Vector2.new(edge, 0), Position = UDim2.new(edge, 0, 0, 0), Size = UDim2.new(0, 110, 1, 0),
			BackgroundColor3 = C.Background, BorderSizePixel = 0, ZIndex = 11 }, reel)
		make("UIGradient", { Transparency = NumberSequence.new(edge == 0 and { NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) }
			or { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.05) }) }, fade)
	end

	local status = label({ Position = UDim2.fromOffset(REEL_X, REEL_Y + VIEW_H + 6), Size = UDim2.fromOffset(VIEW_W, 20), Text = "", TextSize = 14,
		Font = F.Bold, TextColor3 = C.Bad, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, frame)

	-- Chancen je Seltenheit: Karte mit Schein in der Seltenheitsfarbe
	local y = REEL_Y + VIEW_H + 30
	label({ Position = UDim2.fromOffset(REEL_X, y), Size = UDim2.fromOffset(300, 18), Text = "CHANCEN", TextSize = 13, Font = F.Bold,
		TextColor3 = C.Muted, ZIndex = 6 }, frame)
	local x = REEL_X
	local odds = CrateConfig.Odds(crate)
	local chipW = math.floor((VIEW_W - 8 * (#odds - 1)) / math.max(#odds, 1))
	for _, entry in odds do
		local rarity = Cosmetics.Rarities[entry.Rarity]
		local chip = make("Frame", { Position = UDim2.fromOffset(x, y + 22), Size = UDim2.fromOffset(chipW, 40), BackgroundColor3 = C.Card,
			ZIndex = 6 }, frame)
		UITheme.Corner(chip, UITheme.Radius.Medium)
		UITheme.Stroke(chip, rarity.Color, 1, 0.35)
		local tint = glow(chip, rarity.Color, { Size = UDim2.fromScale(1, 1), ZIndex = 6 }, 0.8, 0)
		UITheme.Corner(tint, UITheme.Radius.Medium)
		label({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -96, 1, 0), Text = upper(rarity.Name), TextSize = 14, Font = F.Bold,
			TextColor3 = rarity.Color, ZIndex = 7 }, chip)
		label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(84, 40),
			Text = string.format("%.1f %%", entry.Chance * 100), TextSize = 18, Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 7 }, chip)
		x += chipW + 8
	end

	-- Inhalt der Kiste
	y += 74
	label({ Position = UDim2.fromOffset(REEL_X, y), Size = UDim2.fromOffset(400, 18), Text = "DAS STECKT DRIN  ·  CHANCE JE SKIN", TextSize = 13,
		Font = F.Bold, TextColor3 = C.Muted, ZIndex = 6 }, frame)
	label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(REEL_X + VIEW_W, y), Size = UDim2.fromOffset(460, 18),
		Text = PaidRandom.Note, TextSize = 11, Font = F.Medium, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 }, frame)
	local itemOdds = CrateConfig.ItemOdds(crate)
	local listTop = y + 22
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(REEL_X, listTop), Size = UDim2.fromOffset(VIEW_W, WIN_H - listTop - 96),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 6 }, frame)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(math.floor((VIEW_W - 8 - 3 * 8) / 4), 52), CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder }, list)
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
		local cell = make("Frame", { LayoutOrder = index, BackgroundColor3 = C.Card, ZIndex = 6 }, list)
		UITheme.Corner(cell, UITheme.Radius.Small)
		UITheme.AccentBar(cell, rarity.Color, { Side = "Left", Thickness = 4, ZIndex = 6 })
		local swatch = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = item.Color or rarity.Color, BorderSizePixel = 0, ZIndex = 7 }, cell)
		UITheme.Corner(swatch, UITheme.Radius.Small)
		UITheme.Stroke(swatch, rarity.Color, 1, 0.3)
		label({ Position = UDim2.fromOffset(50, 6), Size = UDim2.new(1, -56, 0, 22), Text = upper(item.Name), TextSize = 15, Font = F.Display,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 }, cell)
		local value = RapConfig.Value(item.Id)
		label({ Position = UDim2.fromOffset(50, 29), Size = UDim2.new(1, -56, 0, 16), TextSize = 11, Font = F.Bold, TextColor3 = value and C.Rap or C.Muted,
			Text = PaidRandom.Percent(itemOdds[item.Id]) .. (value and ("  ·  RAP " .. format(value)) or ""), TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 7 }, cell)
	end

	local openButton = UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(460, 62),
		Color = crate.Color, Text = "ÖFFNEN", TextSize = 23, TextColor = C.OnLight, ZIndex = 6 }, frame, function()
		CrateClient.Request()
	end)
	-- Knopf atmet, solange man öffnen kann
	local pulse = make("UIStroke", { Color = crate.Color, Thickness = 0, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		openButton.Button)
	TweenService:Create(pulse, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Thickness = 4, Transparency = 0.7 }):Play()
	window = { Crate = crate, Frame = frame, Strip = strip, Reel = reel, ReelGlow = reelGlow, Marker = marker, Open = openButton, Status = status,
		CoinsLabel = coinsLabel, Quick = quick, Crate3D = crate3d, Spinning = false, Generation = 0, Tiles = {} }
	UITheme.SetBlur("Crate", true)
	fillStrip(idleIds(crate))
	strip.Position = UDim2.fromOffset(TILE_GAP * 2, 0)
	setOpenButton()
	InputActions.Focus(frame, openButton.Button) -- Controller: gleich auf ÖFFNEN
	Sfx.UI("CrateRoll", { Pitch = 0.85, Volume = 0.6 })
	return window
end

function CrateClient.Open(crateId)
	local crate = CrateConfig.Get(crateId)
	if crate then
		build(crate)
	end
end

-- ---------- Automat in der Welt ----------
-- Bei jedem Gewinn (Attribut OpenCount an CrateWeapon, OpenRarity = Seltenheit) klappt der Deckel auf (Scharnier hinten
-- oben), innen leuchtet es in der Seltenheitsfarbe, Funken steigen auf; nach kurzer Zeit klappt er wieder zu.
local OPEN_ANGLE = math.rad(68)

-- Namensendung der Automaten-Teile: Waffen-Kiste ohne (CrateMachineLid), sonst "_<Id>" (CrateMachineLid_Robux)
function CrateClient.MachineSuffix(crateId)
	return crateId == "Weapon" and "" or "_" .. crateId
end

local function setupMachine(machine, suffix)
	local folder = machine.Parent
	local lid = folder and folder:FindFirstChild("CrateMachineLid" .. suffix)
	local glowPart = folder and folder:FindFirstChild("CrateMachineGlow" .. suffix)
	if not lid or not lid:IsA("BasePart") then
		return
	end
	local parts = {}
	for _, name in { "CrateMachineLid", "CrateMachineLidTop" } do
		local p = folder:FindFirstChild(name .. suffix)
		if p and p:IsA("BasePart") then
			parts[p] = p.CFrame
		end
	end
	-- Scharnier: hintere Oberkante des Deckels (Front zeigt nach lokal -Z)
	local hinge = lid.CFrame * CFrame.new(0, -lid.Size.Y / 2, lid.Size.Z / 2)
	local light = glowPart and glowPart:FindFirstChildOfClass("PointLight")
	local sparks
	if glowPart then
		sparks = make("ParticleEmitter", { Name = "Sparks", Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = 0,
			Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(30, 30),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -8, 0), LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, glowPart)
	end
	local playing = 0
	local function setAngle(angle)
		local turn = hinge * CFrame.Angles(angle, 0, 0) * hinge:Inverse()
		for p, base in parts do
			p.CFrame = turn * base
		end
	end
	machine:GetAttributeChangedSignal("OpenCount"):Connect(function()
		local rarity = Cosmetics.Rarities[machine:GetAttribute("OpenRarity") or ""]
		local rank = RANK[machine:GetAttribute("OpenRarity") or ""] or 1
		local color = rarity and rarity.Color or C.Gold
		playing += 1
		local mine = playing
		if light then
			light.Color = color
			light.Brightness = 1 + rank * 0.9
			TweenService:Create(light, TweenInfo.new(2 + rank * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 0 }):Play()
		end
		if sparks then
			sparks.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
			sparks:Emit(({ 10, 22, 45, 90 })[rank])
		end
		if glowPart then
			Sfx.At(rank >= 3 and "CrateWinBig" or "CrateWin", glowPart, { Volume = 0.7 })
		end
		local t = 0
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			if playing ~= mine then
				connection:Disconnect()
				return
			end
			t += dt
			local angle
			if t < 0.35 then -- auf (federt leicht über)
				local k = t / 0.35
				angle = OPEN_ANGLE * (1 - (1 - k) ^ 3) * (1 + 0.12 * math.sin(k * math.pi))
			elseif t < 2.2 + rank * 0.3 then
				angle = OPEN_ANGLE
			elseif t < 2.7 + rank * 0.3 then -- zu
				local k = (t - 2.2 - rank * 0.3) / 0.5
				angle = OPEN_ANGLE * (1 - k * k)
			else
				angle = 0
				connection:Disconnect()
			end
			setAngle(angle)
		end)
	end)
end

function CrateClient.Init()
	gui = make("ScreenGui", { Name = "Crates", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 13,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	root = UITheme.ScaledRoot(gui, nil, nil, 0.55)

	-- Automat im Camp (Gruppe Zentrale der Map Extinction): Part "Crate<Kisten-Id>" (Waffen-Kiste: "CrateWeapon")
	for _, crate in CrateConfig.Crates do
		task.spawn(function()
			local machine = Zentrale.Part("Crate" .. crate.Id, 60)
			if machine then
				local prompt = Instance.new("ProximityPrompt")
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
				prompt.ActionText = "Kiste öffnen"
				prompt.ObjectText = crate.Name .. "  ·  " .. (crate.Product and priceText(crate) or (crate.Price .. " Münzen"))
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Parent = machine
				prompt.Triggered:Connect(function()
					CrateClient.Open(crate.Id)
				end)
				setupMachine(machine, CrateClient.MachineSuffix(crate.Id))
			end
		end)
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
	player:GetAttributeChangedSignal("PaidRandomOk"):Connect(setOpenButton)
	player:GetAttributeChangedSignal("Pass_" .. CrateConfig.QuickSpinPass):Connect(setOpenButton)
	local function onPlaceChanged()
		if window and not Modes.InLounge(player) then
			closeWindow()
		end
	end
	player:GetAttributeChangedSignal("Mode"):Connect(onPlaceChanged)
	player:GetAttributeChangedSignal("InSafeZone"):Connect(onPlaceChanged)
	UserInputService.InputBegan:Connect(function(input, processed)
		if window and (input.KeyCode == Enum.KeyCode.ButtonB or (input.KeyCode == Enum.KeyCode.Escape and not processed)) then
			closeWindow()
		end
	end)
end

return CrateClient
