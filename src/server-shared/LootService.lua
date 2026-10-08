-- LootService (ModuleScript, nur Server)
-- Beute am Boden der offenen Welt (EXTINCTION). Arten ("Kind"):
--   Death    Todestasche: Wer außerhalb der Safe Zone stirbt (oder dort das Spiel bzw. den Modus verlässt), lässt seine ganze
--            Tasche fallen. Großer Rucksack mit rotem Licht und Lichtsäule, 5 Minuten (BagLifetime).
--   Drop     "Fallen lassen" aus dem Inventar: kleiner Beutel, 90 Sekunden (DropLifetime).
--   Crate    Lagerkiste in der Welt (ContainerService): bleibt, bis sie leer ist, dann füllt sie sich später neu.
--   Airdrop  Versorgungsabwurf (AirdropService): großes Kiste, E halten zum Öffnen.
--   Corpse   Beute in einer Zombie-Leiche (LootService.Attach): ohne eigenes Modell, die Leiche selbst ist die Tasche.
-- Jeder, der nah genug ist, kann mit E durchsuchen (Fenster) und Items einzeln herausnehmen. Alles auf einmal nehmen
-- (F bzw. Knopf ALLES NEHMEN) gibt es nur mit dem Gamepass ALLES LOOTEN (RobuxConfig, Attribut Pass_LootAll); ohne ihn
-- öffnet F das Fenster. Belohnungen (Aufträge, Verstecke) legt LootService.Grab direkt ins Inventar.
-- Modelle liegen in Workspace.ExtinctionLoot (Teil "LootBag" mit ProximityPrompts), Inhalt nur auf dem Server.
-- Client: Remotes.ExtUpdate("Loot", { Id, Title, Items }) öffnet/aktualisiert das Fenster, ("LootClosed", Id) schließt es.
-- Herausnehmen: Remotes.ExtAction("Loot", Id, Platz) bzw. ("Loot", Id, "All").
-- Andere Dienste: LootService.OnRemoved = { callback(bag) } wird aufgerufen, wenn eine Tasche/Kiste weg ist (leer, abgelaufen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Inventory = require(Shared.Inventory)
local Modes = require(Shared.Modes)
local RobuxConfig = require(Shared.RobuxConfig)
local InventoryService = require(script.Parent.InventoryService)

local LootService = {}

-- Alles auf einmal nehmen: nur mit dem Gamepass
LootService.TakeAllPass = "LootAll"
LootService.TakeAllHint = "ALLES NEHMEN gibt es mit dem Gamepass ALLES LOOTEN im Robux-Shop. Einzeln herausnehmen geht immer."

function LootService.CanTakeAll(player)
	return RobuxConfig.Has(player, LootService.TakeAllPass)
end

LootService.OnRemoved = {}
-- callback(player, bag): jemand hat eine Tasche/Kiste geöffnet oder alles genommen (Aufträge zählen Lootdrops)
LootService.OnOpened = {}

local function opened(player, bag)
	for _, callback in LootService.OnOpened do
		local ok, err = pcall(callback, player, bag)
		if not ok then
			warn("LootService.OnOpened: " .. tostring(err))
		end
	end
end

local folder = workspace:FindFirstChild("ExtinctionLoot") or Instance.new("Folder")
folder.Name = "ExtinctionLoot"
folder.Parent = workspace

local bags = {} -- [Id] = { Id, Title, Kind, Container, Model, Part, Expires, Viewers = { [Player] = true }, Meta }
local nextId = 0

-- Farben und Licht je Art (Aussehen siehe buildModel)
local LOOKS = {
	Death = { Size = Vector3.new(2.4, 1.7, 1.8), Color = Color3.fromRGB(78, 70, 62), Light = Color3.fromRGB(255, 96, 70), Range = 12 },
	Drop = { Size = Vector3.new(1.5, 1.1, 1.3), Color = Color3.fromRGB(96, 104, 64), Light = Color3.fromRGB(255, 220, 120), Range = 7 },
	Crate = { Size = Vector3.new(3.4, 2.4, 2.4), Color = Color3.fromRGB(128, 96, 62), Light = Color3.fromRGB(255, 214, 140), Range = 8 },
	Airdrop = { Size = Vector3.new(5, 3.6, 5), Color = Color3.fromRGB(214, 120, 40), Light = Color3.fromRGB(255, 150, 60), Range = 22 },
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
		and (root.Position - bag.Part.Position).Magnitude <= (bag.Range or ExtinctionConfig.LootRange)
		and Modes.IsSurvival(player:GetAttribute("Mode"))
end

-- Kurzer Text für Items: "Verband ×2, 9mm-Munition ×14"
function LootService.Summary(items)
	local parts = {}
	for _, item in items do
		local config = ExtinctionConfig.Get(item.Id)
		if config and (item.Count or 0) > 0 then
			table.insert(parts, config.Name .. ((item.Count or 1) > 1 and (" ×" .. item.Count) or ""))
		end
	end
	return table.concat(parts, ", ")
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
	if bag.Detach then
		bag.Detach() -- Beute an einem fremden Modell (Leiche): nur Prompts weg, das Modell regelt sein Besitzer
	else
		bag.Model:Destroy()
	end
	for _, callback in LootService.OnRemoved do
		local ok, err = pcall(callback, bag)
		if not ok then
			warn("LootService.OnRemoved: " .. tostring(err))
		end
	end
end

-- ---------- Aussehen ----------

local function addPart(model, name, size, cframe, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Fabric
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	if shape then
		part.Shape = shape
	end
	part.CFrame = cframe
	part.Parent = model
	return part
end

local function darker(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Modell bauen: Hauptteil "LootBag" (Prompts, Label, Licht) plus Zierteile. origin = Mitte der Unterkante auf dem Boden.
local function buildModel(kind, look, spec, id, ground, yaw)
	local model = Instance.new("Model")
	model.Name = "Loot_" .. id
	local base = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	local size = look.Size
	local main = addPart(model, "LootBag", size, base * CFrame.new(0, size.Y / 2, 0), look.Color,
		kind == "Crate" and Enum.Material.WoodPlanks or (kind == "Airdrop" and Enum.Material.Metal or Enum.Material.Fabric))
	if kind == "Death" then
		-- Rucksack: Klappe, Taschen, Gurte, rote Markierung
		addPart(model, "Flap", Vector3.new(size.X * 0.92, 0.35, size.Z * 0.6), main.CFrame * CFrame.new(0, size.Y * 0.5, size.Z * 0.15),
			darker(look.Color, 0.25))
		for _, side in { -1, 1 } do
			addPart(model, "Pocket", Vector3.new(0.45, size.Y * 0.55, size.Z * 0.6), main.CFrame * CFrame.new(side * (size.X / 2 + 0.2), -size.Y * 0.12, 0),
				darker(look.Color, 0.15))
			addPart(model, "Strap", Vector3.new(0.3, size.Y + 0.1, 0.18), main.CFrame * CFrame.new(side * size.X * 0.28, 0, -size.Z / 2 - 0.06),
				darker(look.Color, 0.5))
		end
		addPart(model, "Mark", Vector3.new(0.7, 0.14, 0.7), main.CFrame * CFrame.new(0, size.Y / 2 + 0.2, -size.Z * 0.1),
			Color3.fromRGB(255, 70, 50), Enum.Material.Neon)
		-- Lichtsäule: von weitem zu sehen
		local beam = addPart(model, "Beam", Vector3.new(0.5, 16, 0.5), CFrame.new(ground + Vector3.new(0, 8, 0)), Color3.fromRGB(255, 80, 60),
			Enum.Material.Neon)
		beam.Transparency = 0.6
	elseif kind == "Drop" then
		addPart(model, "Knot", Vector3.new(0.5, 0.4, 0.5), main.CFrame * CFrame.new(0, size.Y / 2 + 0.15, 0), darker(look.Color, 0.4))
	elseif kind == "Crate" then
		-- Kiste mit Deckel, Kanten und je nach Art Beschriftung (SpotKind)
		local trim = darker(look.Color, 0.35)
		addPart(model, "Lid", Vector3.new(size.X + 0.2, 0.3, size.Z + 0.2), main.CFrame * CFrame.new(0, size.Y / 2 + 0.1, 0), trim,
			Enum.Material.WoodPlanks)
		for _, x in { -1, 1 } do
			addPart(model, "Edge", Vector3.new(0.25, size.Y, size.Z + 0.1), main.CFrame * CFrame.new(x * size.X * 0.36, 0, 0), trim,
				Enum.Material.Metal)
		end
		local spot = spec and spec.SpotKind
		if spot == "Medical" then
			addPart(model, "CrossH", Vector3.new(1.1, 0.12, 0.35), main.CFrame * CFrame.new(0, size.Y / 2 + 0.28, 0), Color3.fromRGB(220, 50, 50),
				Enum.Material.SmoothPlastic)
			addPart(model, "CrossV", Vector3.new(0.35, 0.12, 1.1), main.CFrame * CFrame.new(0, size.Y / 2 + 0.28, 0), Color3.fromRGB(220, 50, 50),
				Enum.Material.SmoothPlastic)
		elseif spot == "Ammo" then
			addPart(model, "Label", Vector3.new(1.4, 0.12, 0.7), main.CFrame * CFrame.new(0, size.Y / 2 + 0.28, 0), Color3.fromRGB(230, 190, 60),
				Enum.Material.SmoothPlastic)
		elseif spot == "Military" then
			addPart(model, "Stencil", Vector3.new(2.2, 0.12, 0.5), main.CFrame * CFrame.new(0, size.Y / 2 + 0.28, 0), Color3.fromRGB(210, 210, 190),
				Enum.Material.SmoothPlastic)
		elseif spot == "Toolbox" then
			addPart(model, "Handle", Vector3.new(1.6, 0.18, 0.25), main.CFrame * CFrame.new(0, size.Y / 2 + 0.45, 0), Color3.fromRGB(40, 40, 44),
				Enum.Material.Metal)
		end
	elseif kind == "Airdrop" then
		local stripe = Color3.fromRGB(240, 240, 235)
		for _, x in { -1, 1 } do
			addPart(model, "Band", Vector3.new(0.5, size.Y + 0.2, size.Z + 0.2), main.CFrame * CFrame.new(x * size.X * 0.32, 0, 0), stripe,
				Enum.Material.Metal)
		end
		addPart(model, "Lid", Vector3.new(size.X + 0.3, 0.4, size.Z + 0.3), main.CFrame * CFrame.new(0, size.Y / 2 + 0.15, 0), darker(look.Color, 0.3),
			Enum.Material.Metal)
		local beacon = addPart(model, "Beacon", Vector3.new(0.9, 0.9, 0.9), main.CFrame * CFrame.new(0, size.Y / 2 + 0.9, 0), Color3.fromRGB(255, 80, 40),
			Enum.Material.Neon, Enum.PartType.Ball)
		beacon.Transparency = 0.1
		local beam = addPart(model, "Beam", Vector3.new(1.2, 60, 1.2), CFrame.new(ground + Vector3.new(0, 30, 0)), Color3.fromRGB(255, 110, 50),
			Enum.Material.Neon)
		beam.Transparency = 0.7
	end
	return model, main
end

-- F: alles auf einmal nehmen (ohne Fenster). Der Client zeigt den Prompt nur mit dem Gamepass ALLES LOOTEN.
local function takeAllPrompt(part, title, hold, range)
	local takeAll = Instance.new("ProximityPrompt")
	takeAll.Name = "TakeAllPrompt"
	takeAll.ActionText = "Alles nehmen"
	takeAll.ObjectText = title
	takeAll.KeyboardKeyCode = Enum.KeyCode.F
	takeAll.GamepadKeyCode = Enum.KeyCode.ButtonX
	takeAll.HoldDuration = hold
	takeAll.UIOffset = Vector2.new(0, 70)
	takeAll.MaxActivationDistance = range
	takeAll.RequiresLineOfSight = false
	takeAll.Parent = part
	return takeAll
end

-- F gedrückt: mit Gamepass alles nehmen, sonst das Fenster öffnen (dort einzeln herausnehmen)
local function takeAllTriggered(player, id)
	if LootService.CanTakeAll(player) then
		LootService.Take(player, id, "All")
	elseif LootService.Open(player, id) then
		InventoryService.Status(player, LootService.TakeAllHint)
	end
end

-- Neue Tasche/Kiste bei position (wird auf den Boden gelegt). items = { { Id, Count, Mag } }, kind = "Death", "Drop", "Crate"
-- oder "Airdrop". options = { Persist (kein Ablauf), HoldTime (Sekunden E halten), SpotKind, Meta, Lifetime, NoGround }.
-- Gibt die Id zurück (nil, wenn nichts drin wäre).
function LootService.Create(position, items, kind, title, options)
	options = options or {}
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
	if options.Size or options.Color then
		look = { Size = options.Size or look.Size, Color = options.Color or look.Color, Light = look.Light, Range = look.Range }
	end

	-- auf den Boden legen (Charaktere und andere Taschen ignorieren)
	local ground = position
	if not options.NoGround then
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
		ground = hit and hit.Position or position
	end

	local model, part = buildModel(kind, look, { SpotKind = options.SpotKind }, id, ground, options.Yaw or math.rad(math.random(0, 359)))
	part:SetAttribute("LootBag", id)
	part:SetAttribute("Kind", kind)
	local light = Instance.new("PointLight")
	light.Color = look.Light
	light.Range = look.Range
	light.Brightness = kind == "Crate" and 0.5 or 0.9
	light.Parent = part

	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.fromOffset(190, 36)
	label.StudsOffset = Vector3.new(0, look.Size.Y + 1.6, 0)
	label.MaxDistance = kind == "Airdrop" and 400 or 70
	label.AlwaysOnTop = true
	label.Parent = part
	local text = Instance.new("TextLabel")
	text.Name = "Title"
	text.Size = UDim2.new(1, 0, 0.55, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.BuilderSansBold
	text.TextSize = 14
	text.TextColor3 = look.Light
	text.TextStrokeTransparency = 0.4
	text.Text = title
	text.Parent = label
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Position = UDim2.fromScale(0, 0.55)
	count.Size = UDim2.new(1, 0, 0.45, 0)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.BuilderSansMedium
	count.TextSize = 11
	count.TextColor3 = Color3.fromRGB(220, 224, 230)
	count.TextStrokeTransparency = 0.5
	count.Text = #list .. (#list == 1 and " ITEM" or " ITEMS")
	count.Parent = label

	local hold = options.HoldTime or (kind == "Death" and 0.4 or 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootPrompt"
	prompt.ActionText = kind == "Airdrop" and "Lootdrop öffnen" or "Durchsuchen"
	prompt.ObjectText = title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = ExtinctionConfig.LootRange - 1
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	local takeAll = takeAllPrompt(part, title, hold, ExtinctionConfig.LootRange - 1)
	model.Parent = folder

	local lifetime = options.Lifetime or (kind == "Death" and ExtinctionConfig.BagLifetime or ExtinctionConfig.DropLifetime)
	local bag = {
		Id = id,
		Title = title,
		Kind = kind,
		Container = container,
		Model = model,
		Part = part,
		Expires = options.Persist and math.huge or (os.clock() + lifetime),
		Viewers = {},
		Meta = options.Meta,
		Label = count,
	}
	bags[id] = bag
	prompt.Triggered:Connect(function(player)
		LootService.Open(player, id)
	end)
	takeAll.Triggered:Connect(function(player)
		takeAllTriggered(player, id)
	end)
	return id
end

-- Beute an einem vorhandenen Modell (z.B. Zombie-Leiche): wie eine Tasche, nur ohne eigenes Modell – part (z.B. der
-- Rumpf) trägt die Prompts. E öffnet das Fenster (einzeln herausnehmen), F nimmt alles (Gamepass). items = { { Id, Count,
-- Mag } }. options = { PromptName (Standard "LootPrompt"), ActionText, ObjectText (Name vor der Inhaltsangabe), Range
-- (Abstand für E/F), Lifetime (Sekunden), OnRemoved (leer oder abgelaufen: z.B. Leiche ausblenden) }.
-- Gibt die Id zurück (nil, wenn nichts drin wäre). Das Modell bleibt Sache des Aufrufers.
function LootService.Attach(model, part, items, title, options)
	options = options or {}
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
	local container = Inventory.New(#list)
	for slot, item in list do
		container.Slots[slot] = { Id = item.Id, Count = item.Count, Mag = item.Mag }
	end
	local range = options.Range or (ExtinctionConfig.LootRange - 1)
	local name = options.ObjectText or title
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = options.PromptName or "LootPrompt"
	prompt.ActionText = options.ActionText or "Durchsuchen"
	prompt.ObjectText = name .. " · " .. LootService.Summary(list)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = range
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	local takeAll = takeAllPrompt(part, name, 0, range)
	local bag = {
		Id = id,
		Title = title,
		Kind = "Corpse",
		Container = container,
		Model = model,
		Part = part,
		Range = range + 3, -- Leichen rutschen noch etwas (Ragdoll)
		Expires = os.clock() + (options.Lifetime or ExtinctionConfig.DropLifetime),
		Viewers = {},
	}
	function bag.Refresh()
		local rest = {}
		for _, item in container.Slots do
			if item then
				table.insert(rest, { Id = item.Id, Count = item.Count })
			end
		end
		prompt.ObjectText = name .. " · " .. LootService.Summary(rest)
	end
	function bag.Detach()
		prompt:Destroy()
		takeAll:Destroy()
		if options.OnRemoved then
			options.OnRemoved()
		end
	end
	bags[id] = bag
	prompt.Triggered:Connect(function(player)
		LootService.Open(player, id)
	end)
	takeAll.Triggered:Connect(function(player)
		takeAllTriggered(player, id)
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
	opened(player, bag)
	return true
end

-- Anzahl der Items in der Tasche am Beschriftungsschild nachführen
local function refreshLabel(bag)
	local n = 0
	for _, item in bag.Container.Slots do
		if item then
			n += 1
		end
	end
	if bag.Label then
		bag.Label.Text = n .. (n == 1 and " ITEM" or " ITEMS")
	end
	if bag.Refresh then
		bag.Refresh()
	end
end

-- Item herausnehmen: slot = Platz in der Tasche oder "All" (nur mit dem Gamepass ALLES LOOTEN)
function LootService.Take(player, id, slot)
	local bag = type(id) == "number" and bags[id]
	if not bag then
		return false
	end
	if slot == "All" and not LootService.CanTakeAll(player) then
		InventoryService.Status(player, LootService.TakeAllHint)
		return false
	end
	if not inRange(player, bag) then
		InventoryService.Status(player, "Du bist zu weit weg.")
		return false
	end
	if slot == "All" then
		opened(player, bag)
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
	local taken = {}
	for _, s in slots do
		local item = bag.Container.Slots[s]
		if item then
			local before = item.Count
			local id_ = item.Id
			if Inventory.Move(bag.Container, s, playerBag, nil) then
				moved = true
			end
			local left = bag.Container.Slots[s]
			local got = before - (left and left.Count or 0)
			if got > 0 then
				table.insert(taken, { Id = id_, Count = got })
			end
			if left then
				full = true -- passte nicht (ganz) in die Tasche
			end
		end
	end
	if full then
		InventoryService.Status(player, "Deine Tasche ist voll.")
	elseif moved and slot == "All" then
		InventoryService.Status(player, "+ " .. LootService.Summary(taken), true)
	end
	if moved then
		InventoryService.Changed(player)
		if Inventory.IsEmpty(bag.Container) then
			LootService.Remove(id)
		else
			refreshLabel(bag)
			for viewer in bag.Viewers do
				if viewer.Parent then
					send(viewer, bag)
				end
			end
		end
	end
	return moved
end

-- Belohnung direkt ins Inventar (Aufträge, Verstecke): items = { { Id, Count, Mag } }. Gibt zurück: Rest (was nicht mehr
-- hineinpasste) und den Text, was genommen wurde. Meldet dem Spieler, was er bekommen hat.
function LootService.Grab(player, items)
	local rest, got = {}, {}
	for _, item in items do
		local added = InventoryService.Give(player, item.Id, item.Count, { Mag = item.Mag })
		if added > 0 then
			table.insert(got, { Id = item.Id, Count = added })
		end
		if added < item.Count then
			table.insert(rest, { Id = item.Id, Count = item.Count - added, Mag = item.Mag })
		end
	end
	if #got > 0 then
		InventoryService.Status(player, "+ " .. LootService.Summary(got), true)
	end
	if #rest > 0 then
		InventoryService.Status(player, "Deine Tasche ist voll.")
	end
	return rest, LootService.Summary(got)
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
