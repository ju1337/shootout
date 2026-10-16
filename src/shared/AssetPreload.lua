-- AssetPreload (ModuleScript, nur Client)
-- Lädt hinter dem Ladebildschirm alles vor, was sonst erst beim ersten Anzeigen nachlädt: Waffenmodelle, Skins und
-- Aufsätze aus ReplicatedStorage.Assets (Meshes und Texturen der 3D-Vorschauen in Inventar, Hotbar, Markt und Shop)
-- und die Umgebung des Spawns (Meshes, Texturen, Decals der Teile um den Charakter). Ohne das bauen sich die
-- Waffen-Vorschauen erst beim ersten Öffnen des Inventars sichtbar auf.
-- Jede Gruppe wird für sich mit ContentProvider:PreloadAsync geladen, mehrere gleichzeitig; eine hängende Gruppe hält
-- nur bis zur Frist auf (der Ladebildschirm darf nie für immer stehen bleiben).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetPreload = {}

AssetPreload.Workers = 6 -- Gruppen, die gleichzeitig laden
AssetPreload.ChunkSize = 40 -- Teile der Umgebung je Gruppe
AssetPreload.SpawnRadius = 220 -- Studs um den Charakter, die vor dem Ausblenden fertig sein sollen

-- Klassen mit eigenen Inhalten (Mesh, Textur, Bild); alles andere lädt nichts nach
local CONTENT_CLASSES = { "MeshPart", "SpecialMesh", "Decal", "Texture", "SurfaceAppearance", "ImageLabel", "ImageButton",
	"ParticleEmitter", "Beam", "Trail", "Sky" }

local function hasContent(obj)
	for _, class in CONTENT_CLASSES do
		if obj:IsA(class) then
			return true
		end
	end
	return false
end

-- Gruppen aus ReplicatedStorage.Assets: jede Waffe (mit ihren Skins) und jeder Aufsatz für sich, damit der
-- Fortschritt in kleinen Schritten läuft. Gibt eine Liste von Instanzen zurück.
function AssetPreload.AssetGroups()
	local groups = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return groups
	end
	for _, folder in assets:GetChildren() do
		if folder:IsA("Folder") then
			for _, child in folder:GetChildren() do
				table.insert(groups, child)
			end
		else
			table.insert(groups, folder)
		end
	end
	return groups
end

-- Gruppen der Umgebung um position: Teile mit Inhalten im Umkreis radius, in Stücken zu ChunkSize.
-- Gibt eine Liste von Listen zurück (PreloadAsync nimmt eine Liste).
function AssetPreload.AreaGroups(root, position, radius)
	local groups, current = {}, {}
	if not root then
		return groups
	end
	radius = radius or AssetPreload.SpawnRadius
	for _, obj in root:GetDescendants() do
		if hasContent(obj) then
			local part = obj:IsA("BasePart") and obj or obj:FindFirstAncestorWhichIsA("BasePart")
			if part == nil or (part.Position - position).Magnitude <= radius then
				table.insert(current, obj)
				if #current >= AssetPreload.ChunkSize then
					table.insert(groups, current)
					current = {}
				end
			end
		end
	end
	if #current > 0 then
		table.insert(groups, current)
	end
	return groups
end

-- Alle Gruppen laden. onProgress(fertig, gesamt) nach jeder Gruppe. Kehrt zurück, wenn alles da ist oder die Frist
-- (Sekunden) um ist; gibt (fertig, gesamt) zurück. Fehler einzelner Inhalte stören nicht (PreloadAsync meldet sie nur).
function AssetPreload.Run(groups, onProgress, timeout)
	local total, done, nextIndex = #groups, 0, 1
	if total == 0 then
		return 0, 0
	end
	local deadline = os.clock() + (timeout or 20)
	local function worker()
		while nextIndex <= total do
			local group = groups[nextIndex]
			nextIndex += 1
			pcall(ContentProvider.PreloadAsync, ContentProvider, typeof(group) == "Instance" and { group } or group)
			done += 1
			if onProgress then
				onProgress(done, total)
			end
		end
	end
	for _ = 1, math.min(AssetPreload.Workers, total) do
		task.spawn(worker)
	end
	while done < total and os.clock() < deadline do
		task.wait(0.1)
	end
	return done, total
end

return AssetPreload
