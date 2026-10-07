-- ExtinctionClient (ModuleScript, nur Client)
-- Oberfläche der offenen Welt (EXTINCTION):
--   HUD: Hotbar unten (Plätze 1-9, Waffe in der Hand hervorgehoben, Fahrzeug draußen / Wartezeit), Anzeige oben
--        (SAFE ZONE · PVP IN 3 S · PVP AKTIV), Münzen, Meldungen, Balken beim Benutzen (Verband, Weste)
--   Tasten: 1-9 Hotbar benutzen, TAB Menü (INVENTAR), M Menü (zuletzt offener Reiter), K Fahrzeug einpacken,
--           E an Ständen/Lager/Taschen (ProximityPrompt)
--   Controller: R1/L1 nächste/vorige Waffe der Hotbar (im Menü: Reiter), △ = heilen (Heil-Item aus der Hotbar),
--               Select = Menü; gehalten: Steuerkreuz oben = Weltkarte (angetippt: Ping), Select = Squad, △ = Fahrzeug einpacken
--   Menü (kleiner als der Bildschirm): Reiter INVENTAR · MARKT (Spielermarkt, nur in der Safe Zone) · SQUAD · SHOP ·
--            BATTLE PASS · STATISTIK · CODES · OPTIONEN (die letzten fünf sind Seiten der Lobby, GameMenu.BorrowPage)
--   Fenster: Stand (kaufen links, verkaufen rechts), Lager (Tasche links, Lager rechts),
--            Tasche am Boden (Inhalt links, eigene Tasche rechts; anklicken = einzeln nehmen. ALLES NEHMEN und F an Taschen,
--            Kisten, Lootdrops und Leichen nur mit dem Gamepass ALLES LOOTEN, sonst führt der Knopf zum Kauf)
-- Items ziehen und ablegen (Maus) oder anklicken und dann den Zielplatz anklicken; Rechtsklick legt ein Item
-- zwischen Hotbar und Tasche hin und her. Der Server prüft alles (InventoryService, LootService).
-- Daten: Spieler-Attribute ExtBag, ExtStash, ExtEquipped, ExtVehicle, ExtVehicleReadyAt, InSafeZone, PvP, PvPAt,
-- Coins, Redzone; Karten-Attribute Redzones (die rote Zone: Zeile unter der Uhr), Airdrops, RedzoneBoard (Rangliste
-- rechts oben), Weltkarte (N, ExtinctionMap); Remotes.ExtUpdate ("Status", "Loot", "LootClosed", "UseStart", "UseEnd").
-- Squad (J oder Knopf SQUAD): Fenster zum Einladen/Annehmen/Verlassen (PartyService über Remotes.PartyAction), Liste der
-- Mitglieder links unter den Aufträgen (Ort bzw. Entfernung, Leben). In der offenen Welt ist der Squad das Team.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local GunModels = require(Shared.GunModels)
local RobuxConfig = require(Shared.RobuxConfig)
local ExtinctionMap = require(script.Parent:WaitForChild("ExtinctionMap"))
local VehicleClient = require(script.Parent:WaitForChild("VehicleClient"))
local DayCycle = require(Shared.DayCycle)
local GameMenu = require(Shared.GameMenu)
local LobbyPages = require(Shared.LobbyPages)

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
	Repel = Color3.fromRGB(120, 220, 120),
}
local KIND_NAMES = { Weapon = "WAFFE", Ammo = "MUNITION", Heal = "HEILUNG", Armor = "RÜSTUNG", Vehicle = "FAHRZEUG",
	Repel = "SCHUTZ" }
