-- AimbotESP.lua
-- Developer: IshKeb
-- Note: this script should work for most games.
--
-- EXECUTOR DEPENDENCIES:
--   Drawing        – executor Drawing API (Xeno, Synapse X, KRNL, Script-Ware, etc.)
--   mousemoverel   – executor mouse-movement function (same executors)
--   gethui         – Xeno/most modern executors' protected GUI container (optional fallback)

-- ──────────────────────────────────────────────────────────────
--  Services
-- ──────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Camera            = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer

-- ──────────────────────────────────────────────────────────────
--  State
-- ──────────────────────────────────────────────────────────────
local aimbotEnabled = false
local fovRadius     = 120        -- default FOV circle radius (pixels)
-- 0.97 caps the lerp factor so aim never fully freezes (leaves 3% of motion at max smoothness)
local SMOOTHNESS_SCALE   = 0.97
local HEALTH_BAR_OFFSET  = 10   -- pixels left of character centre for the health bar
local LOADING_DURATION   = 5    -- seconds the fake loading screen is shown

local smoothness    = 1 - (0.15 * SMOOTHNESS_SCALE) -- matches slider default 0.15 in inverted formula
local lockedTarget  = nil        -- the BasePart we are locked onto
local visibleOnly   = false

local espEnabled    = false
local chamsEnabled  = false
local nameEnabled   = false
local healthEnabled = false

-- tables holding ESP drawings per player
local espObjects = {}   -- [player] = { box, name, healthBG, healthBar, chams={} }

-- ──────────────────────────────────────────────────────────────
--  GUI SETUP
-- ──────────────────────────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name            = "AimbotESPMenu"
ScreenGui.ResetOnSpawn    = false
ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
-- Use gethui() (Xeno/modern executors) with a CoreGui fallback.
-- rawget avoids triggering __index metamethods if gethui is not defined.
local guiParent = (rawget(_G, "gethui") and gethui()) or game:GetService("CoreGui")
ScreenGui.Parent          = guiParent

-- ── Theme colours ──
local COL_BG       = Color3.fromRGB(6,   6,   8)
local COL_PANEL    = Color3.fromRGB(16,  16,  20)
local COL_ACCENT   = Color3.fromRGB(220, 40,  40)
local COL_DIM      = Color3.fromRGB(180, 170, 170)
local COL_TOGON    = Color3.fromRGB(200, 30,  30)
local COL_TOGOFF   = Color3.fromRGB(45,  45,  50)
local COL_SLIDER   = Color3.fromRGB(220, 40,  40)
local COL_BORDER   = Color3.fromRGB(30,  30,  36)
local COL_TAB_ACTIVE = Color3.fromRGB(28, 28, 34)

-- ── Main Window ──
local MainFrame = Instance.new("Frame")
MainFrame.Name            = "MainFrame"
MainFrame.Size            = UDim2.new(0, 480, 0, 340)
MainFrame.Position        = UDim2.new(0.5, -240, 0.5, -170)
MainFrame.BackgroundColor3 = COL_BG
MainFrame.BorderSizePixel = 0
MainFrame.Active          = true
MainFrame.Draggable       = true
MainFrame.Visible         = false    -- hidden until loading screen finishes
MainFrame.Parent          = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1
MainStroke.Color = COL_BORDER
MainStroke.Transparency = 0.35
MainStroke.Parent = MainFrame

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Size              = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3  = COL_PANEL
TitleBar.BorderSizePixel   = 0
TitleBar.Parent            = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = TitleBar

-- Fill bottom corners of title bar
local TitleFill = Instance.new("Frame")
TitleFill.Size             = UDim2.new(1, 0, 0, 10)
TitleFill.Position         = UDim2.new(0, 0, 1, -10)
TitleFill.BackgroundColor3 = COL_PANEL
TitleFill.BorderSizePixel  = 0
TitleFill.Parent           = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size              = UDim2.new(1, -40, 1, 0)
TitleLabel.Position          = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text              = "IshKeb Menu"
TitleLabel.Font              = Enum.Font.GothamBold
TitleLabel.TextSize          = 15
TitleLabel.TextColor3        = COL_ACCENT
TitleLabel.TextXAlignment    = Enum.TextXAlignment.Left
TitleLabel.Parent            = TitleBar

