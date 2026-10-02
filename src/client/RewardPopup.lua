-- RewardPopup (ModuleScript, nur Client)
-- Zeigt Belohnungen (Remotes.Reward vom RewardService) als Karte oben in der Mitte: Titel in Gold,
-- darunter die Belohnungen ("+500 Münzen", "Neuer Skin: Veteran"). Mehrere nacheinander, je ~3,5 s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local Cosmetics = require(Shared.Cosmetics)

local player = Players.LocalPlayer
local C = UITheme.Colors
local make = UITheme.Make

local RewardPopup = {}

local SHOW_TIME = 3.5
local GOLD = Color3.fromRGB(230, 182, 74)

function RewardPopup.Init()
	local gui = make("ScreenGui", { Name = "RewardPopup", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 25 },
		player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(gui)
	local card = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -140),
		Size = UDim2.new(0, 460, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08, Visible = false }, root)
	UITheme.Corner(card, UITheme.Radius.Large)
	local stroke = UITheme.Stroke(card, GOLD, 1.5, 0.2)
	make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 22),
		PaddingRight = UDim.new(0, 22) }, card)
	make("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder }, card)
	UITheme.Label({ Size = UDim2.new(1, 0, 0, 16), Text = "BELOHNUNG", TextSize = 13, Font = UITheme.Fonts.Bold,
		TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 }, card)
	local title = UITheme.Label({ Size = UDim2.new(1, 0, 0, 34), Text = "", TextSize = 30, Font = UITheme.Fonts.Display,
		TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 }, card)
	local lines = UITheme.Label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", TextSize = 17,
		Font = UITheme.Fonts.Bold, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		LayoutOrder = 3 }, card)

	local queue, running = {}, false
	local function showNext()
		if #queue == 0 then
			running = false
			return
		end
		running = true
		local data = table.remove(queue, 1)
		local rarity = data.Rarity and Cosmetics.Rarities[data.Rarity]
		title.Text = tostring(data.Title or "")
		lines.Text = table.concat(data.Lines or {}, "\n")
		stroke.Color = rarity and rarity.Color or GOLD
		card.Visible = true
		card.Position = UDim2.new(0.5, 0, 0, -140)
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 96) }):Play()
		task.delay(SHOW_TIME, function()
			local out = TweenService:Create(card, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -140) })
			out:Play()
			out.Completed:Wait()
			card.Visible = false
			showNext()
		end)
	end
	Remotes.Reward.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		table.insert(queue, data)
		if not running then
			showNext()
		end
	end)
end

return RewardPopup
