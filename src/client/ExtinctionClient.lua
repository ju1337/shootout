-- ExtinctionClient (ModuleScript, nur Client)
-- Oberfläche der offenen Welt (EXTINCTION):
--   HUD: Hotbar unten (Plätze 1-9, Waffe in der Hand hervorgehoben, Fahrzeug draußen / Wartezeit), Anzeige oben
--        (SAFE ZONE · PVP IN 3 S · PVP AKTIV), Münzen, Meldungen, Balken beim Benutzen (Verband, Weste)
--   Tasten: 1-9 Hotbar benutzen, TAB Inventar, K Fahrzeug einpacken, E an Ständen/Lager/Taschen (ProximityPrompt)
--   Controller: R1/L1 nächste/vorige Waffe der Hotbar, Select = Inventar, △ = Fahrzeug einpacken
--   Fenster: Inventar (TAB), Stand (kaufen links, verkaufen rechts), Lager (Tasche links, Lager rechts),
--            Tasche am Boden (Inhalt links, eigene Tasche rechts)
-- Items ziehen und ablegen (Maus) oder anklicken und dann den Zielplatz anklicken; Rechtsklick legt ein Item
-- zwischen Hotbar und Tasche hin und her. Der Server prüft alles (InventoryService, LootService).
-- Daten: Spieler-Attribute ExtBag, ExtStash, ExtEquipped, ExtVehicle, ExtVehicleReadyAt, InSafeZone, PvP, PvPAt,
-- Coins; Remotes.ExtUpdate ("Status", "Loot", "LootClosed", "UseStart", "UseEnd").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local GunModels = require(Shared.GunModels)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label
local upper = UITheme.Upper

local ExtinctionClient = {}

local HOTBAR = ExtinctionConfig.HotbarSlots
local BAG = ExtinctionConfig.BagSlots
local STASH = ExtinctionConfig.StashSlots
local SAFE = Color3.fromRGB(112, 200, 120)
local DANGER = Color3.fromRGB(215, 85, 45)
local KIND_COLORS = {
	Weapon = Color3.fromRGB(196, 150, 80),
	Ammo = Color3.fromRGB(176, 150, 96),
	Heal = Color3.fromRGB(206, 86, 76),
	Armor = Color3.fromRGB(96, 150, 196),
	Vehicle = Color3.fromRGB(112, 178, 112),
}
local KIND_NAMES = { Weapon = "WAFFE", Ammo = "MUNITION", Heal = "HEILUNG", Armor = "RÜSTUNG", Vehicle = "FAHRZEUG" }
local MOUSE_PRIORITY = 201 -- direkt nach der Kamera (Enum.RenderPriority.Camera.Value + 1): Maus frei, solange ein Fenster offen ist

local bag, stash = {}, {} -- [Platz] = { Id, N, Mag, Out }
local equipped = 0
local hud, root, windowGui, canvas
local window = nil -- { Kind, Frame, Refresh, Stand, Loot }
local selected = nil -- { Container, Slot }
local drag = nil -- { Container, Slot, Start, Ghost, Moved }
local hovered = nil -- { Container, Slot }

local function inExtinction()
	return Modes.IsSurvival(player:GetAttribute("Mode"))
end

local function decodeList(text)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, text or "[]")
	local result = {}
	if ok and type(list) == "table" then
		for _, entry in list do
			if type(entry) == "table" and type(entry.S) == "number" then
				result[entry.S] = entry
			end
		end
	end
	return result
end

local function itemConfig(id)
	return ExtinctionConfig.Get(id)
end

local function sendAction(...)
	Remotes.ExtAction:FireServer(...)
end

-- ---------- Symbole ----------

-- Kleine 3D-Waffe (ViewportFrame) bzw. gezeichnetes Symbol für Munition, Heilung, Rüstung, Fahrzeug
local function buildIcon(parent, id, zIndex)
	local config = itemConfig(id)
	local holder = make("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.86, 0.62), BackgroundTransparency = 1, ZIndex = zIndex }, parent)
	if not config then
		return holder
	end
	local color = KIND_COLORS[config.Kind] or C.Muted
	if config.Kind == "Weapon" and GunModels.Info[config.Weapon] then
		local view = make("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = zIndex,
			Ambient = Color3.fromRGB(150, 150, 160), LightColor = Color3.fromRGB(255, 245, 235),
			LightDirection = Vector3.new(-0.5, -1, 0.6) }, holder)
		local ok, model = pcall(GunModels.Build, config.Weapon)
		if ok and model then
			model.Parent = view
			local box, size = model:GetBoundingBox()
			local camera = Instance.new("Camera")
			camera.FieldOfView = 30
			local distance = math.max(size.Z, size.Y * 2.2) / 2 / math.tan(math.rad(15)) * 1.05 + size.X / 2
			camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(distance, distance * 0.12, 0), box.Position)
			camera.Parent = view
			view.CurrentCamera = camera
		end
	elseif config.Kind == "Ammo" then
		for k = -1, 1 do
			local shell = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, k * 9, 0.55, 0),
				Size = UDim2.fromOffset(6, 18), BackgroundColor3 = Color3.fromRGB(198, 160, 84), BorderSizePixel = 0,
				ZIndex = zIndex }, holder)
			UITheme.Corner(shell, 3)
			make("Frame", { Position = UDim2.fromOffset(0, -5), Size = UDim2.fromOffset(6, 7), BackgroundColor3 = Color3.fromRGB(150, 110, 70),
				BorderSizePixel = 0, ZIndex = zIndex }, shell)
		end
	elseif config.Kind == "Heal" then
		local box = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(24, 24), BackgroundColor3 = id == "Adrenaline" and Color3.fromRGB(230, 200, 80)
				or Color3.fromRGB(232, 232, 232), BorderSizePixel = 0, ZIndex = zIndex }, holder)
		UITheme.Corner(box, 5)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 4),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = zIndex }, box)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 14),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = zIndex }, box)
	elseif config.Kind == "Armor" then
		local vest = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromOffset(id == "HeavyVest" and 26 or 22, 26), BackgroundColor3 = Color3.fromRGB(70, 84, 72),
			BorderSizePixel = 0, ZIndex = zIndex }, holder)
		UITheme.Corner(vest, 6)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -6, 0, 4),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = zIndex }, vest)
	elseif config.Kind == "Vehicle" then
		local vehicle = ExtinctionConfig.Vehicles[config.Vehicle]
		local body = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.fromOffset(34, 10), BackgroundColor3 = vehicle and vehicle.Color or color, BorderSizePixel = 0,
			ZIndex = zIndex }, holder)
		UITheme.Corner(body, 3)
		make("Frame", { Position = UDim2.fromOffset(8, -7), Size = UDim2.fromOffset(16, 8), BackgroundColor3 = Color3.fromRGB(60, 72, 80),
			BorderSizePixel = 0, ZIndex = zIndex }, body)
		for _, x in { 7, 27 } do
			local wheel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 11), Size = UDim2.fromOffset(9, 9),
				BackgroundColor3 = Color3.fromRGB(26, 26, 28), BorderSizePixel = 0, ZIndex = zIndex }, body)
			UITheme.Corner(wheel, 5)
		end
	end
	return holder
