-- InviteService (ModuleScript, nur Server)
-- Freunde einladen: Der Client öffnet die Roblox-Einladung (SocialService:PromptGameInvite, Knopf FREUNDE EINLADEN im
-- Squad-Fenster). Tritt der Eingeladene über die Einladung bei, steht in seinen Join-Daten ReferredByPlayerId. Ist der
-- Einladende auf diesem Server, bekommt er Münzen (InviteService.Reward) und eine Meldung; beim ersten Mal das Badge
-- "Recruiter". Jeder Eingeladene zählt nur einmal (Profil Invited = { [UserId] = true } des Einladenden); Telemetry:
-- "InviteJoin". Statistik "Invites" im Profil des Einladenden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ProgressService = require(script.Parent.ProgressService)
local Badges = require(script.Parent.Badges)
local Telemetry = require(script.Parent.Telemetry)

local InviteService = {}

InviteService.Reward = 300 -- Münzen für den Einladenden je neuem Freund

local function referrerOf(player)
	local ok, data = pcall(player.GetJoinData, player)
	local id = ok and type(data) == "table" and tonumber(data.ReferredByPlayerId) or nil
	return id and id > 0 and id or nil
end

-- Eingeladener ist da: Einladenden belohnen (wenn hier und Profil geladen)
function InviteService.OnJoin(player)
	local referrerId = referrerOf(player)
	if not referrerId or referrerId == player.UserId then
		return false
	end
	Telemetry.Event(player, "InviteJoin", 1, tostring(referrerId))
	local inviter = Players:GetPlayerByUserId(referrerId)
	-- lädt das Profil des Einladenden noch (Sperre, Wiederholungen), landete die Belohnung im leeren Ersatzprofil
	for _ = 1, 60 do
		if not inviter or not inviter.Parent or ProgressService.IsLoaded(inviter) then
			break
		end
		task.wait(0.5)
	end
	local profile = inviter and inviter.Parent and ProgressService.IsLoaded(inviter) and ProgressService.Get(inviter)
	if not inviter or not profile then
		return false
	end
	profile.Invited = type(profile.Invited) == "table" and profile.Invited or {}
	local key = tostring(player.UserId)
	if profile.Invited[key] then
		return false
	end
	profile.Invited[key] = true
	ProgressService.AddCoins(inviter, InviteService.Reward, "Einladung")
	ProgressService.AddStat(inviter, "Invites", 1)
	Badges.Trigger(inviter, "Recruiter")
	Remotes.Notify:FireClient(inviter, "Banner", { Caption = "Einladung", Title = string.upper(player.Name) .. " IST DA",
		Sub = "Dein Freund ist über deine Einladung beigetreten · +" .. InviteService.Reward .. " Münzen", Style = "Good" })
	return true
end

function InviteService.Init()
	Players.PlayerAdded:Connect(function(player)
		-- kurz warten, bis das Profil des Einladenden sicher geladen ist (er ist meist schon länger da)
		task.delay(1, InviteService.OnJoin, player)
	end)
end

return InviteService