local SHIELD = Color3.fromRGB(150, 230, 70) -- Anti-Zombie-Spritze wirkt (Anzeige oben)
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
	elseif config.Kind == "Repel" then
		-- Spritze: Kolben, Zylinder mit grünem Serum, Nadel (schräg)
		local syringe = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromOffset(40, 10), Rotation = -35, BackgroundTransparency = 1, ZIndex = zIndex }, holder)
		make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 10),
			BackgroundColor3 = Color3.fromRGB(210, 210, 214), BorderSizePixel = 0, ZIndex = zIndex }, syringe)
		make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(6, 2),
			BackgroundColor3 = Color3.fromRGB(210, 210, 214), BorderSizePixel = 0, ZIndex = zIndex }, syringe)
		local barrel = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(20, 8),
			BackgroundColor3 = Color3.fromRGB(236, 240, 236), BorderSizePixel = 0, ZIndex = zIndex }, syringe)
		UITheme.Corner(barrel, 2)
		make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -1, 0.5, 0), Size = UDim2.fromOffset(13, 6),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = zIndex }, barrel)
		make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 29, 0.5, 0), Size = UDim2.fromOffset(11, 1),
			BackgroundColor3 = Color3.fromRGB(190, 196, 204), BorderSizePixel = 0, ZIndex = zIndex }, syringe)
	elseif config.Kind == "Vehicle" and (ExtinctionConfig.Vehicles[config.Vehicle] or {}).Kind == "Heli" then
		-- Helikopter (Nase links): Kabine mit Scheibe, Heckausleger mit Leitwerk, Rotor auf dem Mast, Kufen auf Streben
		local paint = ExtinctionConfig.Vehicles[config.Vehicle].Color
		local metal = Color3.fromRGB(34, 34, 36)
		local cabin = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -8, 0.56, 0),
			Size = UDim2.fromOffset(20, 12), BackgroundColor3 = paint, BorderSizePixel = 0, ZIndex = zIndex }, holder)
		UITheme.Corner(cabin, 6)
		local pane = make("Frame", { Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(8, 5),
			BackgroundColor3 = Color3.fromRGB(150, 180, 200), BorderSizePixel = 0, ZIndex = zIndex }, cabin)
		UITheme.Corner(pane, 3)
		for _, part in {
			{ Vector2.new(0, 0.5), UDim2.new(1, -3, 0.5, -1), UDim2.fromOffset(19, 3), paint },   -- Heckausleger
			{ Vector2.new(1, 1), UDim2.new(1, 16, 0.5, 1), UDim2.fromOffset(3, 8), paint },       -- Seitenleitwerk
			{ Vector2.new(0.5, 1), UDim2.new(0.5, 0, 0, 0), UDim2.fromOffset(2, 3), metal },      -- Mast
			{ Vector2.new(0.5, 1), UDim2.new(0.5, 0, 0, -3), UDim2.fromOffset(38, 2), metal },    -- Rotor
			{ Vector2.new(0.5, 0), UDim2.new(0.5, 0, 1, 3), UDim2.fromOffset(24, 2), metal },     -- Kufe
			{ Vector2.new(0.5, 0), UDim2.new(0, 6, 1, 0), UDim2.fromOffset(2, 3), metal },        -- Streben
			{ Vector2.new(0.5, 0), UDim2.new(0, 14, 1, 0), UDim2.fromOffset(2, 3), metal },
		} do
			make("Frame", { AnchorPoint = part[1], Position = part[2], Size = part[3], BackgroundColor3 = part[4], BorderSizePixel = 0,
				ZIndex = zIndex }, cabin)
		end
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
	elseif config.Kind == "Repel" then
		return math.floor((config.Duration or 0) / 60) .. " Min spawnen bei dir keine Zombies · "
			.. string.gsub(tostring(config.UseTime), "%.", ",") .. " s"
	elseif config.Kind == "Vehicle" then
		local vehicle = ExtinctionConfig.Vehicles[config.Vehicle]
		return vehicle and ((vehicle.Kind == "Heli" and "Fliegt · " or "") .. "Tempo " .. vehicle.Speed .. " · " .. vehicle.Health
			.. " Leben · " .. vehicle.Seats .. (vehicle.Seats == 1 and " Sitz" or " Sitze")) or ""
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
local shieldPill, shieldText
local markerHolder, vignette, placeLabel, placeSub
local places, currentPlace, placeShownAt = {}, nil, -100 -- Orte der Karte (Gruppe Places), aktueller Ort, Zeit des Banners
local markerRows = {}
local RED = Color3.fromRGB(226, 56, 48)
local DROP = Color3.fromRGB(255, 190, 70)
local NEST = Color3.fromRGB(160, 230, 80)
local MAX_MARKERS = 4
local MISSION_GAP = 24 -- Abstand der Aufträge unter dem VERLASSEN-Knopf (auf Touch unter der Lebensanzeige)
-- Rangliste der roten Zone rechts oben unter der Uhr (nur in der Zone); der Killfeed des HUD rückt dann darunter
-- (HUD.lua: SURVIVAL_KILLFEED_TOP = BOARD_TOP + BOARD_H + 12)
local BOARD_TOP, BOARD_W, BOARD_H, BOARD_H_SHORT = 88, 250, 144, 116
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
	zonePill = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(400, 30),
		BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, root)
	UITheme.Corner(zonePill, UITheme.Radius.Small)
	UITheme.Stroke(zonePill, SAFE, 1, 0.3)
	zoneText = label({ Size = UDim2.fromScale(1, 1), Text = "SAFE ZONE", TextSize = 18, Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = SAFE }, zonePill)

	-- Anti-Zombie-Spritze wirkt: Zeile unter der Zonen-Anzeige mit der Restzeit
	shieldPill = make("Frame", { Name = "ZombieShield", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(400, 24), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0,
		Visible = false }, root)
	UITheme.Corner(shieldPill, UITheme.Radius.Small)
	UITheme.Stroke(shieldPill, SHIELD, 1, 0.3)
	shieldText = label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 14, Font = F.Bold, TextColor3 = SHIELD,
		TextXAlignment = Enum.TextXAlignment.Center }, shieldPill)

	-- roter Rand, solange man in der roten Zone steht (4 Verläufe vom Rand nach innen)
	vignette = make("Frame", { Name = "RedzoneVignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false,
		Active = false }, root)
	for _, side in { { UDim2.new(1, 0, 0, 120), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, 0, 120), UDim2.new(0, 0, 1, -120), 270 },
		{ UDim2.new(0, 120, 1, 0), UDim2.fromScale(0, 0), 0 }, { UDim2.new(0, 120, 1, 0), UDim2.new(1, -120, 0, 0), 180 } } do
		local strip = make("Frame", { Size = side[1], Position = side[2], BackgroundColor3 = RED, BorderSizePixel = 0 }, vignette)
		make("UIGradient", { Rotation = side[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1) }) }, strip)
	end

	-- Banner beim Betreten eines Ortes (blendet nach einigen Sekunden aus)
	placeSub = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.2, 0), Size = UDim2.fromOffset(600, 18), Text = "",
		TextSize = 13, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, Visible = false }, root)
	placeLabel = label({ Name = "PlaceBanner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.2, 18),
		Size = UDim2.fromOffset(700, 44), Text = "", TextSize = 36, Font = F.Display, TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Center, Visible = false }, root)
	UITheme.Outline(placeLabel)

	-- Marker unter der Anzeige: rote Zonen und Lootdrops mit Pfeil und Entfernung
	markerHolder = make("Frame", { Name = "Markers", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(300, MAX_MARKERS * 24), BackgroundTransparency = 1 }, root)
	for i = 1, MAX_MARKERS do
		local row = make("Frame", { Name = "Marker" .. i, Position = UDim2.fromOffset(0, (i - 1) * 24), Size = UDim2.fromOffset(300, 22),
			BackgroundColor3 = C.Panel, BackgroundTransparency = 0.35, BorderSizePixel = 0, Visible = false }, markerHolder)
		UITheme.Corner(row, UITheme.Radius.Small)
		local arrow = label({ Name = "Arrow", Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(22, 22), Text = "▲", TextSize = 16,
			Font = F.Display, TextXAlignment = Enum.TextXAlignment.Center }, row)
		local text = label({ Name = "Text", Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -36, 1, 0), Text = "", TextSize = 13,
			Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Left }, row)
		markerRows[i] = { Row = row, Arrow = arrow, Text = text }
	end

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
	vehicleCooldown = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -98), Size = UDim2.fromOffset(560, 18),
		Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, root)
	coinsText = label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -barWidth / 2 - 14, 1, -46),
		Size = UDim2.fromOffset(160, 22), Text = "", TextSize = 20, Font = F.Display, TextColor3 = C.Primary,
		TextXAlignment = Enum.TextXAlignment.Right }, root)
	label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -barWidth / 2 - 14, 1, -30), Size = UDim2.fromOffset(160, 14),
		Text = "MÜNZEN", TextSize = 10, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, root)
	hints = label({ Name = "Hints", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(900, 16),
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

-- Eine Tastenzeile unter der Hotbar für alles: Die allgemeine Zeile des HUD (SCHIESSEN, FÄHIGKEIT, ...) ist in der
-- offenen Welt aus, sonst lägen beide Zeilen übereinander. Als Pilot eines Helikopters zeigt sie die Flugsteuerung.
local heliHints = false
local function updateHints()
	if not hints then
		return
	end
	local device = InputActions.Device()
	if heliHints then
		if device == "Touch" then
			hints.Text = "STICK = FLIEGEN  ·  HOCH / RUNTER = STEIGEN / SINKEN  ·  RAUS = AUSSTEIGEN  ·  PARKEN = EINPACKEN (GELANDET)"
		elseif device == "Gamepad" then
			hints.Text = "L-STICK  FLIEGEN  ·  R2  STEIGEN  ·  L2  SINKEN  ·  ✕  AUSSTEIGEN  ·  " .. InputActions.Hint("StoreVehicle")
				.. "  EINPACKEN (GELANDET)"
		else
			hints.Text = "W / S  VOR / ZURÜCK  ·  A / D  DREHEN  ·  LEERTASTE  STEIGEN  ·  SHIFT  SINKEN  ·  F  AUSSTEIGEN  ·  "
				.. InputActions.Hint("StoreVehicle") .. "  EINPACKEN (GELANDET)"
		end
		return
	end
	if device == "Touch" then
		hints.Text = "PLÄTZE ANTIPPEN ZUM BENUTZEN  ·  TASCHE = INVENTAR  ·  PARKEN = FAHRZEUG EINPACKEN"
		return
	end
	local pad = device == "Gamepad"
	local parts, seen = {}, {}
	for _, entry in {
		{ InputActions.Hint("Fire"), "SCHIESSEN" },
		{ InputActions.Hint("Reload"), "NACHLADEN" },
		{ pad and "R1 / L1" or "1-9", pad and "WAFFE" or "BENUTZEN" },
		{ pad and InputActions.Hint("QuickHeal") or "", "HEILEN" },
		{ InputActions.Hint("Inventory"), "INVENTAR" },
		{ InputActions.Hint("Interact"), "INTERAGIEREN" },
		{ InputActions.Hint("StoreVehicle"), "FAHRZEUG EINPACKEN" },
		{ InputActions.Hint("WorldMap"), "KARTE" },
		{ InputActions.Hint("Squad"), "SQUAD" },
	} do
		local key, text = entry[1], entry[2]
		if key ~= "" and seen[key] then -- gleiche Taste (Controller: □ lädt nach oder interagiert)
			parts[seen[key]] ..= " / " .. text
		elseif key ~= "" then
			table.insert(parts, key .. "  " .. text)
			seen[key] = #parts
		end
	end
	hints.Text = table.concat(parts, "  ·  ")
end

local function updateZone()
	if not zonePill then
		return
	end
	local stroke = zonePill:FindFirstChildOfClass("UIStroke")
	if vignette then
		local red = player:GetAttribute("Redzone") ~= nil and player:GetAttribute("Redzone") ~= false
		vignette.Visible = red and not player:GetAttribute("InSafeZone")
	end
	if player:GetAttribute("InSafeZone") then
		local title = player:GetAttribute("SafeZoneTitle")
		zoneText.Text = "SAFE ZONE  ·  " .. (type(title) == "string" and (string.upper(title) .. "  ·  ") or "") .. "KEIN PVP"
		zoneText.TextColor3 = SAFE
		stroke.Color = SAFE
	elseif vignette and vignette.Visible then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 4)
		zoneText.Text = "ROTE ZONE  ·  PVP AKTIV"
		zoneText.TextColor3 = RED:Lerp(Color3.new(1, 1, 1), 0.25 * pulse)
		stroke.Color = RED
		vignette.Position = UDim2.fromOffset(0, 0)
		for _, strip in vignette:GetChildren() do
			strip.BackgroundTransparency = 0.35 * (1 - pulse)
		end
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

-- Anti-Zombie-Spritze (Charakter-Attribut ZombieShieldUntil): Restzeit oben anzeigen
local function updateShield()
	if not shieldPill then
		return
	end
	local character = player.Character
	local left = character and math.floor((character:GetAttribute("ZombieShieldUntil") or 0) - workspace:GetServerTimeNow()) or 0
	shieldPill.Visible = left > 0
	if left > 0 then
		shieldText.Text = string.format("ANTI-ZOMBIE-SPRITZE  %d:%02d  ·  KEINE ZOMBIES BEI DIR", left // 60, left % 60)
	end
end

-- Marker: Liste aus den Karten-Attributen Airdrops / Activities lesen, nach Entfernung sortieren, Pfeil zur Kamera drehen
local function mapList(map, attribute)
	local text = map and map:GetAttribute(attribute)
	if type(text) ~= "string" then
		return {}
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, text)
	return ok and type(list) == "table" and list or {}
end

-- Richtungsanzeiger mit Entfernung oben am Bildschirm: abgeschaltet (Spieler finden Ziele über Minimap und Weltkarte)
local SHOW_MARKERS = false

local function updateMarkers()
	if not markerHolder then
		return
	end
	if not SHOW_MARKERS then
		markerHolder.Visible = false
		return
	end
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	local character = player.Character
	local root3 = character and character:FindFirstChild("HumanoidRootPart")
	local entries = {}
	if map and root3 then
		local here = root3.Position
		local now = workspace:GetServerTimeNow()
		for _, drop in mapList(map, "Airdrops") do
			local dx, dz = (drop.X or 0) - here.X, (drop.Z or 0) - here.Z
			local distance = math.floor(math.sqrt(dx * dx + dz * dz))
			local text
			if drop.State == "Landed" then
				text = "LOOTDROP GELANDET  ·  " .. distance .. " M"
			else
				text = "LOOTDROP  ·  " .. math.max(0, math.ceil((drop.Eta or now) - now)) .. " S  ·  " .. distance .. " M"
			end
			if drop.Zone then
				text ..= "  ·  ROT"
			end
			table.insert(entries, { Order = distance - 5000, X = drop.X, Z = drop.Z, Color = DROP, Text = text })
		end
		-- Aktivitäten: Nester und volle Vorratslager in der Nähe, Überlebende
		for _, act in mapList(map, "Activities") do
			local dx, dz = (act.X or 0) - here.X, (act.Z or 0) - here.Z
			local distance = math.floor(math.sqrt(dx * dx + dz * dz))
			if act.Kind == "Nest" and act.State == "Active" and distance < 350 then
				table.insert(entries, { Order = distance, X = act.X, Z = act.Z, Color = NEST, Text = "ZOMBIENEST  ·  " .. distance .. " M" })
			elseif act.Kind == "Survivor" and act.State == "Ready" and distance < 260 then
				table.insert(entries, { Order = distance + 100, X = act.X, Z = act.Z, Color = Color3.fromRGB(120, 220, 140),
					Text = "ÜBERLEBENDER  ·  " .. distance .. " M" })
			elseif act.Kind == "Survivor" and act.State == "Following" then
				local zone = map:FindFirstChild("Zone") and map.Zone:FindFirstChild("SafeZone")
				if zone then
					local sx, sz = zone.Position.X - here.X, zone.Position.Z - here.Z
					table.insert(entries, { Order = -9000, X = zone.Position.X, Z = zone.Position.Z, Color = Color3.fromRGB(120, 220, 140),
						Text = "ÜBERLEBENDEN ZUR SAFE ZONE BRINGEN  ·  " .. math.floor(math.sqrt(sx * sx + sz * sz)) .. " M" })
				end
			elseif act.Kind == "Cache" and act.State == "Ready" and distance < 220 then
				table.insert(entries, { Order = distance + 200, X = act.X, Z = act.Z, Color = DROP, Text = "VORRATSLAGER  ·  " .. distance .. " M" })
			end
		end
	end
	table.sort(entries, function(a, b)
		return a.Order < b.Order
	end)
	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
	local forward = Vector3.new(look.X, 0, look.Z)
	forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, -1)
	for i, view in markerRows do
		local entry = entries[i]
		view.Row.Visible = entry ~= nil
		if entry and root3 then
			local to = Vector3.new(entry.X - root3.Position.X, 0, entry.Z - root3.Position.Z)
			if to.Magnitude > 0.01 then
				to = to.Unit
				-- Winkel zwischen Blickrichtung und Ziel: 0 = geradeaus, positiv = rechts
				local angle = math.atan2(forward.X * to.Z - forward.Z * to.X, forward.X * to.X + forward.Z * to.Z)
				view.Arrow.Rotation = math.deg(angle)
			end
			view.Arrow.TextColor3 = entry.Color
			view.Text.TextColor3 = entry.Color
			view.Text.Text = entry.Text
		end
	end
end

-- Orte: Teile Place_<Name> in der Gruppe Places der Karte (Breite = Durchmesser, Attribut Title)
local function loadPlaces(map)
	places = {}
	local folder = map and map:FindFirstChild("Places")
	for _, part in folder and folder:GetChildren() or {} do
		if part:IsA("BasePart") and string.match(part.Name, "^Place_") then
			table.insert(places, { Name = part.Name, Title = part:GetAttribute("Title") or string.sub(part.Name, 7),
				X = part.Position.X, Z = part.Position.Z, R = part.Size.X / 2 })
		end
	end
end