end

-- Kurzbeschreibung eines Items (für Details und Stände)
local function describe(id, entry)
	local config = itemConfig(id)
	if not config then
		return ""
	end
	if config.Kind == "Weapon" then
		local weapon = WeaponConfig.Get(config.Weapon)
		local ammo = itemConfig(config.Ammo)
		local mag = entry and entry.Mag or (weapon and weapon.MagazineSize)
		return string.format("Magazin %s/%d · %s · %d Schaden", tostring(mag or "?"), weapon and weapon.MagazineSize or 0,
			ammo and ammo.Name or "?", weapon and weapon.Damage or 0)
	elseif config.Kind == "Ammo" then
		local users = {}
		for _, other in ExtinctionConfig.Items do
			if other.Ammo == id then
				table.insert(users, other.Name)
			end
		end
		table.sort(users)
		return "Für " .. table.concat(users, ", ") .. (config.Pack and (" · Packung " .. config.Pack .. " Schuss") or "")
	elseif config.Kind == "Heal" then
		return "+" .. config.Heal .. " Leben · " .. string.gsub(tostring(config.UseTime), "%.", ",") .. " s"
			.. (config.Speed and " · kurz schneller" or "")
	elseif config.Kind == "Armor" then
		return "+" .. config.Armor .. " Rüstung · " .. string.gsub(tostring(config.UseTime), "%.", ",") .. " s"
	elseif config.Kind == "Vehicle" then
		local vehicle = ExtinctionConfig.Vehicles[config.Vehicle]
		return vehicle and ("Tempo " .. vehicle.Speed .. " · " .. vehicle.Health .. " Leben · " .. vehicle.Seats
			.. (vehicle.Seats == 1 and " Sitz" or " Sitze")) or ""
	end
	return ""
end

-- ---------- Plätze (Hotbar, Tasche, Lager, Tasche am Boden) ----------

local slotViews = {} -- [Container .. ":" .. Platz] = { Frame, Stroke, Content, Count, Key, Id, Overlay }

local function entryOf(container, slot)
	if container == "Bag" or container == "Hotbar" then
		return bag[slot]
	elseif container == "Stash" then
		return stash[slot]
	elseif container == "Loot" and window and window.Loot then
		for _, entry in window.Loot.Items do
			if entry.S == slot then
				return entry
			end
		end
	end
	return nil
end

-- Platz-Inhalt neu zeichnen (nur wenn sich Item oder Anzahl geändert haben)
local function paintSlot(view, entry, isSelected, isEquipped)
	local id = entry and entry.Id
	if view.Id ~= id then
		view.Id = id
		for _, child in view.Content:GetChildren() do
			child:Destroy()
		end
		if id then
			buildIcon(view.Content, id, view.Frame.ZIndex + 1)
		end
	end
	local config = id and itemConfig(id)
	local countText = ""
	if entry and entry.N and entry.N > 1 then
		countText = tostring(entry.N)
	elseif config and config.Kind == "Weapon" and entry.Mag then
		countText = tostring(entry.Mag)
	end
	view.Count.Text = countText
	view.Name.Text = config and upper(config.Name) or ""
	view.Overlay.Visible = entry ~= nil and entry.Out == true
	view.Stroke.Color = isSelected and C.Primary or (isEquipped and SAFE or (config and KIND_COLORS[config.Kind] or C.Border))
	view.Stroke.Thickness = (isSelected or isEquipped) and 2 or 1
	view.Stroke.Transparency = (isSelected or isEquipped) and 0 or (config and 0.45 or 0.7)
	view.Frame.BackgroundColor3 = isEquipped and Color3.fromRGB(34, 46, 38) or C.Card
end

local function repaint()
	for key, view in slotViews do
		if view.Frame.Parent then
			local entry = entryOf(view.Container, view.Slot)
			local isSelected = selected ~= nil and selected.Container == view.Container and selected.Slot == view.Slot
			local inBag = view.Container == "Bag" or view.Container == "Hotbar"
			paintSlot(view, entry, isSelected, inBag and view.Slot == equipped and entry ~= nil)
		else
			slotViews[key] = nil
		end
	end
end

local onSlotClick, onSlotDrop, onSlotRightClick -- unten gesetzt (je nach Fenster)

