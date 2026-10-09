-- TradeService (ModuleScript, nur Server)
-- Tauschen zwischen zwei Spielern in einer Safe Zone der offenen Welt oder im Markt (RapConfig):
--   1. Request: Spieler A fragt B an (beide in einer Safe Zone bzw. beide im Markt, nah beieinander, keiner tauscht gerade).
--      B bekommt die Anfrage (gilt RapConfig.TradeRequestTime Sekunden). Fragen sich beide gegenseitig an,
--      geht der Tausch sofort auf.
--   2. Respond: B nimmt an oder lehnt ab.
--   3. Im Tausch legen beide handelbare Skins (AddItem/RemoveItem, je ein Stück) und RAP (SetRap) hinein. Skins im
--      Angebot sind zurückgelegt (EconomyService, Schlüssel "Trade") und lassen sich nicht gleichzeitig verkaufen.
--   4. Ready: Sind beide BEREIT, läuft ein Countdown (RapConfig.TradeConfirmTime). Jede Änderung an einem Angebot
--      nimmt beide BEREIT zurück und stoppt den Countdown – so kann niemand im letzten Moment etwas austauschen.
--   5. Nach dem Countdown wird alles auf einmal getauscht (EconomyService.Exchange) und beide Spielstände gespeichert.
-- Nur wenn beide laut PolicyGate handeln dürfen (Roblox-Regeln je Land).
-- Abbruch: Cancel, Moduswechsel oder Spiel verlassen eines der beiden. Remotes: TradeAction (Client -> Server),
-- TradeUpdate (Server -> Client: "Request" { From, Name, Seconds }, "State" {...}, "Closed" { Reason },
-- "Done" { Partner, Received, Gave }, "Status" { Text, Success }).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local DiscordLog = require(game:GetService("ServerStorage"):WaitForChild("ServerShared").DiscordLog)
local Cosmetics = require(Shared.Cosmetics)
local RapConfig = require(Shared.RapConfig)
local Modes = require(Shared.Modes)
local ProgressService = require(script.Parent.ProgressService)
local EconomyService = require(script.Parent.EconomyService)
local PolicyGate = require(script.Parent.PolicyGate)

local TradeService = {}

TradeService.Key = "Trade"
local MIN_INTERVAL = 0.1

local requests = {}   -- [Ziel] = { [Absender] = läuft ab (os.clock) }
local trades = {}     -- [Player] = Tausch { Id, A, B, Offers = { [Player] = { Items, Rap } }, Ready = {}, Ends, Version }
local lastAction = {} -- [Player] = os.clock()
local nextId = 0
local format = EconomyService.Format

local function status(player, message, success)
	if player.Parent then
		Remotes.TradeUpdate:FireClient(player, "Status", { Text = message, Success = success })
	end
end

local function partnerOf(trade, player)
	return trade.A == player and trade.B or trade.A
end

-- Beide im selben ruhigen Bereich (Safe Zone der offenen Welt bzw. Markt) und nah genug beieinander?
local function canMeet(a, b)
	local mode = a:GetAttribute("Mode")
	if not mode or not Modes.InLounge(a) or not Modes.InLounge(b) or b:GetAttribute("Mode") ~= mode then
		return false, "Tauschen geht nur in einer Safe Zone oder im Markt."
	end
	local ra = a.Character and a.Character:FindFirstChild("HumanoidRootPart")
	local rb = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
	if not ra or not rb or (ra.Position - rb.Position).Magnitude > RapConfig.TradeRange then
		return false, "Geh näher an " .. b.Name .. " heran."
	end
	-- Roblox: wer gekaufte Gegenstände nicht handeln darf (PolicyGate), tauscht gar nicht
	if not PolicyGate.TradeAllowed(a) then
		return false, "Tauschen ist in deinem Land nicht erlaubt."
	end
	if not PolicyGate.TradeAllowed(b) then
		return false, "Mit " .. b.Name .. " kann man nicht tauschen (Ländervorgabe von Roblox)."
	end
	return true
end

-- Stand des Tauschs aus Sicht von player
local function view(trade, player)
	local partner = partnerOf(trade, player)
	local function side(p)
		local offer = trade.Offers[p]
		return { Items = table.clone(offer.Items), Rap = offer.Rap, Ready = trade.Ready[p] == true }
	end
	return {
		Id = trade.Id,
		Partner = { UserId = partner.UserId, Name = partner.Name },
		Mine = side(player),
		Theirs = side(partner),
		Countdown = trade.Ends and math.max(0, trade.Ends - os.clock()) or nil,
		Version = trade.Version,
	}
end