-- Close button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size              = UDim2.new(0, 28, 0, 28)
CloseBtn.Position          = UDim2.new(1, -32, 0, 4)
CloseBtn.BackgroundColor3  = Color3.fromRGB(200, 50, 50)
CloseBtn.Text              = "✕"
CloseBtn.Font              = Enum.Font.GothamBold
CloseBtn.TextSize          = 13
CloseBtn.TextColor3        = Color3.fromRGB(245, 245, 245)
CloseBtn.BorderSizePixel   = 0
CloseBtn.Parent            = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

-- Keybind hint
local KeyHint = Instance.new("TextLabel")
KeyHint.Size                   = UDim2.new(1, 0, 0, 14)
KeyHint.Position               = UDim2.new(0, 0, 1, -16)
KeyHint.BackgroundTransparency = 1
KeyHint.Text                   = "Press INSERT to toggle menu"
KeyHint.Font                   = Enum.Font.Gotham
KeyHint.TextSize               = 11
KeyHint.TextColor3             = COL_DIM
KeyHint.TextXAlignment         = Enum.TextXAlignment.Center
KeyHint.Parent                 = ScreenGui

-- ──────────────────────────────────────────────────────────────
--  LOADING SCREEN
-- ──────────────────────────────────────────────────────────────
local LoadFrame = Instance.new("Frame")
LoadFrame.Size             = UDim2.new(1, 0, 1, 0)
LoadFrame.BackgroundColor3 = COL_BG
LoadFrame.BorderSizePixel  = 0
LoadFrame.ZIndex           = 20
LoadFrame.Parent           = ScreenGui

local LoadTitle = Instance.new("TextLabel")
LoadTitle.Size                   = UDim2.new(1, 0, 0, 40)
LoadTitle.Position               = UDim2.new(0, 0, 0.38, 0)
LoadTitle.BackgroundTransparency = 1
LoadTitle.Text                   = "IshKeb Menu"
LoadTitle.Font                   = Enum.Font.GothamBold
LoadTitle.TextSize               = 22
LoadTitle.TextColor3             = COL_ACCENT
LoadTitle.TextXAlignment         = Enum.TextXAlignment.Center
LoadTitle.ZIndex                 = 21
LoadTitle.Parent                 = LoadFrame

local LoadSub = Instance.new("TextLabel")
LoadSub.Size                   = UDim2.new(1, 0, 0, 22)
LoadSub.Position               = UDim2.new(0, 0, 0.38, 44)
LoadSub.BackgroundTransparency = 1
LoadSub.Text                   = "Developer: IshKeb"
LoadSub.Font                   = Enum.Font.Gotham
LoadSub.TextSize               = 12
LoadSub.TextColor3             = COL_DIM
LoadSub.TextXAlignment         = Enum.TextXAlignment.Center
LoadSub.ZIndex                 = 21
LoadSub.Parent                 = LoadFrame

local ProgressBG = Instance.new("Frame")
ProgressBG.Size             = UDim2.new(0, 320, 0, 6)
ProgressBG.Position         = UDim2.new(0.5, -160, 0.58, 0)
ProgressBG.BackgroundColor3 = COL_TOGOFF
ProgressBG.BorderSizePixel  = 0
ProgressBG.ZIndex           = 21
ProgressBG.Parent           = LoadFrame

local ProgressBGCorner = Instance.new("UICorner")
ProgressBGCorner.CornerRadius = UDim.new(1, 0)
ProgressBGCorner.Parent = ProgressBG

local ProgressFill = Instance.new("Frame")
ProgressFill.Size             = UDim2.new(0, 0, 1, 0)
ProgressFill.BackgroundColor3 = COL_ACCENT
ProgressFill.BorderSizePixel  = 0
ProgressFill.ZIndex           = 22
ProgressFill.Parent           = ProgressBG

local ProgressFillCorner = Instance.new("UICorner")
ProgressFillCorner.CornerRadius = UDim.new(1, 0)
ProgressFillCorner.Parent = ProgressFill