-- Ein Platz als Knopf. container = "Bag", "Stash", "Loot", "Hotbar" (HUD, nur benutzen)
local function slotButton(parent, container, slot, size, position, zIndex, keyText)
	local frame = make("TextButton", { Name = container .. slot, Size = size, Position = position or UDim2.new(), Text = "",
		AutoButtonColor = false, BackgroundColor3 = C.Card, BackgroundTransparency = 0.12, BorderSizePixel = 0, ZIndex = zIndex,
		LayoutOrder = slot }, parent)
	UITheme.Corner(frame, UITheme.Radius.Small)
	local stroke = UITheme.Stroke(frame, C.Border, 1, 0.6)
	local content = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = zIndex + 1 }, frame)
	local count = label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -5, 1, -3), Size = UDim2.fromOffset(40, 14),
		Text = "", TextSize = 12, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = zIndex + 3 }, frame)
	UITheme.Outline(count)
	local name = label({ Position = UDim2.new(0, 4, 1, -14), Size = UDim2.new(1, -30, 0, 12), Text = "", TextSize = 8,
		Font = F.Bold, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = zIndex + 3,
		Visible = size.X.Offset >= 70 }, frame)
	local key = nil
	if keyText then
		key = label({ Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(16, 14), Text = keyText, TextSize = 12,
			Font = F.Bold, TextColor3 = C.Muted, ZIndex = zIndex + 3 }, frame)
	end
	local overlay = label({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.35, BackgroundColor3 = C.Background,
		Text = "DRAUSSEN", TextSize = 10, Font = F.Bold, TextColor3 = SAFE, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = zIndex + 4, Visible = false }, frame)
	UITheme.Corner(overlay, UITheme.Radius.Small)
	local view = { Frame = frame, Stroke = stroke, Content = content, Count = count, Name = name, Key = key, Overlay = overlay,
		Container = container, Slot = slot }
	slotViews[container .. ":" .. slot .. ":" .. tostring(frame)] = view

	if container ~= "Hotbar" then
		frame.MouseButton1Down:Connect(function()
			-- Maus: Klick und Ziehen laufen über das Loslassen (endDrag), auch auf leeren Plätzen (Ziel wählen)
			if InputActions.Device() == "Keyboard" then
				drag = { Container = container, Slot = slot, Start = UserInputService:GetMouseLocation(), Moved = false }
			end
		end)
		frame.MouseEnter:Connect(function()
			hovered = { Container = container, Slot = slot }
		end)
		frame.MouseLeave:Connect(function()
			if hovered and hovered.Container == container and hovered.Slot == slot then
				hovered = nil
			end
		end)
		frame.MouseButton2Click:Connect(function()
			if onSlotRightClick then
				onSlotRightClick(container, slot)
			end
		end)
		frame.Activated:Connect(function(input)
			-- Maus: Klick-Logik läuft beim Loslassen (siehe Ziehen); Touch/Controller hier
			if input and input.UserInputType == Enum.UserInputType.MouseButton1 and InputActions.Device() == "Keyboard" then
				return
			end
			if onSlotClick then
				onSlotClick(container, slot)
			end
		end)
	end
	return view
end

-- ---------- HUD ----------

local zonePill, zoneText, coinsText, toast, toastId, useBar, useFill, useText, hints
local hotbarViews = {}
local vehicleCooldown

local function showToast(text, ok)
	toastId = (toastId or 0) + 1
	local id = toastId
	toast.Text = text
	toast.TextColor3 = ok and C.Good or C.Text
	toast.Visible = true
	task.delay(3.5, function()
		if toastId == id then
			toast.Visible = false
		end
	end)
end
ExtinctionClient.Toast = function(text, ok)
	if toast then
		showToast(text, ok)
	end
end

local function buildHud()
	hud = make("ScreenGui", { Name = "ExtinctionHUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	root = UITheme.ScaledRoot(hud)

	-- oben: Safe Zone / PvP
	zonePill = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(250, 30),
		BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, root)
	UITheme.Corner(zonePill, UITheme.Radius.Small)
	UITheme.Stroke(zonePill, SAFE, 1, 0.3)
	zoneText = label({ Size = UDim2.fromScale(1, 1), Text = "SAFE ZONE", TextSize = 18, Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = SAFE }, zonePill)

	-- unten: Hotbar
	local cell, gap = 64, 6
	local barWidth = HOTBAR * cell + (HOTBAR - 1) * gap
	local bar = make("Frame", { Name = "Hotbar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26),
		Size = UDim2.fromOffset(barWidth, cell), BackgroundTransparency = 1 }, root)
	for slot = 1, HOTBAR do
		local view = slotButton(bar, "Hotbar", slot, UDim2.fromOffset(cell, cell),
			UDim2.fromOffset((slot - 1) * (cell + gap), 0), 2, tostring(slot))
		view.Frame.Activated:Connect(function()
			sendAction("Use", slot)
		end)
		hotbarViews[slot] = view
	end
	vehicleCooldown = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -98), Size = UDim2.fromOffset(300, 18),
		Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, root)
	coinsText = label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -barWidth / 2 - 14, 1, -46),
		Size = UDim2.fromOffset(160, 22), Text = "", TextSize = 20, Font = F.Display, TextColor3 = C.Primary,
		TextXAlignment = Enum.TextXAlignment.Right }, root)
	label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -barWidth / 2 - 14, 1, -30), Size = UDim2.fromOffset(160, 14),
		Text = "MÜNZEN", TextSize = 10, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, root)
	hints = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(barWidth, 16),
		Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, root)

	-- Meldungen und Benutzen-Balken über der Hotbar
	toast = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -126), Size = UDim2.fromOffset(620, 22),
		Text = "", TextSize = 15, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Center, Visible = false }, root)
	UITheme.Outline(toast)
	useBar = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -158), Size = UDim2.fromOffset(240, 26),
		BackgroundColor3 = C.Panel, BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false }, root)
	UITheme.Corner(useBar, UITheme.Radius.Small)
	useFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Good, BackgroundTransparency = 0.4,
		BorderSizePixel = 0 }, useBar)
	UITheme.Corner(useFill, UITheme.Radius.Small)
	useText = label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 13, Font = F.Bold,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 }, useBar)
end

