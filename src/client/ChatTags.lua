-- ChatTags (ModuleScript, nur Client)
-- Team-Rang (StaffConfig, Attribut "StaffRank") als farbiges Präfix vor dem Namen im Chat, z.B. "👑 OWNER Name: …".
-- Staff-Chat: Nachrichten im Kanal "Staff" bekommen ein rotes [STAFF] davor; "/s Text" schreibt dort hinein.

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
		local prefix = message.PrefixText
		if rank then
			prefix = StaffConfig.Prefix(rank) .. " " .. prefix
		end
		if message.TextChannel and message.TextChannel.Name == StaffConfig.ChatChannel then
			prefix = '<font color="#FF5A6E"><b>[STAFF]</b></font> ' .. prefix
		end
		properties.PrefixText = prefix
		return properties
	end

	-- /s Text -> Staff-Chat (nur wer im Kanal ist; der Server entscheidet die Mitgliedschaft)
	local command = Instance.new("TextChatCommand")
	command.Name = "StaffChatCommand"
	command.PrimaryAlias = "/s"
	command.SecondaryAlias = "/staff"
	command.Triggered:Connect(function(_, text)
		local channels = TextChatService:FindFirstChild("TextChannels")
		local channel = channels and channels:FindFirstChild(StaffConfig.ChatChannel)
		local body = text:gsub("^%s*/%a+%s*", "")
		if not channel or body == "" then
			return
		end
		for _, source in channel:GetChildren() do
			if source:IsA("TextSource") and source.UserId == Players.LocalPlayer.UserId then
				channel:SendAsync(body)
				return
			end
		end
	end)
	command.Parent = TextChatService
end

return ChatTags