local function updatePlace()
	if not placeLabel then
		return
	end
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	if #places == 0 and map then
		loadPlaces(map)
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local here = nil
	if rootPart then
		local best = math.huge
		for _, place in places do -- liegt man in mehreren Orten (Viertel, Gebäude darin), gilt der kleinste
			local distance = math.sqrt((rootPart.Position.X - place.X) ^ 2 + (rootPart.Position.Z - place.Z) ^ 2)
			if distance <= place.R and place.R < best then
				best, here = place.R, place
			end
		end
	end
	if here ~= currentPlace then
		currentPlace = here
		if here then
			placeLabel.Text = upper(here.Title)
			placeSub.Text = "ORT"
			placeShownAt = os.clock()
		end
	end
	local age = os.clock() - placeShownAt
	local visible = age < 4.2
	placeLabel.Visible, placeSub.Visible = visible, visible
	if visible then
		local alpha = age < 0.5 and (1 - age / 0.5) or (age > 3.2 and (age - 3.2) or 0)
		alpha = math.clamp(alpha, 0, 1)
		placeLabel.TextTransparency, placeSub.TextTransparency = alpha, alpha
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
	if window.Borrowed then
		GameMenu.ReturnPage(window.Borrowed) -- Seite der Lobby zurückgeben, bevor der Rahmen verschwindet
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

-- ---------- Menü (TAB / M) ----------
-- Etwas kleiner als der Bildschirm: oben die Reiter (Controller: L1/R1 blättern), rechts Münzen und Schließen, darunter
-- der Inhalt. INVENTAR, MARKT und SQUAD baut dieses Modul; die übrigen Reiter sind Seiten der Lobby (GameMenu.BorrowPage),
-- verkleinert auf die Breite des Inhalts.
local MENU_W, MENU_H = 1400, 820
local CONTENT_X, CONTENT_Y = 28, 78
local CONTENT_W, CONTENT_H = MENU_W - 2 * CONTENT_X, MENU_H - CONTENT_Y - 16
local MENU_TABS = {
	{ Id = "Inventory", Text = "INVENTAR" },
	{ Id = "Market", Text = "MARKT" },
	{ Id = "Squad", Text = "SQUAD" },
	{ Id = "Shop", Text = "SHOP", Page = true },
	{ Id = "Pass", Text = "BATTLE PASS", Page = true },
	{ Id = "Stats", Text = "STATISTIK", Page = true },
	{ Id = "Codes", Text = "CODES", Page = true },
	{ Id = "Settings", Text = "OPTIONEN", Page = true },
}
local menuTab = {} -- [Id] = Eintrag aus MENU_TABS
for index, tab in MENU_TABS do
	tab.Index = index
	menuTab[tab.Id] = tab
end
local lastMenuTab = "Inventory"
local openMenuTab -- unten gesetzt (öffnet einen Reiter)

local function newMenu(kind, title, subtitle, accent)
	local frame = UITheme.Card({ Name = "Menu", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(MENU_W, MENU_H), BackgroundTransparency = 0.04, ZIndex = 5 }, canvas)
	make("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = accent or C.Primary, BorderSizePixel = 0, ZIndex = 5 }, frame)
	-- Reiter
	local tabs = make("Frame", { Name = "Tabs", Position = UDim2.fromOffset(CONTENT_X, 10), Size = UDim2.new(1, -330, 0, 50),
		BackgroundTransparency = 1, ZIndex = 5 }, frame)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center }, tabs)
	local pad = InputActions.Device() == "Gamepad"
	if pad then
		label({ Name = "PrevHint", Size = UDim2.fromOffset(30, 30), Text = "L1", TextSize = 13, Font = F.Bold, TextColor3 = C.Muted,
			LayoutOrder = 0, ZIndex = 6, TextXAlignment = Enum.TextXAlignment.Center }, tabs)
	end
	for _, tab in MENU_TABS do
		local on = tab.Id == kind
		local button = make("TextButton", { Name = "Tab_" .. tab.Id, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, Text = tab.Text, Font = F.Bold, TextSize = 17, TextColor3 = on and C.Text or C.Muted,
			LayoutOrder = tab.Index, ZIndex = 6, AutoButtonColor = false }, tabs)
		button:SetAttribute("NoFocus", true) -- Controller: die Auswahl startet im Inhalt, Reiter mit L1/R1
		make("Frame", { Name = "Underline", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = accent or C.Primary, BorderSizePixel = 0, Visible = on, ZIndex = 6 }, button)
		button.Activated:Connect(function()
			if not on then
				openMenuTab(tab.Id)
			end
		end)
	end
	if pad then
		label({ Name = "NextHint", Size = UDim2.fromOffset(30, 30), Text = "R1", TextSize = 13, Font = F.Bold, TextColor3 = C.Muted,
			LayoutOrder = #MENU_TABS + 1, ZIndex = 6, TextXAlignment = Enum.TextXAlignment.Center }, tabs)
	end
	make("Frame", { Name = "Divider", Position = UDim2.fromOffset(CONTENT_X, 62), Size = UDim2.new(1, -2 * CONTENT_X, 0, 1),
		BackgroundColor3 = C.Border, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 5 }, frame)
	local close = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 12), Size = UDim2.fromOffset(44, 44),
		Color = C.Card, StrokeColor = C.Border, Text = "", ZIndex = 5 }, frame, closeWindow)
	close.Button:SetAttribute("NoFocus", true)
	UITheme.Cross(close.Face, 14, C.Text, 2).ZIndex = 6
	local coins = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -78, 0, 20), Size = UDim2.fromOffset(220, 30),
		Text = "", TextSize = 24, Font = F.Display, TextColor3 = C.Primary, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }, frame)
	local content = make("Frame", { Name = "Content", Position = UDim2.fromOffset(CONTENT_X, CONTENT_Y),
		Size = UDim2.fromOffset(CONTENT_W, CONTENT_H), BackgroundTransparency = 1, ZIndex = 5 }, frame)
	local sub, body
	if menuTab[kind].Page then
		body = content
	else
		-- eigene Reiter: Titel und Unterzeile wie die Seiten der Lobby, darunter der Inhalt
		label({ Name = "Title", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 40), Text = title, TextSize = 34,
			Font = F.Display, ZIndex = 5 }, content)
		sub = label({ Name = "Sub", Position = UDim2.fromOffset(2, 38), Size = UDim2.new(1, 0, 0, 16), Text = subtitle or "",
			TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, content)
		body = make("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 1, -60),
			BackgroundTransparency = 1, ZIndex = 5 }, content)
	end
	lastMenuTab = kind
	return { Kind = kind, Menu = true, Frame = frame, Body = body, Coins = coins, Sub = sub }
end

local function newWindow(kind, title, subtitle, accent)
	closeWindow()
	windowGui.Enabled = true
	if menuTab[kind] then
		window = newMenu(kind, title, subtitle, accent)
		window.Coins.Text = UITheme.FormatNumber(player:GetAttribute("Coins") or 0) .. " MÜNZEN"
		UITheme.SetBlur("Extinction", true)
		RunService:BindToRenderStep("ExtinctionMouse", MOUSE_PRIORITY, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
		InputActions.Focus(window.Frame:FindFirstChild("Content")) -- Controller: Auswahl in den Inhalt (nach dem Aufbau)
		return window
	end
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
	InputActions.Focus(frame) -- Controller: Auswahl auf den ersten Platz (nach dem Aufbau)
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
		InputActions.Refocus(window.Frame)
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
	local cell, gap = 92, 10
	sectionTitle(body, "TASCHE", UDim2.fromOffset(0, 0))
	grid(body, "Bag", HOTBAR + 1, BAG, 7, cell, gap, UDim2.fromOffset(0, 22))
	sectionTitle(body, "HOTBAR  ·  TASTEN 1-9", UDim2.fromOffset(0, 348))
	grid(body, "Bag", 1, HOTBAR, HOTBAR, 64, gap, UDim2.fromOffset(0, 370), true)
	label({ Name = "Help", Position = UDim2.fromOffset(0, 462), Size = UDim2.fromOffset(660, 60), TextWrapped = true,
		Text = "Anklicken und dann den Zielplatz anklicken (oder ziehen) legt ein Item um. Rechtsklick legt es zwischen Hotbar "
			.. "und Tasche hin und her. Was du draußen bei dir trägst, verlierst du, wenn du stirbst – sicher ist nur das Lager im Camp.",
		TextSize = 13, Font = F.Medium, TextColor3 = C.Muted, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5 }, body)
	local update = detailsPanel(body, UDim2.fromOffset(720, 0), UDim2.fromOffset(CONTENT_W - 720, 600))
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

-- REISEN: an einer Haltestelle (Teil "Travel" / "Travel_<Name>" in Stands) eine andere Safe Zone wählen
local function openTravel(pointName)
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	local zoneFolder = map and map:FindFirstChild("Zone")
	if not zoneFolder then
		return
	end
	local win = newWindow("Travel", "REISEN", "WÄHLE EINE SAFE ZONE  ·  DORT SPAWNST DU AB JETZT NACH DEM TOD", SAFE)
	win.Point = pointName
	local character = player.Character
	local root3 = character and character:FindFirstChild("HumanoidRootPart")
	local list = {}
	for _, part in zoneFolder:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "SafeZone" or string.sub(part.Name, 1, 9) == "SafeZone_") then
			local key = part.Name == "SafeZone" and "" or string.sub(part.Name, 10)
			local distance = root3 and Vector3.new(part.Position.X - root3.Position.X, 0, part.Position.Z - root3.Position.Z).Magnitude or 0
			table.insert(list, { Key = key, Title = part:GetAttribute("Title") or (key == "" and "CAMP PHOENIX" or key),
				Distance = distance, Here = distance <= part.Size.X / 2 })
		end
	end
	table.sort(list, function(a, b)
		if (a.Key == "") ~= (b.Key == "") then
			return a.Key == ""
		end
		return a.Title < b.Title
	end)
	for index, entry in list do
		local column, row = (index - 1) % 2, (index - 1) // 2
		local text = string.upper(entry.Title) .. (entry.Here and "  ·  DU BIST HIER" or ("  ·  " .. math.floor(entry.Distance) .. " M"))
		local chunky = UITheme.Chunky({ Name = "Travel_" .. (entry.Key == "" and "Camp" or entry.Key),
			Position = UDim2.fromOffset(column * 552, 10 + row * 92), Size = UDim2.fromOffset(536, 78),
			Color = entry.Here and C.Card or SAFE:Lerp(Color3.new(0, 0, 0), 0.55), StrokeColor = entry.Here and C.Border or SAFE,
			Text = text, TextSize = 22, ZIndex = 5 }, win.Body, function()
			if not entry.Here then
				sendAction("Travel", entry.Key)
				closeWindow()
			end
		end)
		chunky.Button:SetAttribute("TravelKey", entry.Key)
	end
	function win.Refresh() end
end

-- ---------- SQUAD: bis zu 4 Spieler, in der offenen Welt ein Team ----------

local pendingInvite = nil -- { Name, UserId, Until } (Einladung, angenommen wird im Squad-Fenster)

local function squadInfo()
	local raw = player:GetAttribute("Party")
	local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "")
	return ok and type(data) == "table" and type(data.Members) == "table" and data or nil
end

