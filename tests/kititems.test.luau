-- Kit-Items: Kits geben eigene Ausführungen ("<Id>_Kit"), die wie das Original funktionieren, aber unverkäuflich sind
-- (Verkaufspreis 0, Kit = true). Munition bleibt die normale, bringt aus Kits beim Verkaufen aber nichts (SellSplit).
local failures = 0
local function check(c, m) if not c then failures += 1 print("FEHLER: " .. m) end end

local ExtinctionConfig = require("ExtinctionConfig")
local KitConfig = require("KitConfig")

for _, base in ExtinctionConfig.KitVariants do
	local original, variant = ExtinctionConfig.Get(base), ExtinctionConfig.Get(base .. "_Kit")
	check(variant ~= nil, base .. "_Kit fehlt")
	if variant and original then
		check(variant.Kit == true and variant.Base == base, base .. "_Kit ist nicht als Kit-Item markiert")
		check(variant.Kind == original.Kind and variant.Weapon == original.Weapon and variant.Vehicle == original.Vehicle,
			base .. "_Kit verhält sich anders als das Original")
		check(ExtinctionConfig.SellPrice(base .. "_Kit", 1) == 0, base .. "_Kit bringt beim Verkaufen Münzen")
		check(ExtinctionConfig.SellPrice(base, 1) > 0 or original.Price == nil, base .. " (Original) ist wertlos geworden")
	end
end

-- Kits enthalten nur Kit-Ausführungen oder Munition, und jedes Item gibt es
for _, kit in KitConfig.List do
	for _, entry in kit.Items do
		local config = ExtinctionConfig.Get(entry[1])
		check(config ~= nil, kit.Id .. ": Item " .. tostring(entry[1]) .. " gibt es nicht")
		if config then
			check(config.Kit or config.Kind == "Ammo", kit.Id .. ": " .. entry[1] .. " wäre verkäuflich")
		end
	end
end

-- Munition aus Kits: zuerst gegen das Guthaben, Rest wird bezahlt
local free, paid = KitConfig.SellSplit({ Ammo_9mm = 100 }, "Ammo_9mm", 150)
check(free == 100 and paid == 50, "SellSplit rechnet falsch: " .. free .. " / " .. paid)
free, paid = KitConfig.SellSplit(nil, "Ammo_9mm", 30)
check(free == 0 and paid == 30, "SellSplit ohne Guthaben rechnet falsch")

if failures == 0 then
	print("Kit-Items ok")
end
