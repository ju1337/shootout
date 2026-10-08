-- ExtDailyService (ModuleScript, nur Server)
-- Tägliche Kiste (Werte in ExtDailyConfig): beim Betreten der offenen Welt einmal am Tag Items ins Lager (passt etwas nicht
-- hinein: in die Tasche), Münzen am Tag 7, Meldung mit Inhalt und Serie. Stand im Profil (ExtDaily) und im Attribut.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local ExtDailyConfig = require(Shared.ExtDailyConfig)
local ProgressService = require(script.Parent.ProgressService)
local InventoryService = require(script.Parent.InventoryService)

local ExtDailyService = {}

local random = Random.new()

local function publish(player, data)
	if player.Parent then
		player:SetAttribute("ExtDaily", HttpService:JSONEncode(data))
	end
end

-- Beim Betreten: Kiste geben, falls heute noch keine. Gibt den Tag der Serie zurück (nil = schon bekommen).
function ExtDailyService.Claim(player)
	local profile = ProgressService.Get(player)
	if not profile then
		return nil
	end
	local now = os.time()
	local day = ExtDailyConfig.NextDay(profile.ExtDaily, now)
	if not day then
		publish(player, profile.ExtDaily)
		return nil
	end
	local reward = ExtDailyConfig.Days[day]
	local items = table.clone(reward.Items)
	for _, list in { reward.Pick, reward.Pick2 } do
		if list then
			table.insert(items, { list[random:NextInteger(1, #list)], 1 })
		end
	end
	local names = {}
	for _, item in items do
		local id, count = item[1], item[2]
		local config = ExtinctionConfig.Get(id)
		if config then
			local put = InventoryService.GiveStash(player, id, count)
			if put < count then
				put += InventoryService.Give(player, id, count - put)
			end
			if put > 0 then
				table.insert(names, (put > 1 and (put .. "× ") or "") .. config.Name)
			end
		end
	end
	if reward.Coins then
		ProgressService.AddCoins(player, reward.Coins, "Tägliche Kiste")
		table.insert(names, reward.Coins .. " Münzen")
	end
	profile.ExtDaily = { Date = ExtDailyConfig.Date(now), Day = day }
	publish(player, profile.ExtDaily)
	Remotes.Notify:FireClient(player, "Banner", { Caption = "Tägliche Kiste · Tag " .. day .. " von " .. #ExtDailyConfig.Days,
		Title = day == #ExtDailyConfig.Days and "GROSSER PREIS" or "DEINE KISTE IST DA", Sub = "Im Lager: " .. table.concat(names, ", ")
			.. (day < #ExtDailyConfig.Days and " · morgen wiederkommen, Tag 7 = seltene Waffe" or ""), Style = "Good" })
	return day
end

return ExtDailyService
