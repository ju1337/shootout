-- RobuxService (ModuleScript, nur Server)
-- Robux-Käufe: Entwicklerprodukte (MarketplaceService.ProcessReceipt) schreiben Münzen, Glücksrad-Drehs,
-- Doppel-XP oder Skins gut; jede Kauf-Nummer nur einmal (im Profil gemerkt, falls Roblox den Beleg wiederholt).
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

local RobuxService = {}

local RECEIPT_MEMORY = 50 -- so viele Kauf-Nummern pro Spieler merken

local function checkPasses(player)
	for _, pass in RobuxConfig.Passes do
		if pass.PassId ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.PassId)
			if ok and owns then
				player:SetAttribute("Pass_" .. pass.Id, true)
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
	if product.Spins then
		ProgressService.AddSpins(player, product.Spins)
		table.insert(lines, "+" .. product.Spins .. " Glücksrad-Drehs")
	end
	if product.BoostMinutes then
		ProgressService.AddXPBoost(player, product.BoostMinutes)
		table.insert(lines, product.BoostMinutes .. " Min. Doppel-XP")
	end
	-- Skins: neu oder (handelbar) als weiteres Stück
	for _, itemId in product.Items or {} do
		local item = Cosmetics.Get(itemId)
		local granted = item and ProgressService.GrantSkin(player, itemId)
		if item and granted then
			table.insert(lines, (granted == "copy" and "Skin-Duplikat: " or "Neuer Skin: ") .. item.Name)
		end
	end
	Remotes.Reward:FireClient(player, { Title = "DANKE FÜR DEINEN KAUF!", Lines = lines, Rarity = "Legendary" })
end

function RobuxService.Init()
	Players.PlayerAdded:Connect(checkPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPasses, player)
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
