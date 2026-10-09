-- Agenten-Skins mit eigenem 3D-Modell (Cosmetics Model = true, z.B. AS_Scout): Modell in Assets.Agents heißt wie der
-- Skin, lädt wie ein Agentenmodell. Wer den Skin trägt, wird zu diesem Modell (Spawn, Vorschau); ohne Modell im Place
-- bleibt der normale Look. Andere Namen werden weiter abgelehnt.
local failures = 0
local function check(c, m) if not c then failures += 1 print("FEHLER: " .. m) end end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder", ReplicatedStorage)
assets.Name = "Assets"
local folder = assets:FindFirstChild("Agents") or Instance.new("Folder", assets)
folder.Name = "Agents"

-- 15 starre Teile <Körperteil>_Suit auf dem Spielkörper (wie tools: Scout.glb)
local PARTS = {
	Head = { Vector3.new(1.5, 1.4, 1.5), Vector3.new(0, 4.55, 0) },
	UpperTorso = { Vector3.new(1.6, 1.5, 0.9), Vector3.new(0, 3.1, 0) },
	LowerTorso = { Vector3.new(1.6, 0.4, 0.9), Vector3.new(0, 2.15, 0) },
	LeftUpperArm = { Vector3.new(0.7, 0.8, 0.8), Vector3.new(-1.25, 3.45, 0) },
	LeftLowerArm = { Vector3.new(0.7, 0.67, 0.8), Vector3.new(-1.25, 2.72, 0) },
	LeftHand = { Vector3.new(0.7, 0.5, 0.8), Vector3.new(-1.25, 2.13, 0) },
	RightUpperArm = { Vector3.new(0.7, 0.8, 0.8), Vector3.new(1.25, 3.45, 0) },
	RightLowerArm = { Vector3.new(0.7, 0.67, 0.8), Vector3.new(1.25, 2.72, 0) },
	RightHand = { Vector3.new(0.7, 0.5, 0.8), Vector3.new(1.25, 2.13, 0) },
	LeftUpperLeg = { Vector3.new(0.75, 0.8, 0.8), Vector3.new(-0.4, 1.55, 0) },
	LeftLowerLeg = { Vector3.new(0.75, 0.66, 0.8), Vector3.new(-0.4, 0.83, 0) },
	LeftFoot = { Vector3.new(0.8, 0.5, 1.0), Vector3.new(-0.4, 0.25, 0) },
	RightUpperLeg = { Vector3.new(0.75, 0.8, 0.8), Vector3.new(0.4, 1.55, 0) },
	RightLowerLeg = { Vector3.new(0.75, 0.66, 0.8), Vector3.new(0.4, 0.83, 0) },
	RightFoot = { Vector3.new(0.8, 0.5, 1.0), Vector3.new(0.4, 0.25, 0) },
}
local function suit(name)
	local model = Instance.new("Model")
	model.Name = name
	for part, def in PARTS do
		local p = Instance.new("MeshPart")
		p.Name = part .. "_Suit"
		p.Size = def[1]
		p.CFrame = CFrame.new(def[2])
		Instance.new("SurfaceAppearance", p)
		p.Parent = model
	end
	local root = Instance.new("Part")
	root.Name = "Point_Root"
	root.Size = Vector3.new(0.05, 0.05, 0.05)
	root.Parent = model
	return model
end
suit("AS_Scout").Parent = folder
suit("AS_Feldgrau").Parent = folder -- Skin ohne Model = true: kein gültiger Name

local AgentModels = require("AgentModels")
local AgentConfig = require("AgentConfig")
local Cosmetics = require("Cosmetics")
local AgentFigure = require("AgentFigure")

local scout = Cosmetics.Get("AS_Scout")
check(scout ~= nil and scout.Type == "Agent" and scout.Model == true, "AS_Scout fehlt oder ohne Model = true")
check(scout ~= nil and Cosmetics.ForSale(scout), "Scout nicht im Shop")
local report = AgentModels.AssetReport()
check(report.AS_Scout and report.AS_Scout.Loaded, "Scout-Modell lädt nicht: "
	.. (report.AS_Scout and table.concat(report.AS_Scout.Errors, "; ") or "kein Bericht"))
check(report.AS_Feldgrau and not report.AS_Feldgrau.Loaded, "Skin ohne eigenes Modell wird als Modell geladen")

local main = AgentConfig.MainId
check(AgentModels.LookFor(main, scout) == "AS_Scout", "Scout-Skin trägt nicht das Scout-Modell")
check(AgentModels.LookFor(main, nil) == main, "ohne Skin nicht der Agent")
check(AgentModels.LookFor(main, Cosmetics.Get("AS_Feldgrau")) == main, "Farb-Skin wechselt das Modell")
check(AgentModels.LookFor(main, { Id = "AS_Fehlt", Model = true }) == main, "Skin ohne geladenes Modell bricht den Look")

local character = AgentModels.BuildCharacter("AS_Scout")
check(character ~= nil and character:GetAttribute("AgentModelCharacter") == "AS_Scout", "kein Scout-Charakter")
check(character and character:FindFirstChild("HumanoidRootPart") ~= nil, "Scout-Charakter ohne HumanoidRootPart")

-- Vorschau (Menü SKINS, Shop): mit look das Scout-Modell, ohne der Standard-Agent
local agent = AgentConfig.Get(main)
local function suitParts(model)
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and string.find(d.Name, "_Suit", 1, true) then n += 1 end
	end
	return n
end
local withScout = AgentFigure.Build(agent, Color3.new(), Color3.new(), nil, nil, nil, "AS_Scout")
check(suitParts(withScout) == 15, "Vorschau zeigt das Scout-Modell nicht (" .. suitParts(withScout) .. " Teile)")
local fallback = AgentFigure.Build(agent, Color3.new(), Color3.new(), nil, nil, nil, "AS_Fehlt")
check(fallback ~= nil, "Vorschau mit fehlendem Modell bricht ab")

if failures == 0 then print("alles ok") end
