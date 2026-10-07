-- Deine Agentenmodelle: assets/Agents/*.rbxmx (in Studio per Rechtsklick "Save to File..." gespeichert) gegen die
-- Anleitung (docs/agenten-modelle.md). Jedes Modell muss laden (Name eines Agenten, sichtbare Teile), und an einem
-- Körper hängt jedes Teil angeschweißt an einem Körperteil und zählt nie als Treffer. Hinweise erscheinen als HINWEIS
-- im Log.
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

local models = ReplicatedStorage.Assets.Agents:GetChildren()
if #models == 0 then
	print("Noch keine Agentenmodelle in assets/Agents – alle Agenten haben den Standard-Look")
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
		AgentBody.Dress(body, Color3.fromRGB(40, 60, 50), name)
		local count = 0
		for _, part in body:GetDescendants() do -- (im Untermodell AgentModel)
			if part:IsA("BasePart") and part:GetAttribute("AgentGear") then
				count += 1
				local weld = part:FindFirstChildOfClass("WeldConstraint")
				check(weld ~= nil and weld.Part0 ~= nil and weld.Part0.Parent == body, name .. ": " .. part.Name .. " angeschweißt")
				check(part.CanQuery == false and part.CanCollide == false, name .. ": " .. part.Name .. " nie Trefferzone")
			end
		end
		check(count > 0, name .. ": trägt das Modell")
		-- Spielkörper unsichtbar (Trefferzone)
		for _, partName in AgentModels.BodyParts do
			local part = body:FindFirstChild(partName)
			check(part and part.Transparency == 1 and not part:GetAttribute("AgentGear"), name .. ": Spielkörper " .. partName
				.. " unsichtbar")
		end
		print(string.format("%s: Modell geladen (%d Teile)", name, count))
	end
end

if failures == 0 then
	print("Agentenmodelle: alles in Ordnung")
end
