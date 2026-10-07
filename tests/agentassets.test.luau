-- Deine Agentenmodelle: assets/Agents/*.rbxmx (in Studio per Rechtsklick "Save to File..." gespeichert) gegen die
-- Spezifikation (docs/agenten-modelle.md). Jedes Modell muss laden (Name eines Agenten, Ausrüstung an Körperteilen,
-- plausible Lage und Größe), Textur-Skins müssen zu echten Skins dieses Agenten gehören, und an einem Körper sitzt
-- jedes Teil eng an seinem Körperteil und zählt nie als Treffer. Hinweise erscheinen als HINWEIS im Log.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AgentModels = require("AgentModels")
local AgentBody = require("AgentBody")
local Cosmetics = require("Cosmetics")

local models = ReplicatedStorage.Assets.Agents:GetChildren()
if #models == 0 then
	print("Noch keine Agentenmodelle in assets/Agents – alle Agenten tragen die Quader-Ausrüstung")
end
local report = AgentModels.AssetReport()
for _, source in models do
	local name = source.Name
	local entry = report[name]
	check(entry ~= nil and entry.Loaded,
		name .. ": nicht geladen – " .. (entry and table.concat(entry.Errors, "; ") or "kein Prüfbericht"))
	for _, warning in entry and entry.Warnings or {} do
		print("HINWEIS " .. name .. ": " .. warning)
	end
	local skins = source:FindFirstChild("Skins")
	for _, folder in skins and skins:GetChildren() or {} do
		local item = Cosmetics.Get(folder.Name)
		check(item ~= nil and item.Type == "Agent" and item.Agent == name,
			name .. ": Skins/" .. folder.Name .. " ist kein Agenten-Skin von " .. name)
	end
	if entry and entry.Loaded then
		-- an einem Körper wie im Spiel: jedes Teil hängt an seinem Körperteil und ist nie Trefferzone
		local body = Instance.new("Model")
		for _, partName in AgentModels.BodyParts do
			local rest = AgentModels.Body[partName]
			local part = Instance.new("Part")
			part.Name = partName
			part.Size = rest.Size
			part.CFrame = rest.CFrame
			part.Parent = body
		end
		local agentColor = Color3.fromRGB(90, 160, 110)
		AgentBody.Dress(body, agentColor:Lerp(Color3.new(0, 0, 0), 0.6), agentColor, name)
		local count = 0
		for _, part in body:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("AgentGear") then
				count += 1
				local weld = part:FindFirstChildOfClass("WeldConstraint")
				check(weld ~= nil and weld.Part0 ~= nil and weld.Part0.Parent == body, name .. ": " .. part.Name .. " angeschweißt")
				check(part.CanQuery == false and part.CanCollide == false, name .. ": " .. part.Name .. " nie Trefferzone")
			end
		end
		check(count > 0 and body:FindFirstChild("AgentVest") == nil, name .. ": trägt die Ausrüstung aus dem Modell")
		if AgentModels.IsCharacter(name) then
			-- ganzer Charakter: Spielkörper unsichtbar (Trefferzone), seine Teile bleiben die einzigen mit Körperteil-Namen
			for _, partName in AgentModels.BodyParts do
				local part = body:FindFirstChild(partName)
				check(part and part.Transparency == 1, name .. ": Spielkörper " .. partName .. " unsichtbar")
				check(part and not part:GetAttribute("AgentGear"), name .. ": " .. partName .. " ist der Spielkörper, nicht das Modell")
			end
		end
		print(string.format("%s: %s geladen (%d Teile)", name, AgentModels.IsCharacter(name) and "Charakter" or "3D-Modell", count))
	end
end

if failures == 0 then
	print("Agentenmodelle: alles in Ordnung")
end