local function updateHints()
	if not hints then
		return
	end
	local device = InputActions.Device()
	if device == "Gamepad" then
		hints.Text = "R1 / L1  WAFFE  ·  SELECT  INVENTAR  ·  △  FAHRZEUG EINPACKEN"
	elseif device == "Touch" then
		hints.Text = "PLÄTZE ANTIPPEN ZUM BENUTZEN"
	else
		hints.Text = "1-9  BENUTZEN  ·  TAB  INVENTAR  ·  K  FAHRZEUG EINPACKEN  ·  E  INTERAGIEREN"
	end
end

local function updateZone()
	if not zonePill then
		return
	end
	local stroke = zonePill:FindFirstChildOfClass("UIStroke")
	if player:GetAttribute("InSafeZone") then
		zoneText.Text = "SAFE ZONE  ·  KEIN PVP"
		zoneText.TextColor3 = SAFE
		stroke.Color = SAFE
	elseif player:GetAttribute("PvP") then
		zoneText.Text = "PVP AKTIV"
		zoneText.TextColor3 = C.Bad
		stroke.Color = C.Bad
	else
		local left = math.max(0, (player:GetAttribute("PvPAt") or 0) - workspace:GetServerTimeNow())
		zoneText.Text = "PVP IN " .. math.ceil(left) .. " S"
		zoneText.TextColor3 = DANGER
		stroke.Color = DANGER
	end
end

-- ---------- Fenster ----------

local function closeWindow()
	if not window then
		return
	end
	if window.Kind == "Loot" and window.Loot then
		sendAction("LootClose", window.Loot.Id)
	end
	window.Frame:Destroy()
	window = nil
	selected = nil
	drag = nil
	windowGui.Enabled = false
	UITheme.SetBlur("Extinction", false)
	RunService:UnbindFromRenderStep("ExtinctionMouse")
	InputActions.Unfocus(canvas)
end
ExtinctionClient.Close = closeWindow

local function newWindow(kind, title, subtitle, accent)
	closeWindow()
	windowGui.Enabled = true
	local frame = UITheme.Card({ Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1180, 640), BackgroundTransparency = 0.04, ZIndex = 5 }, canvas)
	make("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = accent or C.Primary, BorderSizePixel = 0, ZIndex = 5 }, frame)
	label({ Position = UDim2.fromOffset(28, 16), Size = UDim2.new(1, -400, 0, 40), Text = title, TextSize = 34, Font = F.Display,
		ZIndex = 5 }, frame)
	local sub = label({ Position = UDim2.fromOffset(30, 54), Size = UDim2.new(1, -400, 0, 16), Text = subtitle or "", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, frame)
	local close = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(44, 44),
		Color = C.Card, StrokeColor = C.Border, Text = "", ZIndex = 5 }, frame, closeWindow)
	close.Button:SetAttribute("NoFocus", true)
	UITheme.Cross(close.Face, 14, C.Text, 2).ZIndex = 6
	local coins = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -80, 0, 24), Size = UDim2.fromOffset(220, 30),
		Text = "", TextSize = 24, Font = F.Display, TextColor3 = C.Primary, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }, frame)
	local body = make("Frame", { Name = "Body", Position = UDim2.fromOffset(28, 84), Size = UDim2.new(1, -56, 1, -108),
		BackgroundTransparency = 1, ZIndex = 5 }, frame)
	window = { Kind = kind, Frame = frame, Body = body, Coins = coins, Sub = sub }
	coins.Text = UITheme.FormatNumber(player:GetAttribute("Coins") or 0) .. " MÜNZEN"
	UITheme.SetBlur("Extinction", true)
	RunService:BindToRenderStep("ExtinctionMouse", MOUSE_PRIORITY, function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
	return window
end

local function sectionTitle(parent, text, position, width)
	return label({ Position = position, Size = UDim2.fromOffset(width or 400, 18), Text = text, TextSize = 12, Font = F.Bold,
		TextColor3 = C.Muted, ZIndex = 5 }, parent)
end

-- Raster aus Plätzen first..last eines Containers
local function grid(parent, container, first, last, columns, cell, gap, position, keys)
	local holder = make("Frame", { Position = position, Size = UDim2.fromOffset(columns * (cell + gap) - gap,
		math.ceil((last - first + 1) / columns) * (cell + gap) - gap), BackgroundTransparency = 1, ZIndex = 5 }, parent)
	for slot = first, last do
		local index = slot - first
		local column, row = index % columns, index // columns
		slotButton(holder, container, slot, UDim2.fromOffset(cell, cell),
			UDim2.fromOffset(column * (cell + gap), row * (cell + gap)), 6, keys and slot <= HOTBAR and tostring(slot) or nil)
	end
	return holder
end

-- Details zum gewählten Item (Inventar-Fenster)
local function detailsPanel(parent, position, size)
	local panel = make("Frame", { Position = position, Size = size, BackgroundColor3 = C.Card, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, ZIndex = 5 }, parent)
	UITheme.Corner(panel, UITheme.Radius.Medium)
	UITheme.Stroke(panel, C.Border, 1, 0.5)
	local iconHolder = make("Frame", { Position = UDim2.fromOffset(16, 16), Size = UDim2.new(1, -32, 0, 120),
		BackgroundTransparency = 1, ZIndex = 6 }, panel)
	local name = label({ Position = UDim2.fromOffset(18, 146), Size = UDim2.new(1, -36, 0, 28), Text = "", TextSize = 26,
		Font = F.Display, ZIndex = 6 }, panel)
	local kind = label({ Position = UDim2.fromOffset(18, 176), Size = UDim2.new(1, -36, 0, 14), Text = "", TextSize = 11,
		Font = F.Bold, TextColor3 = C.Muted, ZIndex = 6 }, panel)
	local info = label({ Position = UDim2.fromOffset(18, 196), Size = UDim2.new(1, -36, 0, 60), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Text, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6 }, panel)
	local buttons = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.new(1, -32, 0, 150),
		BackgroundTransparency = 1, ZIndex = 6 }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom }, buttons)
	local shownId = nil
	local function update(actions)
		local entry = selected and entryOf(selected.Container, selected.Slot)
		local id = entry and entry.Id
		if id ~= shownId then
			shownId = id
			iconHolder:ClearAllChildren()
			if id then
				local icon = buildIcon(iconHolder, id, 7)
				icon.Size = UDim2.fromScale(0.9, 0.9)
				icon.Position = UDim2.fromScale(0.5, 0.5)
			end
		end
		local config = id and itemConfig(id)
		name.Text = config and upper(config.Name) or "NICHTS GEWÄHLT"
		kind.Text = config and (KIND_NAMES[config.Kind] or "") .. ((entry.N or 1) > 1 and ("  ·  " .. entry.N .. " STÜCK") or "") or ""
		kind.TextColor3 = config and KIND_COLORS[config.Kind] or C.Muted
		info.Text = config and describe(id, entry) or "Klick ein Item an oder zieh es auf einen anderen Platz. Rechtsklick: "
			.. "zwischen Hotbar und Tasche hin und her."
		for _, child in buttons:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, action in actions or {} do
			UITheme.Chunky({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = i, Color = action.Primary and C.Primary or C.Panel,
				TextColor = action.Primary and C.PrimaryText or C.Text, StrokeColor = C.Border, Text = action.Text, TextSize = 16,
				ZIndex = 7 }, buttons, action.Run)
		end
	end
	return update
