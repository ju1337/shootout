-- ChatTags (ModuleScript, nur Client)
-- Team-Rang (StaffConfig, Attribut "StaffRank") als farbiges Präfix vor dem Namen im Chat, z.B. "👑 OWNER Name: …".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local StaffConfig = require(ReplicatedStorage:WaitForChild("Shared").StaffConfig)

local ChatTags = {}

function ChatTags.Init()
	TextChatService.OnIncomingMessage = function(message)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		local rank = StaffConfig.Of(sender)
		if rank then
			properties.PrefixText = StaffConfig.Prefix(rank) .. " " .. message.PrefixText
		end
		return properties
	end
end

return ChatTags
