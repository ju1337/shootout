-- Vorladen hinter dem Ladebildschirm (AssetPreload): jede Waffe aus ReplicatedStorage.Assets ist eine eigene Gruppe,
-- alle Gruppen laden über ContentProvider:PreloadAsync mit Fortschritt; eine hängende Gruppe hält nur bis zur Frist auf.
-- Die Umgebung des Spawns: nur Teile mit Inhalten im Umkreis.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

SIM.IsServer = false
local ContentProvider = game:GetService("ContentProvider")
local preloaded = {}
local hang = nil
ContentProvider.PreloadAsync = function(_, list)
	for _, obj in list do
		if obj == hang then
			task.wait(1000)
		end
		table.insert(preloaded, obj)
	end
end

local AssetPreload = require("AssetPreload")

-- ---------- Assets ----------
local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
check(assets ~= nil and assets:FindFirstChild("Weapons") ~= nil, "Assets.Weapons fehlt im Test")
local groups = AssetPreload.AssetGroups()
for _, weapon in assets.Weapons:GetChildren() do
	check(table.find(groups, weapon) ~= nil, "Waffe nicht vorgeladen: " .. weapon.Name)
end

local lastDone, lastTotal = 0, 0
local finished = false
task.spawn(function()
	AssetPreload.Run(groups, function(done, total)
		lastDone, lastTotal = done, total
	end, 20)
	finished = true
end)
SIM.Advance(1)
check(finished, "Vorladen ist nicht fertig geworden")
check(lastDone == #groups and lastTotal == #groups, "Fortschritt endet nicht bei gesamt: " .. lastDone .. "/" .. lastTotal)
for _, weapon in assets.Weapons:GetChildren() do
	check(table.find(preloaded, weapon) ~= nil, "PreloadAsync bekam die Waffe nicht: " .. weapon.Name)
end

-- hängende Gruppe: Frist greift
local stuck = Instance.new("Folder")
hang = stuck
finished = false
local doneCount = -1
task.spawn(function()
	doneCount = AssetPreload.Run({ stuck, Instance.new("Folder") }, nil, 5)
	finished = true
end)
SIM.Advance(4)
check(not finished, "Frist zu früh abgelaufen")
SIM.Advance(2)
check(finished, "hängendes Asset hält den Ladebildschirm über die Frist hinaus fest")
check(doneCount == 1, "nur die nicht hängende Gruppe ist fertig: " .. tostring(doneCount))

-- leere Liste kehrt sofort zurück
check(select(2, AssetPreload.Run({}, nil, 5)) == 0, "leere Liste")

-- ---------- Umgebung ----------
local map = Instance.new("Model", workspace)
local near = Instance.new("MeshPart", map)
near.Position = Vector3.new(10, 0, 0)
local far = Instance.new("MeshPart", map)
far.Position = Vector3.new(5000, 0, 0)
local plain = Instance.new("Part", map)
plain.Position = Vector3.new(0, 0, 0)
local decal = Instance.new("Decal", plain)
local area = AssetPreload.AreaGroups(map, Vector3.zero, 200)
local flat = {}
for _, chunk in area do
	for _, obj in chunk do
		table.insert(flat, obj)
	end
end
check(table.find(flat, near) ~= nil, "MeshPart in der Nähe fehlt")
check(table.find(flat, decal) ~= nil, "Decal in der Nähe fehlt")
check(table.find(flat, far) == nil, "weit entfernter Teil wird mitgeladen")
check(table.find(flat, plain) == nil, "Teil ohne Inhalt wird mitgeladen")

if failures > 0 then
	error(failures .. " Fehler")
end
print("assetpreload: alles ok")