local function publish(trade)
	for _, p in { trade.A, trade.B } do
		if p.Parent then
			Remotes.TradeUpdate:FireClient(p, "State", view(trade, p))
		end
	end
end

-- Tausch beenden (ohne Austausch): Skins wieder frei, beiden Bescheid geben
local function close(trade, reason)
	for _, p in { trade.A, trade.B } do
		if trades[p] == trade then
			trades[p] = nil
		end
		EconomyService.ClearKey(p, TradeService.Key)
		if p.Parent then
			Remotes.TradeUpdate:FireClient(p, "Closed", { Reason = reason })
		end
	end
	trade.Closed = true
end

-- Etwas am Angebot geändert: BEREIT zurück, Countdown stoppen
local function changed(trade)
	trade.Ready = {}
	trade.Ends = nil
	trade.Version += 1
	publish(trade)
end

local function execute(trade)
	local a, b = trade.A, trade.B
	local ok, reason = EconomyService.Exchange(a, b, trade.Offers[a], trade.Offers[b], TradeService.Key)
	if not ok then
		close(trade, "Tausch fehlgeschlagen: " .. tostring(reason))
		return
	end
	trades[a], trades[b] = nil, nil
	trade.Closed = true
	local function describe(offer)
		local parts = {}
		for itemId, count in offer.Items or {} do
			table.insert(parts, itemId .. (count > 1 and (" ×" .. count) or ""))
		end
		table.sort(parts)
		if (offer.Rap or 0) > 0 then
			table.insert(parts, offer.Rap .. " RAP")
		end
		return #parts > 0 and table.concat(parts, ", ") or "nichts"
	end
	DiscordLog.Log("Economy", "Tausch", DiscordLog.Who(a) .. " ⇄ " .. DiscordLog.Who(b), {
		{ a.Name .. " gibt", describe(trade.Offers[a]) }, { b.Name .. " gibt", describe(trade.Offers[b]) } })
	EconomyService.ClearKey(a, TradeService.Key)
	EconomyService.ClearKey(b, TradeService.Key)
	for _, p in { a, b } do
		local partner = partnerOf(trade, p)
		if p.Parent then
			Remotes.TradeUpdate:FireClient(p, "Done", { Partner = partner.Name, Received = trade.Offers[partner], Gave = trade.Offers[p] })
		end
	end
end

local function start(a, b)
	nextId += 1
	local trade = { Id = nextId, A = a, B = b, Offers = { [a] = { Items = {}, Rap = 0 }, [b] = { Items = {}, Rap = 0 } },
		Ready = {}, Ends = nil, Version = 0 }
	trades[a], trades[b] = trade, trade
	if requests[a] then
		requests[a][b] = nil
	end
	if requests[b] then
		requests[b][a] = nil
	end
	publish(trade)
	return trade
end

local actions = {}

function actions.Request(player, userId)
	local target = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if not target or target == player then
		return "Diesen Spieler gibt es nicht.", false
	end
	if trades[player] then
		return "Du tauschst gerade schon.", false
	end
	if trades[target] then
		return target.Name .. " tauscht gerade mit jemand anderem.", false
	end
	if not ProgressService.IsLoaded(player) or not ProgressService.IsLoaded(target) then
		return "Daten werden noch geladen.", false
	end
	local ok, reason = canMeet(player, target)
	if not ok then
		return reason, false
	end
	-- Hat target uns schon gefragt? Dann gleich los
	local mine = requests[player]
	if mine and mine[target] and mine[target] > os.clock() then
		start(target, player)
		return nil
	end
	requests[target] = requests[target] or {}
	requests[target][player] = os.clock() + RapConfig.TradeRequestTime
	Remotes.TradeUpdate:FireClient(target, "Request", { From = player.UserId, Name = player.Name,
		Seconds = RapConfig.TradeRequestTime })
	return "Tausch-Anfrage an " .. target.Name .. " geschickt.", true
end

function actions.Respond(player, userId, accept)
	local from = Players:GetPlayerByUserId(tonumber(userId) or 0)
	local pending = requests[player]
	if not from or not pending or not pending[from] or pending[from] < os.clock() then
		return "Diese Anfrage gilt nicht mehr.", false
	end
	pending[from] = nil
	if accept ~= true then
		status(from, player.Name .. " möchte gerade nicht tauschen.", false)
		return nil
	end
	if trades[player] or trades[from] then
		return "Einer von euch tauscht schon.", false
	end
	local ok, reason = canMeet(player, from)
	if not ok then
		return reason, false
	end
	start(from, player)
	return nil
end

