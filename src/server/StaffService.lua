-- StaffService (ModuleScript, nur Server)
-- Setzt beim Beitreten den Team-Rang (StaffConfig) als Spieler-Attribut "StaffRank", dazu "IsAdmin" (ganzes
-- Admin-Panel) und "IsMod" (nur Moderation im Admin-Panel). Im Spiel vergebene Ränge liegen im DataStore
-- "StaffRanks_v1" (Schlüssel = UserId); StaffService.Assign ändert sie (Rechte prüft AdminService).
-- Staff-Chat: eigener TextChannel "Staff" (Reiter im Chatfenster), Mitglieder = Ränge ab StaffConfig.ChatPower.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StaffConfig = require(ReplicatedStorage:WaitForChild("Shared").StaffConfig)

local StaffService = {}

StaffService.StoreName = "StaffRanks_v1"
-- Zusätzliche volle Admins ohne sichtbaren Rang (alte Liste aus AdminService)
StaffService.AdminIds = {}

local store
local function getStore()
	if not store then
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, StaffService.StoreName)
		store = ok and result or nil
	end
	return store
end

local stored = {} -- [UserId] = im Spiel vergebener Rang (oder false)

local function better(a, b)
	local ra, rb = StaffConfig.Get(a), StaffConfig.Get(b)
	if not ra then
		return b
	end
	if not rb then
		return a
	end
	return ra.Power >= rb.Power and a or b
end

-- Rang aus Gruppe bzw. Besitzer
local function ownerRank(player)
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId and "Owner" or nil
	end
	local ok, groupRank = pcall(player.GetRankInGroup, player, game.CreatorId)
	if ok and groupRank >= 255 then
		return "Owner"
	elseif ok and groupRank >= 254 then
		return "Developer"
	end
	return nil
end

-- Kanal des Staff-Chats (einmal anlegen)
local channel
local function staffChannel()
	if not channel then
		local folder = TextChatService:FindFirstChild("TextChannels") or TextChatService:WaitForChild("TextChannels", 10)
		if not folder then
			return nil
		end
		channel = folder:FindFirstChild(StaffConfig.ChatChannel) or Instance.new("TextChannel")
		channel.Name = StaffConfig.ChatChannel
		channel.Parent = folder
	end
	return channel
end

-- Spieler in den Staff-Chat aufnehmen bzw. entfernen
local function setChatMember(player, member)
	local c = staffChannel()
	if not c then
		return
	end
	local source
	for _, child in c:GetChildren() do
		if child:IsA("TextSource") and child.UserId == player.UserId then
			source = child
		end
	end
	if member and not source then
		pcall(c.AddUserAsync, c, player.UserId)
	elseif not member and source then
		source:Destroy()
	end
end

local function apply(player)
	if not player.Parent then
		return
	end
	local rankId = ownerRank(player)
	rankId = better(rankId, StaffConfig.Members[player.UserId])
	rankId = better(rankId, stored[player.UserId] or nil)
	if player:GetAttribute("Pass_VIP") == true then
		rankId = better(rankId, "VIP")
	end
	-- In Studio ist jeder Developer (zum Testen von Panel und Präfix)
	if RunService:IsStudio() then
		rankId = better(rankId, "Developer")
	end
	local rank = StaffConfig.Get(rankId)
	player:SetAttribute("StaffRank", rank and rank.Id or nil)
	local admin = (rank and rank.Admin) or table.find(StaffService.AdminIds, player.UserId) ~= nil
	player:SetAttribute("IsAdmin", admin == true)
	player:SetAttribute("IsMod", (not admin and rank and rank.Kick) == true)
	task.spawn(setChatMember, player, rank ~= nil and rank.Power >= StaffConfig.ChatPower)
end

local function load(player)
	local s = getStore()
	if s and stored[player.UserId] == nil then
		local ok, value = pcall(s.GetAsync, s, tostring(player.UserId))
		stored[player.UserId] = ok and StaffConfig.Get(value) and value or false
	end
	apply(player)
end

-- Rang vergeben (rankId nil = entfernen). Gibt einen Text für das Panel zurück.
function StaffService.Assign(userId, rankId)
	local id = tonumber(userId)
	if not id or id <= 0 then
		return "Keine gültige UserId."
	end
	if rankId ~= nil and not StaffConfig.Get(rankId) then
		return "Unbekannter Rang."
	end
	local s = getStore()
	if not s then
		return "Rang konnte nicht gespeichert werden (DataStore)."
	end
	local ok = pcall(function()
		if rankId then
			s:SetAsync(tostring(id), rankId)
		else
			s:RemoveAsync(tostring(id))
		end
	end)
	if not ok then
		return "Rang konnte nicht gespeichert werden (DataStore)."
	end
	stored[id] = rankId or false
	local online = Players:GetPlayerByUserId(id)
	if online then
		apply(online)
	end
	local rank = StaffConfig.Get(rankId)
	return (online and online.Name or tostring(id)) .. ": " .. (rank and rank.Name or "kein Rang")
end

-- Rang einer UserId (online: der aktuelle, offline: fest im Code oder im Spiel vergeben) oder nil
function StaffService.StoredRank(userId)
	local id = tonumber(userId) or 0
	local online = Players:GetPlayerByUserId(id)
	if online then
		return StaffConfig.Of(online)
	end
	local rankId = StaffConfig.Members[id]
	local s = getStore()
	if stored[id] == nil and s then
		local ok, value = pcall(s.GetAsync, s, tostring(id))
		stored[id] = ok and StaffConfig.Get(value) and value or false
	end
	rankId = better(rankId, stored[id] or nil)
	return StaffConfig.Get(rankId)
end

-- Stärke des Rangs einer UserId (für die Rechteprüfung), auch offline
function StaffService.StoredPower(userId)
	local rank = StaffService.StoredRank(userId)
	return rank and rank.Power or 0
end

function StaffService.Init()
	-- Reiter im Chatfenster, damit der Staff-Chat einen eigenen Tab hat
	task.spawn(pcall, function()
		TextChatService:WaitForChild("ChannelTabsConfiguration", 10).Enabled = true
	end)
	task.spawn(staffChannel)
	local function added(player)
		load(player)
		player:GetAttributeChangedSignal("Pass_VIP"):Connect(function()
			apply(player)
		end)
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		task.spawn(added, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		stored[player.UserId] = nil
	end)
end

return StaffService