-- Ort eines Mitspielers für Liste und Fenster: Text und Leben (0..1, nil = unbekannt)
local function whereIs(other)
	if not other or not other.Parent then
		return "OFFLINE", nil
	end
	if other:GetAttribute("Mode") ~= player:GetAttribute("Mode") then
		return "NICHT IN DER OFFENEN WELT", nil
	end
	local character = other.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return "TOT", 0
	end
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local distance = mine and math.floor(Vector3.new(root.Position.X - mine.Position.X, 0, root.Position.Z - mine.Position.Z).Magnitude) or 0
	local title = other:GetAttribute("SafeZoneTitle")
	local where = other:GetAttribute("InSafeZone") and upper(type(title) == "string" and title or "SAFE ZONE") or (distance .. " M")
	return where, humanoid.Health / math.max(1, humanoid.MaxHealth)
end

local function partyAction(action, userId)
	Remotes.PartyAction:FireServer(action, userId)
end

local function openSquad()
	local ALLY = C.Ally
	local win = newWindow("Squad", "SQUAD", "BIS ZU 4 SPIELER  ·  KEIN FRIENDLY FIRE  ·  PINGS NUR FÜR DEN SQUAD  ·  NAMEN UND "
		.. "PUNKTE AUF DER MINIMAP", ALLY)
	local body = win.Body
	sectionTitle(body, "DEIN SQUAD", UDim2.fromOffset(0, 0), 540)
	sectionTitle(body, "SPIELER IN DER OFFENEN WELT", UDim2.fromOffset(580, 0), 540)
	local function column(x, name)
		local list = make("ScrollingFrame", { Name = name, Position = UDim2.fromOffset(x, 24), Size = UDim2.fromOffset(540, 420),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 5 }, body)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		return list
	end
	local mine, others = column(0, "SquadMembers"), column(580, "SquadPlayers")
	local leave = UITheme.Chunky({ Name = "LeaveSquad", Position = UDim2.fromOffset(0, 462), Size = UDim2.fromOffset(260, 52),
		Color = C.Bad:Lerp(Color3.new(0, 0, 0), 0.25), Text = "SQUAD VERLASSEN", TextSize = 18, ZIndex = 5 }, body, function()
		partyAction("Leave")
	end)
	local whereLabels = {} -- { Label, Player } (Entfernung laufend nachführen)

	local function row(parent, order, name, sub, buttons)
		local entry = make("Frame", { Name = "Row", Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = C.Card, BorderSizePixel = 0,
			LayoutOrder = order, ZIndex = 5 }, parent)
		UITheme.Corner(entry, UITheme.Radius.Small)
		label({ Name = "Name", Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -260, 0, 24), Text = name, TextSize = 20,
			Font = F.Display, ZIndex = 6 }, entry)
		local subLabel = label({ Name = "Where", Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -260, 0, 16), Text = sub or "",
			TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 6 }, entry)
		for index, info in buttons or {} do
			UITheme.Chunky({ Name = info.Name, AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10 - (index - 1) * 126, 0.5, 0), Size = UDim2.fromOffset(118, 40), Color = info.Color,
				Text = info.Text, TextSize = 15, ZIndex = 6 }, entry, info.Run)
		end
		return entry, subLabel
	end

	function win.Refresh()
		whereLabels = {}
		for _, list in { mine, others } do
			for _, child in list:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
		end
		local party = squadInfo()
		local iAmLeader = not party or party.Leader == player.UserId
		local inParty = {}
		local order = 0
		-- offene Einladung oben in der eigenen Spalte
		if pendingInvite and os.clock() < pendingInvite.Until then
			order += 1
			local invite = pendingInvite
			row(mine, order, "EINLADUNG VON " .. upper(invite.Name), "ANNEHMEN = SQUAD BEITRETEN", {
				{ Name = "AcceptInvite", Text = "ANNEHMEN", Color = C.Good:Lerp(Color3.new(0, 0, 0), 0.2), Run = function()
					partyAction("Accept", invite.UserId)
					pendingInvite = nil
				end },
				{ Name = "DeclineInvite", Text = "ABLEHNEN", Color = C.Panel, Run = function()
					partyAction("Decline", invite.UserId)
					pendingInvite = nil
					win.Refresh()
				end },
			})
		end
		if party then
			for _, member in party.Members do
				order += 1
				inParty[member.UserId] = true
				local other = Players:GetPlayerByUserId(member.UserId)
				local isMe = member.UserId == player.UserId
				local buttons = (iAmLeader and not isMe) and { { Name = "Kick", Text = "ENTFERNEN", Color = C.Panel, Run = function()
					partyAction("Kick", member.UserId)
				end } } or nil
				local _, whereLabel = row(mine, order, (member.UserId == party.Leader and "★  " or "") .. upper(tostring(member.Name)),
					isMe and "DU" or (whereIs(other)), buttons)
				if not isMe then
					table.insert(whereLabels, { Label = whereLabel, Player = other })
				end
			end
		else
			order += 1
			row(mine, order, "DU SPIELST ALLEIN", "LADE RECHTS JEMANDEN EIN – ALS SQUAD SEID IHR EIN TEAM")
		end
		leave.Button.Visible = party ~= nil
		local count = 0
		for _, other in Players:GetPlayers() do
			if other ~= player and not inParty[other.UserId] and Modes.IsSurvival(other:GetAttribute("Mode")) then
				count += 1
				local busy = other:GetAttribute("SquadId") ~= nil
				local full = party ~= nil and #party.Members >= 4
				local canInvite = iAmLeader and not busy and not full
				local _, whereLabel = row(others, count, upper(other.Name), busy and "SCHON IN EINEM SQUAD" or (whereIs(other)),
					canInvite and { { Name = "Invite", Text = "EINLADEN", Color = C.Good:Lerp(Color3.new(0, 0, 0), 0.2), Run = function()
						partyAction("Invite", other.UserId)
					end } } or nil)
				if not busy then
					table.insert(whereLabels, { Label = whereLabel, Player = other })
				end
			end
		end
		if count == 0 then
			row(others, 1, "NIEMAND SONST HIER", "MITSPIELER KOMMEN ÜBER DAS TOR IM HUB")
		end
	end
	-- Entfernungen laufend nachführen (ohne die Knöpfe neu zu bauen)
	function win.Tick()
		for _, entry in whereLabels do
			if entry.Label.Parent then
				entry.Label.Text = (whereIs(entry.Player))
			end
		end
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

-- SPIELERMARKT (Stand "Stand_Market" im Camp): links alle Angebote (Karten-Attribut PlayerMarket vom ExtMarketService),
-- rechts die eigene Tasche – ein Item anklicken, Anzahl und Preis eintragen, ANBIETEN
local MARKET_FILTERS = {
	{ Key = "All", Text = "ALLE" },
	{ Key = "Weapon", Text = "WAFFEN" },
	{ Key = "Ammo", Text = "MUNITION" },
	{ Key = "Gear", Text = "AUSRÜSTUNG" },
	{ Key = "Vehicle", Text = "FAHRZEUGE" },
}
local function marketGroup(kind)
	if kind == "Heal" or kind == "Armor" or kind == "Repel" then
		return "Gear"
	end
	return kind
end

-- Vorschlag für den Preis: Preis am Stand (Munition anteilig), sonst das Doppelte des Verkaufspreises
local function suggestedPrice(id, count)
	local config = itemConfig(id)
	if config and config.Price then
		return math.max(1, math.floor(config.Price / (config.Pack or 1) * count + 0.5))
	end
	return math.max(1, ExtinctionConfig.SellPrice(id, count) * 2)
end

