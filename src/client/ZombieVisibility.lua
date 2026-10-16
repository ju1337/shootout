-- ZombieVisibility (ModuleScript, nur Client)
-- Zombies pro Spieler (ZombieOwner): Zombies, die einem anderen Spieler gehören (Attribut ZombieOwnerId), nimmt dieser
-- Client aus der Welt (nur lokal, in einen Ordner in ReplicatedStorage). Damit sind sie für ihn ganz weg: nicht zu sehen,
-- nicht zu hören (ihre Geräusche hängen am Körper), keine Kollision, kein Treffer, kein Beute-Prompt an der Leiche.
-- Gemeinsame Zombies (Bosse, Events, Dungeon) bleiben für alle sichtbar. Der Server löscht versteckte Zombies wie alle
-- anderen (dann sind sie auch hier weg); was nach dem Streaming neu ankommt, wird wieder versteckt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieOwner = require(ReplicatedStorage:WaitForChild("Shared").ZombieOwner)

local player = Players.LocalPlayer

local ZombieVisibility = {}

local hidden = nil -- Ordner für fremde Zombies (nur lokal)

local function check(child, folder)
	if child.Parent == folder and not ZombieOwner.CanSee(child, player) then
		child.Parent = hidden
	end
end

function ZombieVisibility.Init()
	hidden = Instance.new("Folder")
	hidden.Name = "HiddenZombies"
	hidden.Parent = ReplicatedStorage
	task.spawn(function()
		local folder = workspace:WaitForChild("Zombies")
		for _, child in folder:GetChildren() do
			check(child, folder)
		end
		folder.ChildAdded:Connect(function(child)
			-- erst nach dem Einfügen umhängen (im ChildAdded selbst warnt Roblox beim Umhängen)
			task.defer(check, child, folder)
		end)
	end)
end

return ZombieVisibility
