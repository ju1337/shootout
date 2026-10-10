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
	if not profile or not ExtDailyConfig.Enabled then
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
	profile.ExtDaily = { Date = ExtDailyConfig.Date(now), Day = day } -- vor dem Verteilen: kein zweites Abholen bei einem Fehler
	local names, rest = {}, {}
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
			if put < count then
				table.insert(rest, { Id = id, Count = count - put })
			end
		end
	end
	if #rest > 0 then
		-- Lager und Tasche voll: als Beutel neben den Spieler (er spawnt gerade, darum kurz auf den Charakter warten)
		task.spawn(function()
			local deadline = os.clock() + 15 -- nicht ewig warten (Spieler kann gehen, bevor er gespawnt ist)
			while player.Parent and not player.Character and os.clock() < deadline do
				task.wait(0.5)
			end
			local character = player.Character
			local root = character and character:WaitForChild("HumanoidRootPart", 10)
			if root and player.Parent and player:GetAttribute("Mode") == "Extinction" and InventoryService.DropItems then
				InventoryService.DropItems(player, rest, root.Position)
				InventoryService.Status(player, "Lager und Tasche sind voll – der Rest der Kiste liegt als Beutel neben dir.")
			end
		end)
	end
	if reward.Coins then
		ProgressService.AddCoins(player, reward.Coins, "Tägliche Kiste")
		table.insert(names, reward.Coins .. " Münzen")
	end
	publish(player, profile.ExtDaily)
	Remotes.Notify:FireClient(player, "Banner", { Caption = "Tägliche Kiste · Tag " .. day .. " von " .. #ExtDailyConfig.Days,
		Title = day == #ExtDailyConfig.Days and "GROSSER PREIS" or "DEINE KISTE IST DA", Sub = "Im Lager: " .. table.concat(names, ", ")
			.. (day < #ExtDailyConfig.Days and " · morgen wiederkommen, Tag 7 = seltene Waffe" or ""), Style = "Good" })
	return day
end

return ExtDailyService