end

-- Erster freier Platz in [first, last] der Tasche
local function freeSlot(first, last)
	for slot = first, last do
		if not bag[slot] then
			return slot
		end
	end
	return nil
end

-- Item zwischen Hotbar und Tasche hin und her legen
local function quickSwap(slot)
	if slot <= HOTBAR then
		local target = freeSlot(HOTBAR + 1, BAG)
		if target then
			sendAction("Move", "Bag", slot, "Bag", target)
		end
	else
		local target = freeSlot(1, HOTBAR)
		if target then
			sendAction("Move", "Bag", slot, "Bag", target)
		else
			showToast("Die Hotbar ist voll.", false)
		end
	end
end

-- Standard-Verhalten der Plätze: anklicken = auswählen bzw. dorthin legen, ziehen = verschieben
local function defaultClick(container, slot)
	if selected and not (selected.Container == container and selected.Slot == slot) then
		local from = selected
		selected = nil
		if from.Container == "Loot" then
			if container == "Bag" then
				sendAction("Loot", window and window.Loot and window.Loot.Id, from.Slot)
			end
		else
			sendAction("Move", from.Container, from.Slot, container, slot)
		end
	elseif selected then
		selected = nil
	elseif entryOf(container, slot) then
		selected = { Container = container, Slot = slot }
	end
	if window and window.Refresh then
		window.Refresh()
	end
	repaint()
end

local function defaultDrop(fromContainer, fromSlot, toContainer, toSlot)
	selected = nil
	if fromContainer == "Loot" then
		if toContainer == "Bag" then
			sendAction("Loot", window and window.Loot and window.Loot.Id, fromSlot)
		end
		return
	end
	if toContainer == "Loot" then
		return
	end
	sendAction("Move", fromContainer, fromSlot, toContainer, toSlot)
end

-- INVENTAR (TAB): Tasche oben, Hotbar unten, Details rechts
local function openInventory()
	local win = newWindow("Inventory", "INVENTAR", "TASCHE " .. BAG .. " PLÄTZE  ·  1-9 = HOTBAR  ·  DRAUSSEN STERBEN = ALLES WEG",
		C.Primary)
	local body = win.Body
	local cell, gap = 78, 8
	sectionTitle(body, "TASCHE", UDim2.fromOffset(0, 0))
	grid(body, "Bag", HOTBAR + 1, BAG, 7, cell, gap, UDim2.fromOffset(0, 22))
	sectionTitle(body, "HOTBAR  ·  TASTEN 1-9", UDim2.fromOffset(0, 300))
	grid(body, "Bag", 1, HOTBAR, HOTBAR, cell - 18, gap, UDim2.fromOffset(0, 322), true)
	local update = detailsPanel(body, UDim2.fromOffset(700, 0), UDim2.fromOffset(424, 516))
	onSlotClick, onSlotDrop = defaultClick, defaultDrop
	onSlotRightClick = function(container, slot)
		if container == "Bag" and bag[slot] then
			quickSwap(slot)
		end
	end
	function win.Refresh()
		local actions = {}
		local entry = selected and selected.Container == "Bag" and bag[selected.Slot]
		if entry then
			local slot = selected.Slot
			if slot <= HOTBAR then
				table.insert(actions, { Text = "BENUTZEN  (" .. slot .. ")", Primary = true, Run = function()
					sendAction("Use", slot)
				end })
				table.insert(actions, { Text = "IN DIE TASCHE", Run = function()
					selected = nil
					quickSwap(slot)
				end })
			else
				table.insert(actions, { Text = "AUF DIE HOTBAR", Primary = true, Run = function()
					selected = nil
					quickSwap(slot)
				end })
			end
			table.insert(actions, { Text = "FALLEN LASSEN", Run = function()
				selected = nil
				sendAction("Drop", slot)
			end })
		end
		update(actions)
		repaint()
	end
	win.Refresh()
end

-- LAGER: Tasche links, Lager rechts; anklicken legt ins andere
local function openStash()
	local win = newWindow("Stash", "LAGER", "IMMER SICHER  ·  ANKLICKEN = HINÜBERLEGEN  ·  ZIEHEN = AUF EINEN PLATZ", Color3.fromRGB(226, 178, 52))
	local body = win.Body
	local cell, gap = 62, 7
	sectionTitle(body, "TASCHE  (1-9 = HOTBAR)", UDim2.fromOffset(0, 0))
	grid(body, "Bag", 1, BAG, 6, cell, gap, UDim2.fromOffset(0, 22), true)
	sectionTitle(body, "LAGER  ·  " .. STASH .. " PLÄTZE", UDim2.fromOffset(470, 0))
	grid(body, "Stash", 1, STASH, 8, cell, gap, UDim2.fromOffset(470, 22))
	onSlotClick = function(container, slot)
		if entryOf(container, slot) then
			sendAction("Move", container, slot, container == "Bag" and "Stash" or "Bag", nil)
		end
	end
	onSlotDrop = defaultDrop
	onSlotRightClick = onSlotClick
	function win.Refresh()
		repaint()
	end
	win.Refresh()
