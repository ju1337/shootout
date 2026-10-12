-- ItemPreview (ModuleScript, nur Client)
-- 3D-Vorschau von Waffen in ViewportFrames (Markt, Tausch, Kisten, Stände, Inventar, Hotbar): Waffe von der Seite,
-- die Kamera rückt so nah heran, dass die Waffe die Fläche füllt (ohne Verzerrung). Gemessen wird die echte Größe
-- des ViewportFrames, ändert sie sich (Fenster, Handy, UIScale), wird neu eingepasst. Helles Licht, damit die
-- matten dunklen Modelle auf den dunklen Karten lesbar bleiben.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)

local ItemPreview = {}

local FOV = 20 -- kleines Sichtfeld = kaum Perspektive, die Waffe wirkt flach von der Seite
local FILL = 0.94 -- Anteil der Fläche, den die Waffe in der knappen Richtung füllt
local LIFT = 0.08 -- Kamera leicht von oben

-- Neuer ViewportFrame mit hellem Vorschau-Licht (props wie bei Instance-Eigenschaften)
function ItemPreview.New(parent, props)
	local view = Instance.new("ViewportFrame")
	view.BackgroundTransparency = 1
	ItemPreview.Light(view)
	for key, value in props or {} do
		view[key] = value
	end
	view.Parent = parent
	return view
end

-- Licht von vorne oben (Kamera steht auf +X), Grundlicht hoch: dunkle Waffen bleiben erkennbar
function ItemPreview.Light(view)
	view.Ambient = Color3.fromRGB(205, 208, 218)
	view.LightColor = Color3.fromRGB(255, 250, 240)
	view.LightDirection = Vector3.new(-0.7, -1, 0.35)
end

-- Achsenparallele Hülle aller sichtbaren Teile (unsichtbare Hilfsteile wie Mündung/Lader zählen nicht)
local function visibleBounds(model)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf, half = part.CFrame, part.Size / 2
			local extent = Vector3.new(
				math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z,
				math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z,
				math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z)
			low = low:Min(cf.Position - extent)
			high = high:Max(cf.Position + extent)
		end
	end
	if low.X > high.X then
		local box, size = model:GetBoundingBox()
		return box.Position, size
	end
	return (low + high) / 2, high - low
end

-- Kamera so setzen, dass die Waffe (Lauf zeigt nach -Z) die Fläche füllt; aspect = Breite / Höhe
function ItemPreview.Fit(view, camera, center, size, aspect, fill)
	local tanV = math.tan(math.rad(FOV / 2))
	local tanH = tanV * aspect
	local distance = math.max(size.Z / 2 / tanH, size.Y / 2 / tanV) / (fill or FILL) + size.X / 2
	camera.FieldOfView = FOV
	camera.CFrame = CFrame.lookAt(center + Vector3.new(distance, distance * LIFT, 0), center)
end

-- Modell in den ViewportFrame setzen und einpassen; passt sich an, wenn sich die Größe des Frames ändert.
-- fallbackAspect gilt, solange der Frame noch keine Größe hat (unsichtbar/noch nicht im Bild).
function ItemPreview.Frame(view, model, fallbackAspect, fill)
	local camera = Instance.new("Camera")
	model.Parent = view
	camera.Parent = view
	view.CurrentCamera = camera
	local center, size = visibleBounds(model)
	local function refit()
		local abs = view.AbsoluteSize
		local aspect = (abs.X > 1 and abs.Y > 1) and abs.X / abs.Y or fallbackAspect or 1.4
		ItemPreview.Fit(view, camera, center, size, aspect, fill)
	end
	refit()
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	return camera
end

-- Skin item in view zeigen; aspect = Breite / Höhe der Vorschau (nur bis der Frame seine echte Größe kennt)
function ItemPreview.Show(view, item, aspect)
	view:ClearAllChildren()
	if not item then
		return
	end
	ItemPreview.Frame(view, GunModels.Build(item.Weapon or "Rifle", item), aspect)
end

return ItemPreview
