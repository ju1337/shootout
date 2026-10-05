-- LootService (ModuleScript, nur Server)
-- Taschen am Boden der offenen Welt (EXTINCTION): Wer außerhalb der Safe Zone stirbt (oder dort das Spiel bzw. den
-- Modus verlässt), lässt seine ganze Tasche fallen; Zombies lassen manchmal einen kleinen Beutel fallen; Spieler
-- können Stapel fallen lassen. Jeder, der nah genug ist, kann mit E durchsuchen und Items herausnehmen.
-- Modelle liegen in Workspace.ExtinctionLoot (Teil "LootBag" mit ProximityPrompt), Inhalt nur auf dem Server.
-- Client: Remotes.ExtUpdate("Loot", { Id, Title, Items }) öffnet/aktualisiert das Fenster, ("LootClosed", Id) schließt es.
-- Herausnehmen: Remotes.ExtAction("Loot", Id, Platz) bzw. ("Loot", Id, "All").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Inventory = require(Shared.Inventory)
local Modes = require(Shared.Modes)
local InventoryService = require(script.Parent.InventoryService)

local LootService = {}

local folder = workspace:FindFirstChild("ExtinctionLoot") or Instance.new("Folder")
folder.Name = "ExtinctionLoot"
folder.Parent = workspace

local bags = {} -- [Id] = { Id, Title, Kind, Container, Model, Part, Expires, Viewers = { [Player] = true } }
local nextId = 0

-- Aussehen: Todestasche groß und braun, Beutel (Zombie, fallen gelassen) klein und oliv mit Licht
local LOOKS = {
	Death = { Size = Vector3.new(2.4, 1.5, 1.8), Color = Color3.fromRGB(92, 66, 44), Light = Color3.fromRGB(255, 120, 80) },
	Drop = { Size = Vector3.new(1.5, 1.1, 1.3), Color = Color3.fromRGB(96, 104, 64), Light = Color3.fromRGB(255, 220, 120) },
}

local function contents(bag)
	local list = {}
	for slot = 1, bag.Container.Size do
		local item = bag.Container.Slots[slot]
		if item then
			table.insert(list, { S = slot, Id = item.Id, N = item.Count, Mag = item.Mag })
		end
	end
	return list
end

local function send(player, bag)
	Remotes.ExtUpdate:FireClient(player, "Loot", { Id = bag.Id, Title = bag.Title, Items = contents(bag) })
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function inRange(player, bag)
	local root = rootOf(player)
	return root ~= nil and bag.Part.Parent ~= nil
		and (root.Position - bag.Part.Position).Magnitude <= ExtinctionConfig.LootRange
		and Modes.IsSurvival(player:GetAttribute("Mode"))
end

function LootService.Remove(id)
	local bag = bags[id]
	if not bag then
		return
	end
	bags[id] = nil
	for viewer in bag.Viewers do
		if viewer.Parent then
			Remotes.ExtUpdate:FireClient(viewer, "LootClosed", id)
		end
	end
	bag.Model:Destroy()
end