local function openMarket()
	local win = newWindow("Market", "SPIELERMARKT", "SPIELER KAUFEN UND VERKAUFEN  ·  MÜNZEN  ·  "
		.. math.floor(ExtinctionConfig.Market.FeeRate * 100 + 0.5) .. " % GEBÜHR  ·  ANGEBOTE BLEIBEN IN DEINEM SPIELSTAND",
		Color3.fromRGB(226, 178, 52))
	local body = win.Body
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	local filter = "All"
	sectionTitle(body, "ANGEBOTE", UDim2.fromOffset(0, 0), 300)
	local chips = make("Frame", { Position = UDim2.fromOffset(0, 22), Size = UDim2.fromOffset(600, 34), BackgroundTransparency = 1,
		ZIndex = 5 }, body)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder },
		chips)
	local listFrame = make("ScrollingFrame", { Name = "Listings", Position = UDim2.fromOffset(0, 64), Size = UDim2.fromOffset(600, 450),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 5 }, body)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)

	sectionTitle(body, "DEINE TASCHE  ·  ANKLICKEN = ANBIETEN", UDim2.fromOffset(640, 0), 480)
	grid(body, "Bag", 1, BAG, 6, 64, 8, UDim2.fromOffset(640, 22), true)
	local offerInfo = label({ Name = "OfferInfo", Position = UDim2.fromOffset(640, 392), Size = UDim2.fromOffset(470, 36), Text = "",
		TextSize = 13, Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5 }, body)
	local function input(name, x, width, placeholder)
		local box = make("TextBox", { Name = name, Position = UDim2.fromOffset(x, 436), Size = UDim2.fromOffset(width, 44),
			BackgroundColor3 = C.Card, BorderSizePixel = 0, Text = "", PlaceholderText = placeholder, ClearTextOnFocus = false,
			Font = F.Bold, TextSize = 18, TextColor3 = C.Text, PlaceholderColor3 = C.Muted, ZIndex = 6 }, body)
		UITheme.Corner(box, UITheme.Radius.Small)
		UITheme.Stroke(box, C.Border, 1, 0.3)
		return box
	end
	local countBox = input("OfferCount", 640, 110, "ANZAHL")
	local priceBox = input("OfferPrice", 760, 150, "PREIS")
	local offerButton = UITheme.Chunky({ Name = "OfferButton", Position = UDim2.fromOffset(920, 436), Size = UDim2.fromOffset(190, 44),
		Color = C.Primary, TextColor = C.PrimaryText, Text = "ANBIETEN", TextSize = 18, ZIndex = 6 }, body, function()
		local entry = selected and selected.Container == "Bag" and bag[selected.Slot]
		if not entry then
			return
		end
		local count = math.floor(tonumber(countBox.Text) or entry.N or 1)
		sendAction("MarketList", selected.Slot, count, tonumber(priceBox.Text))
		selected = nil
		win.Refresh()
	end)

	local function listings()
		local raw = map and map:GetAttribute("PlayerMarket")
		local ok, list = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "[]")
		return ok and type(list) == "table" and list or {}
	end

	local function buildList()
		for _, child in listFrame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local mine, shown = 0, 0
		for _, offer in listings() do
			local config = itemConfig(offer.Item)
			local own = offer.Seller == player.UserId
			if own then
				mine += 1
			end
			if config and (filter == "All" or marketGroup(config.Kind) == filter) then
				shown += 1
				local row = make("Frame", { Name = "Listing", Size = UDim2.new(1, -8, 0, 64), BackgroundColor3 = C.Card,
					BackgroundTransparency = own and 0.05 or 0.2, BorderSizePixel = 0, LayoutOrder = shown, ZIndex = 5 }, listFrame)
				UITheme.Corner(row, UITheme.Radius.Small)
				if own then
					UITheme.Stroke(row, C.Primary, 1, 0.4)
				end
				local iconBox = make("Frame", { Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(72, 56), BackgroundTransparency = 1,
					ZIndex = 6 }, row)
				local icon = buildIcon(iconBox, offer.Item, 6)
				icon.Size = UDim2.fromScale(1, 1)
				icon.Position = UDim2.fromScale(0.5, 0.5)
				local count = tonumber(offer.Count) or 1
				label({ Position = UDim2.fromOffset(86, 8), Size = UDim2.fromOffset(300, 24), Text = upper(config.Name)
					.. (count > 1 and ("  ×" .. count) or ""), TextSize = 19, Font = F.Display, ZIndex = 6 }, row)
				label({ Position = UDim2.fromOffset(86, 36), Size = UDim2.fromOffset(300, 18), Text = (own and "DEIN ANGEBOT"
					or ("VON " .. upper(tostring(offer.SellerName)))) .. "  ·  " .. (config.Kind == "Weapon" and offer.Mag
					and ("MAGAZIN " .. offer.Mag) or (KIND_NAMES[config.Kind] or "")), TextSize = 11, Font = F.Bold,
					TextColor3 = C.Muted, ZIndex = 6 }, row)
				local price = tonumber(offer.Price) or 0
				if own then
					UITheme.Chunky({ Name = "CancelListing", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
						Size = UDim2.fromOffset(170, 44), Color = C.Panel, StrokeColor = C.Border, Text = UITheme.FormatNumber(price)
							.. "  ·  ZURÜCK", TextSize = 15, ZIndex = 6 }, row, function()
						sendAction("MarketCancel", offer.Id)
					end)
				else
					UITheme.Chunky({ Name = "BuyListing", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
						Size = UDim2.fromOffset(170, 44), Color = C.Primary, TextColor = C.PrimaryText,
						Text = UITheme.FormatNumber(price) .. "  ·  KAUFEN", TextSize = 15, ZIndex = 6 }, row, function()
						sendAction("MarketBuy", offer.Id, price)
					end)
				end
			end
		end
		if shown == 0 then
			label({ Name = "Empty", Size = UDim2.new(1, -8, 0, 40), Text = filter == "All" and "NOCH KEINE ANGEBOTE – BIETE RECHTS ETWAS AN"
				or "IN DIESER KATEGORIE GIBT ES GERADE NICHTS", TextSize = 14, Font = F.Bold, TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, listFrame)
		end
		return mine
	end

	for index, info in MARKET_FILTERS do
		UITheme.Chunky({ Name = "Filter_" .. info.Key, Size = UDim2.fromOffset(info.Key == "Gear" and 128 or 108, 32), LayoutOrder = index,
			Color = C.Panel, StrokeColor = C.Border, Text = info.Text, TextSize = 13, ZIndex = 6 }, chips, function()
			filter = info.Key
			win.Refresh()
		end)
	end

	onSlotClick = function(container, slot)
		if container == "Bag" and bag[slot] then
			selected = { Container = container, Slot = slot }
			local entry = bag[slot]
			countBox.Text = tostring(entry.N or 1)
			priceBox.Text = tostring(suggestedPrice(entry.Id, entry.N or 1))
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
		for _, chip in chips:GetChildren() do
			local key = chip:IsA("GuiObject") and string.match(chip.Name, "^Filter_(.+)$")
			local face = key and chip:FindFirstChild("Face")
			if face then
				face.BackgroundColor3 = key == filter and C.Primary or C.Panel
				local text = face:FindFirstChild("Label")
				if text then
					text.TextColor3 = key == filter and C.PrimaryText or C.Text
				end
			end
		end
		local mine = buildList()
		local entry = selected and selected.Container == "Bag" and bag[selected.Slot]
		local full = mine >= ExtinctionConfig.Market.MaxListings
		if entry then
			local config = itemConfig(entry.Id)
			offerInfo.Text = upper(config.Name) .. (entry.N > 1 and ("  ×" .. entry.N) or "") .. "  ·  DEINE ANGEBOTE " .. mine .. "/"
				.. ExtinctionConfig.Market.MaxListings .. (entry.Out and "\nDas Fahrzeug ist draußen – erst einpacken (K)."
				or (full and "\nDu hast schon alle Angebote belegt – nimm links eins zurück." or "\nAnzahl und Preis eintragen, dann ANBIETEN."))
		else
			offerInfo.Text = "DEINE ANGEBOTE " .. mine .. "/" .. ExtinctionConfig.Market.MaxListings
				.. "  ·  Klick ein Item deiner Tasche an, um es anzubieten. Angebote sieht jeder auf dem Server."
		end
		local active = entry ~= nil and not entry.Out and not full
		countBox.Visible = entry ~= nil and (entry.N or 1) > 1
		priceBox.Visible = entry ~= nil
		offerButton.Button.Visible = active
		repaint()
	end
	if map then
		local connection
		connection = map:GetAttributeChangedSignal("PlayerMarket"):Connect(function()
			if window ~= win then
				connection:Disconnect()
				return
			end
			win.Refresh()
		end)
	end
	win.Refresh()
end

-- Reiter aus der Lobby (SHOP, BATTLE PASS, STATISTIK, CODES, OPTIONEN): Seite ausleihen und auf die Breite des Inhalts
-- verkleinern. Meldungen des Servers (Kaufen, Codes …) kommen als Meldung unten (Remotes.ShopStatus, siehe Init).
local function openLobbyTab(id)
	local win = newWindow(id)
	local scale = math.min(CONTENT_W / LobbyPages.PAGE_W, CONTENT_H / LobbyPages.PAGE_H)
	local holder = make("Frame", { Name = "PageHolder", Size = UDim2.fromOffset(LobbyPages.PAGE_W, LobbyPages.PAGE_H),
		BackgroundTransparency = 1, ZIndex = 5 }, win.Body)
	make("UIScale", { Scale = scale }, holder)
	if GameMenu.BorrowPage(id, holder) then
		win.Borrowed = id
	else
		label({ Size = UDim2.fromOffset(CONTENT_W, 60), Text = "GERADE NICHT VERFÜGBAR", TextSize = 18, Font = F.Bold,
			TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, win.Body)
	end
	function win.Refresh() end
end

openMenuTab = function(id)
	if id == "Inventory" then
		openInventory()
	elseif id == "Market" then
		openMarket()
	elseif id == "Squad" then
		ExtinctionMap.Set(false)
		openSquad()
	elseif menuTab[id] then
		openLobbyTab(id)
	end
end

-- Controller L1/R1: Reiter weiterblättern
local function cycleMenu(step)
	local index = window and menuTab[window.Kind] and menuTab[window.Kind].Index or 1
	openMenuTab(MENU_TABS[(index - 1 + step) % #MENU_TABS + 1].Id)
end

-- TASCHE AM BODEN: Inhalt links (anklicken = nehmen), eigene Tasche rechts
-- ---------- Alles looten (Gamepass) ----------
-- Alles auf einmal nehmen (F an Taschen, Kisten, Lootdrops und Leichen, Knopf ALLES NEHMEN im Beute-Fenster) gibt es nur
-- mit dem Gamepass ALLES LOOTEN. Ohne ihn ist der F-Prompt aus (nur bei diesem Spieler) und man nimmt im Fenster einzeln
-- heraus; der Knopf führt dann zum Kauf. Der Server prüft das auch (LootService.Take).
local LOOT_ALL_PASS = "LootAll"

local function canTakeAll()
	return RobuxConfig.Has(player, LOOT_ALL_PASS)
end

local function buyLootAll()
	local pass = RobuxConfig.Pass(LOOT_ALL_PASS)
	if pass and pass.PassId ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
	else
		showToast("Gamepass ALLES LOOTEN kommt bald in den Robux-Shop. Bis dahin: Items anklicken", false)
	end
end

local function paintTakeAll(button)
	if canTakeAll() then
		button.SetColor(C.Primary, C.PrimaryText)
		button.SetText("ALLES NEHMEN")
	else
		button.SetColor(C.MutedBack, C.Text)
		button.SetText("ALLES NEHMEN · GAMEPASS")
	end
end

-- F-Prompt einer Tasche/Kiste/Leiche nur mit Gamepass zeigen
local function applyTakeAll(obj)
	if obj:IsA("ProximityPrompt") and obj.Name == "TakeAllPrompt" then
		obj.Enabled = canTakeAll()
	end
end

local function refreshTakeAll()
	for _, name in { "ExtinctionLoot", "Zombies" } do
		local folder = workspace:FindFirstChild(name)
		for _, obj in folder and folder:GetDescendants() or {} do
			applyTakeAll(obj)
		end
	end
	if window and window.Kind == "Loot" and window.TakeAll then
		paintTakeAll(window.TakeAll)
	end
end

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
		win.TakeAll = UITheme.Chunky({ Position = UDim2.fromOffset(0, 466), Size = UDim2.fromOffset(300, 48), Color = C.Primary,
			TextColor = C.PrimaryText, Text = "ALLES NEHMEN", TextSize = 18, ZIndex = 6 }, body, function()
			if canTakeAll() then
				sendAction("Loot", data.Id, "All")
			else
				buyLootAll()
			end
		end)
		paintTakeAll(win.TakeAll)
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

-- ---------- Hinweis-Blasen über den Ständen ----------
-- Über jedem Stand (Camp und Safehouses) schwebt eine Sprechblase mit dem Namen und Symbolen der Ware, damit man
-- schon von weitem sieht, wo was ist. Wände verdecken sie wie alles in der Welt, ab BUBBLE_RANGE Studs blendet sie aus.
local BUBBLE_RANGE = 180
local BUBBLE_HEIGHT = 9.5 -- über dem Stand-Punkt (liegt vor der Theke auf Hüfthöhe): knapp über dem Dach
local BUBBLE_CELL = 46    -- Symbolfeld in Pixeln
local BUBBLE_BACK = Color3.fromRGB(22, 24, 28)
local BUBBLES = {
	Stand_Weapons = { Title = "WAFFEN", Icons = { "Rifle", "Pistol", "Ammo_Rifle" }, Color = KIND_COLORS.Weapon },
	Stand_Items = { Title = "SANI", Icons = { "Medkit", "Vest", "AntiZombie" }, Color = KIND_COLORS.Heal },
	Stand_Vehicles = { Title = "FAHRZEUGE", Icons = { "V_Quad", "V_Pickup", "V_Heli" }, Color = KIND_COLORS.Vehicle },
	Stand_Market = { Title = "SPIELERMARKT", Icons = { "Coins", "SMG", "Medkit" }, Color = Color3.fromRGB(226, 182, 72) },
	Stash = { Title = "LAGER", Icons = { "Crate" }, Color = Color3.fromRGB(150, 160, 176) },
	Travel = { Title = "REISEN", Icons = { "Route" }, Color = Color3.fromRGB(110, 170, 220) },
}
local bubbles = {}

-- Gezeichnete Symbole für Dinge, die keine Items sind: Münzen (Markt), Kiste (Lager), Wegweiser (Reisen)
local function buildSymbol(parent, kind, zIndex)
	local holder = make("Frame", { Name = "Icon", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = zIndex },
		parent)
	local function box(props, into)
		props.BorderSizePixel = 0
		props.ZIndex = zIndex
		return make("Frame", props, into or holder)
	end
	if kind == "Coins" then
		for _, offset in { Vector2.new(-6, 5), Vector2.new(5, -3) } do
			local coin = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, offset.X, 0.5, offset.Y),
				Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromRGB(226, 182, 72) })
			UITheme.Corner(coin, 10)
			UITheme.Stroke(coin, Color3.fromRGB(150, 110, 40), 2)
			box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 10),
				BackgroundColor3 = Color3.fromRGB(150, 110, 40) }, coin)
		end
	elseif kind == "Crate" then
		local crate = box({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(30, 22),
			BackgroundColor3 = Color3.fromRGB(128, 100, 66) })
		UITheme.Corner(crate, 3)
		box({ Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = Color3.fromRGB(86, 66, 44) }, crate) -- Deckel
		for _, x in { 8, 20 } do
			box({ Position = UDim2.fromOffset(x, 5), Size = UDim2.fromOffset(2, 17), BackgroundColor3 = Color3.fromRGB(100, 78, 52) }, crate)
		end
		box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(6, 5),
			BackgroundColor3 = Color3.fromRGB(190, 192, 196) }, crate) -- Verschluss
	elseif kind == "Route" then
		local sign = Color3.fromRGB(110, 170, 220)
		box({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(3, 30),
			BackgroundColor3 = Color3.fromRGB(150, 152, 158) }) -- Pfosten
		box({ Position = UDim2.new(0.5, -2, 0, 8), Size = UDim2.fromOffset(18, 7), BackgroundColor3 = sign }) -- nach rechts
		box({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, 2, 0, 18), Size = UDim2.fromOffset(18, 7),
			BackgroundColor3 = Color3.fromRGB(232, 236, 240) }) -- nach links
	end
	return holder