end

-- STAND: links kaufen, rechts verkaufen (eigene Tasche anklicken)
local function openStand(standKey)
	local stand = ExtinctionConfig.Stands[standKey]
	if not stand then
		return
	end
	local win = newWindow("Stand", stand.Title, "KAUFEN MIT MÜNZEN  ·  RECHTS EIN ITEM ANKLICKEN ZUM VERKAUFEN ("
		.. math.floor(ExtinctionConfig.SellFactor * 100) .. " %)", DANGER)
	win.Stand = standKey
	local body = win.Body
	sectionTitle(body, "ANGEBOT", UDim2.fromOffset(0, 0))
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 22), Size = UDim2.fromOffset(600, 494),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 5 }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, id in stand.Items do
		local config = itemConfig(id)
		local row = make("Frame", { Size = UDim2.new(1, -10, 0, 74), BackgroundColor3 = C.Card, BackgroundTransparency = 0.1,
			BorderSizePixel = 0, LayoutOrder = i, ZIndex = 5 }, list)
		UITheme.Corner(row, UITheme.Radius.Medium)
		UITheme.Stroke(row, KIND_COLORS[config.Kind] or C.Border, 1, 0.6)
		local iconBox = make("Frame", { Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(96, 62), BackgroundTransparency = 1,
			ZIndex = 6 }, row)
		local icon = buildIcon(iconBox, id, 6)
		icon.Size = UDim2.fromScale(1, 1)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		label({ Position = UDim2.fromOffset(114, 10), Size = UDim2.fromOffset(250, 26), Text = upper(config.Name)
			.. (config.Pack and ("  ×" .. config.Pack) or ""), TextSize = 21, Font = F.Display, ZIndex = 6 }, row)
		label({ Position = UDim2.fromOffset(114, 40), Size = UDim2.fromOffset(300, 28), Text = describe(id), TextSize = 11,
			Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6 }, row)
		local stack = (config.MaxStack or 1) > 1
		local function buy(qty)
			sendAction("Buy", standKey, id, qty)
		end
		UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, stack and -84 or -10, 0.5, 0),
			Size = UDim2.fromOffset(120, 44), Color = C.Primary, TextColor = C.PrimaryText, Text = tostring(config.Price),
			TextSize = 20, ZIndex = 6 }, row, function()
			buy(1)
		end)
		if stack then
			UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(66, 44),
				Color = C.Panel, StrokeColor = C.Border, Text = "×5", TextSize = 18, ZIndex = 6 }, row, function()
				buy(5)
			end)
		end
	end
	sectionTitle(body, "DEINE TASCHE  ·  ANKLICKEN = VERKAUFEN", UDim2.fromOffset(640, 0), 480)
	grid(body, "Bag", 1, BAG, 6, 64, 8, UDim2.fromOffset(640, 22), true)
	local sellInfo = label({ Position = UDim2.fromOffset(640, 400), Size = UDim2.fromOffset(470, 60), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5 }, body)
	local sellButtons = make("Frame", { Position = UDim2.fromOffset(640, 466), Size = UDim2.fromOffset(470, 48),
		BackgroundTransparency = 1, ZIndex = 5 }, body)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder }, sellButtons)
	onSlotClick = function(container, slot)
		if container == "Bag" and bag[slot] then
			selected = { Container = container, Slot = slot }
		else
			selected = nil
		end
		win.Refresh()
	end
	onSlotDrop = defaultDrop
	onSlotRightClick = function(container, slot)
		if container == "Bag" and bag[slot] then
			quickSwap(slot)
		end
	end
	function win.Refresh()
		win.Coins.Text = UITheme.FormatNumber(player:GetAttribute("Coins") or 0) .. " MÜNZEN"
		for _, child in sellButtons:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local entry = selected and selected.Container == "Bag" and bag[selected.Slot]
		if entry then
			local config = itemConfig(entry.Id)
			local slot = selected.Slot
			sellInfo.Text = upper(config.Name) .. (entry.N > 1 and ("  ×" .. entry.N) or "") .. "\nVerkauf: "
				.. ExtinctionConfig.SellPrice(entry.Id, 1) .. " pro Stück, alles " .. ExtinctionConfig.SellPrice(entry.Id, entry.N)
				.. " Münzen" .. (entry.Out and "\nDas Fahrzeug ist draußen – erst einpacken (K)." or "")
			if entry.N > 1 then
				UITheme.Chunky({ Size = UDim2.fromOffset(150, 44), LayoutOrder = 1, Color = C.Panel, StrokeColor = C.Border,
					Text = "1 VERKAUFEN", TextSize = 16, ZIndex = 6 }, sellButtons, function()
					sendAction("Sell", slot, 1)
				end)
			end
			UITheme.Chunky({ Size = UDim2.fromOffset(entry.N > 1 and 200 or 240, 44), LayoutOrder = 2, Color = C.Primary,
				TextColor = C.PrimaryText, Text = (entry.N > 1 and "ALLE VERKAUFEN" or "VERKAUFEN"), TextSize = 16, ZIndex = 6 },
				sellButtons, function()
				selected = nil
				sendAction("Sell", slot, entry.N)
			end)
		else
			selected = nil
			sellInfo.Text = "Was du findest, kannst du hier zu Münzen machen. Waffen, Munition, Heilung und Fahrzeuge."
		end
		repaint()
	end
	win.Refresh()
end

