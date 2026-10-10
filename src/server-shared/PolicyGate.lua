-- PolicyGate (ModuleScript, nur Server)
-- Fragt PolicyService je Spieler, ob er bezahlte Zufallsitems nutzen (Kisten, gekaufte Glücksrad-Drehs) und gekaufte
-- Gegenstände handeln (Tausch, Markt) darf, merkt sich die Antwort und setzt die Spieler-Attribute PaidRandomOk und
-- PaidTradeOk für die Anzeige (PaidRandom). Klappt die Abfrage nicht, gilt beides als verboten (so verlangt es Roblox)
-- und beim nächsten Aufruf wird erneut gefragt.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local PolicyGate = {}

PolicyGate.Tries = 3
PolicyGate.RetryAfter = 60 -- s bis zur nächsten Abfrage nach einem Fehlschlag

local cache = {} -- [Player] = { Random = bool, Trade = bool }

local function fetch(player)
	for attempt = 1, PolicyGate.Tries do
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if ok and type(info) == "table" then
			return { Random = info.ArePaidRandomItemsRestricted ~= true, Trade = info.IsPaidItemTradingAllowed == true }
		end
		if attempt < PolicyGate.Tries then
			task.wait(attempt)
		end
	end
	return nil
end

-- { Random, Trade } für den Spieler (wartet beim ersten Mal auf PolicyService)
function PolicyGate.Get(player)
	local entry = cache[player]
	if entry and not (entry.RetryAt and os.clock() >= entry.RetryAt) then
		return entry
	end
	entry = fetch(player)
	if not entry then
		-- Abfrage fehlgeschlagen: verboten, auch in der Anzeige (nil hieße dort „erlaubt“), und eine Weile merken,
		-- damit nicht jeder Aufruf erneut ~3 s wartet
		entry = { Random = false, Trade = false, RetryAt = os.clock() + PolicyGate.RetryAfter }
		if player.Parent then
			cache[player] = entry
			player:SetAttribute("PaidRandomOk", false)
			player:SetAttribute("PaidTradeOk", false)
			-- selbst neu fragen: der Client fragt bei „gesperrt“ nicht mehr nach (Kisten/Drehs ausgeblendet)
			task.delay(PolicyGate.RetryAfter, function()
				if player.Parent and cache[player] == entry then
					PolicyGate.Get(player)
				end
			end)
		end
		return entry
	end
	if player.Parent then
		cache[player] = entry
		player:SetAttribute("PaidRandomOk", entry.Random)
		player:SetAttribute("PaidTradeOk", entry.Trade)
	end
	return entry
end

-- Darf Kisten öffnen und Glücksrad-Drehs kaufen?
function PolicyGate.RandomAllowed(player)
	return PolicyGate.Get(player).Random
end

-- Darf Skins tauschen und im Markt mit anderen Spielern handeln?
function PolicyGate.TradeAllowed(player)
	return PolicyGate.Get(player).Trade
end

function PolicyGate.Init()
	Players.PlayerAdded:Connect(function(player)
		PolicyGate.Get(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(PolicyGate.Get, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return PolicyGate