end

local function bubbleOf(name)
	return BUBBLES[name] or (string.sub(name, 1, 7) == "Travel_" and BUBBLES.Travel) or nil
end

-- Blase an einen Stand-Punkt hängen (einmal je Punkt)
local function addBubble(part)
	local def = part:IsA("BasePart") and bubbleOf(part.Name)
	if not def or part:FindFirstChild("StandBubble") then
		return
	end
	local count = #def.Icons
	local gui = make("BillboardGui", { Name = "StandBubble", Size = UDim2.fromOffset(math.max(count * BUBBLE_CELL + 20, 136), 92),
		StudsOffset = Vector3.new(0, BUBBLE_HEIGHT, 0), MaxDistance = BUBBLE_RANGE, AlwaysOnTop = false, LightInfluence = 0,
		Enabled = inExtinction() }, part)
	-- Spitze unten (Sprechblase): halb hinter dem Feld, nur die untere Hälfte mit Rand ist zu sehen
	local tail = make("Frame", { Name = "Tail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -13),
		Size = UDim2.fromOffset(16, 16), Rotation = 45, BackgroundColor3 = BUBBLE_BACK, BackgroundTransparency = 0.08,
		BorderSizePixel = 0, ZIndex = 1 }, gui)
	UITheme.Stroke(tail, def.Color, 2)
	local panel = make("Frame", { Name = "Panel", Size = UDim2.new(1, 0, 1, -13), BackgroundColor3 = BUBBLE_BACK,
		BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 2 }, gui)
	UITheme.Corner(panel, 10)
	UITheme.Stroke(panel, def.Color, 2)
	label({ Name = "Title", Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 18), Text = def.Title, TextSize = 15,
		TextColor3 = def.Color, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, panel)
	local row = make("Frame", { Name = "Icons", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 27),
		Size = UDim2.fromOffset(count * BUBBLE_CELL, BUBBLE_CELL - 4), BackgroundTransparency = 1, ZIndex = 3 }, panel)
	for i, id in def.Icons do
		local cell = make("Frame", { Name = "Cell" .. i, Position = UDim2.fromOffset((i - 1) * BUBBLE_CELL + 2, 0),
			Size = UDim2.fromOffset(BUBBLE_CELL - 4, BUBBLE_CELL - 4), BackgroundColor3 = Color3.fromRGB(44, 46, 52),
			BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 3 }, row)
		UITheme.Corner(cell, 6)
		local icon = itemConfig(id) and buildIcon(cell, id, 4) or buildSymbol(cell, id, 4)
		icon.Name = "Icon_" .. id
	end
	table.insert(bubbles, gui)
end

local function setupPrompts()
	local maps = workspace:WaitForChild("Maps")
	local map = maps:WaitForChild("Extinction", 30)
	local stands = map and map:WaitForChild("Stands", 10)
	if not stands then
		return
	end
	-- Stände: jeder Teil mit dem Namen bekommt eine Aufforderung (Camp und Safehouses haben eigene)
	for key in ExtinctionConfig.Stands do
		stands:WaitForChild(key, 10)
	end
	for _, part in stands:GetChildren() do
		local stand = part:IsA("BasePart") and ExtinctionConfig.Stands[part.Name]
		if stand then
			local prompt = make("ProximityPrompt", { Name = "StandPrompt", ActionText = "Handeln", ObjectText = stand.Title,
				KeyboardKeyCode = Enum.KeyCode.E, HoldDuration = 0, MaxActivationDistance = ExtinctionConfig.StandRange - 2,
				RequiresLineOfSight = false, Enabled = false }, part)
			prompt.Triggered:Connect(function()
				openStand(part.Name)
				if window then
					window.Part = part
				end
			end)
			table.insert(prompts, prompt)
		end
	end
	-- Haltestellen (Reisen): im Camp "Travel", in den Safehouses "Travel_<Name>"
	local function travelPrompt(part)
		if not part:IsA("BasePart") or not (part.Name == "Travel" or string.sub(part.Name, 1, 7) == "Travel_") then
			return
		end
		local prompt = make("ProximityPrompt", { Name = "TravelPrompt", ActionText = "Reisen", ObjectText = "FAHRER",
			KeyboardKeyCode = Enum.KeyCode.E, HoldDuration = 0, MaxActivationDistance = ExtinctionConfig.StandRange - 2,
			RequiresLineOfSight = false, Enabled = inExtinction() }, part)
		prompt.Triggered:Connect(function()
			openTravel(part.Name)
			if window then
				window.Part = part
			end
		end)
		table.insert(prompts, prompt)
	end
	for _, part in stands:GetChildren() do
		travelPrompt(part)
	end
	-- Spielermarkt (nur im Camp)
	for _, marketPart in stands:GetChildren() do
		if marketPart:IsA("BasePart") and marketPart.Name == "Stand_Market" then
			local prompt = make("ProximityPrompt", { Name = "MarketPrompt", ActionText = "Handeln", ObjectText = "SPIELERMARKT",
				KeyboardKeyCode = Enum.KeyCode.E, HoldDuration = 0, MaxActivationDistance = ExtinctionConfig.StandRange - 2,
				RequiresLineOfSight = false, Enabled = false }, marketPart)
			prompt.Triggered:Connect(function()
				openMarket() -- Menü auf dem Reiter MARKT
			end)
			table.insert(prompts, prompt)
		end
	end
	stands:WaitForChild("Stash", 10)
	for _, stashPart in stands:GetChildren() do
		if stashPart:IsA("BasePart") and stashPart.Name == "Stash" then
			local prompt = make("ProximityPrompt", { Name = "StashPrompt", ActionText = "Lager öffnen", ObjectText = "LAGER",
				KeyboardKeyCode = Enum.KeyCode.E, HoldDuration = 0, MaxActivationDistance = ExtinctionConfig.StandRange - 2,
				RequiresLineOfSight = false, Enabled = false }, stashPart)
			prompt.Triggered:Connect(function()
				openStash()
				if window then
					window.Part = stashPart
				end
			end)
			table.insert(prompts, prompt)
		end
	end
	-- Hinweis-Blasen über allen Ständen, dem Lager und den Haltestellen
	for _, part in stands:GetChildren() do
		addBubble(part)
	end
	for _, prompt in prompts do
		prompt.Enabled = inExtinction()
	end
	for _, gui in bubbles do
		gui.Enabled = inExtinction()
	end
end

-- Fenster am Stand/Lager schließen, wenn man weggeht
local function standDistanceCheck()
	if not window or (window.Kind ~= "Stand" and window.Kind ~= "Stash" and window.Kind ~= "Travel") then
		return
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local maps = workspace:FindFirstChild("Maps")
	local stands = maps and maps:FindFirstChild("Extinction") and maps.Extinction:FindFirstChild("Stands")
	local part = window.Part
		or (stands and stands:FindFirstChild(window.Kind == "Stash" and "Stash" or window.Kind == "Travel" and window.Point
			or window.Stand))
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
		InputActions.Refocus(window.Frame)
	end
	repaint()
end

-- Controller in der offenen Welt: dieselben Tasten tragen angetippt und gehalten zwei Aktionen (InputActions.PadHold),
-- weil es auf dem Controller nicht genug Tasten gibt. Außerhalb gelten wieder die normalen Belegungen.
--   Steuerkreuz oben: antippen = Ping, halten = Weltkarte
--   Select:           antippen = Inventar, halten = Squad
--   △:                antippen = heilen, halten = Fahrzeug einpacken
InputActions.Bindings.QuickHeal = { Keys = {}, Pad = {} }
local function applyPadLayout()
	local on = inExtinction()
	local function hold(action, code)
		local binding = InputActions.Bindings[action]
		if binding then
			binding.PadHold = on and { code } or nil
		end
	end
	hold("WorldMap", Enum.KeyCode.DPadUp)
	hold("Squad", Enum.KeyCode.ButtonSelect)
	hold("StoreVehicle", Enum.KeyCode.ButtonY)
	InputActions.Bindings.QuickHeal.Pad = on and { Enum.KeyCode.ButtonY } or {}
end

-- Heilen mit einem Druck: Medikit, wenn viel Leben fehlt, sonst Verband (bzw. was in der Hotbar liegt)
local function quickHeal()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local missing = humanoid and (humanoid.MaxHealth - humanoid.Health) or 0
	local best, bestScore = nil, -math.huge
	for slot = 1, HOTBAR do
		local entry = bag[slot]
		local config = entry and itemConfig(entry.Id)
		if config and config.Kind == "Heal" then
			local score = entry.Id == "Medkit" and (missing >= 50 and 3 or 1) or (entry.Id == "Bandage" and 2 or 0)
			if score > bestScore then
				best, bestScore = slot, score
			end
		end
	end
	if best then
		sendAction("Use", best)
	else
		showToast("Kein Heil-Item in der Hotbar.", false)
	end
end

