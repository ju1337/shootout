-- RobuxService (ModuleScript, nur Server)
-- Robux-Käufe: Entwicklerprodukte (MarketplaceService.ProcessReceipt) schreiben Münzen, Glücksrad-Drehs,
-- Doppel-XP, Skins oder Versteckstufen gut; jede Kauf-Nummer nur einmal (im Profil gemerkt, falls Roblox den Beleg wiederholt).
-- Gamepässe (VIP, Doppel-XP) werden beim Beitreten und nach dem Kauf geprüft → Spieler-Attribut "Pass_<Id>".
-- Wirkung: ProgressService fragt RobuxConfig.Has (VIP: doppelte Münzen, DoubleXP: doppelte XP).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local DiscordLog = require(game:GetService("ServerStorage"):WaitForChild("ServerShared").DiscordLog)
local RobuxConfig = require(Shared.RobuxConfig)
local Cosmetics = require(Shared.Cosmetics)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)
local PolicyGate = require(ServerStorage:WaitForChild("ServerShared").PolicyGate)
local HideoutService = require(ServerStorage:WaitForChild("ServerShared").HideoutService)
local HideoutConfig = require(Shared.HideoutConfig)

local RobuxService = {}

local RECEIPT_MEMORY = 50 -- so viele Kauf-Nummern pro Spieler merken
RobuxService.PassTries = 4 -- Versuche für die Gamepass-Abfrage

local function checkPasses(player)
	for _, pass in RobuxConfig.Passes do
		if pass.PassId ~= 0 then
			-- bei Fehlern (Drosselung, wenn viele gleichzeitig beitreten) nochmal: sonst fehlt der Pass die ganze Sitzung
			for attempt = 1, RobuxService.PassTries do
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.PassId)
				if ok then
					if owns then
						player:SetAttribute("Pass_" .. pass.Id, true)
					end
					break
				end
				if attempt < RobuxService.PassTries and player.Parent then
					task.wait(3 * attempt)
				elseif not player.Parent then
					return
				end
			end
		end
	end
end

-- Produkt gutschreiben, Popup an den Spieler
local function grant(player, profile, product)
	local lines = {}
	if product.Coins then
		ProgressService.AddCoins(player, product.Coins, "Robux")
		table.insert(lines, "+" .. product.Coins .. " Münzen")
	end
	if product.Spins and RobuxService.SpinsRestricted(player) then
		-- Land verbietet bezahlte Zufallsitems: Münzen statt Drehs (die Drehs wären sonst nie nutzbar)
		local coins = product.Spins * RobuxConfig.SpinCoins
		ProgressService.AddCoins(player, coins, "Robux")
		table.insert(lines, "+" .. coins .. " Münzen (statt " .. product.Spins .. " Glücksrad-Drehs)")
	elseif product.Spins then
		ProgressService.AddSpins(player, product.Spins, true)
		table.insert(lines, "+" .. product.Spins .. " Glücksrad-Drehs")
	end
	if product.BoostMinutes then
		ProgressService.AddXPBoost(player, product.BoostMinutes)
		table.insert(lines, product.BoostMinutes .. " Min. Doppel-XP")
	end
	-- Versteckstufe: sofort, ohne Level-Grenze (eine schon vorhandene Stufe wird nicht verkauft, siehe Versteck-Fenster)
	if product.HideoutTier and HideoutService.GrantTier(player, product.HideoutTier) then
		local tier = HideoutConfig.Tiers[product.HideoutTier]
		table.insert(lines, "Versteck: Stufe " .. product.HideoutTier .. " (" .. (tier and tier.Name or "") .. ")")
	end
	-- Skins: neu oder (handelbar) als weiteres Stück
	for _, itemId in product.Items or {} do
		local item = Cosmetics.Get(itemId)
		local granted = item and ProgressService.GrantSkin(player, itemId)
		if item and granted then
			table.insert(lines, (granted == "copy" and "Skin-Duplikat: " or "Neuer Skin: ") .. item.Name)
		end
	end
	-- nur das Popup: ein Fehler hier (Spieler geht gerade) darf den Kauf nicht scheitern lassen (sonst doppelt beim Wiederholen)
	pcall(Remotes.Reward.FireClient, Remotes.Reward, player, { Title = "DANKE FÜR DEINEN KAUF!", Lines = lines,
		Rarity = "Legendary" })