local LoadStatus = Instance.new("TextLabel")
LoadStatus.Size                   = UDim2.new(1, 0, 0, 18)
LoadStatus.Position               = UDim2.new(0, 0, 0.58, 14)
LoadStatus.BackgroundTransparency = 1
LoadStatus.Text                   = "Initializing..."
LoadStatus.Font                   = Enum.Font.Gotham
LoadStatus.TextSize               = 11
LoadStatus.TextColor3             = COL_DIM
LoadStatus.TextXAlignment         = Enum.TextXAlignment.Center
LoadStatus.ZIndex                 = 21
LoadStatus.Parent                 = LoadFrame


local TabBar = Instance.new("Frame")
TabBar.Size             = UDim2.new(1, 0, 0, 32)
TabBar.Position         = UDim2.new(0, 0, 0, 36)
TabBar.BackgroundColor3 = COL_PANEL
TabBar.BorderSizePixel  = 0
TabBar.Parent           = MainFrame

local TabList = Instance.new("UIListLayout")
TabList.FillDirection  = Enum.FillDirection.Horizontal
TabList.SortOrder      = Enum.SortOrder.LayoutOrder
TabList.Parent         = TabBar

-- Content area
local ContentArea = Instance.new("Frame")
ContentArea.Size             = UDim2.new(1, 0, 1, -68)
ContentArea.Position         = UDim2.new(0, 0, 0, 68)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent           = MainFrame

-- ──────────────────────────────────────────────────────────────
--  Helper: create a tab button + its panel
-- ──────────────────────────────────────────────────────────────
local tabPanels = {}
local tabButtons = {}
local activeTab = nil

local function switchTab(name)
    if activeTab then
        tabPanels[activeTab].Visible     = false
        tabButtons[activeTab].TextColor3 = COL_DIM
        tabButtons[activeTab].BackgroundColor3 = COL_PANEL
    end
    activeTab = name
    tabPanels[name].Visible     = true
    tabButtons[name].TextColor3 = COL_ACCENT
    tabButtons[name].BackgroundColor3 = COL_TAB_ACTIVE
end

local function createTab(name, order)
    local btn = Instance.new("TextButton")
    btn.Size              = UDim2.new(0, 120, 1, 0)
    btn.BackgroundColor3  = COL_PANEL
    btn.BorderSizePixel   = 0
    btn.Text              = name
    btn.Font              = Enum.Font.GothamSemibold
    btn.TextSize          = 13
    btn.TextColor3        = COL_DIM
    btn.LayoutOrder       = order
    btn.Parent            = TabBar

    local panel = Instance.new("ScrollingFrame")
    panel.Size               = UDim2.new(1, 0, 1, 0)
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel    = 0
    panel.ScrollBarThickness = 4
    panel.ScrollBarImageColor3 = COL_DIM
    panel.Visible            = false
    panel.Parent             = ContentArea

    local layout = Instance.new("UIListLayout")
    layout.Padding         = UDim.new(0, 6)
    layout.SortOrder       = Enum.SortOrder.LayoutOrder
    layout.Parent          = panel

    local padding = Instance.new("UIPadding")
    padding.PaddingTop    = UDim.new(0, 10)
    padding.PaddingLeft   = UDim.new(0, 14)
    padding.PaddingRight  = UDim.new(0, 14)
    padding.Parent        = panel

    tabPanels[name]  = panel
    tabButtons[name] = btn

    -- Auto-size ScrollingFrame canvas
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        panel.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
    end)

    btn.MouseButton1Click:Connect(function()
        switchTab(name)
    end)

    return panel
end

-- ──────────────────────────────────────────────────────────────
--  Helper: row label
-- ──────────────────────────────────────────────────────────────
local function makeLabel(parent, text, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, 0, 0, 18)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 12
    lbl.TextColor3             = COL_DIM
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.LayoutOrder            = order
    lbl.Parent                 = parent
    return lbl
end

