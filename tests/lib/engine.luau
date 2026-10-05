-- Roblox-Nachbildung für die Tests (läuft im normalen Luau-Interpreter, ohne Roblox):
--   * virtuelle Zeit: task.wait/delay/spawn/defer laufen über einen eigenen Scheduler (SIM.Run, SIM.Advance)
--   * Signale, Instanzen (Eigenschaften, Kinder, Attribute, Klon), Dienste (Players, DataStoreService, ...)
--   * die Module des Projekts: require(script.Parent.X), require(Shared.X) usw. wie in Rojo (Pfade aus
--     default.project.json, eingetragen von tests/run.py)
-- Erwartet die Datentypen aus shim.luau (Vector3, CFrame, Color3, Enum, ...) als lokale Namen davor.

local SIM = {}
SIM.Now = 0              -- virtuelle Zeit in Sekunden
SIM.Deferred = false     -- Signal-Verhalten: false = sofort (Immediate), true = verzögert (Deferred)
SIM.Errors = 0           -- Fehler in Threads (Signale, task.spawn, ...)
SIM.IsServer = true      -- RunService:IsServer()
SIM.IsStudio = false     -- RunService:IsStudio()
SIM.Warnings = {}        -- alle warn()-Ausgaben
SIM.RemoteLog = {}       -- { Remote, Player ("all" bei FireAllClients, "server" bei FireServer), Args }
SIM.Kicked = {}          -- [Player] = Nachricht
SIM.Closers = {}         -- game:BindToClose
SIM.CreateDelay = function() return 0.05 + math.random() * 0.4 end -- Dauer von CreateHumanoidModelFromDescription
SIM.DataStoreLatency = 0 -- Sekunden pro DataStore-Anfrage (hin und zurück je zur Hälfte)
SIM.BaseTime = 1790000000 -- os.time() zur virtuellen Zeit 0
SIM.Quiet = false        -- true: warn() nicht ausgeben
SIM.LoadCharacterDelay = 0 -- so lange wartet Player:LoadCharacter() nach dem Anlegen des Charakters

-- ---------- Scheduler ----------
local queue = {}
local seq = 0
local canceled = setmetatable({}, { __mode = "k" })

local function schedule(t, co, args)
	seq += 1
	table.insert(queue, { T = t, Seq = seq, Co = co, Args = args or { n = 0 } })
end

local function resume(co, ...)
	if canceled[co] or coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		SIM.Errors += 1
		if SIM.Errors <= 10 then
			print("FEHLER im Thread: " .. tostring(err))
		end
	end
end

