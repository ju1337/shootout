-- Telemetry (ModuleScript, nur Server)
-- Spielanalyse über den Roblox AnalyticsService (Creator Hub › Analytics): Wo steigen neue Spieler aus, woher kommen
-- Münzen und wohin gehen sie, was wird gespielt. Alles läuft über pcall – fehlt der Dienst (Studio ohne API-Zugriff,
-- Tests), passiert nichts. In Studio wird nur gezählt, nicht gesendet (Telemetry.Enabled).
--
--   Telemetry.Economy(player, "Source"|"Sink", "Coins"|"RAP", amount, balance, transactionType, sku, reason)
--       Münzen/RAP-Fluss (LogEconomyEvent). transactionType: "Gameplay", "Shop", "IAP", "TimedReward", "Onboarding",
--       "ContextualPurchase" (Enum.AnalyticsEconomyTransactionType); reason = Grund als Text (CustomField01),
--       sku = Item-Id. ProgressService ruft das bei AddCoins/SpendCoins/AddRap/SpendRap auf.
--   Telemetry.Onboarding(player, step, name)
--       Onboarding-Trichter (LogOnboardingFunnelStepEvent): 1 Beigetreten, 2 Offene Welt betreten, 3-8 Tutorial-Schritte,
--       9 Tutorial fertig. Jeder Schritt zählt pro Spieler nur einmal (höchster Schritt im Profil: OnboardingStep).
--   Telemetry.Event(player, name, value, field1, field2, field3)
--       Eigenes Ereignis (LogCustomEvent), z.B. "ModeJoin" mit Modus, "PlayerKill", "Death" mit Ursache.
--   Telemetry.Count(player, name, n)
--       Gesammelt: wird je Spieler alle FlushEvery Sekunden und beim Verlassen als ein Ereignis mit Summe gesendet
--       (Zombie-Kills, damit nicht jeder Kill ein Aufruf ist – der Dienst hat Mengengrenzen).
--   Telemetry.Progression(player, path, status, level, name)
--       Fortschritt (LogProgressionEvent): status "Begin"|"Complete"|"Fail"|"Abandon", z.B. Spielerlevel.
--
-- Datenschutz: nur Spiel-Ereignisse, keine Chat- oder Freitexte.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Telemetry = {}

Telemetry.Enabled = not RunService:IsStudio() -- in Studio nicht senden
Telemetry.FlushEvery = 60                      -- Sekunden zwischen zwei Sammel-Ereignissen je Spieler
Telemetry.Sent = {}                            -- für Tests: letzte Aufrufe { Kind, Player, ... }
Telemetry.KeepSent = false                     -- Aufrufe in Sent merken (Tests)

local service = nil
local counts = {}        -- [player] = { [name] = n }
local onboarding = {}    -- [player] = höchster gesendeter Schritt dieser Sitzung
local profileStep = nil  -- function(player) -> (get, set) für den Profil-Stand (ProgressService)

local FIELD = { "CustomField01", "CustomField02", "CustomField03" }

local function analytics()
	if service == nil then
		local ok, s = pcall(game.GetService, game, "AnalyticsService")
		service = ok and s or false
	end
	return service or nil
end

local function fieldKey(index)
	local ok, key = pcall(function()
		local item = (Enum.AnalyticsCustomFieldKeys :: any)[FIELD[index]]
		return item and item.Name
	end)
	return ok and type(key) == "string" and key or FIELD[index]
end

local function fields(a, b, c)
	local result = nil
	for index, value in { a, b, c } do
		if value ~= nil then
			result = result or {}
			result[fieldKey(index)] = string.sub(tostring(value), 1, 64)
		end
	end
	return result
end

local function record(kind, player, ...)
	if Telemetry.KeepSent then
		table.insert(Telemetry.Sent, { Kind = kind, Player = player, ... })
	end
end

