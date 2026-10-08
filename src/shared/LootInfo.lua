-- LootInfo (ModuleScript, Client)
-- Was man aus Lootdrop, Konvoi, Heli-Absturz und Horden-Kiste bekommen kann (Reiter LOOT im Extinction-Menü).
-- Die Chancen kommen aus denselben Werten, mit denen die Server würfeln (ExtinctionConfig.RollLoot): jede Quelle wird
-- Trials-mal nachgewürfelt; Chance = Anteil der Kisten, in denen das Item mindestens einmal liegt. Aufsätze werden je
-- Seltenheit zu einer Zeile zusammengefasst.

local ExtinctionConfig = require(script.Parent.ExtinctionConfig)

local LootInfo = {}

local TRIALS = 4000

local A, C, H, Ho = ExtinctionConfig.Airdrop, ExtinctionConfig.Convoy, ExtinctionConfig.HeliCrash, ExtinctionConfig.Horde

local function range(r)
	return r[1] == r[2] and tostring(r[1]) or (r[1] .. "–" .. r[2])
end

-- Rolls: { Table, Items = { min, max }, Chance = Wahrscheinlichkeit, dass gewürfelt wird (nil = immer) }
LootInfo.Sources = {
	{ Id = "Airdrop", Name = "LOOT DROP", Color = Color3.fromRGB(226, 182, 72),
		Info = "Every 7–11 min, often in the red zone  ·  hold E to open  ·  " .. range(A.Items) .. " items (+1 in the red zone)",
		Rolls = { { Table = "Airdrop", Items = A.Items } } },
	{ Id = "Convoy", Name = "CONVOY", Color = Color3.fromRGB(110, 176, 230),
		Info = "Shoot the convoy, kill the guards  ·  " .. range(C.Items) .. " items + " .. range(C.Attachments)
			.. " attachments guaranteed",
		Rolls = { { Table = C.Table, Items = C.Items }, { Table = "ConvoyAttachments", Items = C.Attachments } } },
	{ Id = "HeliCrash", Name = "HELI CRASH", Color = Color3.fromRGB(230, 120, 70),
		Info = H.Crates .. " military crates at the wreck once the fire is out  ·  chances per crate",
		Rolls = { { Table = H.Table, Items = H.Items }, { Table = H.BonusTable, Items = H.BonusItems },
			{ Table = "ConvoyAttachments", Items = { 1, 1 }, Chance = H.AttachmentChance } } },
	{ Id = "Horde", Name = "HORDE CRATE", Color = Color3.fromRGB(200, 90, 90),
		Info = "Survive 3 zombie waves next to the crate  ·  " .. (Ho.Items[1] + Ho.BonusItems[1]) .. "–"
			.. (Ho.Items[2] + Ho.BonusItems[2]) .. " items",
		Rolls = { { Table = Ho.Table, Items = Ho.Items }, { Table = Ho.BonusTable, Items = Ho.BonusItems } } },
}

-- Zeilen-Schlüssel: Aufsätze je Seltenheit zusammen ("Att_T3"), sonst die Item-Id
local function rowKey(id)
	local config = ExtinctionConfig.Items[id]
	if config and config.Kind == "Attachment" then
		return "Att_T" .. (config.Tier or 2), config.Tier or 2
	end
	return id, config and config.Tier or 1
end

-- Mengen je Zeile aus den Tabellen der Quelle: { min, max }
local function countRanges(source)
	local ranges = {}
	for _, roll in source.Rolls do
		for _, entry in ExtinctionConfig.LootTables[roll.Table] or {} do
			local key = rowKey(entry.Id)
			local r = ranges[key]
			ranges[key] = r and { math.min(r[1], entry.Count[1]), math.max(r[2], entry.Count[2]) } or { entry.Count[1], entry.Count[2] }
		end
	end
	return ranges
end

local cache = {}

-- Liste { Key, Id (für Symbol und Name), Tier, Chance (0..1), Count = { min, max }, Attachment = true|nil }, beste Chance zuerst
function LootInfo.Rows(source)
	if cache[source.Id] then
		return cache[source.Id]
	end
	local rows = {}
	local random = Random.new(source.Id:len() * 7919)
	local hits, firstId, tiers = {}, {}, {}
	for _ = 1, TRIALS do
		local seen = {}
		for _, roll in source.Rolls do
			if not roll.Chance or random:NextNumber() < roll.Chance then
				for _, item in ExtinctionConfig.RollLoot(roll.Table, random:NextInteger(roll.Items[1], roll.Items[2]), random) do
					local key, tier = rowKey(item.Id)
					seen[key] = true
					firstId[key] = firstId[key] or item.Id
					tiers[key] = tier
				end
			end
		end
		for key in seen do
			hits[key] = (hits[key] or 0) + 1
		end
	end
	local ranges = countRanges(source)
	for key, n in hits do
		table.insert(rows, { Key = key, Id = firstId[key], Tier = tiers[key], Chance = n / TRIALS,
			Count = ranges[key] or { 1, 1 }, Attachment = string.sub(key, 1, 5) == "Att_T" or nil })
	end
	table.sort(rows, function(a, b)
		if a.Chance ~= b.Chance then
			return a.Chance > b.Chance
		end
		return a.Key < b.Key
	end)
	cache[source.Id] = rows
	return rows
end

-- Chance als Text: "100 %", "37 %", "4.2 %", "<0.1 %"
function LootInfo.FormatChance(chance)
	local pct = chance * 100
	if pct >= 99.95 then
		return "100 %"
	elseif pct >= 10 then
		return string.format("%d %%", math.floor(pct + 0.5))
	elseif pct >= 0.1 then
		return string.format("%.1f %%", pct)
	end
	return "<0.1 %"
end

-- Seltenheit nach Chance: Name und Farbe
function LootInfo.Rarity(chance)
	if chance >= 0.5 then
		return "COMMON", Color3.fromRGB(120, 200, 120)
	elseif chance >= 0.2 then
		return "UNCOMMON", Color3.fromRGB(120, 176, 230)
	elseif chance >= 0.07 then
		return "RARE", Color3.fromRGB(176, 136, 232)
	end
	return "VERY RARE", Color3.fromRGB(236, 178, 70)
end

LootInfo.AttachmentNames = { [2] = "ATTACHMENT (COMMON)", [3] = "ATTACHMENT (RARE)", [4] = "ATTACHMENT (VERY RARE)" }

return LootInfo
