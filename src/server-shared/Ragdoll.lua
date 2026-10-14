-- Ragdoll (ModuleScript, nur Server)
-- Tote Körper fallen als ganzer Körper um, statt in einzelne Teile zu zerfallen (Roblox-Standard BreakJointsOnDeath)
-- oder steif stehen zu bleiben (Avatar Joint Upgrade): jedes Gelenk (Motor6D bzw. AnimationConstraint) wird durch ein
-- Kugelgelenk mit Grenzen ersetzt. Für Spieler, Bots und Zombies. Vorher BreakJointsOnDeath = false setzen (Prepare).

local Ragdoll = {}

-- Humanoid soll beim Tod nicht selbst die Gelenke lösen (das macht Apply)
function Ragdoll.Prepare(humanoid)
	humanoid.BreakJointsOnDeath = false
end

function Ragdoll.Apply(model)
	local limbs = {} -- [Teil] = true: hängt an einem Gelenk (Augen, Blut, Accessoires bleiben ohne Kollision)
	for _, joint in model:GetDescendants() do
		if (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) and joint.Parent then
			-- AnimationConstraint: Part0/Part1/C0/C1 sind lesbare Aliase der Attachments. Klappt das Kugelgelenk
			-- nicht, zerfällt der Körper eben klassisch – Hauptsache, er bleibt nicht stehen.
			pcall(function()
				local part0, part1 = joint.Part0, joint.Part1
				if part0 and part1 then
					limbs[part0], limbs[part1] = true, true
					local a0 = Instance.new("Attachment")
					a0.Name = "RagdollAttachment"
					a0.CFrame = joint.C0
					a0.Parent = part0
					local a1 = Instance.new("Attachment")
					a1.Name = "RagdollAttachment"
					a1.CFrame = joint.C1
					a1.Parent = part1
					local socket = Instance.new("BallSocketConstraint")
					socket.Attachment0 = a0
					socket.Attachment1 = a1
					socket.LimitsEnabled = true
					socket.UpperAngle = 70
					socket.TwistLimitsEnabled = true
					socket.TwistLowerAngle = -45
					socket.TwistUpperAngle = 45
					socket.Parent = part1
					-- Nachbarteile nicht gegeneinander stoßen lassen (sonst zittert der Körper)
					local noCollide = Instance.new("NoCollisionConstraint")
					noCollide.Part0 = part0
					noCollide.Part1 = part1
					noCollide.Parent = part1
				end
			end)
			joint:Destroy()
		end
	end
	for part in limbs do
		if part.Parent and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true -- Gliedmaßen liegen auf dem Boden statt hindurchzufallen
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(part.SetNetworkOwner, part, nil) -- der Server rechnet den fallenden Körper
		end
	end
end

return Ragdoll
