-- KitService (ModuleScript, nur Server)
-- Kits beim Kit-Händler am Spawn im Camp (Werte in KitConfig): Aktion "ClaimKit" (Kit-Id) über Remotes.ExtAction, nur
-- in der Nähe des Punkts KitConfig.Point. Items kommen in die Tasche, was nicht passt ins Lager. Zuletzt abgeholt steht
-- im Profil (Kits = { [Id] = os.time() }) und im Spieler-Attribut "Kits" (JSON) für den Client.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sfx = require(Shared.Sfx)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local KitConfig = require(Shared.KitConfig)
local RobuxConfig = require(Shared.RobuxConfig)
local ProgressService = require(script.Parent.ProgressService)
local InventoryService = require(script.Parent.InventoryService)

local KitService = {}

local status = InventoryService.Status

function KitService.Publish(player)
	local profile = ProgressService.Get(player)
	if profile and player.Parent then
		player:SetAttribute("Kits", HttpService:JSONEncode(type(profile.Kits) == "table" and profile.Kits or {}))
		player:SetAttribute("KitCredit", HttpService:JSONEncode(type(profile.KitCredit) == "table" and profile.KitCredit or {}))
	end
end

function KitService.Claim(player, kitId)
	local kit = type(kitId) == "string" and KitConfig.Get(kitId)
	local profile = ProgressService.Get(player)
	if not kit or not profile then
		return
	end
	if #kit.Items == 0 then
		status(player, kit.Name .. " ist bald verfügbar.")
		return
	end
	if not InventoryService.NearPoint(player, KitConfig.Point) then
		status(player, "Geh näher an den Kit-Händler.")
		return
	end
	if kit.Pass and not RobuxConfig.Has(player, kit.Pass) then
		status(player, "Für das " .. kit.Name .. " brauchst du den Gamepass " .. kit.Pass .. ".")
		return
	end
	if type(profile.Kits) ~= "table" then
		profile.Kits = {}
	end
	local now = os.time()
	local remaining = KitConfig.Remaining(kit, profile.Kits, now)
	if remaining > 0 then
		status(player, kit.Name .. " ist wieder bereit in " .. KitConfig.FormatTime(remaining) .. ".")
		return
	end
	profile.Kits[kit.Id] = now
	-- Kit-Items bringen beim Verkaufen keine Münzen (KitConfig.SellSplit)
	if type(profile.KitCredit) ~= "table" then
		profile.KitCredit = {}
	end
	for _, entry in kit.Items do
		local id, count = entry[1], entry[2]
		profile.KitCredit[id] = math.min((tonumber(profile.KitCredit[id]) or 0) + count, count * KitConfig.CreditCap)
	end
	KitService.Publish(player)
	local stashed = false
	for _, entry in kit.Items do
		local id, count = entry[1], entry[2]
		if ExtinctionConfig.Get(id) then
			local put = InventoryService.Give(player, id, count)
			if put < count and InventoryService.GiveStash(player, id, count - put) > 0 then
				stashed = true
			end
		end
	end
	Sfx.ToPlayers({ player }, "AmmoBox")
	status(player, kit.Name .. (stashed and " abgeholt – die Tasche war voll, der Rest liegt im Lager." or " abgeholt!"), true)
end

function KitService.Init()
	InventoryService.Handlers.ClaimKit = KitService.Claim
end

return KitService
