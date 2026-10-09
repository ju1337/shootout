-- Studio-Modell (.rbxm) in XML (.rbxmx) umwandeln: lune run tools/models/rbxm_to_rbxmx.luau <in.rbxm> <out.rbxmx>
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local src, dst = process.args[1], process.args[2]
local inst = roblox.deserializeModel(fs.readFile(src))
fs.writeFile(dst, roblox.serializeModel(inst, true))