-- Neue Tasche bei position (wird auf den Boden gelegt). items = { { Id, Count, Mag } }, kind = "Death" oder "Drop".
-- Gibt die Id zurück (nil, wenn nichts drin wäre).
function LootService.Create(position, items, kind, title)
	local list = {}
	for _, item in items do
		if ExtinctionConfig.Get(item.Id) and (item.Count or 0) > 0 then
			table.insert(list, item)
		end
	end
	if #list == 0 then
		return nil
	end
	nextId += 1
	local id = nextId
	local container = Inventory.New(math.max(#list, 1))
	for slot, item in list do
		container.Slots[slot] = { Id = item.Id, Count = item.Count, Mag = item.Mag }
	end
	local look = LOOKS[kind] or LOOKS.Drop

	-- auf den Boden legen (Charaktere und andere Taschen ignorieren)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local zombies = workspace:FindFirstChild("Zombies")
	if zombies then
		table.insert(ignore, zombies)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -60, 0), params)
	local ground = hit and hit.Position or position

	local model = Instance.new("Model")
	model.Name = "Loot_" .. id
	local part = Instance.new("Part")
	part.Name = "LootBag"
	part.Size = look.Size
	part.Color = look.Color
	part.Material = Enum.Material.Fabric
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(ground + Vector3.new(0, look.Size.Y / 2, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	part:SetAttribute("LootBag", id)
	part:SetAttribute("Kind", kind)
	part.Parent = model
	local strap = Instance.new("Part")
	strap.Name = "Strap"
	strap.Size = Vector3.new(look.Size.X + 0.08, 0.25, look.Size.Z * 0.35)
	strap.Color = look.Color:Lerp(Color3.new(0, 0, 0), 0.4)
	strap.Material = Enum.Material.Fabric
	strap.Anchored = true
	strap.CanCollide = false
	strap.CanQuery = false
	strap.CanTouch = false
	strap.CFrame = part.CFrame * CFrame.new(0, look.Size.Y * 0.2, 0)
	strap.Parent = model
	local light = Instance.new("PointLight")
	light.Color = look.Light
	light.Range = kind == "Death" and 10 or 7
	light.Brightness = 0.8
	light.Parent = part

	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.fromOffset(160, 22)
	label.StudsOffset = Vector3.new(0, 2.2, 0)
	label.MaxDistance = 70
	label.AlwaysOnTop = true
	label.Parent = part
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 13
	text.TextColor3 = look.Light
	text.TextStrokeTransparency = 0.4
	text.Text = title
	text.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootPrompt"
	prompt.ActionText = "Durchsuchen"
	prompt.ObjectText = title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = kind == "Death" and 0.4 or 0
	prompt.MaxActivationDistance = ExtinctionConfig.LootRange - 1
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	model.Parent = folder

	local bag = {
		Id = id,
		Title = title,
		Kind = kind,
		Container = container,
		Model = model,
		Part = part,
		Expires = os.clock() + (kind == "Death" and ExtinctionConfig.BagLifetime or ExtinctionConfig.DropLifetime),
		Viewers = {},
	}
	bags[id] = bag
	prompt.Triggered:Connect(function(player)
		LootService.Open(player, id)
	end)
	return id
end

-- Fenster öffnen (nach E)
function LootService.Open(player, id)
	local bag = bags[id]
	if not bag or not inRange(player, bag) then
		return false
	end
	bag.Viewers[player] = true
	send(player, bag)
	return true
end

-- Item herausnehmen: slot = Platz in der Tasche oder "All"
function LootService.Take(player, id, slot)
	local bag = type(id) == "number" and bags[id]
	if not bag then
		return false
	end
	if not inRange(player, bag) then
		InventoryService.Status(player, "Du bist zu weit weg.")
		return false
	end
	local playerBag = InventoryService.GetBag(player)
	if not playerBag then
		return false
	end
	local slots = {}
	if slot == "All" then
		for s = 1, bag.Container.Size do
			table.insert(slots, s)
		end
	elseif type(slot) == "number" then
		slots = { slot }
	end
	local moved, full = false, false
	for _, s in slots do
		if bag.Container.Slots[s] then
			if Inventory.Move(bag.Container, s, playerBag, nil) then
				moved = true
			end
			if bag.Container.Slots[s] then
				full = true -- passte nicht (ganz) in die Tasche
			end
		end
	end
	if full then
		InventoryService.Status(player, "Deine Tasche ist voll.")
	end
	if moved then
		InventoryService.Changed(player)
		if Inventory.IsEmpty(bag.Container) then
			LootService.Remove(id)
		else
			for viewer in bag.Viewers do
				if viewer.Parent then
					send(viewer, bag)
				end
			end
		end
	end
	return moved
end

-- Fenster geschlossen (Client)
function LootService.Close(player, id)
	local bag = type(id) == "number" and bags[id]
	if bag then
		bag.Viewers[player] = nil
	end
end

-- Inhalt einer Tasche (für Tests und Admin)
function LootService.Get(id)
	return bags[id]
end

function LootService.Init()
	InventoryService.Handlers.Loot = LootService.Take
	InventoryService.Handlers.LootClose = LootService.Close
	InventoryService.Handlers.LootOpen = LootService.Open
	-- "Fallen lassen" aus dem Inventar: kleiner Beutel
	InventoryService.DropItems = function(player, items, position)
		LootService.Create(position, items, "Drop", "BEUTEL · " .. player.Name)
	end
	-- Abgelaufene Taschen entfernen, Zuschauer außer Reichweite abmelden
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for id, bag in bags do
				if now >= bag.Expires or not bag.Model.Parent then
					LootService.Remove(id)
				else
					for viewer in bag.Viewers do
						if not viewer.Parent or not inRange(viewer, bag) then
							bag.Viewers[viewer] = nil
							if viewer.Parent then
								Remotes.ExtUpdate:FireClient(viewer, "LootClosed", id)
							end
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, bag in bags do
			bag.Viewers[player] = nil
		end
	end)
end

return LootService