-- ──────────────────────────────────────────────────────────────
--  Helper: toggle row
-- ──────────────────────────────────────────────────────────────
local function makeToggle(parent, labelText, order, callback)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, 0, 0, 32)
    row.BackgroundColor3 = COL_PANEL
    row.BorderSizePixel  = 0
    row.LayoutOrder      = order
    row.Parent           = parent

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 6)
    rowCorner.Parent = row

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -60, 1, 0)
    lbl.Position               = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = labelText
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 13
    lbl.TextColor3             = COL_ACCENT
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = row

    local togBG = Instance.new("Frame")
    togBG.Size             = UDim2.new(0, 40, 0, 20)
    togBG.Position         = UDim2.new(1, -50, 0.5, -10)
    togBG.BackgroundColor3 = COL_TOGOFF
    togBG.BorderSizePixel  = 0
    togBG.Parent           = row

    local togBGCorner = Instance.new("UICorner")
    togBGCorner.CornerRadius = UDim.new(1, 0)
    togBGCorner.Parent = togBG

    local togKnob = Instance.new("Frame")
    togKnob.Size             = UDim2.new(0, 16, 0, 16)
    togKnob.Position         = UDim2.new(0, 2, 0.5, -8)
    togKnob.BackgroundColor3 = COL_ACCENT
    togKnob.BorderSizePixel  = 0
    togKnob.Parent           = togBG

    local togKnobCorner = Instance.new("UICorner")
    togKnobCorner.CornerRadius = UDim.new(1, 0)
    togKnobCorner.Parent = togKnob

    local state = false
    local btn = Instance.new("TextButton")
    btn.Size                   = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text                   = ""
    btn.Parent                 = row

    btn.MouseButton1Click:Connect(function()
        state = not state
        togBG.BackgroundColor3 = state and COL_TOGON or COL_TOGOFF
        togKnob.Position       = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        togKnob.BackgroundColor3 = state and COL_BG or COL_ACCENT
        if callback then callback(state) end
    end)

    return row
end