local function call(method, player, ...)
	if not Telemetry.Enabled then
		return false
	end
	local s = analytics()
	if not s then
		return false
	end
	local okMethod, fn = pcall(function()
		return s[method]
	end)
	if not okMethod or type(fn) ~= "function" then
		service = false -- Dienst ohne diese Methode (Tests, alte Clients): still bleiben
		return false
	end
	local args = table.pack(...)
	local ok, err = pcall(function()
		s[method](s, player, table.unpack(args, 1, args.n))
	end)
	if not ok then
		warn("Telemetry: " .. method .. " fehlgeschlagen: " .. tostring(err))
	end
	return ok
end

local function enumItem(group, name, fallback)
	local ok, item = pcall(function()
		return Enum[group][name]
	end)
	if ok and item then
		return item
	end
	local ok2, item2 = pcall(function()
		return Enum[group][fallback]
	end)
	return ok2 and item2 or nil
end

-- ---------- Ereignisse ----------

function Telemetry.Economy(player, flow, currency, amount, balance, transactionType, sku, reason)
	if not player or type(amount) ~= "number" or amount <= 0 then
		return
	end
	record("Economy", player, flow, currency, amount, balance, transactionType, sku, reason)
	local flowItem = enumItem("AnalyticsEconomyFlowType", flow, "Source")
	local kind = enumItem("AnalyticsEconomyTransactionType", transactionType or "Gameplay", "Gameplay")
	if not flowItem or not kind then
		return
	end
	call("LogEconomyEvent", player, flowItem, currency, math.floor(amount), math.floor(balance or 0), kind.Name,
		sku and string.sub(tostring(sku), 1, 64) or nil, fields(reason))
end

-- Profil-Zugriff für den Onboarding-Stand: getter(player) -> Schritt, setter(player, Schritt)
function Telemetry.BindProfile(getter, setter)
	profileStep = { Get = getter, Set = setter }
end

function Telemetry.Onboarding(player, step, name)
	if not player or type(step) ~= "number" then
		return
	end
	local done = onboarding[player] or 0
	if profileStep then
		local ok, saved = pcall(profileStep.Get, player)
		if ok and type(saved) == "number" then
			done = math.max(done, saved)
		end
	end
	if step <= done then
		return
	end
	onboarding[player] = step
	if profileStep then
		pcall(profileStep.Set, player, step)
	end
	record("Onboarding", player, step, name)
	call("LogOnboardingFunnelStepEvent", player, step, name)
end

function Telemetry.Event(player, name, value, a, b, c)
	if not player or type(name) ~= "string" then
		return
	end
	record("Event", player, name, value, a, b, c)
	call("LogCustomEvent", player, name, type(value) == "number" and value or 1, fields(a, b, c))
end

function Telemetry.Count(player, name, n)
	if not player or type(name) ~= "string" then
		return
	end
	counts[player] = counts[player] or {}
	counts[player][name] = (counts[player][name] or 0) + (tonumber(n) or 1)
end

-- Gesammelte Zähler eines Spielers senden
function Telemetry.Flush(player)
	local list = counts[player]
	if not list then
		return
	end
	counts[player] = nil
	for name, n in list do
		if n > 0 then
			Telemetry.Event(player, name, n)
		end
	end
end

function Telemetry.Progression(player, path, status, level, name)
	if not player or type(path) ~= "string" then
		return
	end
	record("Progression", player, path, status, level, name)
	local statusItem = enumItem("AnalyticsProgressionStatus", status or "Complete", "Complete")
	if not statusItem then
		return
	end
	call("LogProgressionEvent", player, path, statusItem, math.floor(tonumber(level) or 0), name)
end

-- ---------- Start ----------

function Telemetry.Init()
	Players.PlayerRemoving:Connect(function(player)
		Telemetry.Flush(player)
		onboarding[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Telemetry.FlushEvery)
			for player in counts do
				if player.Parent then
					Telemetry.Flush(player)
				else
					counts[player] = nil
				end
			end
		end
	end)
end

-- Für Tests
function Telemetry._Reset()
	counts, onboarding, service = {}, {}, nil
	Telemetry.Sent = {}
end

return Telemetry