-- TASCHE AM BODEN: Inhalt links (anklicken = nehmen), eigene Tasche rechts
local function openLoot(data)
	local win = window
	if not win or win.Kind ~= "Loot" or not win.Loot or win.Loot.Id ~= data.Id then
		win = newWindow("Loot", tostring(data.Title or "TASCHE"), "ANKLICKEN = NEHMEN  ·  JEDER KANN DIESE TASCHE DURCHSUCHEN",
			Color3.fromRGB(255, 140, 90))
		win.Loot = data
		local body = win.Body
		sectionTitle(body, "INHALT", UDim2.fromOffset(0, 0))
		win.LootHolder = make("Frame", { Position = UDim2.fromOffset(0, 22), Size = UDim2.fromOffset(560, 420),
			BackgroundTransparency = 1, ZIndex = 5 }, body)
		UITheme.Chunky({ Position = UDim2.fromOffset(0, 466), Size = UDim2.fromOffset(260, 48), Color = C.Primary,
			TextColor = C.PrimaryText, Text = "ALLES NEHMEN", TextSize = 18, ZIndex = 6 }, body, function()
			sendAction("Loot", data.Id, "All")
		end)
		sectionTitle(body, "DEINE TASCHE", UDim2.fromOffset(640, 0), 480)
		grid(body, "Bag", 1, BAG, 6, 64, 8, UDim2.fromOffset(640, 22), true)
		onSlotClick = function(container, slot)
			if container == "Loot" then
				sendAction("Loot", data.Id, slot)
			else
				defaultClick(container, slot)
			end
		end
		onSlotDrop = defaultDrop
		onSlotRightClick = onSlotClick
		function win.Refresh()
			repaint()
		end
	end
	win.Loot = data
	-- Plätze der Tasche am Boden neu aufbauen (Anzahl ändert sich)
	for _, child in win.LootHolder:GetChildren() do
		child:Destroy()
	end
	local count = 0
	for _, entry in data.Items do
		count = math.max(count, entry.S)
	end
	if count > 0 then
		grid(win.LootHolder, "Loot", 1, count, 7, 72, 8, UDim2.new())
	end
	win.Refresh()
end

-- ---------- Ziehen mit der Maus ----------

local function updateDrag()
	if not drag then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	if not drag.Moved and (mouse - drag.Start).Magnitude > 6 then
		drag.Moved = true
		local entry = entryOf(drag.Container, drag.Slot)
		if entry then
			drag.Ghost = make("Frame", { Size = UDim2.fromOffset(62, 62), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.Card,
				BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 50 }, windowGui)
			UITheme.Corner(drag.Ghost, UITheme.Radius.Small)
			UITheme.Stroke(drag.Ghost, C.Primary, 2, 0)
			buildIcon(drag.Ghost, entry.Id, 51)
		end
	end
	if drag.Ghost then
		drag.Ghost.Position = UDim2.fromOffset(mouse.X, mouse.Y) -- Fenster-Ebene ignoriert den Rand oben
	end
end

local function endDrag()
	local current = drag
	drag = nil
	if not current then
		return
	end
	if current.Ghost then
		current.Ghost:Destroy()
	end
	if not current.Moved then
		if onSlotClick then
			onSlotClick(current.Container, current.Slot)
		end
		return
	end
	if hovered and not (hovered.Container == current.Container and hovered.Slot == current.Slot) and onSlotDrop then
		onSlotDrop(current.Container, current.Slot, hovered.Container, hovered.Slot)
	end
end

-- ---------- Stände und Lager (E) ----------

local prompts = {}

local function setupPrompts()
	local maps = workspace:WaitForChild("Maps")
	local map = maps:WaitForChild("Extinction", 30)
	local stands = map and map:WaitForChild("Stands", 10)
	if not stands then
		return
	end
	for key, stand in ExtinctionConfig.Stands do
		local part = stands:WaitForChild(key, 10)
		if part then
			local prompt = make("ProximityPrompt", { Name = "StandPrompt", ActionText = "Handeln", ObjectText = stand.Title,
				KeyboardKeyCode = Enum.KeyCode.E, HoldDuration = 0, MaxActivationDistance = ExtinctionConfig.StandRange - 2,
				RequiresLineOfSight = false, Enabled = false }, part)
			prompt.Triggered:Connect(function()
				openStand(key)
			end)
			table.insert(prompts, prompt)
		end
	end
	local stashPart = stands:WaitForChild("Stash", 10)
	if stashPart then
		local prompt = make("ProximityPrompt", { Name = "StashPrompt", ActionText = "Lager öffnen", ObjectText = "LAGER",
			KeyboardKeyCode = Enum.KeyCode.E, HoldDuration = 0, MaxActivationDistance = ExtinctionConfig.StandRange - 2,
			RequiresLineOfSight = false, Enabled = false }, stashPart)
		prompt.Triggered:Connect(openStash)
		table.insert(prompts, prompt)
	end
	for _, prompt in prompts do
		prompt.Enabled = inExtinction()
	end
end

-- Fenster am Stand/Lager schließen, wenn man weggeht
local function standDistanceCheck()
	if not window or (window.Kind ~= "Stand" and window.Kind ~= "Stash") then
		return
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local maps = workspace:FindFirstChild("Maps")
	local stands = maps and maps:FindFirstChild("Extinction") and maps.Extinction:FindFirstChild("Stands")
	local part = stands and stands:FindFirstChild(window.Kind == "Stash" and "Stash" or window.Stand)
	if not rootPart or not part or (rootPart.Position - part.Position).Magnitude > ExtinctionConfig.StandRange + 4 then
		closeWindow()
	end
end

-- ---------- Hotbar-Anzeige ----------

local function refreshHotbar()
	for slot, view in hotbarViews do
		local entry = bag[slot]
		paintSlot(view, entry, false, slot == equipped and entry ~= nil)
	end
end

