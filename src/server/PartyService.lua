-- PartyService (ModuleScript, nur Server)
-- Squads wie bei Rogue Company (bis zu 4 Spieler): einladen, annehmen, verlassen, rauswerfen.
-- Wechselt der Anführer in einen Modus, kommt der ganze Squad mit. In Team-Modi landet der Squad
-- im selben Team (TeamRoundMode fragt PartyService.Leader).
-- Spieler-Attribut "Party" (JSON): { Leader = UserId, Members = { { UserId, Name }, ... } }
-- Spieler-Attribut "PartyReady" (true/nil): BEREIT-Schalter in der Lobby; zurückgesetzt, sobald der
-- Squad in einen Kampfmodus wechselt oder man den Squad verlässt.
-- Spieler-Attribut "SquadId" (Zahl/nil): gleiche Zahl = gleicher Squad. In der offenen Welt (EXTINCTION) ist der Squad das
-- Team: kein Friendly Fire (WeaponService, VehicleService), Pings nur an den Squad (PingService), Namen, Punkte auf der
-- Minimap und Squad-Liste für die Mitglieder (TeamCheck, ExtinctionClient). Verlässt der Anführer die offene Welt, bleiben die
-- anderen dort (draußen würde Verlassen sonst ihre Tasche kosten); betritt er sie, kommt der Squad mit.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local PartyService = {}

local MAX_SIZE = 4
local INVITE_TIME = 60 -- Sekunden gültig

local partyOf = {}  -- [Player] = party ({ Id, Leader = Player, Members = { Player, ... } })
local nextId = 0
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
		member:SetAttribute("SquadId", party.Id)
	end
end

local function leave(player)
	local party = partyOf[player]
	if not party then
		return
	end
	partyOf[player] = nil
	player:SetAttribute("Party", nil)
	player:SetAttribute("PartyReady", nil)
	player:SetAttribute("SquadId", nil)
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	if #party.Members <= 1 then
		-- Squad mit nur noch einer Person auflösen
		for _, member in party.Members do
			partyOf[member] = nil
			member:SetAttribute("Party", nil)
			member:SetAttribute("PartyReady", nil)
			member:SetAttribute("SquadId", nil)
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

-- Sind beide im selben Squad?
function PartyService.SameSquad(a, b)
	return a ~= nil and b ~= nil and partyOf[a] ~= nil and partyOf[a] == partyOf[b]
end

-- Wer mit dem Spieler den Server wechselt (MatchmakingService): als Anführer sein Squad – ohne die, die gerade in der
-- offenen Welt sind (wie beim Moduswechsel) –, sonst nur er selbst
function PartyService.Followers(player)
	local party = partyOf[player]
	if not party or party.Leader ~= player then
		return { player }
	end
	local list = {}
	for _, member in party.Members do
		if member == player or member:GetAttribute("Mode") ~= "Extinction" then
			table.insert(list, member)
		end
	end
	return list
end

-- Squad nach einem Serverwechsel wieder bilden: party = { Leader = UserId, Members = { UserId } } aus den Ankunftsdaten.
-- Zusammen kommt nur, wer sich gegenseitig nennt (Anführer listet das Mitglied, das Mitglied nennt den Anführer).
local regroup = {} -- [UserId] = { Leader, Members = { [UserId] = true }, Expires }
local REGROUP_TIME = 120

local function tryRegroup()
	for _, member in Players:GetPlayers() do
		local mine = regroup[member.UserId]
		local leader = mine and Players:GetPlayerByUserId(mine.Leader)
		local theirs = leader and regroup[leader.UserId]
		if mine and os.clock() > mine.Expires then
			regroup[member.UserId] = nil
		elseif leader and leader ~= member and theirs and theirs.Leader == leader.UserId and theirs.Members[member.UserId]
			and not partyOf[member] then
			local party = partyOf[leader]
			if not party then
				nextId += 1
				party = { Id = nextId, Leader = leader, Members = { leader } }
				partyOf[leader] = party
			end
			if party.Leader == leader and #party.Members < MAX_SIZE then
				table.insert(party.Members, member)
				partyOf[member] = party
				publish(party)
			end
			regroup[member.UserId] = nil
		end
	end
end

function PartyService.Regroup(player, party)
	local members = {}
	for _, id in party.Members do
		if tonumber(id) then
			members[tonumber(id)] = true
		end
	end
	regroup[player.UserId] = { Leader = tonumber(party.Leader), Members = members, Expires = os.clock() + REGROUP_TIME }
	tryRegroup()
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
		status(player, "Nur der Squad-Anführer kann einladen.")
		return
	end
	if party and #party.Members >= MAX_SIZE then
		status(player, "Squad ist voll (" .. MAX_SIZE .. ").")
		return
	end
	if partyOf[target] then
		status(player, target.Name .. " ist schon in einem Squad.")
		return
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
		status(player, "Einladung abgelaufen.")
		return
	end
	invites[player][leader] = nil
	leave(player)
	local party = partyOf[leader]
	if not party then
		nextId += 1
		party = { Id = nextId, Leader = leader, Members = { leader } }
		partyOf[leader] = party
	end
	if #party.Members >= MAX_SIZE then
		status(player, "Squad ist voll.")
		return
	end
	table.insert(party.Members, player)
	partyOf[player] = party
	publish(party)
	-- Gleich in den Modus des Anführers mitkommen (auf diesem Server)
	if manager and leader:GetAttribute("Mode") ~= player:GetAttribute("Mode") then
		manager.Join(player, leader:GetAttribute("Mode"), true)
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

-- BEREIT umschalten (Lobby: eigener Platz im Squad)
function actions.Ready(player)
	player:SetAttribute("PartyReady", not player:GetAttribute("PartyReady") or nil)
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
	-- Anführer wechselt den Modus: Squad kommt mit (im Kampf gilt BEREIT nicht mehr). In den Markt geht jeder selbst.
	modeManager.Joined:Connect(function(player, modeId)
		if modeId ~= "Hub" and modeId ~= "Market" then
			player:SetAttribute("PartyReady", nil)
		end
		local party = partyOf[player]
		if not party or party.Leader ~= player or modeId == "Market" then
			return
		end
		for _, member in party.Members do
			-- aus der offenen Welt wird niemand mitgezogen (draußen kostet Verlassen die Tasche)
			if member ~= player and member:GetAttribute("Mode") ~= modeId and member:GetAttribute("Mode") ~= "Extinction" then
				task.spawn(manager.Join, member, modeId, true)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		invites[player] = nil
		regroup[player.UserId] = nil
	end)
end

return PartyService