function actions.AddItem(player, itemId)
	local trade = trades[player]
	if not trade then
		return "Du tauschst gerade nicht.", false
	end
	local item = typeof(itemId) == "string" and Cosmetics.Get(itemId)
	if not item or not RapConfig.Tradeable(itemId) then
		return "Diesen Skin kann man nicht tauschen.", false
	end
	local offer = trade.Offers[player]
	if not offer.Items[itemId] then
		local kinds = 0
		for _ in offer.Items do
			kinds += 1
		end
		if kinds >= RapConfig.TradeSlots then
			return "Höchstens " .. RapConfig.TradeSlots .. " verschiedene Skins pro Tausch.", false
		end
	end
	if not EconomyService.Reserve(player, itemId, 1, TradeService.Key) then
		return "Kein freies Stück von " .. item.Name .. ".", false
	end
	offer.Items[itemId] = (offer.Items[itemId] or 0) + 1
	changed(trade)
	return nil
end

function actions.RemoveItem(player, itemId)
	local trade = trades[player]
	local offer = trade and trade.Offers[player]
	if not offer or typeof(itemId) ~= "string" or not offer.Items[itemId] then
		return nil
	end
	offer.Items[itemId] -= 1
	if offer.Items[itemId] <= 0 then
		offer.Items[itemId] = nil
	end
	EconomyService.Unreserve(player, itemId, 1, TradeService.Key)
	changed(trade)
	return nil
end

function actions.SetRap(player, amount)
	local trade = trades[player]
	if not trade then
		return nil
	end
	amount = math.floor(tonumber(amount) or 0)
	if amount ~= amount or amount < 0 then
		amount = 0
	end
	if amount > ProgressService.GetRap(player) then
		return "So viel RAP hast du nicht (" .. format(ProgressService.GetRap(player)) .. ").", false
	end
	if trade.Offers[player].Rap ~= amount then
		trade.Offers[player].Rap = amount
		changed(trade)
	end
	return nil
end

function actions.Ready(player, ready)
	local trade = trades[player]
	if not trade then
		return nil
	end
	trade.Ready[player] = ready == true or nil
	if trade.Ready[trade.A] and trade.Ready[trade.B] then
		-- beide bereit: nach dem Countdown tauschen, wenn sich nichts mehr ändert
		trade.Ends = os.clock() + RapConfig.TradeConfirmTime
		local version = trade.Version
		publish(trade)
		task.delay(RapConfig.TradeConfirmTime, function()
			if not trade.Closed and trade.Version == version and trade.Ends and trade.Ready[trade.A] and trade.Ready[trade.B] then
				execute(trade)
			end
		end)
	else
		trade.Ends = nil
		trade.Version += 1
		publish(trade)
	end
	return nil
end

function actions.Cancel(player)
	local trade = trades[player]
	if trade then
		close(trade, player.Name .. " hat den Tausch abgebrochen.")
	end
	return nil
end

-- Für Tests: Aktion direkt ausführen
function TradeService.Do(player, action, ...)
	local handler = actions[action]
	if not handler then
		return "Unbekannte Aktion.", false
	end
	return handler(player, ...)
end

function TradeService.TradeOf(player)
	return trades[player]
end

function TradeService.Init()
	Remotes.TradeAction.OnServerEvent:Connect(function(player, action, a, b)
		local handler = typeof(action) == "string" and actions[action]
		if not handler then
			return
		end
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < MIN_INTERVAL then
			return
		end
		lastAction[player] = now
		local ok, message, success = pcall(handler, player, a, b)
		if not ok then
			warn("Tausch-Fehler: " .. tostring(message))
			message, success = "Fehler, bitte nochmal versuchen.", false
		end
		if message then
			status(player, message, success)
		end
	end)
	local function watch(player)
		player:GetAttributeChangedSignal("Mode"):Connect(function()
			local trade = trades[player]
			if trade then
				close(trade, player.Name .. " ist gegangen – Tausch abgebrochen.")
			end
			requests[player] = nil
		end)
		-- Offene Welt: wer die Safe Zone verlässt, bricht den Tausch ab
		player:GetAttributeChangedSignal("InSafeZone"):Connect(function()
			if Modes.InLounge(player) then
				return
			end
			local trade = trades[player]
			if trade then
				close(trade, player.Name .. " hat die Safe Zone verlassen – Tausch abgebrochen.")
			end
			requests[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local trade = trades[player]
		if trade then
			close(trade, player.Name .. " hat das Spiel verlassen – Tausch abgebrochen.")
		end
		requests[player] = nil
		lastAction[player] = nil
		for _, pending in requests do
			pending[player] = nil
		end
	end)
end

return TradeService