local function refreshAll()
	bag = decodeList(player:GetAttribute("ExtBag"))
	stash = decodeList(player:GetAttribute("ExtStash"))
	equipped = player:GetAttribute("ExtEquipped") or 0
	if selected and not entryOf(selected.Container, selected.Slot) then
		selected = nil
	end
	refreshHotbar()
	if window and window.Refresh then
		window.Refresh()
	end
	repaint()
end

local function updateVisible()
	local on = inExtinction()
	if hud then
		hud.Enabled = on
	end
	for _, prompt in prompts do
		prompt.Enabled = on
	end
	if not on then
		closeWindow()
	end
end

-- Controller: nächster/voriger belegter Hotbar-Platz
local function cycle(direction)
	local start = equipped > 0 and equipped or (direction > 0 and 0 or HOTBAR + 1)
	for k = 1, HOTBAR do
		local slot = (start - 1 + direction * k) % HOTBAR + 1
		local entry = bag[slot]
		local config = entry and itemConfig(entry.Id)
		if config and config.Kind == "Weapon" then
			sendAction("Use", slot)
			return
		end
	end
end

function ExtinctionClient.Init()
	buildHud()
	windowGui = make("ScreenGui", { Name = "ExtinctionWindow", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	-- Klicks neben das Fenster sollen nicht schießen: unsichtbarer Knopf über dem ganzen Bild
	make("TextButton", { Name = "Blocker", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background, BackgroundTransparency = 0.55,
		Text = "", AutoButtonColor = false, ZIndex = 1 }, windowGui)
	canvas = UITheme.Canvas(windowGui, 1600, 900)
	canvas.ZIndex = 2

	-- Tasten: 1-9, TAB, K (eigene Belegungen in InputActions)
	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
		Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }
	for slot = 1, HOTBAR do
		local action = "Hotbar" .. slot
		InputActions.Bindings[action] = { Keys = { keys[slot] }, Pad = {} }
		InputActions.Bind(action, function(began)
			if began and inExtinction() then
				sendAction("Use", slot)
			end
		end)
	end
	InputActions.Bindings.Inventory = { Keys = { Enum.KeyCode.Tab }, Pad = { Enum.KeyCode.ButtonSelect } }
	InputActions.Bind("Inventory", function(began)
		if not began or not inExtinction() then
			return
		end
		if window then
			closeWindow()
		else
			openInventory()
		end
	end)
	-- Controller: △ (Waffenwechsel gibt es hier nicht, die Hotbar macht das)
	InputActions.Bindings.StoreVehicle = { Keys = { Enum.KeyCode.K }, Pad = { Enum.KeyCode.ButtonY } }
	InputActions.Bind("StoreVehicle", function(began)
		if began and inExtinction() then
			sendAction("StoreVehicle")
		end
	end)
	-- Controller: R1/L1 (in der offenen Welt keine Gadgets/Fähigkeiten) wechseln die Hotbar
	InputActions.Bind("Gadget", function(began)
		if began and inExtinction() and InputActions.Device() == "Gamepad" then
			cycle(1)
		end
	end)
	InputActions.Bind("Ability", function(began)
		if began and inExtinction() and InputActions.Device() == "Gamepad" then
			cycle(-1)
		end
	end)
	InputActions.Bind("Menu", function(began)
		if began then
			closeWindow()
		end
	end)
	updateHints()
	InputActions.DeviceChanged:Connect(updateHints)

	-- Ziehen
	UserInputService.InputChanged:Connect(function(input)
		if drag and input.UserInputType == Enum.UserInputType.MouseMovement then
			updateDrag()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if drag and input.UserInputType == Enum.UserInputType.MouseButton1 then
			endDrag()
		end
	end)

	-- Daten vom Server
	for _, attribute in { "ExtBag", "ExtStash", "ExtEquipped" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshAll)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		coinsText.Text = UITheme.FormatNumber(player:GetAttribute("Coins") or 0)
		if window and window.Coins then
			window.Coins.Text = UITheme.FormatNumber(player:GetAttribute("Coins") or 0) .. " MÜNZEN"
		end
	end)
	coinsText.Text = UITheme.FormatNumber(player:GetAttribute("Coins") or 0)
	player:GetAttributeChangedSignal("Mode"):Connect(updateVisible)
	Remotes.ExtUpdate.OnClientEvent:Connect(function(kind, a, b)
		if kind == "Status" then
			showToast(tostring(a), b == true)
		elseif kind == "Loot" and type(a) == "table" then
			openLoot(a)
		elseif kind == "LootClosed" then
			if window and window.Kind == "Loot" and window.Loot and window.Loot.Id == a then
				window.Loot = nil -- schon weg: nicht noch einmal abmelden
				closeWindow()
			end
		elseif kind == "UseStart" then
			useBar.Visible = true
			useText.Text = upper(tostring(a))
			useFill.Size = UDim2.fromScale(0, 1)
			local duration = tonumber(b) or 1
			local started = os.clock()
			task.spawn(function()
				while useBar.Visible and os.clock() - started < duration do
					useFill.Size = UDim2.fromScale(math.clamp((os.clock() - started) / duration, 0, 1), 1)
					task.wait()
				end
				useBar.Visible = false
			end)
		elseif kind == "UseEnd" then
			useBar.Visible = false
		end
	end)
	player.CharacterAdded:Connect(function(character)
		useBar.Visible = false
		closeWindow()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(closeWindow)
		end
	end)

	-- Anzeige oben und Wartezeit fürs Fahrzeug
	RunService.Heartbeat:Connect(function()
		if not hud.Enabled then
			return
		end
		updateZone()
		standDistanceCheck()
		local readyAt = player:GetAttribute("ExtVehicleReadyAt") or 0
		local left = readyAt - workspace:GetServerTimeNow()
		vehicleCooldown.Text = left > 0 and ("FAHRZEUG WIEDER BEREIT IN " .. math.ceil(left) .. " S") or ""
	end)

	refreshAll()
	updateVisible()
	task.spawn(setupPrompts)
end

return ExtinctionClient
