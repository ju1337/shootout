-- Invites (ModuleScript, Client)
-- Freunde einladen: öffnet die Roblox-Einladung (SocialService:PromptGameInvite) – Knopf FREUNDE EINLADEN im Squad-Fenster
-- (SideMenu und offene Welt). Tritt ein Freund über die Einladung bei, belohnt der Server den Einladenden (InviteService).
-- Prompt() gibt false zurück, wenn Einladungen gerade nicht gehen (Konsole, Einstellungen, Studio); dann sagt der Aufrufer
-- es kurz an.

local Players = game:GetService("Players")

local Invites = {}

function Invites.CanInvite()
	local player = Players.LocalPlayer
	local ok, result = pcall(function()
		local SocialService = game:GetService("SocialService")
		return SocialService:CanSendGameInviteAsync(player)
	end)
	return ok and result == true
end

function Invites.Prompt()
	local player = Players.LocalPlayer
	if not player or not Invites.CanInvite() then
		return false
	end
	local ok = pcall(function()
		game:GetService("SocialService"):PromptGameInvite(player)
	end)
	return ok
end

return Invites
