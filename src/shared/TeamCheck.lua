-- TeamCheck (ModuleScript, nur Client)
-- Wer gehört zu wem? Spieler über Player.Team, Bots über ihr Modell (Workspace.Bots) bzw.
-- ReplicatedStorage.BotInfo (bleibt auch nach dem Tod erhalten). Benutzt von Fadenkreuz,
-- Killfeed, Minimap und Teamleiste.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local TeamCheck = {}

local function botInfo(name)
	local folder = ReplicatedStorage:FindFirstChild("BotInfo")
	return folder and folder:FindFirstChild(name)
end

local function botModel(name)
	local folder = workspace:FindFirstChild("Bots")
	local model = folder and folder:FindFirstChild(name)
	return model and model:IsA("Model") and model or nil
end

local function myTeamName()
	return player.Team and player.Team.Name or nil
end

-- Teamname zu einem Spieler- oder Bot-Namen (nil = kein Team, z.B. Free-for-All)
function TeamCheck.TeamOfName(name)
	local other = Players:FindFirstChild(name)
	if other and other:IsA("Player") then
		return other.Team and other.Team.Name or nil
	end
	local info = botInfo(name)
	local team = info and info:GetAttribute("TeamName")
	return (team ~= nil and team ~= "") and team or nil
end

-- "Self", "Mate" oder "Enemy" (ohne Teams ist jeder andere ein Gegner)
function TeamCheck.Relation(name)
	if name == player.Name then
		return "Self"
	end
	local mine, theirs = myTeamName(), TeamCheck.TeamOfName(name)
	if mine ~= nil and mine == theirs then
		return "Mate"
	end
	return "Enemy"
end

-- Lebt das Modell noch?
local function living(model)
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Lebender Gegner im eigenen Modus (Spieler oder Bot)? Übungspuppen zählen als Gegner.
function TeamCheck.IsEnemy(model)
	if not living(model) then
		return false
	end
	local other = Players:GetPlayerFromCharacter(model)
	if other then
		return other ~= player and other:GetAttribute("Mode") == player:GetAttribute("Mode")
			and not (player.Team ~= nil and other.Team == player.Team)
	end
	if model:GetAttribute("IsDummy") then
		return true
	end
	if model:GetAttribute("IsBot") then
		return model:GetAttribute("Mode") == player:GetAttribute("Mode")
			and not (player.Team ~= nil and model:GetAttribute("TeamName") == player.Team.Name)
	end
	return false
end

-- Zustand eines Modells: "alive", "downed" oder "dead"
function TeamCheck.StateOf(model)
	if not living(model) then
		return "dead"
	end
	return model:GetAttribute("Downed") and "downed" or "alive"
end

-- Alle Kämpfer im eigenen Team-Modus, in fester Reihenfolge (man selbst zuerst, dann Spieler, dann Bots):
-- { Name, Model, AgentId, Player (oder nil), IsSelf, IsMate, State }
function TeamCheck.Fighters()
	local mode = player:GetAttribute("Mode")
	local mine = myTeamName()
	local list = {}
	if not mode then
		return list
	end
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Mode") == mode and other.Team then
			local character = other.Character
			table.insert(list, {
				Name = other.Name,
				Model = character,
				AgentId = (character and character:GetAttribute("Agent")) or other:GetAttribute("Agent"),
				Player = other,
				IsSelf = other == player,
				IsMate = mine ~= nil and other.Team.Name == mine,
				State = TeamCheck.StateOf(character),
			})
		end
	end
	local folder = ReplicatedStorage:FindFirstChild("BotInfo")
	if folder then
		for _, info in folder:GetChildren() do
			local team = info:GetAttribute("TeamName")
			if info:GetAttribute("Mode") == mode and team and team ~= "" then
				local model = botModel(info.Name)
				table.insert(list, {
					Name = info.Name,
					Model = model,
					AgentId = info:GetAttribute("Agent"),
					Player = nil,
					IsSelf = false,
					IsMate = team == mine,
					State = TeamCheck.StateOf(model),
				})
			end
		end
	end
	table.sort(list, function(a, b)
		if a.IsSelf ~= b.IsSelf then
			return a.IsSelf
		end
		if (a.Player ~= nil) ~= (b.Player ~= nil) then
			return a.Player ~= nil
		end
		return a.Name < b.Name
	end)
	return list
end

return TeamCheck