local task = {}
function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.defer(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	schedule(SIM.Now, co, table.pack(...))
	return co
end
function task.delay(t, fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	schedule(SIM.Now + (t or 0), co, table.pack(...))
	return co
end
function task.wait(t)
	local co = coroutine.running()
	local start = SIM.Now
	schedule(SIM.Now + math.max(t or 0.03, 0.001), co)
	coroutine.yield()
	return SIM.Now - start
end
function task.cancel(co)
	canceled[co] = true
end
function task.synchronize() end
function task.desynchronize() end
SIM.task = task

-- Alle Threads bis zur (absoluten) Zeit untilTime ausführen. every/onEvery: zusätzlich alle every Sekunden
-- onEvery() aufrufen.
function SIM.Run(untilTime, every, onEvery)
	local nextEvery = SIM.Now + (every or math.huge)
	while true do
		local bestIndex, best = nil, nil
		for i, item in queue do
			if not best or item.T < best.T or (item.T == best.T and item.Seq < best.Seq) then
				bestIndex, best = i, item
			end
		end
		if not best or best.T > untilTime then
			if onEvery and nextEvery <= untilTime then
				SIM.Now = nextEvery
				onEvery()
				nextEvery += every
				continue
			end
			SIM.Now = math.max(SIM.Now, untilTime)
			break
		end
		if onEvery and best.T >= nextEvery then
			SIM.Now = nextEvery
			onEvery()
			nextEvery += every
			continue
		end
		table.remove(queue, bestIndex)
		SIM.Now = math.max(SIM.Now, best.T)
		resume(best.Co, table.unpack(best.Args, 1, best.Args.n))
	end
end

-- ---------- Signale ----------
local Signal = {}
Signal.__index = Signal
function SIM.Signal()
	return setmetatable({ Handlers = {} }, Signal)
end
function Signal:Connect(fn)
	local conn = { Connected = true, Fn = fn }
	function conn:Disconnect()
		conn.Connected = false
	end
	table.insert(self.Handlers, conn)
	return conn
end
Signal.ConnectParallel = Signal.Connect
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Fire(...)
	for _, conn in table.clone(self.Handlers) do
		if conn.Connected then
			if SIM.Deferred then
				task.defer(conn.Fn, ...)
			else
				task.spawn(conn.Fn, ...)
			end
		end
	end
end
function Signal:DisconnectAll()
	for _, conn in self.Handlers do
		conn.Connected = false
	end
end
function Signal:Wait()
	local co = coroutine.running()
	self:Once(function(...)
		task.spawn(co, ...)
	end)
	return coroutine.yield()
end

-- ---------- Module des Projekts ----------
local modules = {} -- [Pfad] = function(script) ... end
local folders = {} -- [Pfad] = true
local loaded = {}  -- [Pfad] = Rückgabe
local loading = {} -- [Pfad] = true während des Ladens
local byName = {}  -- [Name] = { Pfade }
local proxies = {} -- [Pfad] = Stellvertreter-Instanz (script, script.Parent, ...)
local services = {}

local ProxyMT = {}
local ProxyMethods = {}

local function proxyFor(path)
	local proxy = proxies[path]
	if not proxy then
		proxy = setmetatable({ __path = path, __isInstance = true }, ProxyMT)
		proxies[path] = proxy
	end
	return proxy
end

local function sourceChild(path, name)
	local childPath = path .. "/" .. tostring(name)
	if modules[childPath] or folders[childPath] then
		return proxyFor(childPath)
	end
	return nil
end
SIM.SourceChild = sourceChild

function ProxyMethods.FindFirstChild(self, name)
	return sourceChild(rawget(self, "__path"), name)
end
function ProxyMethods.WaitForChild(self, name)
	local child = sourceChild(rawget(self, "__path"), name)
	if not child then
		error("WaitForChild: " .. tostring(name) .. " fehlt in " .. rawget(self, "__path"))
	end
	return child
end
function ProxyMethods.GetChildren(self)
	local prefix = rawget(self, "__path") .. "/"
	local paths = {}
	for _, list in { modules, folders } do
		for path in list do
			if path:sub(1, #prefix) == prefix and not path:sub(#prefix + 1):find("/") and not table.find(paths, path) then
				table.insert(paths, path)
			end
		end
	end
	table.sort(paths)
	local children = {}
	for _, path in paths do
		table.insert(children, proxyFor(path))
	end
	return children
end
function ProxyMethods.IsA(self, className)
	local isModule = modules[rawget(self, "__path")] ~= nil
	return className == "Instance" or (isModule and (className == "ModuleScript" or className == "LuaSourceContainer"))
		or (not isModule and className == "Folder")
end
function ProxyMethods.GetFullName(self)
	return (rawget(self, "__path"):gsub("/", "."))
end
function ProxyMethods.GetAttribute()
	return nil
end
ProxyMT.__index = function(self, key)
	local path = rawget(self, "__path")
	if key == "Name" then
		return path:match("([^/]+)$")
	elseif key == "ClassName" then
		return modules[path] and "ModuleScript" or "Folder"
	elseif key == "Parent" then
		local parentPath = path:match("^(.*)/[^/]+$")
		if not parentPath then
			return nil
		end
		if not parentPath:find("/") then
			return services[parentPath] or SIM.Game:GetService(parentPath)
		end
		return proxyFor(parentPath)
	elseif ProxyMethods[key] then
		return ProxyMethods[key]
	end
	return sourceChild(path, key)
end
ProxyMT.__tostring = function(self)
	return rawget(self, "__path"):match("([^/]+)$")
end

-- Modul eintragen (tests/run.py): path wie "ReplicatedStorage/Shared/PoseMath"
function SIM.Module(path, loader)
	modules[path] = loader
	local name = path:match("([^/]+)$")
	byName[name] = byName[name] or {}
	table.insert(byName[name], path)
	local parent = path:match("^(.*)/[^/]+$")
	while parent and parent:find("/") do
		folders[parent] = true
		parent = parent:match("^(.*)/[^/]+$")
	end
end

-- Pfad zu einem Modul: Stellvertreter (script.Parent.X), voller Pfad oder eindeutiger Name ("PoseMath")
local function resolve(target)
	if type(target) == "table" and rawget(target, "__path") then
		return rawget(target, "__path")
	end
	if type(target) == "string" then
		if modules[target] then
			return target
		end
		local list = byName[target]
		if list and #list == 1 then
			return list[1]
		end
		if list then
			error("Modulname mehrdeutig: " .. target .. " (" .. table.concat(list, ", ") .. ") – vollen Pfad angeben", 3)
		end
	end
	error("require: unbekanntes Modul " .. tostring(target), 3)
end

function SIM.Require(target)
	local path = resolve(target)
	if loaded[path] == nil then
		local loader = modules[path]
		if not loader then
			error("require: " .. path .. " ist kein Modul", 2)
		end
		if loading[path] then
			error("Modul wird rekursiv geladen: " .. path, 2)
		end
		loading[path] = true
		local ok, result = pcall(loader, proxyFor(path))
		loading[path] = nil
		if not ok then
			error(result, 0)
		end
		if result == nil then
			error("Modul " .. path .. " gibt nichts zurück", 2)
		end
		loaded[path] = result
	end
	return loaded[path]
end

-- Modul durch eine Attrappe ersetzen (vor dem ersten require)
function SIM.Stub(target, value)
	loaded[resolve(target)] = value
end

-- ---------- Instanzen ----------
local Instance = {}
local Methods = {}
local InstMT = {}
local SIGNAL_NAMES = {}
for _, name in { "Died", "Running", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Destroying",
	"AncestryChanged", "Changed", "PlayerAdded", "PlayerRemoving", "Heartbeat", "Stepped", "RenderStepped",
	"PreSimulation", "PostSimulation", "PreRender", "PreAnimation", "OnServerEvent", "OnClientEvent", "Event",
	"CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "HealthChanged", "StateChanged", "Touched",
	"TouchEnded", "MoveToFinished", "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up",
	"MouseButton2Click", "MouseButton2Down", "MouseButton2Up", "Seated",
	"MouseEnter", "MouseLeave", "InputBegan", "InputEnded", "InputChanged", "FocusLost", "Focused", "Equipped",
	"Unequipped", "Completed", "Ended", "Played", "Stopped", "DidLoop", "Blocked", "Triggered", "TriggerEnded",
	"PromptShown", "PromptHidden", "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished",
	"PromptPurchaseFinished", "Chatted", "Idled", "Loaded", "SelectionGained", "SelectionLost", "AttributeChanged" } do
	SIGNAL_NAMES[name] = true
end

-- Vererbung für IsA
local PARENT_CLASS = {
	Part = "FormFactorPart", FormFactorPart = "BasePart", SpawnLocation = "Part", Seat = "Part", WedgePart = "FormFactorPart",
	CornerWedgePart = "BasePart", TrussPart = "BasePart", MeshPart = "TriangleMeshPart", TriangleMeshPart = "BasePart",
	UnionOperation = "PartOperation", PartOperation = "TriangleMeshPart", VehicleSeat = "BasePart", Terrain = "BasePart",
	BasePart = "PVInstance", Model = "PVInstance", Workspace = "WorldRoot", WorldRoot = "Model", PVInstance = "Instance",
	Motor6D = "Motor", Motor = "JointInstance", Weld = "JointInstance", Snap = "JointInstance", ManualWeld = "JointInstance",
	JointInstance = "Instance", WeldConstraint = "Instance", NoCollisionConstraint = "Instance",
	AnimationConstraint = "Constraint", BallSocketConstraint = "Constraint", RigidConstraint = "Constraint",
	HingeConstraint = "Constraint", RopeConstraint = "Constraint", AlignPosition = "Constraint",
	AlignOrientation = "Constraint", LinearVelocity = "Constraint", AngularVelocity = "Constraint",
	VectorForce = "Constraint", Constraint = "Instance", Bone = "Attachment",
	Script = "BaseScript", LocalScript = "Script", BaseScript = "LuaSourceContainer", ModuleScript = "LuaSourceContainer",
	Decal = "FaceInstance", Texture = "Decal", SpecialMesh = "FileMesh", FileMesh = "DataModelMesh",
	BlockMesh = "BevelMesh", CylinderMesh = "BevelMesh", BevelMesh = "DataModelMesh",
	PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light",
	ScreenGui = "LayerCollector", BillboardGui = "LayerCollector", SurfaceGui = "SurfaceGuiBase",
	SurfaceGuiBase = "LayerCollector", LayerCollector = "GuiBase2d", Frame = "GuiObject", ScrollingFrame = "GuiObject",
	CanvasGroup = "GuiObject", ViewportFrame = "GuiObject", TextLabel = "GuiObject", ImageLabel = "GuiObject",
	TextBox = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton", GuiButton = "GuiObject",
	GuiObject = "GuiBase2d", GuiBase2d = "Instance", Accessory = "Accoutrement", Hat = "Accoutrement",
	StringValue = "ValueBase", IntValue = "ValueBase", NumberValue = "ValueBase", BoolValue = "ValueBase",
	ObjectValue = "ValueBase", CFrameValue = "ValueBase", Vector3Value = "ValueBase", Color3Value = "ValueBase",
	Tool = "BackpackItem", BackpackItem = "Instance",
}
local function isA(className, wanted)
	if wanted == "Instance" then
		return true
	end
	local cls = className
	while cls do
		if cls == wanted then
			return true
		end
		cls = PARENT_CLASS[cls]
	end
	return false
end
SIM.IsA = isA

local ClassMethods = {} -- [Klasse] = { Methode = Funktion } (gilt auch für abgeleitete Klassen)
local ClassSetters = {} -- [Klasse] = { Eigenschaft = function(self, value) }
local ClassInit = {}    -- [Klasse] = function(self) (Standardwerte)

local function classLookup(tableByClass, className, key)
	local cls = className
	while cls do
		local entry = tableByClass[cls]
		if entry and entry[key] ~= nil then
			return entry[key]
		end
		cls = PARENT_CLASS[cls]
	end
	return nil
end

InstMT.__index = function(self, key)
	local props = rawget(self, "__props")
	local value = props[key]
	if value ~= nil then
		return value
	end
	if Methods[key] then
		return Methods[key]
	end
	local extra = rawget(self, "__methods")
	if extra and extra[key] then
		return extra[key]
	end
	local classMethod = classLookup(ClassMethods, props.ClassName, key)
	if classMethod then
		return classMethod
	end
	if SIGNAL_NAMES[key] then
		local signal = SIM.Signal()
		props[key] = signal
		return signal
	end
	for _, child in rawget(self, "__children") do
		if rawget(child, "__props").Name == key then
			return child
		end
	end
	local sourcePath = rawget(self, "__sourcePath")
	if sourcePath then
		return sourceChild(sourcePath, key)
	end
	return nil
end

local function setParent(self, value)
	local props = rawget(self, "__props")
	if rawget(self, "__destroyed") then
		error("Parent einer zerstörten Instanz kann nicht gesetzt werden: " .. tostring(props.Name), 3)
	end
	local old = props.Parent
	if old == value then
		return
	end
	if old then
		local list = rawget(old, "__children")
		local index = table.find(list, self)
		if index then
			table.remove(list, index)
		end
		if rawget(old, "__props").ChildRemoved then
			old.ChildRemoved:Fire(self)
		end
	end
	props.Parent = value
	if value then
		table.insert(rawget(value, "__children"), self)
		if rawget(value, "__props").ChildAdded then
			value.ChildAdded:Fire(self)
		end
		-- DescendantAdded bei allen Vorfahren, für die Instanz selbst und alle ihre Nachfahren (wie in Roblox)
		local added = nil
		local ancestor = value
		while ancestor do
			local ancestorProps = rawget(ancestor, "__props")
			if not ancestorProps then
				break
			end
			if ancestorProps.DescendantAdded then
				if not added then
					added = { self }
					for _, descendant in Methods.GetDescendants(self) do
						table.insert(added, descendant)
					end
				end
				for _, instance in added do
					ancestor.DescendantAdded:Fire(instance)
				end
			end
			ancestor = ancestorProps.Parent
		end
	end
	if props.AncestryChanged then
		self.AncestryChanged:Fire(self, value)
	end
end

InstMT.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local setter = rawget(self, "__setters")
	local classSetter = classLookup(ClassSetters, props.ClassName, key)
	if setter and setter[key] then
		setter[key](self, value)
	elseif classSetter then
		classSetter(self, value)
	else
		props[key] = value
	end
	local signals = rawget(self, "__propSignals")
	if signals and signals[key] then
		signals[key]:Fire()
	end
end
InstMT.__tostring = function(self)
	return rawget(self, "__props").Name
end

function Instance.new(className, parent)
	local self = setmetatable({
		__props = { ClassName = className, Name = className },
		__children = {},
		__attrs = {},
		__attrSignals = {},
		__isInstance = true,
	}, InstMT)
	local cls = className
	local inits = {}
	while cls do
		if ClassInit[cls] then
			table.insert(inits, 1, ClassInit[cls])
		end
		cls = PARENT_CLASS[cls]
	end
	for _, init in inits do
		init(self)
	end
	if parent then
		self.Parent = parent
	end
	SIM.InstanceCount = (SIM.InstanceCount or 0) + 1
	return self
end

function Methods.GetChildren(self)
	return table.clone(rawget(self, "__children"))
end
function Methods.GetDescendants(self)
	local list = {}
	local function walk(node)
		for _, child in rawget(node, "__children") do
			table.insert(list, child)
			walk(child)
		end
	end
	walk(self)
	return list
end
function Methods.FindFirstChild(self, name, recursive)
	for _, child in rawget(self, "__children") do
		if rawget(child, "__props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "__children") do
			local found = Methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	local sourcePath = rawget(self, "__sourcePath")
	if sourcePath then
		return sourceChild(sourcePath, name)
	end
	return nil
end
function Methods.WaitForChild(self, name, timeout)
	local child = Methods.FindFirstChild(self, name)
	-- mit Zeitlimit wie in Roblox: bis zu timeout Sekunden auf das Kind warten, sonst nil
	if not child and type(timeout) == "number" and coroutine.isyieldable() then
		local deadline = SIM.Now + timeout
		while not child and SIM.Now < deadline do
			task.wait(math.min(0.1, deadline - SIM.Now))
			child = Methods.FindFirstChild(self, name)
		end
		return child
	end
	if not child then
		error("WaitForChild: " .. tostring(name) .. " fehlt in " .. tostring(self), 2)
	end
	return child
end
function Methods.FindFirstChildOfClass(self, className)
	for _, child in rawget(self, "__children") do
		if rawget(child, "__props").ClassName == className then
			return child
		end
	end
	return nil
end
function Methods.FindFirstChildWhichIsA(self, className, recursive)
	for _, child in (recursive and Methods.GetDescendants(self) or rawget(self, "__children")) do
		if isA(rawget(child, "__props").ClassName, className) then
			return child
		end
	end
	return nil
end
function Methods.FindFirstAncestor(self, name)
	local node = rawget(self, "__props").Parent
	while node do
		if node.Name == name then
			return node
		end
		node = node.Parent
	end
	return nil
end
function Methods.FindFirstAncestorOfClass(self, className)
	local node = rawget(self, "__props").Parent
	while node do
		if node.ClassName == className then
			return node
		end
		node = node.Parent
	end
	return nil
end
function Methods.FindFirstAncestorWhichIsA(self, className)
	local node = rawget(self, "__props").Parent
	while node do
		if node:IsA(className) then
			return node
		end
		node = node.Parent
	end
	return nil
end
function Methods.IsA(self, className)
	return isA(rawget(self, "__props").ClassName, className)
end
function Methods.IsDescendantOf(self, ancestor)
	local node = rawget(self, "__props").Parent
	while node do
		if node == ancestor then
			return true
		end
		node = rawget(node, "__props") and rawget(node, "__props").Parent or nil
	end
	return false
end
function Methods.IsAncestorOf(self, descendant)
	return Methods.IsDescendantOf(descendant, self)
end
function Methods.GetFullName(self)
	local names = {}
	local node = self
	while node and rawget(node, "__props") do
		table.insert(names, 1, rawget(node, "__props").Name)
		node = rawget(node, "__props").Parent
	end
	return table.concat(names, ".")
end
function Methods.ClearAllChildren(self)
	for _, child in table.clone(rawget(self, "__children")) do
		Methods.Destroy(child)
	end
end
function Methods.Destroy(self)
	if rawget(self, "__destroyed") then
		return
	end
	local props = rawget(self, "__props")
	if props.Destroying then
		self.Destroying:Fire()
	end
	-- Wie in Roblox: Died feuert, wenn ein lebender Humanoid mit dem Modell zerstört wird (nur wenn eingeschaltet)
	if SIM.DiedOnDestroy and props.ClassName == "Humanoid" and not rawget(self, "__dead") then
		rawset(self, "__dead", true)
		props.Health = 0
		self.Died:Fire()
	end
	for _, child in table.clone(rawget(self, "__children")) do
		Methods.Destroy(child)
	end
	if props.Parent then
		setParent(self, nil)
	end
	rawset(self, "__destroyed", true)
	-- Verbindungen trennen (wie in Roblox)
	for _, value in props do
		if type(value) == "table" and getmetatable(value) == Signal then
			value:DisconnectAll()
		end
	end
	for _, signal in rawget(self, "__attrSignals") do
		signal:DisconnectAll()
	end
end
Methods.Remove = Methods.Destroy
function Methods.SetAttribute(self, key, value)
	local attrs = rawget(self, "__attrs")
	if attrs[key] == value then
		return
	end
	attrs[key] = value
	local signal = rawget(self, "__attrSignals")[key]
	if signal then
		signal:Fire()
	end
	local props = rawget(self, "__props")
	if props.AttributeChanged then
		props.AttributeChanged:Fire(key)
	end
end
function Methods.GetAttribute(self, key)
	return rawget(self, "__attrs")[key]
end
function Methods.GetAttributes(self)
	return table.clone(rawget(self, "__attrs"))
end
function Methods.GetAttributeChangedSignal(self, key)
	local signals = rawget(self, "__attrSignals")
	signals[key] = signals[key] or SIM.Signal()
	return signals[key]
end
function Methods.GetPropertyChangedSignal(self, key)
	local signals = rawget(self, "__propSignals")
	if not signals then
		signals = {}
		rawset(self, "__propSignals", signals)
	end
	signals[key] = signals[key] or SIM.Signal()
	return signals[key]
end
-- Wie in Roblox: Verweise auf Instanzen innerhalb des kopierten Baums zeigen danach auf die Kopien
local function cloneTree(self, map)
	local props = rawget(self, "__props")
	local copy = Instance.new(props.ClassName)
	map[self] = copy
	local copyProps = rawget(copy, "__props")
	for key, value in props do
		if key ~= "Parent" and not (type(value) == "table" and getmetatable(value) == Signal) then
			copyProps[key] = value
		end
	end
	for key, value in rawget(self, "__attrs") do
		rawget(copy, "__attrs")[key] = value
	end
	local methods = rawget(self, "__methods")
	if methods then
		rawset(copy, "__methods", methods)
	end
	for _, child in rawget(self, "__children") do
		if child.Archivable ~= false then
			cloneTree(child, map).Parent = copy
		end
	end
	return copy
end
function Methods.Clone(self)
	if self.Archivable == false then
		return nil
	end
	local map = {}
	local copy = cloneTree(self, map)
	for _, c in map do
		local copyProps = rawget(c, "__props")
		for key, value in copyProps do
			if key ~= "Parent" and type(value) == "table" and rawget(value, "__isInstance") and map[value] then
				copyProps[key] = map[value]
			end
		end
	end
	return copy
end
function Methods.GetTags(self)
	return table.clone(rawget(self, "__tags") or {})
end
function Methods.HasTag(self, tag)
	return table.find(rawget(self, "__tags") or {}, tag) ~= nil
end
function Methods.AddTag(self, tag)
	local tags = rawget(self, "__tags") or {}
	rawset(self, "__tags", tags)
	if not table.find(tags, tag) then
		table.insert(tags, tag)
	end
end
function Methods.RemoveTag(self, tag)
	local tags = rawget(self, "__tags") or {}
	local index = table.find(tags, tag)
	if index then
		table.remove(tags, index)
	end
end
SIM.Instance = Instance
SIM.Methods = Methods
SIM.ClassMethods = ClassMethods
SIM.ClassSetters = ClassSetters
SIM.ClassInit = ClassInit

-- Teile: CFrame und Position bleiben zusammen
ClassInit.BasePart = function(self)
	local props = rawget(self, "__props")
	props.CFrame = CFrame.new()
	props.Position = Vector3.zero
	props.Size = Vector3.new(4, 1, 2)
	props.Transparency = 0
	props.Anchored = false
	props.CanCollide = true
	props.CanQuery = true
	props.CanTouch = true
	props.Massless = false
	props.AssemblyLinearVelocity = Vector3.zero
	props.AssemblyAngularVelocity = Vector3.zero
	props.Color = Color3.new(0.64, 0.64, 0.64)
end
ClassSetters.BasePart = {
	CFrame = function(self, value)
		local props = rawget(self, "__props")
		props.CFrame = value
		props.Position = value.Position
	end,
	Position = function(self, value)
		local props = rawget(self, "__props")
		props.CFrame = CFrame.new(value) * props.CFrame.Rotation
		props.Position = value
	end,
}
ClassMethods.BasePart = {
	PivotTo = function(self, cframe)
		self.CFrame = cframe
	end,
	GetPivot = function(self)
		return self.CFrame
	end,
	GetMass = function(self)
		local size = self.Size
		return size.X * size.Y * size.Z * 0.7
	end,
	SetNetworkOwner = function() end,
	GetNetworkOwner = function() return nil end,
	SetNetworkOwnershipAuto = function() end,
	ApplyImpulse = function() end,
	GetTouchingParts = function() return {} end,
	BreakJoints = function() end,
}
ClassInit.Decal = function(self)
	rawget(self, "__props").Transparency = 0
end

-- Oberflächen: Standardwerte wie in Roblox
ClassInit.GuiObject = function(self)
	local props = rawget(self, "__props")
	props.Visible = true
	props.BackgroundTransparency = 0
	props.BackgroundColor3 = Color3.new(1, 1, 1)
	props.Rotation = 0
	props.ZIndex = 1
	props.Size = UDim2.new()
	props.Position = UDim2.new()
	props.AnchorPoint = Vector2.zero
end
local function textDefaults(self)
	local props = rawget(self, "__props")
	props.Text = ""
	props.TextSize = 14
	props.TextTransparency = 0
	props.TextStrokeTransparency = 1
	props.TextColor3 = Color3.new(0, 0, 0)
end
ClassInit.TextLabel = textDefaults
ClassInit.TextButton = textDefaults
ClassInit.TextBox = textDefaults
ClassInit.LayerCollector = function(self)
	rawget(self, "__props").Enabled = true
end
ClassInit.UIStroke = function(self)
	local props = rawget(self, "__props")
	props.Transparency = 0
	props.Thickness = 1
	props.Enabled = true
	props.Color = Color3.new(0, 0, 0)
end
ClassInit.UIScale = function(self)
	rawget(self, "__props").Scale = 1
end

-- Modelle: PivotTo verschiebt alle Teile (Drehpunkt = PrimaryPart, sonst gespeicherter Pivot)
local function modelPivot(self)
	local props = rawget(self, "__props")
	local primary = props.PrimaryPart
	if not (primary and Methods.IsDescendantOf(primary, self)) then
		primary = Methods.FindFirstChild(self, "HumanoidRootPart")
	end
	if primary then
		return primary.CFrame
	end
	return props.WorldPivot or CFrame.new()
end
ClassMethods.Model = {
	GetPivot = modelPivot,
	PivotTo = function(self, cframe)
		local delta = cframe * modelPivot(self):Inverse()
		for _, part in Methods.GetDescendants(self) do
			if part:IsA("BasePart") then
				part.CFrame = delta * part.CFrame
			end
		end
		rawget(self, "__props").WorldPivot = cframe
	end,
	SetPrimaryPartCFrame = function(self, cframe)
		self:PivotTo(cframe)
	end,
	GetBoundingBox = function(self)
		local minV, maxV
		for _, part in Methods.GetDescendants(self) do
			if part:IsA("BasePart") then
				local half = part.Size / 2
				local low, high = part.Position - half, part.Position + half
				minV = minV and minV:Min(low) or low
				maxV = maxV and maxV:Max(high) or high
			end
		end
		if not minV then
			return CFrame.new(), Vector3.zero
		end
		return CFrame.new((minV + maxV) / 2), maxV - minV
	end,
	GetExtentsSize = function(self)
		local _, size = self:GetBoundingBox()
		return size
	end,
	ScaleTo = function(self, s)
		local pivot = modelPivot(self)
		for _, part in Methods.GetDescendants(self) do
			if part:IsA("BasePart") then
				local rel = pivot:ToObjectSpace(part.CFrame)
				part.Size = part.Size * s
				part.CFrame = pivot * CFrame.new(rel.Position * s) * rel.Rotation
			end
		end
		rawset(self, "__scale", (rawget(self, "__scale") or 1) * s)
	end,
	GetScale = function(self)
		return rawget(self, "__scale") or 1
	end,
	MoveTo = function(self, position)
		self:PivotTo(CFrame.new(position) * modelPivot(self).Rotation)
	end,
	BreakJoints = function() end,
}

-- Humanoid
ClassInit.Humanoid = function(self)
	local props = rawget(self, "__props")
	props.Health = 100
	props.MaxHealth = 100
	props.WalkSpeed = 16
	props.JumpPower = 50
	props.JumpHeight = 7.2
	props.HipHeight = 2
	props.MoveDirection = Vector3.zero
	props.FloorMaterial = Enum.Material.Plastic
	props.BreakJointsOnDeath = true
	props.PlatformStand = false
	props.Sit = false
end
-- Sitze (Seat, VehicleSeat), vereinfacht ohne SeatWeld-Physik: Sit setzt Occupant am Sitz sowie Sit und SeatPart am
-- Humanoid; Humanoid.Sit = false (oder Springen) steht wieder auf und gibt den Sitz frei
local function seatSit(self, humanoid)
	local old = self.Occupant
	if old == humanoid then
		return
	end
	if old then
		rawget(old, "__props").Sit = false
		old.SeatPart = nil
	end
	if humanoid then
		local previous = humanoid.SeatPart
		if previous and previous ~= self then
			previous.Occupant = nil
		end
		rawget(humanoid, "__props").Sit = true
		humanoid.SeatPart = self
		humanoid.Seated:Fire(true, self)
	end
	self.Occupant = humanoid
end
ClassMethods.Seat = { Sit = seatSit }
ClassMethods.VehicleSeat = { Sit = seatSit }
ClassInit.VehicleSeat = function(self)
	local props = rawget(self, "__props")
	props.ThrottleFloat = 0
	props.SteerFloat = 0
	props.Throttle = 0
	props.Steer = 0
	props.Disabled = false
end
ClassInit.Seat = function(self)
	rawget(self, "__props").Disabled = false
end
local function standUp(humanoid)
	local seat = humanoid.SeatPart
	rawget(humanoid, "__props").Sit = false
	if seat then
		humanoid.SeatPart = nil
		if seat.Occupant == humanoid then
			seat.Occupant = nil
		end
		humanoid.Seated:Fire(false, seat)
	end
end

ClassSetters.Humanoid = {
	Sit = function(h, v)
		if v then
			rawget(h, "__props").Sit = true
		else
			standUp(h)
		end
	end,
	Jump = function(h, v)
		rawget(h, "__props").Jump = v
		if v and rawget(h, "__props").Sit then
			standUp(h) -- Springen steht vom Sitz auf
		end
	end,
	Health = function(h, v)
		local props = rawget(h, "__props")
		local wasAlive = props.Health > 0 and not rawget(h, "__dead")
		local before = props.Health
		props.Health = math.clamp(v, 0, props.MaxHealth)
		if props.Health ~= before and not rawget(h, "__destroyed") then
			h.HealthChanged:Fire(props.Health)
		end
		if wasAlive and props.Health <= 0 and not rawget(h, "__destroyed") then
			rawset(h, "__dead", true)
			h.Died:Fire()
		end
	end,
}
ClassMethods.Humanoid = {
	TakeDamage = function(self, amount)
		if self.Parent and self.Parent:FindFirstChildOfClass("ForceField") then
			return
		end
		self.Health -= amount
	end,
	MoveTo = function(self, position)
		rawget(self, "__props").MoveToTarget = position
	end,
	ChangeState = function(self, state)
		rawget(self, "__props").State = state
	end,
	GetState = function(self)
		return rawget(self, "__props").State or Enum.HumanoidStateType.Running
	end,
	SetStateEnabled = function() end,
	UnequipTools = function() end,
	EquipTool = function(self, tool)
		tool.Parent = self.Parent
	end,
	LoadAnimation = function(self, animation)
		return SIM.AnimationTrack(animation)
	end,
	ApplyDescription = function() end,
	ApplyDescriptionReset = function() end,
	GetAppliedDescription = function()
		return Instance.new("HumanoidDescription")
	end,
	GetPlayingAnimationTracks = function()
		return {}
	end,
	BuildRigFromAttachments = function() end,
	AddAccessory = function(self, accessory)
		accessory.Parent = self.Parent
	end,
	GetAccessories = function(self)
		local list = {}
		for _, child in self.Parent and self.Parent:GetChildren() or {} do
			if child:IsA("Accessory") then
				table.insert(list, child)
			end
		end
		return list
	end,
}

function SIM.AnimationTrack(animation)
	local track = { Animation = animation, IsPlaying = false, Length = 1, TimePosition = 0, Speed = 1,
		Stopped = SIM.Signal(), Ended = SIM.Signal(), DidLoop = SIM.Signal(), Looped = false, Priority = nil }
	function track:Play()
		self.IsPlaying = true
	end
	function track:Stop()
		if self.IsPlaying then
			self.IsPlaying = false
			self.Stopped:Fire()
		end
	end
	function track:AdjustSpeed(speed)
		self.Speed = speed
	end
	function track:AdjustWeight() end
	function track:GetMarkerReachedSignal()
		return SIM.Signal()
	end
	function track:Destroy() end
	return track
end
ClassMethods.Animator = {
	LoadAnimation = function(_, animation)
		return SIM.AnimationTrack(animation)
	end,
	GetPlayingAnimationTracks = function()
		return {}
	end,
}
ClassMethods.AnimationController = ClassMethods.Animator

-- Fernaufrufe: werden in SIM.RemoteLog mitgeschrieben
ClassMethods.RemoteEvent = {
	FireClient = function(self, player, ...)
		table.insert(SIM.RemoteLog, { Remote = self.Name, Player = player, Args = table.pack(...) })
	end,
	FireAllClients = function(self, ...)
		table.insert(SIM.RemoteLog, { Remote = self.Name, Player = "all", Args = table.pack(...) })
	end,
	FireServer = function(self, ...)
		table.insert(SIM.RemoteLog, { Remote = self.Name, Player = "server", Args = table.pack(...) })
	end,
}
ClassMethods.UnreliableRemoteEvent = ClassMethods.RemoteEvent
PARENT_CLASS.UnreliableRemoteEvent = "Instance"
ClassMethods.RemoteFunction = {
	InvokeServer = function(self, ...)
		local handler = rawget(self, "__props").OnServerInvoke
		return handler and handler(SIM.LocalPlayer, ...)
	end,
	InvokeClient = function(self, player, ...)
		table.insert(SIM.RemoteLog, { Remote = self.Name, Player = player, Args = table.pack(...) })
		return nil
	end,
}
ClassMethods.BindableEvent = {
	Fire = function(self, ...)
		self.Event:Fire(...)
	end,
}
ClassMethods.BindableFunction = {
	Invoke = function(self, ...)
		local handler = rawget(self, "__props").OnInvoke
		return handler and handler(...)
	end,
}
ClassMethods.Sound = {
	Play = function(self)
		rawget(self, "__props").IsPlaying = true
	end,
	Stop = function(self)
		rawget(self, "__props").IsPlaying = false
	end,
	Pause = function(self)
		rawget(self, "__props").IsPlaying = false
	end,
	Resume = function(self)
		rawget(self, "__props").IsPlaying = true
	end,
}
ClassMethods.ParticleEmitter = { Emit = function() end, Clear = function() end }
ClassMethods.Team = {
	GetPlayers = function(team)
		local list = {}
		for _, p in SIM.PlayerList do
			if p.Team == team then
				table.insert(list, p)
			end
		end
		return list
	end,
}
-- Körper aus einer HumanoidDescription (Player:LoadCharacterWithHumanoidDescription,
-- Players:CreateHumanoidModelFromDescription): [Modell] = Beschreibung, für Tests
SIM.DescriptionOf = setmetatable({}, { __mode = "k" })
SIM.FailDescriptionLoad = false -- true: LoadCharacterWithHumanoidDescription schlägt fehl (z.B. Asset nicht ladbar)

local function loadCharacter(self, description)
	local old = self.Character
	if old then
		if rawget(self, "__props").CharacterRemoving then
			self.CharacterRemoving:Fire(old)
		end
		Methods.Destroy(old)
	end
	local model = SIM.MakeRig(self.Name)
	SIM.DescriptionOf[model] = description
	model.Parent = services.Workspace
	self.Character = model
	self.CharacterAdded:Fire(model)
	if SIM.LoadCharacterDelay > 0 then
		task.wait(SIM.LoadCharacterDelay) -- wie in Roblox: LoadCharacter wartet, bis das Aussehen geladen ist
	end
end

ClassMethods.Player = {
	LoadCharacter = function(self)
		loadCharacter(self, nil)
	end,
	LoadCharacterWithHumanoidDescription = function(self, description)
		if SIM.FailDescriptionLoad then
			error("LoadCharacterWithHumanoidDescription: Beschreibung konnte nicht geladen werden")
		end
		if typeof(description) ~= "Instance" or not description:IsA("HumanoidDescription") then
			error("LoadCharacterWithHumanoidDescription: HumanoidDescription erwartet")
		end
		loadCharacter(self, description)
	end,
	Kick = function(self, message)
		SIM.Kicked[self] = message or ""
		SIM.Leave(self)
	end,
	GetNetworkPing = function()
		return 0.05
	end,
	IsInGroup = function()
		return false
	end,
	GetRankInGroup = function()
		return 0
	end,
	GetRoleInGroup = function()
		return "Guest"
	end,
	HasAppearanceLoaded = function()
		return true
	end,
	GetMouse = function()
		return { Hit = CFrame.new(), Target = nil, X = 0, Y = 0 }
	end,
	GetJoinData = function()
		return {}
	end,
	RequestStreamAroundAsync = function() end,
}
ClassInit.Player = function(self)
	local props = rawget(self, "__props")
	props.UserId = 0
	props.AccountAge = 365
	props.MembershipType = Enum.MembershipType.None
	props.Neutral = true
end
ClassSetters.Player = {
	Name = function(self, value)
		local props = rawget(self, "__props")
		props.Name = value
		props.DisplayName = props.DisplayName or value
	end,
}
ClassInit.Camera = function(self)
	local props = rawget(self, "__props")
	props.CFrame = CFrame.new()
	props.FieldOfView = 70
	props.ViewportSize = Vector2.new(1920, 1080)
end

SIM.Instance = Instance

-- ---------- Dienste ----------
local function service(name)
	local s = Instance.new(name)
	s.Name = name
	services[name] = s
	return s
end

-- Dienste, unter denen Module des Projekts liegen (default.project.json)
for _, name in { "ReplicatedFirst", "ReplicatedStorage", "ServerStorage", "ServerScriptService", "StarterPlayer",
	"StarterGui", "StarterPack" } do
	rawset(service(name), "__sourcePath", name)
end

SIM.PlayerList = {}
local Players = service("Players")
rawget(Players, "__props").MaxPlayers = 20
rawget(Players, "__props").CharacterAutoLoads = true
rawset(Players, "__methods", {
	GetPlayers = function()
		return table.clone(SIM.PlayerList)
	end,
	GetPlayerFromCharacter = function(_, model)
		for _, p in SIM.PlayerList do
			if p.Character == model and model ~= nil then
				return p
			end
		end
		return nil
	end,
	GetPlayerByUserId = function(_, id)
		for _, p in SIM.PlayerList do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end,
	CreateHumanoidModelFromDescription = function(_, description)
		task.wait(SIM.CreateDelay())
		local model = SIM.MakeRig("Bot")
		SIM.DescriptionOf[model] = description
		return model
	end,
	CreateHumanoidModelFromUserId = function()
		return SIM.MakeRig("Avatar")
	end,
	GetHumanoidDescriptionFromUserId = function()
		return Instance.new("HumanoidDescription")
	end,
	GetNameFromUserIdAsync = function(_, id)
		return "Spieler" .. tostring(id)
	end,
	GetUserIdFromNameAsync = function()
		return 1
	end,
	GetUserThumbnailAsync = function()
		return "rbxassetid://0", true
	end,
})

-- Charakter wie in Roblox (vereinfacht): Humanoid, HumanoidRootPart (PrimaryPart), Kopf, Oberkörper, Animator.
-- Bots bekommen Gelenke wie beim Avatar Joint Upgrade (AnimationConstraint) und klassisch (Motor6D).
function SIM.MakeRig(name)
	local model = Instance.new("Model")
	model.Name = name
	local humanoid = Instance.new("Humanoid", model)
	local root = Instance.new("Part", model)
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	model.PrimaryPart = root
	local torso = Instance.new("Part", model)
	torso.Name = "UpperTorso"
	torso.CFrame = CFrame.new(0, 3.5, 0)
	local head = Instance.new("Part", model)
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = CFrame.new(0, 4.5, 0)
	Instance.new("Animator", humanoid)
	if name == "Bot" then
		local neck = Instance.new("AnimationConstraint", head)
		neck.Name = "Neck"
		neck.Part0, neck.Part1 = torso, head
		neck.C0, neck.C1 = CFrame.new(0, 0.8, 0), CFrame.new(0, -0.5, 0)
		neck.Transform = CFrame.new()
		local rootJoint = Instance.new("Motor6D", torso)
		rootJoint.Name = "Root"
		rootJoint.Part0, rootJoint.Part1 = root, torso
		rootJoint.C0, rootJoint.C1 = CFrame.new(), CFrame.new()
	end
	return model, humanoid
end

-- Spieler betritt das Spiel (eindeutige UserId, PlayerAdded feuert)
local nextUserId = 0
function SIM.AddPlayer(name, userId)
	local player = Instance.new("Player")
	nextUserId += 1
	player.Name = name
	player.UserId = userId or nextUserId
	table.insert(SIM.PlayerList, player)
	player.Parent = Players
	Players.PlayerAdded:Fire(player)
	return player
end
SIM.Join = SIM.AddPlayer

-- Spieler verlässt das Spiel: PlayerRemoving feuert, solange er noch da ist; danach ist er weg
function SIM.Leave(player)
	if not table.find(SIM.PlayerList, player) then
		return
	end
	Players.PlayerRemoving:Fire(player)
	local index = table.find(SIM.PlayerList, player)
	if index then
		table.remove(SIM.PlayerList, index)
	end
	if player.Character then
		Methods.Destroy(player.Character)
		player.Character = nil
	end
	player.Parent = nil
end

service("Teams")

local Workspace = service("Workspace")
local camera = Instance.new("Camera", Workspace)
camera.Name = "Camera"
local terrain = Instance.new("Terrain", Workspace)
terrain.Name = "Terrain"
terrain.Anchored = true
rawget(Workspace, "__props").CurrentCamera = camera
rawget(Workspace, "__props").Gravity = 196.2
SIM.RaycastHandler = nil -- function(origin, direction, params) -> Ergebnis oder nil
SIM.SpherecastHandler = nil -- function(origin, radius, direction, params) -> Ergebnis oder nil (z.B. Messer)
rawset(Workspace, "__methods", {
	GetServerTimeNow = function()
		return SIM.BaseTime + SIM.Now
	end,
	Raycast = function(_, origin, direction, params)
		return SIM.RaycastHandler and SIM.RaycastHandler(origin, direction, params) or nil
	end,
	Spherecast = function(_, origin, radius, direction, params)
		return SIM.SpherecastHandler and SIM.SpherecastHandler(origin, radius, direction, params) or nil
	end,
	Blockcast = function()
		return nil
	end,
	GetPartBoundsInRadius = function()
		return {}
	end,
	GetPartBoundsInBox = function()
		return {}
	end,
	GetPartsInPart = function()
		return {}
	end,
	FindPartOnRayWithIgnoreList = function()
		return nil
	end,
	GetRealPhysicsFPS = function()
		return 60
	end,
})

local HttpService = service("HttpService")
local guidCount = 0
local function jsonEncode(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" or kind == "number" then
		if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
			return "null"
		end
		return tostring(value)
	elseif kind == "string" then
		return '"' .. value:gsub('[%c"\\]', function(c)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return map[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif kind == "table" then
		if #value > 0 or next(value) == nil then
			local parts = {}
			for _, item in ipairs(value) do
				table.insert(parts, jsonEncode(item))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for key in value do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		local parts = {}
		for _, key in keys do
			local item = value[key]
			if item == nil then
				item = value[tonumber(key)]
			end
			table.insert(parts, jsonEncode(key) .. ":" .. jsonEncode(item))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("JSONEncode: Typ " .. kind .. " geht nicht")
end
local function jsonDecode(text)
	local pos = 1
	local function skip()
		pos = text:find("[^%s]", pos) or #text + 1
	end
	local parseValue
	local function parseString()
		local out = {}
		pos += 1
		while true do
			local c = text:sub(pos, pos)
			if c == "" then
				error("JSONDecode: Zeichenkette endet nicht")
			elseif c == '"' then
				pos += 1
				return table.concat(out)
			elseif c == "\\" then
				local n = text:sub(pos + 1, pos + 1)
				local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				if n == "u" then
					table.insert(out, utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16)))
					pos += 6
				else
					table.insert(out, map[n] or n)
					pos += 2
				end
			else
				table.insert(out, c)
				pos += 1
			end
		end
	end
	function parseValue()
		skip()
		local c = text:sub(pos, pos)
		if c == "{" then
			local result = {}
			pos += 1
			skip()
			if text:sub(pos, pos) == "}" then
				pos += 1
				return result
			end
			while true do
				skip()
				local key = parseString()
				skip()
				pos += 1 -- :
				result[key] = parseValue()
				skip()
				local sep = text:sub(pos, pos)
				pos += 1
				if sep == "}" then
					return result
				end
			end
		elseif c == "[" then
			local result = {}
			pos += 1
			skip()
			if text:sub(pos, pos) == "]" then
				pos += 1
				return result
			end
			while true do
				table.insert(result, parseValue())
				skip()
				local sep = text:sub(pos, pos)
				pos += 1
				if sep == "]" then
					return result
				end
			end
		elseif c == '"' then
			return parseString()
		elseif text:sub(pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos += 4
			return nil
		end
		local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if not number or number == "" then
			error("JSONDecode: unerwartetes Zeichen an Stelle " .. pos)
		end
		pos += #number
		return tonumber(number)
	end
	return parseValue()
end
rawset(HttpService, "__methods", {
	JSONEncode = function(_, value)
		return jsonEncode(value)
	end,
	JSONDecode = function(_, text)
		return jsonDecode(text)
	end,
	GenerateGUID = function(_, wrap)
		guidCount += 1
		local guid = string.format("00000000-0000-4000-8000-%012d", guidCount)
		return wrap == false and guid or "{" .. guid .. "}"
	end,
	UrlEncode = function(_, text)
		return (text:gsub("[^%w%-_%.~]", function(c)
			return string.format("%%%02X", c:byte())
		end))
	end,
})

local RunService = service("RunService")
SIM.RenderSteps = {}
rawset(RunService, "__methods", {
	IsServer = function()
		return SIM.IsServer
	end,
	IsClient = function()
		return not SIM.IsServer
	end,
	IsStudio = function()
		return SIM.IsStudio
	end,
	IsRunning = function()
		return true
	end,
	IsRunMode = function()
		return false
	end,
	BindToRenderStep = function(_, name, _priority, fn)
		SIM.RenderSteps[name] = fn
	end,
	UnbindFromRenderStep = function(_, name)
		SIM.RenderSteps[name] = nil
	end,
})

-- Zeit um seconds weiterlaufen lassen, dabei fps-mal pro Sekunde Stepped, Heartbeat und RenderStep feuern
function SIM.Advance(seconds, fps)
	local step = 1 / (fps or 60)
	local target = SIM.Now + seconds
	while SIM.Now + step <= target + 1e-9 do
		SIM.Run(SIM.Now + step)
		RunService.Stepped:Fire(SIM.Now, step)
		RunService.PreSimulation:Fire(step)
		RunService.Heartbeat:Fire(step)
		RunService.PostSimulation:Fire(step)
		if not SIM.IsServer then
			RunService.RenderStepped:Fire(step)
			for _, fn in SIM.RenderSteps do
				task.spawn(fn, step)
			end
		end
	end
	SIM.Run(target)
end

local Debris = service("Debris")
rawset(Debris, "__methods", {
	AddItem = function(_, item, lifetime)
		task.delay(lifetime or 10, function()
			if item and item.Destroy then
				item:Destroy()
			end
		end)
	end,
})

-- DataStores im Speicher: SIM.DataStores[Name] (auch geordnete). FailNext = so viele Anfragen schlagen fehl.
SIM.DataStores = {}
local function deepcopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepcopy(v)
	end
	return copy
end
SIM.DeepCopy = deepcopy
local function dataStore(name)
	local store = SIM.DataStores[name]
	if store then
		return store
	end
	store = { Name = name, Data = {}, FailNext = 0, Calls = 0 }
	local function request(self)
		self.Calls += 1
		if SIM.DataStoreLatency > 0 then
			task.wait(SIM.DataStoreLatency / 2)
		end
		if self.FailNext > 0 then
			self.FailNext -= 1
			error("DataStore-Anfrage fehlgeschlagen (simuliert)")
		end
	end
	local function answer()
		if SIM.DataStoreLatency > 0 then
			task.wait(SIM.DataStoreLatency / 2)
		end
	end
	function store:GetAsync(key)
		request(self)
		local value = deepcopy(self.Data[key])
		answer()
		return value
	end
	function store:SetAsync(key, value)
		request(self)
		self.Data[key] = deepcopy(value)
		answer()
	end
	function store:UpdateAsync(key, fn)
		request(self)
		local new = fn(deepcopy(self.Data[key]))
		if new ~= nil then
			self.Data[key] = deepcopy(new)
		end
		answer()
		return deepcopy(new)
	end
	function store:IncrementAsync(key, delta)
		request(self)
		self.Data[key] = (self.Data[key] or 0) + (delta or 1)
		answer()
		return self.Data[key]
	end
	function store:RemoveAsync(key)
		request(self)
		local old = self.Data[key]
		self.Data[key] = nil
		answer()
		return old
	end
	function store:GetSortedAsync(ascending, pageSize)
		request(self)
		local entries = {}
		for key, value in self.Data do
			if type(value) == "number" then
				table.insert(entries, { key = key, value = value })
			end
		end
		table.sort(entries, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(pageSize or 50, #entries) do
			page[i] = entries[i]
		end
		answer()
		return { IsFinished = true, GetCurrentPage = function()
			return page
		end, AdvanceToNextPageAsync = function() end }
	end
	SIM.DataStores[name] = store
	return store
end
SIM.DataStore = dataStore
local DataStoreService = service("DataStoreService")
rawset(DataStoreService, "__methods", {
	GetDataStore = function(_, name, scope)
		return dataStore(scope and (name .. "/" .. scope) or name)
	end,
	GetOrderedDataStore = function(_, name, scope)
		return dataStore(scope and (name .. "/" .. scope) or name)
	end,
	GetGlobalDataStore = function()
		return dataStore("global")
	end,
	GetRequestBudgetForRequestType = function()
		return 100
	end,
})

-- Käufe: SIM.OwnedPasses[UserId][PassId] = true
SIM.OwnedPasses = {}
local MarketplaceService = service("MarketplaceService")
rawset(MarketplaceService, "__methods", {
	UserOwnsGamePassAsync = function(_, userId, passId)
		return (SIM.OwnedPasses[userId] or {})[passId] == true
	end,
	PlayerOwnsAsset = function()
		return false
	end,
	GetProductInfo = function()
		return { Name = "Produkt", PriceInRobux = 0 }
	end,
	PromptGamePassPurchase = function(_, player, passId)
		table.insert(SIM.RemoteLog, { Remote = "PromptGamePassPurchase", Player = player, Args = table.pack(passId) })
	end,
	PromptProductPurchase = function(_, player, productId)
		table.insert(SIM.RemoteLog, { Remote = "PromptProductPurchase", Player = player, Args = table.pack(productId) })
	end,
	PromptPurchase = function() end,
})

local TweenService = service("TweenService")
rawset(TweenService, "__methods", {
	Create = function(_, instance, info, goal)
		local tween = { Instance = instance, TweenInfo = info, PlaybackState = Enum.PlaybackState.Begin,
			Completed = SIM.Signal() }
		local thread
		function tween:Play()
			self.PlaybackState = Enum.PlaybackState.Playing
			thread = task.delay((info and info.Time or 1) + (info and info.DelayTime or 0), function()
				for key, value in goal do
					instance[key] = value
				end
				self.PlaybackState = Enum.PlaybackState.Completed
				self.Completed:Fire(Enum.PlaybackState.Completed)
			end)
		end
		function tween:Cancel()
			if thread then
				task.cancel(thread)
			end
			self.PlaybackState = Enum.PlaybackState.Cancelled
		end
		function tween:Pause()
			if thread then
				task.cancel(thread)
			end
			self.PlaybackState = Enum.PlaybackState.Paused
		end
		function tween:Destroy() end
		return tween
	end,
	GetValue = function(_, alpha)
		return alpha
	end,
})

local CollectionService = service("CollectionService")
rawset(CollectionService, "__methods", {
	AddTag = function(_, instance, tag)
		instance:AddTag(tag)
	end,
	RemoveTag = function(_, instance, tag)
		instance:RemoveTag(tag)
	end,
	HasTag = function(_, instance, tag)
		return instance:HasTag(tag)
	end,
	GetTagged = function(_, tag)
		local list = {}
		for _, root in services do
			for _, instance in root:GetDescendants() do
				if instance:HasTag(tag) then
					table.insert(list, instance)
				end
			end
		end
		return list
	end,
	GetInstanceAddedSignal = function()
		return SIM.Signal()
	end,
	GetInstanceRemovedSignal = function()
		return SIM.Signal()
	end,
})

local PathfindingService = service("PathfindingService")
rawset(PathfindingService, "__methods", {
	CreatePath = function()
		local path = { Status = Enum.PathStatus.NoPath, Blocked = SIM.Signal() }
		function path:ComputeAsync() end
		function path:GetWaypoints()
			return {}
		end
		function path:Destroy() end
		return path
	end,
})

local PhysicsService = service("PhysicsService")
rawset(PhysicsService, "__methods", {
	RegisterCollisionGroup = function() end,
	CollisionGroupSetCollidable = function() end,
	IsCollisionGroupRegistered = function()
		return true
	end,
})

local MessagingService = service("MessagingService")
SIM.Messages = {}
rawset(MessagingService, "__methods", {
	PublishAsync = function(_, topic, message)
		table.insert(SIM.Messages, { Topic = topic, Message = message })
	end,
	SubscribeAsync = function()
		return { Disconnect = function() end }
	end,
})

local BadgeService = service("BadgeService")
rawset(BadgeService, "__methods", {
	AwardBadge = function()
		return true
	end,
	UserHasBadgeAsync = function()
		return false
	end,
})

-- Eingabe: im Simulator tippt niemand in ein Textfeld
local UserInputService = service("UserInputService")
SIM.KeysDown = {} -- [Enum.KeyCode.X] = true: gedrückte Tasten (UserInputService:IsKeyDown)
rawset(UserInputService, "__methods", {
	GetFocusedTextBox = function()
		return nil
	end,
	IsKeyDown = function(_, key)
		return SIM.KeysDown[key] == true
	end,
	GetMouseLocation = function()
		return Vector2.new(0, 0)
	end,
})

local TextService = service("TextService")
rawset(TextService, "__methods", {
	GetTextSize = function(_, text, size)
		return Vector2.new(#tostring(text) * size * 0.5, size)
	end,
	FilterStringAsync = function(_, text)
		return { GetNonChatStringForBroadcastAsync = function()
			return text
		end, GetNonChatStringForUserAsync = function()
			return text
		end }
	end,
})

-- game
SIM.Game = setmetatable({
	JobId = "sim-server",
	PlaceId = 0,
	PlaceVersion = 1,
	CreatorId = 0,
	GameId = 0,
	Loaded = SIM.Signal(),
}, { __index = function(_, key)
	return services[key]
end })
function SIM.Game:GetService(name)
	return services[name] or service(name)
end
function SIM.Game:FindService(name)
	return services[name]
end
function SIM.Game:BindToClose(fn)
	table.insert(SIM.Closers, fn)
end
function SIM.Game:IsLoaded()
	return true
end
SIM.Game.Workspace = Workspace

SIM.Services = services
SIM.Players = Players
SIM.Workspace = Workspace
SIM.RunService = RunService

-- ---------- Globale Funktionen ----------
local realOs = os
SIM.Os = {
	clock = function()
		return SIM.Now
	end,
	time = function(t)
		if t then
			return realOs.time(t)
		end
		return SIM.BaseTime + math.floor(SIM.Now)
	end,
	date = function(format, t)
		return realOs.date(format, t or (SIM.BaseTime + math.floor(SIM.Now)))
	end,
	difftime = realOs.difftime,
}
function SIM.Tick()
	return SIM.BaseTime + SIM.Now
end
function SIM.Time()
	return SIM.Now
end
function SIM.Warn(...)
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	local message = table.concat(parts, " ", 1, parts.n)
	table.insert(SIM.Warnings, message)
	if not SIM.Quiet then
		print("WARN " .. message)
	end
end
SIM.Settings = function()
	return setmetatable({}, { __index = function()
		return setmetatable({}, { __index = function()
			return nil
		end })
	end })
end

-- ---------- Modelle aus assets/*.rbxmx (tests/lib/rbxmx.py) ----------
-- node = { Class, Name, CFrame = { 12 Zahlen }, Size = { 3 }, Color = { r, g, b }, Transparency, Material, Shape,
-- Children = { ... } }
function SIM.BuildInstance(node, parent)
	local instance = Instance.new(node.Class)
	instance.Name = node.Name or node.Class
	if node.CFrame then
		instance.CFrame = CFrame.new(table.unpack(node.CFrame))
	end
	if node.Size then
		instance.Size = Vector3.new(table.unpack(node.Size))
	end
	if node.Color then
		instance.Color = Color3.fromRGB(table.unpack(node.Color))
	end
	if node.Transparency then
		instance.Transparency = node.Transparency
	end
	if node.Material then
		instance.Material = Enum.Material[node.Material]
	end
	if node.Shape then
		instance.Shape = Enum.PartType[node.Shape]
	end
	for _, child in node.Children or {} do
		SIM.BuildInstance(child, instance)
	end
	instance.Parent = parent
	return instance
end

-- ReplicatedStorage.Assets mit seinen Ordnern (wie default.project.json) und den Modellen aus dem Repo
function SIM.LoadAssets(folders)
	local assets = Instance.new("Folder")
	assets.Name = "Assets"
	for folderName, items in folders do
		local folder = Instance.new("Folder")
		folder.Name = folderName
		for _, item in items do
			SIM.BuildInstance(item, folder)
		end
		folder.Parent = assets
	end
	assets.Parent = services.ReplicatedStorage
end

return SIM
