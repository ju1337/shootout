-- CrateConfig (ModuleScript, geteilt)
-- Kisten zum Öffnen (Markt-Mitte): die Waffen-Kiste. Eine Kiste kostet Münzen und gibt genau einen Skin aus dem Pool
-- aller im Shop kaufbaren Skins ihrer Art (Cosmetics.ForSale). Erst wird die Seltenheit nach Gewicht gezogen (Weights;
-- Seltenheiten ohne Skins fallen weg, der Rest wird neu gewichtet), dann ein Skin dieser Seltenheit gleichverteilt.
-- Besitzt man einen gebundenen Skin schon, gibt es einen Teil seines Shop-Preises als Münzen zurück (DuplicateRefund);
-- handelbare Skins (mit RAP-Wert, inzwischen alle Kisten-Skins) landen als weiteres Stück im Inventar und lassen sich
-- im Markt verkaufen oder tauschen. Die Chancen fallen steil ab wie bei Sniper Duels: viel Gewöhnliches, selten
-- Legendäres.
-- Ablauf: Client schickt CrateAction("Open", Kisten-Id), der Server zieht, bucht und antwortet mit CrateResult:
-- { Ok, Message, Crate, Item, Reel (Skin-Ids für die Rolle), Index (Platz des Gewinns in Reel), Status ("new" | "copy" |
-- "duplicate"), Refund, Coins }. Die Rolle ist reine Show: der Gewinn steht beim Server schon fest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cosmetics = require(ReplicatedStorage:WaitForChild("Shared").Cosmetics)

local CrateConfig = {}

CrateConfig.Crates = {
	{ Id = "Weapon", Name = "WAFFEN-KISTE", Sub = "WAFFEN-SKINS", Type = "Weapon", Price = 450,
		Color = Color3.fromRGB(212, 170, 80), Weights = { Common = 62, Rare = 28, Epic = 8, Legendary = 2 } },
}

CrateConfig.RarityOrder = { "Common", "Rare", "Epic", "Legendary" }
CrateConfig.DuplicateRefund = 0.3 -- Anteil des Shop-Preises, der bei einem Duplikat zurückkommt
CrateConfig.ReelLength = 44       -- Skins in der Rolle
CrateConfig.WinnerIndex = 36      -- Platz des Gewinns in der Rolle (der Rest rollt vorher vorbei)
CrateConfig.Cooldown = 1.5        -- Sekunden zwischen zwei Öffnungen
CrateConfig.Modes = { "Market", "Extinction" } -- wo man Kisten öffnen darf (offene Welt: nur in einer Safe Zone)

function CrateConfig.Get(id)
	for _, crate in CrateConfig.Crates do
		if crate.Id == id then
			return crate
		end
	end
	return nil
end

-- Alle Skins, die die Kiste ausgeben kann (nach Id sortiert)
function CrateConfig.Pool(crate)
	local pool = {}
	for _, item in Cosmetics.Items do
		if item.Type == crate.Type and Cosmetics.ForSale(item) and not item.Test then
			table.insert(pool, item)
		end
	end
	table.sort(pool, function(a, b)
		return a.Id < b.Id
	end)
	return pool
end

-- Chancen je Seltenheit: { { Rarity, Chance (0..1), Count (Skins) } } in Reihenfolge Gewöhnlich bis Legendär
function CrateConfig.Odds(crate)
	local count = {}
	for _, item in CrateConfig.Pool(crate) do
		count[item.Rarity] = (count[item.Rarity] or 0) + 1
	end
	local total = 0
	for rarity, n in count do
		total += n > 0 and (crate.Weights[rarity] or 0) or 0
	end
	local odds = {}
	for _, rarity in CrateConfig.RarityOrder do
		local weight = count[rarity] and crate.Weights[rarity] or 0
		if weight > 0 and total > 0 then
			table.insert(odds, { Rarity = rarity, Chance = weight / total, Count = count[rarity] })
		end
	end
	return odds
end

-- Chance je Skin (Roblox verlangt sie für jedes Endergebnis): Chance der Seltenheit / Skins dieser Seltenheit.
-- Gibt { [Skin-Id] = Chance (0..1) } zurück, Summe 1.
function CrateConfig.ItemOdds(crate)
	local chance = {}
	for _, entry in CrateConfig.Odds(crate) do
		chance[entry.Rarity] = entry.Chance / entry.Count
	end
	local odds = {}
	for _, item in CrateConfig.Pool(crate) do
		odds[item.Id] = chance[item.Rarity] or 0
	end
	return odds
end

-- Einen Skin ziehen: Seltenheit nach Gewicht, dann gleichverteilt. random = Random (Standard: neu)
function CrateConfig.Roll(crate, random)
	random = random or Random.new()
	local odds = CrateConfig.Odds(crate)
	local pick = random:NextNumber()
	local rarity = odds[#odds].Rarity
	local sum = 0
	for _, entry in odds do
		sum += entry.Chance
		if pick < sum then
			rarity = entry.Rarity
			break
		end
	end
	local candidates = {}
	for _, item in CrateConfig.Pool(crate) do
		if item.Rarity == rarity then
			table.insert(candidates, item)
		end
	end
	return candidates[random:NextInteger(1, #candidates)]
end

return CrateConfig