end

-- Sicher gesperrt (PolicyService hat geantwortet, nicht nur die Abfrage fehlgeschlagen)?
function RobuxService.SpinsRestricted(player)
	local entry = PolicyGate.Get(player)
	return entry.Random == false and entry.RetryAt == nil
end

-- Schon gekaufte Drehs in einem gesperrten Land in Münzen umwandeln (beim Beitreten, sobald das Profil geladen ist)
function RobuxService.ConvertPaidSpins(player)
	local profile = ProgressService.IsLoaded(player) and ProgressService.Get(player)
	local spins = profile and profile.Wheel and math.floor(tonumber(profile.Wheel.PaidSpins) or 0) or 0
	if spins <= 0 or not RobuxService.SpinsRestricted(player) then
		return 0
	end
	profile.Wheel.PaidSpins = 0
	local coins = spins * RobuxConfig.SpinCoins
	ProgressService.AddCoins(player, coins, "Robux")
	ProgressService.Sync(player)
	task.spawn(ProgressService.SaveNow, player)
	DiscordLog.Log("Economy", "Drehs umgewandelt", spins .. " gekaufte Drehs → " .. coins .. " Münzen (Länder-Sperre)",
		{ { "Spieler", DiscordLog.Who(player) } })
	pcall(Remotes.Reward.FireClient, Remotes.Reward, player, { Title = "DREHS IN MÜNZEN UMGEWANDELT",
		Lines = { "+" .. coins .. " Münzen für " .. spins .. " gekaufte Glücksrad-Drehs",
			"In deinem Land sind bezahlte Zufallsitems nicht erlaubt" }, Rarity = "Legendary" })
	return coins
end

local function onJoin(player)
	checkPasses(player)
	while player.Parent and not ProgressService.IsLoaded(player) do
		task.wait(1)
	end
	if player.Parent then
		RobuxService.ConvertPaidSpins(player)
	end
end

function RobuxService.Init()
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			for _, pass in RobuxConfig.Passes do
				if pass.PassId == passId then
					player:SetAttribute("Pass_" .. pass.Id, true)
					Remotes.Reward:FireClient(player, { Title = "GAMEPASS: " .. pass.Name, Lines = { pass.Description },
						Rarity = "Legendary" })
				end
			end
		end
	end)
	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local product = RobuxConfig.ByProductId(receipt.ProductId)
		local profile = player and ProgressService.Get(player)
		if not player or not product or not profile or not ProgressService.IsLoaded(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- später nochmal (z.B. Profil lädt noch)
		end
		profile.Receipts = profile.Receipts or {}
		if not table.find(profile.Receipts, receipt.PurchaseId) then
			local ok, err = pcall(grant, player, profile, product)
			if not ok then
				warn("Robux-Kauf fehlgeschlagen: " .. tostring(err))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			DiscordLog.Log("Economy", "Robux-Kauf", tostring(product.Name or product.Id), {
				{ "Spieler", DiscordLog.Who(player) }, { "Robux", tostring(receipt.CurrencySpent) },
				{ "Produkt-Id", tostring(receipt.ProductId) } })
			table.insert(profile.Receipts, receipt.PurchaseId)
			while #profile.Receipts > RECEIPT_MEMORY do
				table.remove(profile.Receipts, 1)
			end
		end
		-- Erst bestätigen, wenn der Stand mit dem Kauf sicher gespeichert ist. Sonst fragt Roblox später erneut:
		-- im selben Server ist der Kauf dann schon gutgeschrieben (nur speichern), nach einem Absturz oder
		-- Serverwechsel fehlt er im geladenen Stand und wird dort gutgeschrieben.
		if not ProgressService.SaveNow(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return RobuxService
