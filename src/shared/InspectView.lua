-- InspectView (ModuleScript, nur Client)
-- Inspizieren der Waffe (Taste X, WeaponClient) läuft wie ein Arcade-Trick mitten im Spiel: nur die Animation der
-- Waffe, kein Ausblenden des HUD, keine Kino-Effekte, keine Werte-Karte. Dieses Modul zeigt nur noch den kurzen
-- Hinweis unten in der Mitte, wenn Inspizieren gerade nicht geht (z.B. keine Waffe in der Hand).
--   InspectView.Notice(text)  InspectView.LastNotice()

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = script.Parent
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer
local C = UITheme.Colors
local make = UITheme.Make

local InspectView = {}

local NOTICE_TIME = 2.4 -- so lange bleibt ein Hinweis stehen
local notice, noticeLabel = nil, nil
local noticeToken = 0

local function tween(object, time, props)
	local t = TweenService:Create(object, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Kurzer Hinweis unten in der Mitte (blendet nach NOTICE_TIME Sekunden aus)
function InspectView.Notice(text)
	if not notice then
		notice = make("ScreenGui", { Name = "InspectNotice", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 7 },
			player:WaitForChild("PlayerGui"))
		noticeLabel = UITheme.Label({ Name = "Notice", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -210),
			Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.Panel,
			BackgroundTransparency = 1, Text = "", TextSize = 15, TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center }, UITheme.ScaledRoot(notice))
		UITheme.Corner(noticeLabel, UITheme.Radius.Small)
		make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, noticeLabel)
	end
	noticeToken += 1
	local myToken = noticeToken
	noticeLabel.Text = text
	tween(noticeLabel, 0.15, { TextTransparency = 0, BackgroundTransparency = 0.2 })
	task.delay(NOTICE_TIME, function()
		if noticeToken == myToken then
			tween(noticeLabel, 0.4, { TextTransparency = 1, BackgroundTransparency = 1 })
		end
	end)
end

-- Text des letzten Hinweises (Tests)
function InspectView.LastNotice()
	return noticeLabel and noticeLabel.Text or nil
end

return InspectView