local function updateVisible()
	local on = inExtinction()
	applyPadLayout()
	updateHints()
	if hud then
		hud.Enabled = on
	end
	for _, prompt in prompts do
		prompt.Enabled = on
	end
	for _, gui in bubbles do
		gui.Enabled = on
	end
	if not on then
		closeWindow()
		ExtinctionMap.Set(false)
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
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, player:WaitForChild("PlayerGui"))
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
			openInventory() -- Menü auf dem Reiter INVENTAR
		end
	end)
	-- Weltkarte: N (Controller: Steuerkreuz oben), auf Touch der Knopf KARTE oben rechts
	ExtinctionMap.Init()
	InputActions.Bindings.WorldMap = { Keys = { Enum.KeyCode.N }, Pad = {} } -- Controller: siehe applyPadLayout
	InputActions.Bind("WorldMap", function(began)
		if began and inExtinction() then
			closeWindow()
			ExtinctionMap.Toggle()
		end
	end)
	local mapButton = make("TextButton", { Name = "MapButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 30),
		Size = UDim2.fromOffset(110, 30), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0,
		Text = "", AutoButtonColor = true }, root)
	UITheme.Corner(mapButton, UITheme.Radius.Small)
	label({ Size = UDim2.fromScale(1, 1), Text = "KARTE  ·  N", TextSize = 14, Font = F.Bold, TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Center }, mapButton)
	mapButton.Activated:Connect(function()
		ExtinctionMap.Toggle()
	end)
	-- Squad: J (oder Knopf unter KARTE) öffnet das Fenster; Einladungen nimmt man dort an
	InputActions.Bindings.Squad = { Keys = { Enum.KeyCode.J }, Pad = {} }
	local function toggleSquad()
		if window and window.Kind == "Squad" then
			closeWindow()
		else
			ExtinctionMap.Set(false)
			openSquad()
		end
	end
	InputActions.Bind("Squad", function(began)
		if began and inExtinction() then
			toggleSquad()
		end
	end)
	local squadButton = make("TextButton", { Name = "SquadButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 62),
		Size = UDim2.fromOffset(110, 22), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0,
		Text = "", AutoButtonColor = true }, root)
	UITheme.Corner(squadButton, UITheme.Radius.Small)
	local squadButtonText = label({ Size = UDim2.fromScale(1, 1), Text = "SQUAD  ·  J", TextSize = 12, Font = F.Bold, TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Center }, squadButton)
	squadButton.Activated:Connect(toggleSquad)
	-- Einladung: Hinweis (die Maus ist im Spiel gefangen, darum annehmen im Squad-Fenster)
	Remotes.PartyInvite.OnClientEvent:Connect(function(name, userId)
		if not inExtinction() then
			return
		end
		pendingInvite = { Name = tostring(name), UserId = userId, Until = os.clock() + 55 }
		showToast(upper(tostring(name)) .. " LÄDT DICH IN DEN SQUAD EIN  ·  " .. (InputActions.Hint("Squad") ~= ""
			and (InputActions.Hint("Squad") .. " ZUM ANNEHMEN") or "SQUAD ZUM ANNEHMEN"), true)
		if window and window.Kind == "Squad" then
			window.Refresh()
		end
	end)
	-- Meldungen des Squad-Systems (Einladung gesendet, Squad voll ...)
	Remotes.ShopStatus.OnClientEvent:Connect(function(text, ok)
		if inExtinction() and type(text) == "string" then
			showToast(text, ok == true)
		end
	end)
	player:GetAttributeChangedSignal("Party"):Connect(function()
		if window and window.Kind == "Squad" then
			window.Refresh()
		end
	end)
	-- Squad-Liste links unter den Aufträgen: Mitglieder mit Ort/Entfernung und Leben
	local squadPanel = make("Frame", { Name = "Squad", Position = UDim2.fromOffset(24, 480), Size = UDim2.fromOffset(270, 26),
		BackgroundColor3 = C.Panel, BackgroundTransparency = 0.3, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false }, root)
	UITheme.Corner(squadPanel, UITheme.Radius.Small)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, squadPanel)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10) }, squadPanel)
	label({ Name = "Head", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 16), Text = "SQUAD", TextSize = 13, Font = F.Display,
		TextColor3 = C.Ally }, squadPanel)
	local squadRows = {} -- [UserId] = { Frame, Where, Fill, Player }
	local function refreshSquadPanel()
		local party = squadInfo()
		local seen = {}
		local order = 0
		for _, member in party and party.Members or {} do
			if member.UserId ~= player.UserId then
				order += 1
				seen[member.UserId] = true
				local entry = squadRows[member.UserId]
				if not entry then
					local frame = make("Frame", { Name = "Member", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, squadPanel)
					local nameLabel = label({ Name = "Name", Size = UDim2.new(1, -110, 0, 16), Text = "", TextSize = 12, Font = F.Bold,
						TextColor3 = C.Text, TextTruncate = Enum.TextTruncate.AtEnd }, frame)
					local where = label({ Name = "Where", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
						Size = UDim2.fromOffset(108, 16), Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted,
						TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd }, frame)
					local bar = make("Frame", { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = C.Card,
						BorderSizePixel = 0 }, frame)
					local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ally, BorderSizePixel = 0 }, bar)
					entry = { Frame = frame, Name = nameLabel, Where = where, Fill = fill }
					squadRows[member.UserId] = entry
				end
				entry.Frame.LayoutOrder = order
				entry.Name.Text = (member.UserId == party.Leader and "★ " or "") .. upper(tostring(member.Name))
				entry.Player = Players:GetPlayerByUserId(member.UserId)
			end
		end
		for userId, entry in squadRows do
			if not seen[userId] then
				entry.Frame:Destroy()
				squadRows[userId] = nil
			end
		end
		squadPanel.Visible = order > 0
		squadButtonText.Text = order > 0 and ("SQUAD " .. (order + 1) .. "/4  ·  J") or "SQUAD  ·  J"
	end
	local function tickSquadPanel()
		for _, entry in squadRows do
			local where, health = whereIs(entry.Player)
			entry.Where.Text = where
			entry.Fill.Size = UDim2.fromScale(math.clamp(health or 0, 0, 1), 1)
			entry.Fill.BackgroundColor3 = (health or 1) <= 0.3 and C.Bad or C.Ally
		end
	end
	player:GetAttributeChangedSignal("Party"):Connect(refreshSquadPanel)
	refreshSquadPanel()
	-- Aufträge links unter dem VERLASSEN-Knopf des HUD (Spieler-Attribut ExtMissions vom MissionService). Der Knopf rutscht
	-- je nach Bildschirm tiefer (unter die Roblox-Leiste), auf Touch steht die Lebensanzeige darunter: die Liste folgt mit
	-- etwas Abstand (missionTop).
	local missionHeight = 0
	local missionPanel = make("Frame", { Name = "Missions", Position = UDim2.fromOffset(24, 330), Size = UDim2.fromOffset(270, 26),
		BackgroundColor3 = C.Panel, BackgroundTransparency = 0.3, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.Y }, root)
	UITheme.Corner(missionPanel, UITheme.Radius.Small)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, missionPanel)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10) }, missionPanel)
	label({ Name = "Head", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 16), Text = "AUFTRÄGE", TextSize = 13, Font = F.Display,
		TextColor3 = C.Primary }, missionPanel)
	local function refreshMissions()
		for _, child in missionPanel:GetChildren() do
			if child.Name == "Mission" then
				child:Destroy()
			end
		end
		local ok, list = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("ExtMissions") or "[]")
		list = ok and type(list) == "table" and list or {}
		missionPanel.Visible = #list > 0
		missionHeight = #list > 0 and (30 + 34 * #list) or 0 -- Kopf, Zeilen, Abstände (für die Squad-Liste darunter)
		for index, mission in list do
			local row = make("Frame", { Name = "Mission", LayoutOrder = index, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 },
				missionPanel)
			label({ Name = "Text", Size = UDim2.new(1, -54, 0, 16), Text = upper(tostring(mission.Text or "")), TextSize = 12,
				Font = F.Bold, TextColor3 = C.Text, TextTruncate = Enum.TextTruncate.AtEnd }, row)
			label({ Name = "Count", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(52, 16),
				Text = tostring(mission.Have or 0) .. "/" .. tostring(mission.Need or 1), TextSize = 12, Font = F.Bold,
				TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, row)
			local bar = make("Frame", { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = C.Card,
				BorderSizePixel = 0 }, row)
			make("Frame", { Name = "Fill", Size = UDim2.fromScale(math.clamp((mission.Have or 0) / math.max(1, mission.Need or 1), 0, 1), 1),
				BackgroundColor3 = C.Good, BorderSizePixel = 0 }, bar)
		end
	end
	player:GetAttributeChangedSignal("ExtMissions"):Connect(refreshMissions)
	refreshMissions()
	local function missionTop()
		local hudGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("HUD")
		local hudRoot = hudGui and hudGui:FindFirstChild("Root")
		local bottom = nil
		for _, name in { "LeaveButton", "Vitals" } do
			local item = hudRoot and hudRoot:FindFirstChild(name)
			-- Unterkante oben angeordneter Teile (auf dem PC hängt die Lebensanzeige unten am Rand und zählt nicht);
			-- beide HUDs haben dieselbe Skalierung, die Werte passen also direkt
			if item and item:IsA("GuiObject") and item.Position.Y.Scale == 0 then
				bottom = math.max(bottom or 0, item.Position.Y.Offset + item.Size.Y.Offset * (1 - item.AnchorPoint.Y))
			end
		end
		return bottom and bottom + MISSION_GAP or nil
	end

	-- Uhrzeit (Tag und Nacht, DayCycle) links neben dem Kartenknopf
	local clockText = label({ Name = "Clock", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -140, 0, 30),
		Size = UDim2.fromOffset(260, 30), Text = "", TextSize = 15, Font = F.Bold, TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Right }, root)
	UITheme.Outline(clockText)
	-- Rote Zone (zieht alle 20 Minuten weiter): Ort, Zeit bis zum Wechsel und Entfernung als Zeile unter der Uhr (kein
	-- Richtungspfeil); bei mehreren Zonen die nächste
	local redzoneText = label({ Name = "RedzoneInfo", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -140, 0, 58),
		Size = UDim2.fromOffset(360, 20), Text = "", TextSize = 13, Font = F.Bold, TextColor3 = RED,
		TextXAlignment = Enum.TextXAlignment.Right }, root)
	UITheme.Outline(redzoneText)

	-- Rangliste (Karten-Attribut RedzoneBoard vom Server, siehe RedzoneBoard): nur in der roten Zone, die Top 3 der
	-- Spieler-Kills dieser Runde (jeder Wechsel des Ortes beginnt eine neue); der eigene Platz darunter, wenn man Kills
	-- hat, aber nicht unter den ersten drei steht
	local board = UITheme.HudPanel({ Name = "RedzoneBoard", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, BOARD_TOP),
		Size = UDim2.fromOffset(BOARD_W, BOARD_H_SHORT), Visible = false }, root, "Left")
	make("Frame", { Name = "Accent", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 2 }, board)
	label({ Name = "Caption", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 14), Text = "ROTE ZONE  ·  TOP KILLS",
		TextSize = 11, Font = F.Bold, TextColor3 = RED, ZIndex = 2 }, board)
	local boardTitle = label({ Name = "Title", Position = UDim2.fromOffset(12, 20), Size = UDim2.new(1, -24, 0, 20), Text = "",
		TextSize = 16, Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 }, board)
	local function boardRow(name, y, rankText, rankColor)
		local row = make("Frame", { Name = name, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 20),
			BackgroundTransparency = 1, ZIndex = 2 }, board)
		label({ Name = "Rank", Size = UDim2.fromOffset(24, 20), Text = rankText, TextSize = 15, Font = F.Display,
			TextColor3 = rankColor, ZIndex = 2 }, row)
		local who = label({ Name = "Player", Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -74, 1, 0), Text = "",
			TextSize = 13, Font = F.Bold, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 }, row)
		local kills = label({ Name = "Kills", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(44, 20), Text = "", TextSize = 15, Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 2 }, row)
		return { Row = row, Player = who, Kills = kills }
	end
	local boardRows = {}
	for i = 1, 3 do
		boardRows[i] = boardRow("Top" .. i, 44 + (i - 1) * 22, tostring(i), i == 1 and C.Gold or C.Muted)
	end
	local ownLine = make("Frame", { Name = "OwnLine", Position = UDim2.fromOffset(12, 113), Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = C.Border, BorderSizePixel = 0, ZIndex = 2, Visible = false }, board)
	local ownRow = boardRow("Own", 118, "", C.Primary)
	ownRow.Row.Visible = false
	local boardRaw, boardZone = false, false -- zuletzt gezeigter Stand (false = noch nie)
	local function refreshBoard(raw, zoneKey)
		local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "null")
		data = ok and type(data) == "table" and data or {}
		local zones = type(data.Zones) == "table" and data.Zones or {}
		board.Visible = type(zoneKey) == "string"
		if not board.Visible then
			return
		end
		local zone = type(zones[zoneKey]) == "table" and zones[zoneKey] or {}
		boardTitle.Text = upper(tostring(zone.Title or ""))
		local list = type(zone.List) == "table" and zone.List or {}
		local ownRank = nil
		for index, entry in list do
			if type(entry) == "table" and entry.Id == player.UserId then
				ownRank = index
				break
			end
		end
		for i, view in boardRows do
			local entry = type(list[i]) == "table" and list[i] or nil
			view.Player.Text = entry and tostring(entry.Name or "?") or "—"
			view.Player.TextColor3 = entry and (i == ownRank and C.Primary or C.Text) or C.Muted
			view.Kills.Text = entry and tostring(math.floor(tonumber(entry.Kills) or 0)) or ""
		end
		local showOwn = ownRank ~= nil and ownRank > #boardRows
		ownLine.Visible = showOwn
		ownRow.Row.Visible = showOwn
		if showOwn then
			ownRow.Player.Text = "DU  ·  PLATZ " .. ownRank
			ownRow.Player.TextColor3 = C.Primary
			ownRow.Kills.Text = tostring(math.floor(tonumber(list[ownRank].Kills) or 0))
		end
		board.Size = UDim2.fromOffset(BOARD_W, showOwn and BOARD_H or BOARD_H_SHORT)
	end

	RunService.Heartbeat:Connect(function()
		if not hud.Enabled then
			return
		end
		local missionY, missionX = missionTop(), InputActions.IsTouch() and 16 or 24
		if missionY and (missionPanel.Position.Y.Offset ~= missionY or missionPanel.Position.X.Offset ~= missionX) then
			missionPanel.Position = UDim2.fromOffset(missionX, missionY)
		end
		local squadY = missionPanel.Position.Y.Offset + (missionHeight > 0 and missionHeight + 10 or 0)
		if squadPanel.Position.Y.Offset ~= squadY or squadPanel.Position.X.Offset ~= missionPanel.Position.X.Offset then
			squadPanel.Position = UDim2.fromOffset(missionPanel.Position.X.Offset, squadY)
		end
		if squadPanel.Visible then
			tickSquadPanel()
		end
		if window and window.Kind == "Squad" and window.Tick then
			window.Tick()
		end
		local serverTime = workspace:GetServerTimeNow()
		local clock = DayCycle.Clock(serverTime)
		if DayCycle.IsBloodMoon(serverTime) then
			local left = math.floor(DayCycle.BloodMoonLeft(serverTime))
			clockText.Text = string.format("BLUTMOND  %d:%02d  ·  BOSSE · BESSERE BEUTE", left // 60, left % 60)
			clockText.TextColor3 = Color3.fromRGB(255, 70, 60)
		elseif DayCycle.IsNight(clock) then
			clockText.Text = "NACHT  " .. DayCycle.Label(clock) .. "  ·  MEHR ZOMBIES"
			clockText.TextColor3 = Color3.fromRGB(150, 170, 255)
		else
			clockText.Text = "TAG  " .. DayCycle.Label(clock)
			clockText.TextColor3 = C.Text
		end
		local maps = workspace:FindFirstChild("Maps")
		local map = maps and maps:FindFirstChild("Extinction")
		local boardData, zoneKey = map and map:GetAttribute("RedzoneBoard"), player:GetAttribute("Redzone")
		if boardData ~= boardRaw or zoneKey ~= boardZone then
			boardRaw, boardZone = boardData, zoneKey
			refreshBoard(boardData, zoneKey)
		end
		local character = player.Character
		local root3 = character and character:FindFirstChild("HumanoidRootPart")
		local nearest, nearestDistance = nil, math.huge
		for _, zone in mapList(map, "Redzones") do
			if type(zone) == "table" and tonumber(zone.X) and tonumber(zone.Z) then
				local distance = 0
				if root3 then
					local dx, dz = zone.X - root3.Position.X, zone.Z - root3.Position.Z
					distance = math.sqrt(dx * dx + dz * dz) - (tonumber(zone.R) or 0)
				end
				if not nearest or distance < nearestDistance then
					nearest, nearestDistance = zone, distance
				end
			end
		end
		if nearest then
			local left = math.max(0, math.floor((tonumber(nearest.Ends) or serverTime) - serverTime))
			local text = "ROTE ZONE  " .. string.upper(tostring(nearest.Title or "")) .. "  ·  WECHSEL IN "
				.. string.format("%d:%02d", left // 60, left % 60)
			if root3 then
				text ..= nearestDistance <= 0 and "  ·  DU BIST DRIN" or ("  ·  " .. math.floor(nearestDistance) .. " M")
			end
			redzoneText.Text = text
			redzoneText.Visible = true
		else
			redzoneText.Visible = false
		end
	end)
	-- Controller: △ halten (Waffenwechsel gibt es hier nicht, die Hotbar macht das)
	InputActions.Bindings.StoreVehicle = { Keys = { Enum.KeyCode.K }, Pad = {} } -- Controller: △ halten (applyPadLayout)
	InputActions.Bind("StoreVehicle", function(began)
		if began and inExtinction() then
			sendAction("StoreVehicle")
		end
	end)
	-- Controller: △ antippen heilt mit einem Heil-Item aus der Hotbar
	InputActions.Bind("QuickHeal", function(began)
		if began and inExtinction() then
			quickHeal()
		end
	end)
	applyPadLayout()
	-- Controller: R1/L1 (in der offenen Welt keine Gadgets/Fähigkeiten) wechseln die Hotbar
	-- (im offenen Menü: Reiter weiterblättern)
	InputActions.Bind("Gadget", function(began)
		if began and inExtinction() and InputActions.Device() == "Gamepad" then
			if window and window.Menu then
				cycleMenu(1)
			else
				cycle(1)
			end
		end
	end)
	InputActions.Bind("Ability", function(began)
		if began and inExtinction() and InputActions.Device() == "Gamepad" then
			if window and window.Menu then
				cycleMenu(-1)
			else
				cycle(-1)
			end
		end
	end)
	-- Touch: der Knopf WAFFE wechselt durch die Waffen der Hotbar
	InputActions.Bind("SwapWeapon", function(began)
		if began and inExtinction() and InputActions.IsTouch() then
			cycle(1)
		end
	end)
	-- M (Controller: Steuerkreuz unten): Menü auf dem zuletzt offenen Reiter; zu, wenn schon etwas offen ist
	InputActions.Bind("Menu", function(began)
		if not began then
			return
		end
		if window then
			closeWindow()
		elseif inExtinction() then
			openMenuTab(lastMenuTab)
		end
	end)
	-- Controller: ○ schließt das offene Fenster (auch wenn darin gerade ein Knopf ausgewählt ist)
	UserInputService.InputBegan:Connect(function(input)
		if window and input.KeyCode == Enum.KeyCode.ButtonB then
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
	-- Markt-Reiter: Münzen (KAUFEN / ZU TEUER) und Safe Zone (Sperre) neu zeichnen
	for _, attribute in { "Coins", "InSafeZone" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if window and window.Kind == "Market" and window.Refresh then
				window.Refresh()
			end
		end)
	end
	player:GetAttributeChangedSignal("Mode"):Connect(updateVisible)
	-- Alles looten: F-Prompts nur mit Gamepass (auch für später entstehende Taschen, Kisten und Leichen)
	refreshTakeAll()
	workspace.DescendantAdded:Connect(applyTakeAll)
	player:GetAttributeChangedSignal("Pass_" .. LOOT_ALL_PASS):Connect(refreshTakeAll)
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
		updateShield()
		updateMarkers()
		updatePlace()
		standDistanceCheck()
		-- im Fahrzeug: Name, Tempo und Zustand; sonst die Wartezeit nach dem Einpacken
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		local vehicle = seat and seat:GetAttribute("Vehicle") and seat.Parent
		local pilot = false
		if vehicle and vehicle:GetAttribute("VehicleId") and vehicle.PrimaryPart then
			local velocity = vehicle.PrimaryPart.AssemblyLinearVelocity
			local speed = math.floor(Vector3.new(velocity.X, 0, velocity.Z).Magnitude + 0.5)
			local health = math.ceil(100 * (vehicle:GetAttribute("Health") or 0) / math.max(1, vehicle:GetAttribute("MaxHealth") or 1))
			local owner = vehicle:GetAttribute("Owner") == player.UserId
			local heli = (ExtinctionConfig.Vehicles[vehicle:GetAttribute("VehicleId")] or {}).Kind == "Heli"
			local text = upper(vehicle.Name) .. "  ·  TEMPO " .. speed
			local landed = true
			if heli then
				-- Helikopter: Höhe über dem Boden; einpacken erst gelandet
				local height = VehicleClient.Height(vehicle)
				landed = height < 4
				text ..= "  ·  HÖHE " .. (height < math.huge and math.max(0, math.floor(height + 0.5)) or "–")
				pilot = owner and seat:IsA("VehicleSeat")
			end
			vehicleCooldown.Text = text .. "  ·  ZUSTAND " .. health .. " %" .. ((owner and landed) and "  ·  K EINPACKEN" or "")
			vehicleCooldown.TextColor3 = health <= 30 and C.Bad or C.Text
		else
			local readyAt = player:GetAttribute("ExtVehicleReadyAt") or 0
			local left = readyAt - workspace:GetServerTimeNow()
			vehicleCooldown.Text = left > 0 and ("FAHRZEUG WIEDER BEREIT IN " .. math.ceil(left) .. " S") or ""
			vehicleCooldown.TextColor3 = C.Muted
		end
		if pilot ~= heliHints then
			heliHints = pilot
			updateHints()
		end
	end)

	refreshAll()
	updateVisible()
	task.spawn(setupPrompts)
end

return ExtinctionClient