-- ──────────────────────────────────────────────────────────────
--  Helper: slider row  (returns row frame; valueLabel auto-updates)
-- ──────────────────────────────────────────────────────────────
local function makeSlider(parent, labelText, order, minVal, maxVal, defaultVal, callback)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = COL_PANEL
    row.BorderSizePixel  = 0
    row.LayoutOrder      = order
    row.Parent           = parent

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 6)
    rowCorner.Parent = row

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(0.75, 0, 0, 22)
    lbl.Position               = UDim2.new(0, 10, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = labelText
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 13
    lbl.TextColor3             = COL_ACCENT
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = row

    local valLabel = Instance.new("TextLabel")
    valLabel.Size                   = UDim2.new(0.25, -10, 0, 22)
    valLabel.Position               = UDim2.new(0.75, 0, 0, 4)
    valLabel.BackgroundTransparency = 1
    valLabel.Text                   = tostring(defaultVal)
    valLabel.Font                   = Enum.Font.Gotham
    valLabel.TextSize               = 12
    valLabel.TextColor3             = COL_DIM
    valLabel.TextXAlignment         = Enum.TextXAlignment.Right
    valLabel.Parent                 = row

    local track = Instance.new("Frame")
    track.Size             = UDim2.new(1, -20, 0, 4)
    track.Position         = UDim2.new(0, 10, 0, 34)
    track.BackgroundColor3 = COL_TOGOFF
    track.BorderSizePixel  = 0
    track.Parent           = row

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Size             = UDim2.new((defaultVal - minVal) / (maxVal - minVal), 0, 1, 0)
    fill.BackgroundColor3 = COL_SLIDER
    fill.BorderSizePixel  = 0
    fill.Parent           = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local knob = Instance.new("Frame")
    knob.Size             = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint      = Vector2.new(0.5, 0.5)
    knob.Position         = UDim2.new((defaultVal - minVal) / (maxVal - minVal), 0, 0.5, 0)
    knob.BackgroundColor3 = COL_ACCENT
    knob.BorderSizePixel  = 0
    knob.Parent           = track

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local dragging = false
    local trackBtn = Instance.new("TextButton")
    trackBtn.Size                   = UDim2.new(1, 0, 0, 20)
    trackBtn.Position               = UDim2.new(0, 0, 0.5, -10)
    trackBtn.BackgroundTransparency = 1
    trackBtn.Text                   = ""
    trackBtn.Parent                 = track

    local function updateFromX(absX)
        local trackAbs  = track.AbsolutePosition.X
        local trackSize = track.AbsoluteSize.X
        local t = math.clamp((absX - trackAbs) / trackSize, 0, 1)
        local value
        if math.type and math.type(minVal) == "integer" then
            value = math.floor(minVal + t * (maxVal - minVal) + 0.5)
        else
            -- round to 2 decimal places
            value = math.floor((minVal + t * (maxVal - minVal)) * 100 + 0.5) / 100
        end
        fill.Size     = UDim2.new(t, 0, 1, 0)
        knob.Position = UDim2.new(t, 0, 0.5, 0)
        valLabel.Text = tostring(value)
        if callback then callback(value) end
    end

    -- GuiButton.MouseButton1Down fires with (x: number, y: number) absolute screen coords
    trackBtn.MouseButton1Down:Connect(function(x, _y)
        dragging = true
        updateFromX(x)
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    return row
end

-- ──────────────────────────────────────────────────────────────
--  Build Tabs
-- ──────────────────────────────────────────────────────────────
local aimbotPanel  = createTab("Aimbot",  1)
local visualsPanel = createTab("Visuals", 2)
local notesPanel   = createTab("Notes",   3)

-- ── Aimbot Tab ──
makeToggle(aimbotPanel, "Enable Aimbot", 1, function(val)
    aimbotEnabled = val
    if not val then lockedTarget = nil end
end)

makeSlider(aimbotPanel, "FOV Circle Size", 2, 20, 400, fovRadius, function(val)
    fovRadius = val
end)

-- slider default 0.15 → inverted smoothness: high slider = slow lerp = more smooth
makeSlider(aimbotPanel, "Aim Smoothness", 3, 0.00, 1.00, 0.15, function(val)
    -- invert: high slider value = high smoothness = smaller lerp factor = slower / smoother aim
    smoothness = 1 - (val * SMOOTHNESS_SCALE)
end)

makeToggle(aimbotPanel, "Visible Only", 4, function(val)
    visibleOnly = val
    if not val then lockedTarget = nil end
end)

makeLabel(aimbotPanel, "Hold M2 (Right-Click) to aim.", 5)

-- ── Visuals Tab ──
makeToggle(visualsPanel, "Name ESP",       1, function(val) nameEnabled   = val end)
makeToggle(visualsPanel, "Health Bar ESP", 2, function(val) healthEnabled = val end)
makeToggle(visualsPanel, "Chams ESP",      3, function(val) chamsEnabled  = val end)

-- ── Notes Tab ──
local function makeNote(parent, text, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, 0, 0, 0)
    lbl.AutomaticSize          = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.Font                   = Enum.Font.Gotham
    lbl.TextSize               = 13
    lbl.TextColor3             = COL_ACCENT
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.TextWrapped            = true
    lbl.LayoutOrder            = order
    lbl.Parent                 = parent
    return lbl
end

makeNote(notesPanel, "Developer: IshKeb", 1)
makeNote(notesPanel, "Note: this script should work for most games.", 2)
makeNote(notesPanel, "Toggle key is Insert", 3)
-- (switchTab will be called by the loading screen task after setup is complete)

-- ──────────────────────────────────────────────────────────────
--  FOV CIRCLE  (Drawing API)
-- ──────────────────────────────────────────────────────────────
local fovCircle = Drawing.new("Circle")
fovCircle.Visible   = false
fovCircle.Thickness = 1.5
fovCircle.Color     = COL_ACCENT
fovCircle.Filled    = false
fovCircle.NumSides  = 64
fovCircle.Radius    = fovRadius

-- ──────────────────────────────────────────────────────────────
--  ESP HELPERS
-- ──────────────────────────────────────────────────────────────
local function newDrawing(type_, props)
    local d = Drawing.new(type_)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function removeESPForPlayer(player)
    local obj = espObjects[player]
    if not obj then return end
    -- Remove Drawing objects
    pcall(function() obj.nameTag:Remove() end)
    pcall(function() obj.healthBG:Remove() end)
    pcall(function() obj.healthBar:Remove() end)
    -- Destroy the Highlight instance
    if obj.highlight then pcall(function() obj.highlight:Destroy() end) end
    espObjects[player] = nil
end

local function getCharacterParts(character)
    if not character then return nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not (root and head and humanoid) then return nil end
    return root, head, humanoid
end

-- Build ESP drawings for a player
local function setupESPForPlayer(player)
    if espObjects[player] then return end

    -- Highlight instance for Chams (renders through walls via AlwaysOnTop)
    local hl = Instance.new("Highlight")
    hl.FillColor            = Color3.fromRGB(255, 50, 50)
    hl.OutlineColor         = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency     = 0.4
    hl.OutlineTransparency  = 0
    hl.DepthMode            = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled              = false
    hl.Adornee              = player.Character
    hl.Parent               = workspace

    espObjects[player] = {
        nameTag   = newDrawing("Text",   {Visible=false, Size=14, Color=Color3.fromRGB(255,255,255), Center=true, Outline=true, Font=0}),
        healthBG  = newDrawing("Square", {Visible=false, Thickness=0, Color=Color3.fromRGB(0,0,0),   Filled=true}),
        healthBar = newDrawing("Square", {Visible=false, Thickness=0, Color=Color3.fromRGB(0,200,0), Filled=true}),
        highlight = hl,
    }
end

local function applyChams(player)
    local obj = espObjects[player]
    if not obj or not obj.highlight then return end
    -- Update the Highlight adornee to the player's current character
    obj.highlight.Adornee = player.Character
end

-- ──────────────────────────────────────────────────────────────
--  Register / unregister players
-- ──────────────────────────────────────────────────────────────
local function onPlayerAdded(player)
    if player == LocalPlayer then return end
    setupESPForPlayer(player)

    -- Watch for character changes (respawns, etc.)
    player.CharacterAdded:Connect(function(character)
        task.wait(0.1)
        local obj = espObjects[player]
        if obj and obj.highlight then
            obj.highlight.Adornee = character
        end
    end)

    if player.Character then
        applyChams(player)
    end
end

local function onPlayerRemoving(player)
    removeESPForPlayer(player)
end

for _, p in pairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- ──────────────────────────────────────────────────────────────
--  AIMBOT HELPERS
-- ──────────────────────────────────────────────────────────────
local function getMousePos()
    return UserInputService:GetMouseLocation()
end

local function worldToScreen(pos)
    local vp, inView = Camera:WorldToViewportPoint(pos)
    return Vector2.new(vp.X, vp.Y), inView, vp.Z
end

local function isTargetVisible(targetPart, character)
    if not targetPart or not character then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local ignore = {Camera}
    if LocalPlayer.Character then
        table.insert(ignore, LocalPlayer.Character)
    end
    params.FilterDescendantsInstances = ignore
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    local result = workspace:Raycast(origin, direction, params)
    return (not result) or result.Instance:IsDescendantOf(character)
end

local function getClosestHead(radius)
    local mousePos  = getMousePos()
    local bestDist  = math.huge
    local bestPart  = nil
    local searchRadius = radius or fovRadius

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local character = player.Character
        if not character then continue end
        local head = character:FindFirstChild("Head")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not head or not humanoid or humanoid.Health <= 0 then continue end

        local screenPos, inView = worldToScreen(head.Position)
        if not inView then continue end
        if visibleOnly and not isTargetVisible(head, character) then continue end

        local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        if dist <= searchRadius and dist < bestDist then
            bestDist = dist
            bestPart = head
        end
    end

    return bestPart
end

-- ──────────────────────────────────────────────────────────────
--  MAIN RENDER LOOP
-- ──────────────────────────────────────────────────────────────
local m2Held = false

UserInputService.InputBegan:Connect(function(input, gpe)
    -- MouseButton2 (right-click): never block on gpe so aimbot fires even when menu is focused
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        m2Held = true
        return
    end
    if gpe then return end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        m2Held      = false
        lockedTarget = nil
    end
end)

RunService.RenderStepped:Connect(function()
    local mousePos = getMousePos()

    -- ── FOV Circle ──
    fovCircle.Visible = aimbotEnabled
    fovCircle.Radius  = fovRadius
    fovCircle.Position = mousePos

    -- ── Aimbot ──
    if aimbotEnabled and m2Held then
        if not lockedTarget then
            lockedTarget = getClosestHead()
        end

        if lockedTarget then
            -- validate target still alive
            local humanoid = lockedTarget.Parent and
                             lockedTarget.Parent:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 or not lockedTarget.Parent.Parent then
                lockedTarget = nil
            else
                if visibleOnly and not isTargetVisible(lockedTarget, lockedTarget.Parent) then
                    lockedTarget = nil
                else
                    local screenPos, inView = worldToScreen(lockedTarget.Position)
                    if inView then
                        local current  = mousePos
                        local target   = Vector2.new(screenPos.X, screenPos.Y)
                        local newPos   = current:Lerp(target, smoothness)
                        -- Move mouse toward target (requires executor mousemoverel)
                        local delta = newPos - current
                        if mousemoverel then
                            mousemoverel(delta.X, delta.Y)
                        end
                    end
                end
            end
        end
    elseif not m2Held then
        lockedTarget = nil
    end

    -- ── ESP ──
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        local obj = espObjects[player]
        if not obj then continue end

        local character = player.Character
        local root, head, humanoid = getCharacterParts(character)

        local visible = (root ~= nil and head ~= nil)

        -- Name ESP
        if nameEnabled and visible then
            local sp, inView = worldToScreen(head.Position + Vector3.new(0, 0.7, 0))
            obj.nameTag.Visible   = inView
            obj.nameTag.Position  = sp
            obj.nameTag.Text      = player.Name
        else
            obj.nameTag.Visible = false
        end

        -- Health Bar ESP (positions computed from head/root world positions)
        local topSP, topInView
        local botSP, botInView
        if visible then
            topSP, topInView = worldToScreen(head.Position + Vector3.new(0, 0.7, 0))
            botSP, botInView = worldToScreen(root.Position - Vector3.new(0, 2.5, 0))
        end

        local barVisible = visible and topInView and botInView
        if barVisible and healthEnabled then
            local height = math.abs(topSP.Y - botSP.Y)
            local hp    = humanoid.Health
            local maxHp = humanoid.MaxHealth
            local ratio = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0
            local barW  = 4
            local bx    = topSP.X - HEALTH_BAR_OFFSET
            local by    = topSP.Y

            obj.healthBG.Visible  = true
            obj.healthBG.Position = Vector2.new(bx, by)
            obj.healthBG.Size     = Vector2.new(barW, height)

            obj.healthBar.Visible  = true
            obj.healthBar.Position = Vector2.new(bx, by + height * (1 - ratio))
            obj.healthBar.Size     = Vector2.new(barW, height * ratio)

            local g = math.floor(200 * ratio)
            local r = math.floor(200 * (1 - ratio))
            obj.healthBar.Color = Color3.fromRGB(r, g, 0)
        else
            obj.healthBG.Visible  = false
            obj.healthBar.Visible = false
        end

        -- Chams ESP via Highlight instance (AlwaysOnTop = visible through walls)
        if obj.highlight then
            obj.highlight.Adornee = character
            obj.highlight.Enabled = chamsEnabled and visible and (character ~= nil)
        end
    end
end)

-- ──────────────────────────────────────────────────────────────
--  INSERT to toggle menu visibility
-- ──────────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- ──────────────────────────────────────────────────────────────
--  LOADING SCREEN ANIMATION  (runs after all setup is complete)
-- ──────────────────────────────────────────────────────────────
task.spawn(function()
    local messages = {
        "Initializing...",
        "Loading modules...",
        "Esp Modules Installed...",
        "Workspace injection complete...",
        "Almost ready...",
        "Prepping ByfronBypass",
        "Done!",
    }
    local duration = LOADING_DURATION
    local startTime = tick()

    while tick() - startTime < duration do
        local t = (tick() - startTime) / duration
        ProgressFill.Size = UDim2.new(t, 0, 1, 0)
        local idx = math.clamp(math.floor(t * #messages) + 1, 1, #messages)
        LoadStatus.Text = messages[idx]
        task.wait()
    end

    ProgressFill.Size = UDim2.new(1, 0, 1, 0)
    LoadStatus.Text = "Done!"
    task.wait(0.35)

    LoadFrame:Destroy()
    switchTab("Aimbot")
    MainFrame.Visible = true
end)
