-- PartyService (ModuleScript, nur Server)
-- Squads wie bei Rogue Company (bis zu 4 Spieler): einladen, annehmen, verlassen, rauswerfen.
-- Wechselt der Anführer in einen Modus, kommt der ganze Squad mit. In Team-Modi landet der Squad
-- im selben Team (TeamRoundMode fragt PartyService.Leader).
-- Spieler-Attribut "Party" (JSON): { Leader = UserId, Members = { { UserId, Name }, ... } }

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local PartyService = {}

local MAX_SIZE = 4
local INVITE_TIME = 60 -- Sekunden gültig

local partyOf = {}  -- [Player] = party ({ Leader = Player, Members = { Player, ... } })
local invites = {}  -- [Player] = { [Anführer] = Ablaufzeit }
local manager = nil

local function publish(party)
	local list = {}
	for _, member in party.Members do
		table.insert(list, { UserId = member.UserId, Name = member.Name })
	end
	local data = HttpService:JSONEncode({ Leader = party.Leader.UserId, Members = list })
	for _, member in party.Members do
		member:SetAttribute("Party", data)
	end
end

local function leave(player)
	local party = partyOf[player]
	if not party then
		return
	end
	partyOf[player] = nil
	player:SetAttribute("Party", nil)
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	if #party.Members <= 1 then
		-- Squad mit nur noch einer Person auflösen
		for _, member in party.Members do
			partyOf[member] = nil
			member:SetAttribute("Party", nil)
		end
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
	end
	publish(party)
end

-- Anführer des Squads (oder nil)
function PartyService.Leader(player)
	local party = partyOf[player]
	return party and party.Leader or nil
end

-- Alle Mitglieder (inkl. Spieler selbst) oder nur der Spieler
function PartyService.Members(player)
	local party = partyOf[player]
	return party and party.Members or { player }
end

local function status(player, text)
	Remotes.ShopStatus:FireClient(player, text, true)
end

local actions = {}

function actions.Invite(player, userId)
	local target = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if not target or target == player then
		return
	end
	local party = partyOf[player]
	if party and party.Leader ~= player then
		return status(player, "Nur der Squad-Anführer kann einladen.")
	end
	if party and #party.Members >= MAX_SIZE then
		return status(player, "Squad ist voll (" .. MAX_SIZE .. ").")
	end
	if partyOf[target] then
		return status(player, target.Name .. " ist schon in einem Squad.")
	end
	invites[target] = invites[target] or {}
	invites[target][player] = os.clock() + INVITE_TIME
	Remotes.PartyInvite:FireClient(target, player.Name, player.UserId)
	status(player, "Einladung an " .. target.Name .. " gesendet.")
end

function actions.Accept(player, userId)
	local leader = Players:GetPlayerByUserId(tonumber(userId) or 0)
	local pending = invites[player] and leader and invites[player][leader]
	if not pending or os.clock() > pending then
		return status(player, "Einladung abgelaufen.")
	end
	invites[player][leader] = nil
	leave(player)
	local party = partyOf[leader]
	if not party then
		party = { Leader = leader, Members = { leader } }
		partyOf[leader] = party
	end
	if #party.Members >= MAX_SIZE then
		return status(player, "Squad ist voll.")
	end
	table.insert(party.Members, player)
	partyOf[player] = party
	publish(party)
	-- Gleich in den Modus des Anführers mitkommen
	if manager and leader:GetAttribute("Mode") ~= player:GetAttribute("Mode") then
		manager.Join(player, leader:GetAttribute("Mode"))
	end
end

function actions.Decline(player, userId)
	local leader = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if invites[player] and leader then
		invites[player][leader] = nil
	end
end

function actions.Leave(player)
	leave(player)
end

function actions.Kick(player, userId)
	local party = partyOf[player]
	local target = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if party and party.Leader == player and target and partyOf[target] == party then
		leave(target)
		status(target, "Du wurdest aus dem Squad entfernt.")
	end
end

function PartyService.Init(modeManager)
	manager = modeManager
	Remotes.PartyAction.OnServerEvent:Connect(function(player, action, userId)
		local handler = typeof(action) == "string" and actions[action]
		if handler then
			handler(player, userId)
		end
	end)
	-- Anführer wechselt den Modus: Squad kommt mit
	modeManager.Joined:Connect(function(player, modeId)
		local party = partyOf[player]
		if not party or party.Leader ~= player then
			return
		end
		for _, member in party.Members do
			if member ~= player and member:GetAttribute("Mode") ~= modeId then
				task.spawn(manager.Join, member, modeId)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		invites[player] = nil
	end)
end

return PartyService
