-- BountyService (ModuleScript, nur Server)
-- Kopfgeld der offenen Welt (Werte in ExtinctionConfig.Bounty): Wer draußen mehrere Spieler hintereinander erledigt, wird
-- gesucht, alle bekommen eine Ansage. Sein Standort blitzt nur ab und zu kurz rot auf der Karte auf (Attribut "Bounty" an der
-- Karte; X/Z nur während RevealTime, alle RevealEvery Sekunden). Wer ihn erledigt, kassiert das Kopfgeld; jeder weitere Kill des Gesuchten erhöht es. Überlebt er lange genug draußen,
-- bekommt er selbst einen Teil davon. Stirbt er anders oder verlässt er das Spiel, verfällt es.
-- Anbindung: Modes/Extinction ruft OnKill(killer, victim) bei Spieler-Kills und OnDeath(player) bei jedem Tod.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local DayCycle = require(Shared.DayCycle)
local ProgressService = require(script.Parent.ProgressService)

local BountyService = {}

local B = ExtinctionConfig.Bounty
local options = nil -- { Map, Players(), InSafeZone(position) }
local streaks = {} -- [Player] = Kills seit dem letzten Tod
local target = nil -- { Player, Reward, Survived (Sekunden draußen) }

local function announce(title, sub, style, sound)
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Kopfgeld", Title = title, Sub = sub, Style = style or "Warning",
			Sound = sound })
	end
end

local function publish()
	local data = nil
	if target then
		local root = target.Player.Character and target.Player.Character:FindFirstChild("HumanoidRootPart")
		local visible = root ~= nil and os.clock() < (target.RevealUntil or 0)
		data = { UserId = target.Player.UserId, Name = target.Player.Name, Reward = target.Reward,
			Left = math.max(0, math.floor(B.SurviveTime - target.Survived)),
			X = visible and math.floor(root.Position.X) or nil, Z = visible and math.floor(root.Position.Z) or nil }
	end
	options.Map:SetAttribute("Bounty", data and HttpService:JSONEncode(data) or "")
end

local function clear()
	if target and target.Player.Parent then
		target.Player:SetAttribute("Bounty", nil)
	end
	target = nil
	publish()
end

local function rewardFor(streak)
	return B.Base + math.max(0, streak - B.MinKills) * B.PerKill
end

-- Spieler wird gesucht (oder sein Kopfgeld steigt)
local function mark(player)
	local streak = streaks[player] or 0
	if target and target.Player == player then
		target.Reward = rewardFor(streak)
		player:SetAttribute("Bounty", target.Reward)
		publish()
		announce("KOPFGELD STEIGT", player.Name .. " · " .. streak .. " Kills in Folge · jetzt " .. target.Reward .. " Münzen")
		return
	end
	if target and (streaks[target.Player] or 0) >= streak then
		return -- der bisherige Gesuchte hat die längere Serie
	end
	if target then
		target.Player:SetAttribute("Bounty", nil)
	end
	target = { Player = player, Reward = rewardFor(streak), Survived = 0, RevealUntil = os.clock() + B.RevealTime,
		NextReveal = os.clock() + B.RevealEvery }
	player:SetAttribute("Bounty", target.Reward)
	publish()
	announce("KOPFGELD AUF " .. string.upper(player.Name), streak .. " Kills in Folge · " .. target.Reward
		.. " Münzen für den, der ihn erledigt · sein Standort blitzt ab und zu auf der Karte (N) auf", "Warning", "RadioCall")
end

-- Spieler-Kill draußen (Extinction.OnKill)
function BountyService.OnKill(killer, victim)
	if not options or not B.Enabled or not killer or not victim or killer == victim then
		return
	end
	if target and target.Player == victim then
		local reward = target.Reward
		clear()
		ProgressService.AddCoins(killer, reward, "Kopfgeld")
		ProgressService.AddStat(killer, "Bounties", 1)
		announce("KOPFGELD KASSIERT", killer.Name .. " hat " .. victim.Name .. " erledigt · +" .. reward .. " Münzen", "Info")
	end
	streaks[killer] = (streaks[killer] or 0) + 1
	if streaks[killer] >= B.MinKills then
		mark(killer)
	end
end

-- Tod (egal wodurch): Serie weg; der Gesuchte ohne Spieler-Kill -> Kopfgeld verfällt (kurz warten, ob OnKill noch kommt)
function BountyService.OnDeath(player)
	streaks[player] = 0
	if target and target.Player == player then
		local dying = target
		task.delay(0.5, function()
			if target == dying then
				clear()
				announce("KOPFGELD VERFALLEN", player.Name .. " ist gestorben – ohne dass jemand kassiert hat", "Info")
			end
		end)
	end
end

-- Spieler weg (Spiel oder Modus verlassen)
function BountyService.RemovePlayer(player)
	streaks[player] = nil
	if target and target.Player == player then
		clear()
		announce("KOPFGELD VERFALLEN", player.Name .. " hat die offene Welt verlassen", "Info")
	end
end

-- Spieler sofort zum Gesuchten machen (Admin-Panel, Tests): Serie mindestens MinKills
function BountyService.Force(player)
	streaks[player] = math.max(streaks[player] or 0, B.MinKills)
	if target and target.Player ~= player then
		target.Player:SetAttribute("Bounty", nil)
		target = nil
	end
	mark(player)
	return target
end

function BountyService.Target()
	return target
end

-- opts = { Map, Players(), InSafeZone(position) }
function BountyService.Init(opts)
	options = opts
	publish()
	Players.PlayerRemoving:Connect(BountyService.RemovePlayer)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 then
			return
		end
		local step = elapsed
		elapsed = 0
		if not target then
			return
		end
		local root = target.Player.Character and target.Player.Character:FindFirstChild("HumanoidRootPart")
		-- Überleben zählt nur, wo man ihn auch erwischen kann: draußen, nicht im Dungeon, nicht während der Sturm-PvP-Pause
		local huntable = root ~= nil and not options.InSafeZone(root.Position) and not target.Player:GetAttribute("Dungeon")
			and not DayCycle.StormPvPPaused(workspace:GetServerTimeNow())
		if huntable then
			target.Survived += step
		end
		-- Standort kurz zeigen (nur wenn er erreichbar ist)
		local now = os.clock()
		if huntable and now >= (target.NextReveal or 0) then
			target.NextReveal = now + B.RevealEvery
			target.RevealUntil = now + B.RevealTime
			for _, other in options.Players() do
				if other ~= target.Player then
					Remotes.Notify:FireClient(other, "Banner", { Caption = "Kopfgeld", Title = "GESUCHTER GESICHTET",
						Sub = target.Player.Name .. " · " .. B.RevealTime .. " s auf der Karte (N)", Style = "Warning", Sound = "RadioCall" })
				end
			end
		end
		if target.Survived >= B.SurviveTime then
			local player, reward = target.Player, math.floor(target.Reward * B.SurviveFactor)
			streaks[player] = 0 -- neues Kopfgeld erst nach einer neuen Serie (sonst reicht ein Kill alle 10 Min)
			clear()
			ProgressService.AddCoins(player, reward, "Kopfgeld überlebt")
			announce("KOPFGELD ÜBERLEBT", player.Name .. " war " .. math.floor(B.SurviveTime / 60) .. " Min gesucht und kassiert selbst "
				.. reward .. " Münzen", "Info")
			return
		end
		publish()
	end)
end

-- Admin: Kopfgeld sofort aufheben. Gibt true zurück, wenn jemand gesucht war.
function BountyService.Stop()
	if not target then
		return false
	end
	clear()
	return true
end

return BountyService
