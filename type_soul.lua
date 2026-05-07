--[[
    catboy hub - Type Soul rewrite
    Clean self-contained executor script.

    Focus:
    - ScreenGui UI instead of a remote Drawing library.
    - Clickable Auto Parry toggle with timing sliders.
    - Heartbeat driven movement enforcement for Type Soul entity states.
    - Small debug surface for live tuning.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local VERSION = "1.0.0"
local HUB_NAME = "CatboyHub_TypeSoul"
local DEFAULT_PARRY_KEY = Enum.KeyCode.F
local getgenv = getgenv or function()
    return _G
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

local function round(value, increment)
    increment = increment or 1
    return math.floor((value / increment) + 0.5) * increment
end

local function clamp(value, minimum, maximum)
    return math.clamp(value, minimum, maximum)
end

local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({ tasks = {} }, Maid)
end

function Maid:Give(taskObject)
    table.insert(self.tasks, taskObject)
    return taskObject
end

function Maid:Cleanup()
    for index = #self.tasks, 1, -1 do
        local taskObject = self.tasks[index]
        self.tasks[index] = nil

        if typeof(taskObject) == "RBXScriptConnection" then
            taskObject:Disconnect()
        elseif typeof(taskObject) == "Instance" then
            taskObject:Destroy()
        elseif type(taskObject) == "function" then
            pcall(taskObject)
        elseif type(taskObject) == "table" and taskObject.Destroy then
            pcall(function()
                taskObject:Destroy()
            end)
        end
    end
end

local Hub = {
    Maid = Maid.new(),
    Flags = {
        Debug = false,

        AutoParry = false,
        AutoParryRange = 18,
        AutoParryReactionDelay = 0.02,
        AutoParryCooldown = 0.65,
        AutoParryAnimationWindow = 0.55,
        AutoParryFacingDot = 0.25,
        AutoParryM1Delay = 0.14,
        AutoParryHeavyDelay = 0.24,
        AutoParrySkillDelay = 0.42,
        AutoParryGenericDelay = 0.28,
        AutoParryPingCompensation = 0.45,
        AutoParryMissLockout = 0.85,
        AutoParryThreatReset = 0.9,
        AutoParrySkillAssist = true,

        MovementEnabled = false,
        MovementMode = "Hybrid",
        WalkSpeed = 28,
        SprintSpeed = 36,
        WeaponDrawnSpeed = 30,
        FlashstepEnabled = true,
        FlashstepSpeed = 115,
        VelocityAssist = true,
        VelocityMultiplier = 1.15,
    },

    Runtime = {
        Gui = nil,
        StatusLabel = nil,
        AutoParryConnection = nil,
        MovementConnection = nil,
        LastParry = 0,
        LastDebugLine = "",
        LastThreat = "none",
        LastMovementState = "none",
        KnownAttackTracks = {},
        PendingParry = false,
        ThreatMemory = {},
        LastDebugMovementState = nil,
    },
}

local attackStates = {
    Action = true,
    Attacking = true,
    Critical = true,
    Crit = true,
    Heavy = true,
    M1 = true,
    Skill = true,
    ShikaiSkill = true,
    BankaiSkill = true,
    HakudaSkill = true,
    KidoSkill = true,
}

local unsafeParryStates = {
    Dead = true,
    Died = true,
    Executed = true,
    Executing = true,
    Flashstep = true,
    PostureBroken = true,
    TrueStunned = true,
    Stunned = true,
    Ragdolled = true,
    Skill = true,
    ShikaiSkill = true,
    BankaiSkill = true,
    Action = true,
}

local movementBlockedStates = {
    Dead = true,
    Died = true,
    Executed = true,
    Executing = true,
    PostureBroken = true,
    TrueStunned = true,
    Stunned = true,
    Ragdolled = true,
    Skill = true,
    ShikaiSkill = true,
    BankaiSkill = true,
    Action = true,
}

local CustomSkillProfiles = getgenv().CatboyHubTypeSoulSkillProfiles or {}

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 4,
        })
    end)
end

local function debugPrint(...)
    if not Hub.Flags.Debug then
        return
    end

    local pieces = {}
    for index = 1, select("#", ...) do
        table.insert(pieces, tostring(select(index, ...)))
    end

    local line = "[catboy hub] " .. table.concat(pieces, " ")
    Hub.Runtime.LastDebugLine = line
    warn(line)
end

local function setStatus(text)
    Hub.Runtime.LastDebugLine = tostring(text)
    if Hub.Runtime.StatusLabel then
        Hub.Runtime.StatusLabel.Text = tostring(text)
    end
end

local function safeParent()
    local ok, parent = pcall(function()
        if gethui then
            return gethui()
        end
        return CoreGui
    end)

    if ok and parent then
        return parent
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local function destroyExistingGui()
    local parent = safeParent()
    local old = parent:FindFirstChild(HUB_NAME)
    if old then
        old:Destroy()
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        old = playerGui:FindFirstChild(HUB_NAME)
        if old then
            old:Destroy()
        end
    end
end

local function newInstance(className, properties, children)
    local instance = Instance.new(className)

    for property, value in pairs(properties or {}) do
        instance[property] = value
    end

    for _, child in ipairs(children or {}) do
        child.Parent = instance
    end

    return instance
end

local theme = {
    Background = Color3.fromRGB(13, 15, 18),
    Panel = Color3.fromRGB(22, 25, 30),
    PanelLight = Color3.fromRGB(31, 35, 42),
    Stroke = Color3.fromRGB(60, 67, 78),
    Muted = Color3.fromRGB(151, 160, 174),
    Text = Color3.fromRGB(239, 243, 248),
    Accent = Color3.fromRGB(83, 166, 255),
    AccentDark = Color3.fromRGB(31, 91, 158),
    Good = Color3.fromRGB(75, 205, 135),
    Bad = Color3.fromRGB(239, 93, 93),
}

local UI = {
    Tabs = {},
    Pages = {},
    Controls = {},
}

function UI:StyleText(instance, size, color)
    instance.Font = Enum.Font.Gotham
    instance.TextSize = size or 13
    instance.TextColor3 = color or theme.Text
    instance.TextWrapped = false
    instance.TextXAlignment = Enum.TextXAlignment.Left
    instance.BackgroundTransparency = 1
end

function UI:Corner(radius)
    return newInstance("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function UI:Stroke(color, transparency)
    return newInstance("UIStroke", {
        Color = color or theme.Stroke,
        Transparency = transparency or 0.25,
        Thickness = 1,
    })
end

function UI:MakeDraggable(handle, frame)
    local dragging = false
    local dragStart
    local startPosition

    Hub.Maid:Give(handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        dragging = true
        dragStart = input.Position
        startPosition = frame.Position

        Hub.Maid:Give(input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end))
    end))

    Hub.Maid:Give(UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end))
end

function UI:CreateWindow()
    destroyExistingGui()

    local gui = newInstance("ScreenGui", {
        Name = HUB_NAME,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
    })
    gui.Parent = safeParent()
    Hub.Runtime.Gui = gui
    Hub.Maid:Give(gui)

    local window = newInstance("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(620, 440),
        Parent = gui,
    }, {
        self:Corner(8),
        self:Stroke(Color3.fromRGB(69, 78, 91), 0.1),
    })

    local titleBar = newInstance("Frame", {
        Name = "TitleBar",
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 44),
        Parent = window,
    }, {
        self:Corner(8),
    })

    newInstance("Frame", {
        Name = "TitleBarBottomMask",
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -8),
        Size = UDim2.new(1, 0, 0, 8),
        Parent = titleBar,
    })

    local title = newInstance("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -180, 1, 0),
        Text = "catboy hub / Type Soul",
        Parent = titleBar,
    })
    self:StyleText(title, 15, theme.Text)
    title.Font = Enum.Font.GothamSemibold

    local version = newInstance("TextLabel", {
        Name = "Version",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 0),
        Size = UDim2.fromOffset(150, 44),
        Text = "v" .. VERSION .. "  |  RightShift",
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = titleBar,
    })
    self:StyleText(version, 12, theme.Muted)
    version.TextXAlignment = Enum.TextXAlignment.Right

    local sideBar = newInstance("Frame", {
        Name = "Tabs",
        BackgroundColor3 = Color3.fromRGB(17, 19, 23),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 44),
        Size = UDim2.new(0, 146, 1, -44),
        Parent = window,
    })

    newInstance("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = sideBar,
    })

    newInstance("UIPadding", {
        PaddingTop = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = sideBar,
    })

    local content = newInstance("Frame", {
        Name = "Content",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(146, 44),
        Size = UDim2.new(1, -146, 1, -44),
        Parent = window,
    })

    local statusBar = newInstance("Frame", {
        Name = "StatusBar",
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 146, 1, -32),
        Size = UDim2.new(1, -146, 0, 32),
        Parent = window,
    })

    Hub.Runtime.StatusLabel = newInstance("TextLabel", {
        Name = "Status",
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = "Loaded. Toggle features from the left tabs.",
        Parent = statusBar,
    })
    self:StyleText(Hub.Runtime.StatusLabel, 12, theme.Muted)

    self.Root = window
    self.SideBar = sideBar
    self.Content = content

    self:MakeDraggable(titleBar, window)

    Hub.Maid:Give(UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        if input.KeyCode == Enum.KeyCode.RightShift then
            gui.Enabled = not gui.Enabled
        end
    end))

    return window
end

function UI:AddTab(name)
    local button = newInstance("TextButton", {
        Name = name .. "Tab",
        AutoButtonColor = false,
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 34),
        Text = name,
        Parent = self.SideBar,
    }, {
        self:Corner(6),
    })
    self:StyleText(button, 13, theme.Muted)
    button.TextXAlignment = Enum.TextXAlignment.Left

    newInstance("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        Parent = button,
    })

    local page = newInstance("ScrollingFrame", {
        Name = name .. "Page",
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Position = UDim2.fromOffset(16, 14),
        ScrollBarImageColor3 = theme.Stroke,
        ScrollBarThickness = 4,
        Size = UDim2.new(1, -32, 1, -60),
        Visible = false,
        Parent = self.Content,
    })

    newInstance("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = page,
    })

    local tab = {
        Name = name,
        Button = button,
        Page = page,
    }

    table.insert(self.Tabs, tab)
    self.Pages[name] = page

    Hub.Maid:Give(button.MouseButton1Click:Connect(function()
        self:SelectTab(name)
    end))

    if #self.Tabs == 1 then
        self:SelectTab(name)
    end

    return page
end

function UI:SelectTab(name)
    for _, tab in ipairs(self.Tabs) do
        local selected = tab.Name == name
        tab.Page.Visible = selected
        tab.Button.BackgroundColor3 = selected and theme.AccentDark or theme.Panel
        tab.Button.TextColor3 = selected and theme.Text or theme.Muted
    end
end

function UI:AddSection(page, titleText)
    local section = newInstance("Frame", {
        Name = titleText:gsub("%s+", "") .. "Section",
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -4, 0, 0),
        Parent = page,
    }, {
        self:Corner(7),
        self:Stroke(theme.Stroke, 0.45),
    })

    newInstance("UIPadding", {
        PaddingTop = UDim.new(0, 12),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        Parent = section,
    })

    newInstance("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = section,
    })

    local title = newInstance("TextLabel", {
        Name = "SectionTitle",
        Size = UDim2.new(1, 0, 0, 18),
        Text = titleText,
        Parent = section,
    })
    self:StyleText(title, 13, theme.Text)
    title.Font = Enum.Font.GothamSemibold

    return section
end

function UI:AddLabel(section, text)
    local label = newInstance("TextLabel", {
        Name = "Label",
        Size = UDim2.new(1, 0, 0, 18),
        Text = text,
        Parent = section,
    })
    self:StyleText(label, 12, theme.Muted)
    return label
end

function UI:AddButton(section, data)
    local button = newInstance("TextButton", {
        Name = data.Flag or data.Text,
        AutoButtonColor = false,
        BackgroundColor3 = theme.PanelLight,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 34),
        Text = data.Text,
        Parent = section,
    }, {
        self:Corner(6),
        self:Stroke(theme.Stroke, 0.55),
    })
    self:StyleText(button, 13, theme.Text)
    button.Font = Enum.Font.GothamMedium
    button.TextXAlignment = Enum.TextXAlignment.Center

    Hub.Maid:Give(button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(39, 45, 54) }):Play()
    end))

    Hub.Maid:Give(button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = theme.PanelLight }):Play()
    end))

    Hub.Maid:Give(button.MouseButton1Click:Connect(function()
        if data.Callback then
            data.Callback()
        end
    end))

    return button
end

function UI:AddToggle(section, data)
    Hub.Flags[data.Flag] = data.Default == true

    local row = newInstance("Frame", {
        Name = data.Flag,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 32),
        Parent = section,
    })

    local label = newInstance("TextLabel", {
        Name = "Label",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, -58, 1, 0),
        Text = data.Text,
        Parent = row,
    })
    self:StyleText(label, 13, theme.Text)

    local button = newInstance("TextButton", {
        Name = "Toggle",
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = theme.PanelLight,
        BorderSizePixel = 0,
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(46, 24),
        Text = "",
        Parent = row,
    }, {
        self:Corner(12),
        self:Stroke(theme.Stroke, 0.55),
    })

    local knob = newInstance("Frame", {
        Name = "Knob",
        BackgroundColor3 = theme.Muted,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.fromOffset(16, 16),
        Parent = button,
    }, {
        self:Corner(8),
    })

    local function render()
        local enabled = Hub.Flags[data.Flag] == true
        button.BackgroundColor3 = enabled and theme.AccentDark or theme.PanelLight
        knob.BackgroundColor3 = enabled and theme.Good or theme.Muted
        TweenService:Create(knob, TweenInfo.new(0.12), {
            Position = enabled and UDim2.fromOffset(26, 4) or UDim2.fromOffset(4, 4),
        }):Play()
    end

    local function set(value)
        Hub.Flags[data.Flag] = value == true
        render()
        if data.Callback then
            data.Callback(Hub.Flags[data.Flag])
        end
    end

    Hub.Maid:Give(button.MouseButton1Click:Connect(function()
        set(not Hub.Flags[data.Flag])
    end))

    render()

    local control = { Set = set }
    self.Controls[data.Flag] = control
    return control
end

function UI:AddSlider(section, data)
    Hub.Flags[data.Flag] = data.Default or data.Min or 0

    local row = newInstance("Frame", {
        Name = data.Flag,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 48),
        Parent = section,
    })

    local label = newInstance("TextLabel", {
        Name = "Label",
        Size = UDim2.new(1, -90, 0, 18),
        Text = data.Text,
        Parent = row,
    })
    self:StyleText(label, 12, theme.Text)

    local valueLabel = newInstance("TextLabel", {
        Name = "Value",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(88, 18),
        Text = "",
        Parent = row,
    })
    self:StyleText(valueLabel, 12, theme.Muted)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right

    local track = newInstance("TextButton", {
        Name = "Track",
        AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(13, 15, 18),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 27),
        Size = UDim2.new(1, 0, 0, 8),
        Text = "",
        Parent = row,
    }, {
        self:Corner(4),
    })

    local fill = newInstance("Frame", {
        Name = "Fill",
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
        Parent = track,
    }, {
        self:Corner(4),
    })

    local dragging = false

    local function formatValue(value)
        local suffix = data.Suffix or ""
        if data.Increment and data.Increment < 1 then
            local formatted = string.format("%.2f", value)
            formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
            return formatted .. suffix
        end
        return tostring(math.floor(value + 0.5)) .. suffix
    end

    local function render()
        local minValue = data.Min or 0
        local maxValue = data.Max or 100
        local value = clamp(Hub.Flags[data.Flag], minValue, maxValue)
        local percent = (value - minValue) / (maxValue - minValue)
        fill.Size = UDim2.new(percent, 0, 1, 0)
        valueLabel.Text = formatValue(value)
    end

    local function setFromX(x)
        local absoluteX = track.AbsolutePosition.X
        local width = math.max(track.AbsoluteSize.X, 1)
        local percent = clamp((x - absoluteX) / width, 0, 1)
        local value = (data.Min or 0) + ((data.Max or 100) - (data.Min or 0)) * percent
        value = round(value, data.Increment or 1)
        value = clamp(value, data.Min or 0, data.Max or 100)

        if Hub.Flags[data.Flag] ~= value then
            Hub.Flags[data.Flag] = value
            render()
            if data.Callback then
                data.Callback(value)
            end
        else
            render()
        end
    end

    Hub.Maid:Give(track.MouseButton1Down:Connect(function(x)
        dragging = true
        setFromX(x)
    end))

    Hub.Maid:Give(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    Hub.Maid:Give(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end))

    render()

    local control = {
        Set = function(_, value)
            Hub.Flags[data.Flag] = clamp(round(value, data.Increment or 1), data.Min or 0, data.Max or 100)
            render()
        end,
    }
    self.Controls[data.Flag] = control
    return control
end

function UI:AddModeButtons(section, data)
    Hub.Flags[data.Flag] = data.Default or data.Values[1]

    local holder = newInstance("Frame", {
        Name = data.Flag,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 58),
        Parent = section,
    })

    local label = newInstance("TextLabel", {
        Name = "Label",
        Size = UDim2.new(1, 0, 0, 18),
        Text = data.Text,
        Parent = holder,
    })
    self:StyleText(label, 12, theme.Text)

    local buttons = newInstance("Frame", {
        Name = "Buttons",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 26),
        Size = UDim2.new(1, 0, 0, 28),
        Parent = holder,
    })

    newInstance("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = buttons,
    })

    local renderedButtons = {}

    local function render()
        for value, button in pairs(renderedButtons) do
            local selected = Hub.Flags[data.Flag] == value
            button.BackgroundColor3 = selected and theme.AccentDark or theme.PanelLight
            button.TextColor3 = selected and theme.Text or theme.Muted
        end
    end

    for _, value in ipairs(data.Values) do
        local button = newInstance("TextButton", {
            Name = value,
            AutoButtonColor = false,
            BackgroundColor3 = theme.PanelLight,
            BorderSizePixel = 0,
            Size = UDim2.new(1 / #data.Values, -6, 1, 0),
            Text = value,
            Parent = buttons,
        }, {
            self:Corner(6),
            self:Stroke(theme.Stroke, 0.55),
        })
        self:StyleText(button, 12, theme.Muted)
        button.Font = Enum.Font.GothamMedium
        button.TextXAlignment = Enum.TextXAlignment.Center

        renderedButtons[value] = button

        Hub.Maid:Give(button.MouseButton1Click:Connect(function()
            Hub.Flags[data.Flag] = value
            render()
            if data.Callback then
                data.Callback(value)
            end
        end))
    end

    render()
end

local function getCharacterParts(player)
    local character = player and player.Character
    if not character then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then
        return nil, nil, nil
    end

    return character, humanoid, rootPart
end

local function getEntitiesFolder()
    return workspace:FindFirstChild("Entities") or workspace:FindFirstChild("Living") or workspace:FindFirstChild("Characters")
end

local function getEntityForPlayer(player)
    local entities = getEntitiesFolder()
    if not entities or not player then
        return nil
    end

    return entities:FindFirstChild(player.Name)
end

local function readState(model)
    if not model then
        return "none"
    end

    local attributes = { "CurrentState", "State", "Action", "Status" }
    for _, attribute in ipairs(attributes) do
        local value = model:GetAttribute(attribute)
        if value ~= nil then
            return tostring(value)
        end
    end

    local stateValue = model:FindFirstChild("CurrentState") or model:FindFirstChild("State")
    if stateValue and stateValue:IsA("ValueBase") then
        return tostring(stateValue.Value)
    end

    return "none"
end

local function resolveEnemyParts(enemyEntity)
    if not enemyEntity or not enemyEntity:IsA("Model") then
        return nil, nil, nil, nil
    end

    local enemyPlayer = Players:FindFirstChild(enemyEntity.Name)
    local character = enemyPlayer and enemyPlayer.Character or enemyEntity
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not rootPart then
        humanoid = enemyEntity:FindFirstChildOfClass("Humanoid")
        rootPart = enemyEntity:FindFirstChild("HumanoidRootPart")
        character = enemyEntity
    end

    if not humanoid or not rootPart then
        return nil, nil, nil, nil
    end

    return enemyPlayer, character, humanoid, rootPart
end

local function isFacingMe(enemyRootPart, myRootPart)
    local toMe = myRootPart.Position - enemyRootPart.Position
    if toMe.Magnitude <= 0 then
        return false
    end

    return enemyRootPart.CFrame.LookVector:Dot(toMe.Unit) >= Hub.Flags.AutoParryFacingDot
end

local function getPingSeconds()
    local ok, ping = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)

    if not ok or type(ping) ~= "number" then
        return 0
    end

    return clamp(ping / 1000, 0, 0.35)
end

local function classifyText(text)
    text = string.lower(tostring(text or ""))

    if text == "" or text == "none" then
        return nil
    end

    if string.find(text, "bankai", 1, true)
        or string.find(text, "shikai", 1, true)
        or string.find(text, "skill", 1, true)
        or string.find(text, "kido", 1, true)
        or string.find(text, "hakuda", 1, true)
        or string.find(text, "ability", 1, true)
    then
        return "skill"
    end

    if string.find(text, "crit", 1, true)
        or string.find(text, "critical", 1, true)
        or string.find(text, "heavy", 1, true)
        or string.find(text, "m2", 1, true)
    then
        return "heavy"
    end

    if string.find(text, "m1", 1, true)
        or string.find(text, "attack", 1, true)
        or string.find(text, "swing", 1, true)
        or string.find(text, "slash", 1, true)
        or string.find(text, "punch", 1, true)
        or string.find(text, "kick", 1, true)
        or string.find(text, "combo", 1, true)
        or string.find(text, "aerial", 1, true)
    then
        return "m1"
    end

    if text == "action" or text == "attacking" then
        return "generic"
    end

    return nil
end

local function delayForThreatKind(kind)
    if kind == "skill" then
        return Hub.Flags.AutoParrySkillDelay
    elseif kind == "heavy" then
        return Hub.Flags.AutoParryHeavyDelay
    elseif kind == "m1" then
        return Hub.Flags.AutoParryM1Delay
    end

    return Hub.Flags.AutoParryGenericDelay
end

local function adjustedDelay(kind)
    local baseDelay = delayForThreatKind(kind)
    if kind == "skill" and not Hub.Flags.AutoParrySkillAssist then
        baseDelay = Hub.Flags.AutoParryGenericDelay
    end

    local pingOffset = math.min(getPingSeconds() * Hub.Flags.AutoParryPingCompensation, 0.14)
    return clamp(baseDelay + Hub.Flags.AutoParryReactionDelay - pingOffset, 0.03, 1.25)
end

local function makeThreat(kind, signature, reason)
    return {
        Kind = kind or "generic",
        Signature = tostring(signature or reason or "unknown"),
        Reason = tostring(reason or kind or "unknown"),
    }
end

local function getCustomProfile(threat)
    if not threat then
        return nil
    end

    return CustomSkillProfiles[threat.Signature]
        or CustomSkillProfiles[threat.Reason]
        or CustomSkillProfiles[threat.Kind]
end

local function delayForThreat(threat)
    local profile = getCustomProfile(threat)
    if profile and type(profile.Delay) == "number" then
        local pingOffset = math.min(getPingSeconds() * Hub.Flags.AutoParryPingCompensation, 0.14)
        return clamp(profile.Delay + Hub.Flags.AutoParryReactionDelay - pingOffset, 0.03, 1.25)
    end

    return adjustedDelay(profile and profile.Kind or threat.Kind)
end

local function trackLooksHostile(track)
    if not track or not track.IsPlaying then
        return nil
    end

    local name = string.lower(track.Name or "")
    local id = ""

    pcall(function()
        id = string.lower(track.Animation and track.Animation.AnimationId or "")
    end)

    local textKind = classifyText(name) or classifyText(id)
    if textKind then
        local signature = id ~= "" and id or name
        return makeThreat(textKind, "anim:" .. signature, signature)
    end

    if string.find(tostring(track.Priority), "Action", 1, true) then
        local timePosition = tonumber(track.TimePosition) or 0
        local length = tonumber(track.Length) or 0
        if timePosition <= Hub.Flags.AutoParryAnimationWindow and length > 0.18 then
            local signature = id ~= "" and id or (track.Name ~= "" and track.Name or tostring(track.Priority))
            local kind = length >= 0.55 and "skill" or "generic"
            return makeThreat(kind, "priority:" .. signature, signature)
        end
    end

    return nil
end

local function isEnemyAttacking(character, entity)
    local state = readState(entity)
    local stateKind = classifyText(state)
    if stateKind then
        return makeThreat(stateKind, "state:" .. state, "state:" .. state)
    elseif attackStates[state] then
        return makeThreat("generic", "state:" .. state, "state:" .. state)
    end

    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        return nil
    end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local threat = trackLooksHostile(track)
        if threat then
            if threat.Signature and not Hub.Runtime.KnownAttackTracks[threat.Signature] then
                Hub.Runtime.KnownAttackTracks[threat.Signature] = true
                debugPrint("detected hostile animation", threat.Signature, "kind", threat.Kind)
            end
            return threat
        end
    end

    return nil
end

local function canAct()
    local _, humanoid = getCharacterParts(LocalPlayer)
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    local entity = getEntityForPlayer(LocalPlayer)
    local state = readState(entity)
    if unsafeParryStates[state] then
        return false
    end

    return true
end

local function pressKey(keyCode, duration)
    duration = duration or 0.035

    local usedVirtualInput = pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(duration)
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)

    if not usedVirtualInput and keypress and keyrelease then
        pcall(function()
            keypress(keyCode.Value)
            task.wait(duration)
            keyrelease(keyCode.Value)
        end)
    end
end

local function validateThreat(targetName, memory)
    local _, _, myRootPart = getCharacterParts(LocalPlayer)
    if not myRootPart then
        return false
    end

    local entities = getEntitiesFolder()
    local enemyEntity = entities and entities:FindFirstChild(targetName)
    local _, _, enemyHumanoid, enemyRootPart = resolveEnemyParts(enemyEntity)
    if not enemyHumanoid or enemyHumanoid.Health <= 0 or not enemyRootPart then
        return false
    end

    local distance = (enemyRootPart.Position - myRootPart.Position).Magnitude
    local allowedRange = memory.RangeOverride or Hub.Flags.AutoParryRange
    if distance > allowedRange + 4 then
        return false
    end

    if memory.RequireFacing and not isFacingMe(enemyRootPart, myRootPart) and distance > math.max(7, allowedRange * 0.45) then
        return false
    end

    return true, distance
end

local function scheduleParry(threat)
    local now = os.clock()
    local memory = Hub.Runtime.ThreatMemory[threat.TargetName]

    if not memory
        or memory.Signature ~= threat.Signature
        or now - memory.LastSeen > Hub.Flags.AutoParryThreatReset
    then
        local profile = getCustomProfile(threat)
        local requireFacing = threat.RequireFacing
        if profile and profile.RequireFacing ~= nil then
            requireFacing = profile.RequireFacing
        end

        memory = {
            Signature = threat.Signature,
            Kind = profile and profile.Kind or threat.Kind,
            Reason = threat.Reason,
            FirstSeen = now,
            LastSeen = now,
            Distance = threat.Distance,
            Scheduled = false,
            Consumed = false,
            RequireFacing = requireFacing,
            RangeOverride = profile and profile.Range or nil,
        }
        Hub.Runtime.ThreatMemory[threat.TargetName] = memory
        debugPrint("armed threat", threat.TargetName, memory.Kind, threat.Signature, "delay", delayForThreat(threat))
    else
        local profile = getCustomProfile(threat)
        memory.LastSeen = now
        memory.Distance = threat.Distance
        if profile and profile.RequireFacing ~= nil then
            memory.RequireFacing = profile.RequireFacing
        else
            memory.RequireFacing = threat.RequireFacing
        end
    end

    if memory.Scheduled or memory.Consumed then
        return
    end

    if memory.LastAttempt and now - memory.LastAttempt < Hub.Flags.AutoParryMissLockout then
        return
    end

    local cooldownRemaining = math.max(0, Hub.Flags.AutoParryCooldown - (now - Hub.Runtime.LastParry))
    local parryDelay = math.max(delayForThreat(threat), cooldownRemaining)
    memory.Scheduled = true

    task.spawn(function()
        task.wait(parryDelay)

        local liveMemory = Hub.Runtime.ThreatMemory[threat.TargetName]
        if not liveMemory or liveMemory.Signature ~= threat.Signature or liveMemory.Consumed then
            return
        end

        liveMemory.Scheduled = false
        liveMemory.Consumed = true
        liveMemory.LastAttempt = os.clock()

        if not Hub.Flags.AutoParry or not canAct() then
            debugPrint("parry skipped", threat.TargetName, threat.Signature, "not actionable")
            return
        end

        if os.clock() - Hub.Runtime.LastParry < Hub.Flags.AutoParryCooldown then
            debugPrint("parry skipped", threat.TargetName, threat.Signature, "global cooldown")
            return
        end

        local valid, liveDistance = validateThreat(threat.TargetName, liveMemory)
        if valid then
            Hub.Runtime.LastParry = os.clock()
            pressKey(DEFAULT_PARRY_KEY, 0.04)
            local line = string.format(
                "Auto Parry fired -> %s (%.1f studs, %s)",
                threat.TargetName,
                liveDistance or threat.Distance,
                threat.Reason
            )
            Hub.Runtime.LastThreat = line
            setStatus(line)
            debugPrint(line)
        else
            debugPrint("parry skipped", threat.TargetName, threat.Signature, "threat expired")
        end
    end)
end

local Combat = {}

function Combat:Stop()
    if Hub.Runtime.AutoParryConnection then
        Hub.Runtime.AutoParryConnection:Disconnect()
        Hub.Runtime.AutoParryConnection = nil
    end
    Hub.Runtime.PendingParry = false
    Hub.Runtime.ThreatMemory = {}
end

function Combat:Start()
    self:Stop()

    Hub.Runtime.AutoParryConnection = RunService.Heartbeat:Connect(function()
        if not Hub.Flags.AutoParry or not canAct() then
            return
        end

        local _, _, myRootPart = getCharacterParts(LocalPlayer)
        local entities = getEntitiesFolder()
        if not myRootPart or not entities then
            return
        end

        local closestThreat = nil
        local closestDistance = math.huge

        for _, enemyEntity in ipairs(entities:GetChildren()) do
            if enemyEntity.Name ~= LocalPlayer.Name then
                local _, enemyCharacter, enemyHumanoid, enemyRootPart = resolveEnemyParts(enemyEntity)
                if enemyCharacter and enemyHumanoid and enemyHumanoid.Health > 0 and enemyRootPart then
                    local distance = (enemyRootPart.Position - myRootPart.Position).Magnitude
                    if distance <= Hub.Flags.AutoParryRange and distance < closestDistance then
                        local threat = isEnemyAttacking(enemyCharacter, enemyEntity)
                        local facing = isFacingMe(enemyRootPart, myRootPart)
                        local closePressure = distance <= math.max(7, Hub.Flags.AutoParryRange * 0.45)

                        if threat and (facing or closePressure) then
                            threat.TargetName = enemyEntity.Name
                            threat.Distance = distance
                            threat.RequireFacing = not closePressure
                            closestThreat = threat
                            closestDistance = distance
                        end
                    end
                end
            end
        end

        if closestThreat then
            scheduleParry(closestThreat)
        end

        local now = os.clock()
        for targetName, memory in pairs(Hub.Runtime.ThreatMemory) do
            if now - memory.LastSeen > Hub.Flags.AutoParryThreatReset then
                Hub.Runtime.ThreatMemory[targetName] = nil
                debugPrint("cleared threat", targetName, memory.Signature)
            end
        end
    end)

    Hub.Maid:Give(Hub.Runtime.AutoParryConnection)
    setStatus("Auto Parry enabled. Waiting for threats.")
    debugPrint("auto parry loop started")
end

local Movement = {}

local function currentDesiredSpeed(humanoid, entity)
    local state = readState(entity)
    Hub.Runtime.LastMovementState = state

    if movementBlockedStates[state] then
        return nil, state
    end

    if Hub.Flags.FlashstepEnabled and state == "Flashstep" then
        return Hub.Flags.FlashstepSpeed, state
    end

    if state == "Sprinting" or state == "Running" or state == "Run" then
        return Hub.Flags.SprintSpeed, state
    end

    if humanoid.MoveDirection.Magnitude > 0.05 and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
        return Hub.Flags.SprintSpeed, state
    end

    if state == "WeaponDrawn" or state == "WeaponEquipped" or state == "Combat" then
        return Hub.Flags.WeaponDrawnSpeed, state
    end

    return Hub.Flags.WalkSpeed, state
end

local function writeEntitySpeed(entity, speed)
    if not entity then
        return
    end

    local attributes = {
        "BaseWalkspeed",
        "BaseWalkSpeed",
        "Walkspeed",
        "WalkSpeed",
        "Speed",
    }

    for _, attribute in ipairs(attributes) do
        pcall(function()
            if entity:GetAttribute(attribute) ~= nil then
                entity:SetAttribute(attribute, speed)
            end
        end)
    end
end

local function applyVelocityAssist(humanoid, rootPart, speed)
    if not Hub.Flags.VelocityAssist then
        return
    end

    local mode = Hub.Flags.MovementMode
    if mode ~= "Velocity" and mode ~= "Hybrid" then
        return
    end

    local direction = humanoid.MoveDirection
    if direction.Magnitude <= 0.05 then
        return
    end

    local currentVelocity = rootPart.AssemblyLinearVelocity
    local targetHorizontal = direction.Unit * speed * Hub.Flags.VelocityMultiplier
    rootPart.AssemblyLinearVelocity = Vector3.new(targetHorizontal.X, currentVelocity.Y, targetHorizontal.Z)
end

function Movement:Stop()
    if Hub.Runtime.MovementConnection then
        Hub.Runtime.MovementConnection:Disconnect()
        Hub.Runtime.MovementConnection = nil
    end
end

function Movement:Start()
    self:Stop()

    Hub.Runtime.MovementConnection = RunService.Heartbeat:Connect(function()
        if not Hub.Flags.MovementEnabled then
            return
        end

        local _, humanoid, rootPart = getCharacterParts(LocalPlayer)
        local entity = getEntityForPlayer(LocalPlayer)
        if not humanoid or not rootPart then
            return
        end

        local speed, state = currentDesiredSpeed(humanoid, entity)
        if not speed then
            return
        end

        local mode = Hub.Flags.MovementMode
        if mode == "WalkSpeed" or mode == "Hybrid" then
            if math.abs(humanoid.WalkSpeed - speed) > 0.1 then
                humanoid.WalkSpeed = speed
            end
            writeEntitySpeed(entity, speed)
        end

        applyVelocityAssist(humanoid, rootPart, speed)

        if Hub.Flags.Debug and state ~= Hub.Runtime.LastDebugMovementState then
            Hub.Runtime.LastDebugMovementState = state
            debugPrint("movement state", state, "speed", speed, "mode", mode)
        end
    end)

    Hub.Maid:Give(Hub.Runtime.MovementConnection)
    setStatus("Movement enabled. Mode: " .. Hub.Flags.MovementMode)
    debugPrint("movement loop started")
end

local function buildInterface()
    UI:CreateWindow()

    local combatPage = UI:AddTab("Combat")
    local movementPage = UI:AddTab("Movement")
    local utilityPage = UI:AddTab("Utility")

    local parrySection = UI:AddSection(combatPage, "Auto Parry")
    UI:AddToggle(parrySection, {
        Text = "Auto Parry",
        Flag = "AutoParry",
        Default = false,
        Callback = function(enabled)
            if enabled then
                Combat:Start()
            else
                Combat:Stop()
                setStatus("Auto Parry disabled.")
                debugPrint("auto parry loop stopped")
            end
        end,
    })

    UI:AddSlider(parrySection, {
        Text = "Detection Range",
        Flag = "AutoParryRange",
        Default = Hub.Flags.AutoParryRange,
        Min = 6,
        Max = 40,
        Increment = 1,
        Suffix = " st",
    })

    UI:AddSlider(parrySection, {
        Text = "Reaction Delay",
        Flag = "AutoParryReactionDelay",
        Default = Hub.Flags.AutoParryReactionDelay,
        Min = 0,
        Max = 0.25,
        Increment = 0.01,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "M1 Timing",
        Flag = "AutoParryM1Delay",
        Default = Hub.Flags.AutoParryM1Delay,
        Min = 0.05,
        Max = 0.45,
        Increment = 0.01,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "Heavy Timing",
        Flag = "AutoParryHeavyDelay",
        Default = Hub.Flags.AutoParryHeavyDelay,
        Min = 0.08,
        Max = 0.7,
        Increment = 0.01,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "Skill Timing",
        Flag = "AutoParrySkillDelay",
        Default = Hub.Flags.AutoParrySkillDelay,
        Min = 0.12,
        Max = 1,
        Increment = 0.01,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "Generic Timing",
        Flag = "AutoParryGenericDelay",
        Default = Hub.Flags.AutoParryGenericDelay,
        Min = 0.08,
        Max = 0.8,
        Increment = 0.01,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "Global Cooldown",
        Flag = "AutoParryCooldown",
        Default = Hub.Flags.AutoParryCooldown,
        Min = 0.25,
        Max = 1.5,
        Increment = 0.05,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "Animation Window",
        Flag = "AutoParryAnimationWindow",
        Default = Hub.Flags.AutoParryAnimationWindow,
        Min = 0.1,
        Max = 1.2,
        Increment = 0.05,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "Ping Compensation",
        Flag = "AutoParryPingCompensation",
        Default = Hub.Flags.AutoParryPingCompensation,
        Min = 0,
        Max = 1,
        Increment = 0.05,
    })

    UI:AddSlider(parrySection, {
        Text = "Miss Lockout",
        Flag = "AutoParryMissLockout",
        Default = Hub.Flags.AutoParryMissLockout,
        Min = 0.3,
        Max = 2,
        Increment = 0.05,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "Threat Reset",
        Flag = "AutoParryThreatReset",
        Default = Hub.Flags.AutoParryThreatReset,
        Min = 0.35,
        Max = 2,
        Increment = 0.05,
        Suffix = "s",
    })

    UI:AddSlider(parrySection, {
        Text = "Facing Strictness",
        Flag = "AutoParryFacingDot",
        Default = Hub.Flags.AutoParryFacingDot,
        Min = -0.2,
        Max = 0.85,
        Increment = 0.05,
    })

    UI:AddToggle(parrySection, {
        Text = "Skill Timing Assist",
        Flag = "AutoParrySkillAssist",
        Default = true,
    })

    local parryInfo = UI:AddSection(combatPage, "Live Readout")
    UI:AddLabel(parryInfo, "Auto Parry arms each enemy attack once, waits for its timing window, then consumes it.")
    UI:AddLabel(parryInfo, "Turn on Debug in Utility to record detected states, animations, and skipped parries.")

    local moveSection = UI:AddSection(movementPage, "Speed Control")
    UI:AddToggle(moveSection, {
        Text = "Movement Enabled",
        Flag = "MovementEnabled",
        Default = false,
        Callback = function(enabled)
            if enabled then
                Movement:Start()
            else
                Movement:Stop()
                setStatus("Movement disabled.")
                debugPrint("movement loop stopped")
            end
        end,
    })

    UI:AddModeButtons(moveSection, {
        Text = "Movement Mode",
        Flag = "MovementMode",
        Default = Hub.Flags.MovementMode,
        Values = { "Hybrid", "WalkSpeed", "Velocity" },
        Callback = function(mode)
            setStatus("Movement mode set to " .. mode)
        end,
    })

    UI:AddSlider(moveSection, {
        Text = "Base Speed",
        Flag = "WalkSpeed",
        Default = Hub.Flags.WalkSpeed,
        Min = 16,
        Max = 70,
        Increment = 1,
    })

    UI:AddSlider(moveSection, {
        Text = "Sprint Speed",
        Flag = "SprintSpeed",
        Default = Hub.Flags.SprintSpeed,
        Min = 16,
        Max = 90,
        Increment = 1,
    })

    UI:AddSlider(moveSection, {
        Text = "Weapon Drawn Speed",
        Flag = "WeaponDrawnSpeed",
        Default = Hub.Flags.WeaponDrawnSpeed,
        Min = 16,
        Max = 80,
        Increment = 1,
    })

    UI:AddToggle(moveSection, {
        Text = "Flashstep Override",
        Flag = "FlashstepEnabled",
        Default = true,
    })

    UI:AddSlider(moveSection, {
        Text = "Flashstep Speed",
        Flag = "FlashstepSpeed",
        Default = Hub.Flags.FlashstepSpeed,
        Min = 40,
        Max = 240,
        Increment = 5,
    })

    local velocitySection = UI:AddSection(movementPage, "Reliability")
    UI:AddToggle(velocitySection, {
        Text = "Velocity Assist",
        Flag = "VelocityAssist",
        Default = true,
    })

    UI:AddSlider(velocitySection, {
        Text = "Velocity Multiplier",
        Flag = "VelocityMultiplier",
        Default = Hub.Flags.VelocityMultiplier,
        Min = 0.8,
        Max = 2,
        Increment = 0.05,
    })

    UI:AddLabel(velocitySection, "Hybrid mode enforces Humanoid speed and applies light velocity assist while moving.")
    UI:AddLabel(velocitySection, "Use WalkSpeed mode if velocity correction feels too strong in live servers.")

    local debugSection = UI:AddSection(utilityPage, "Debug")
    UI:AddToggle(debugSection, {
        Text = "Debug Output",
        Flag = "Debug",
        Default = false,
        Callback = function(enabled)
            setStatus(enabled and "Debug output enabled." or "Debug output disabled.")
        end,
    })

    UI:AddButton(debugSection, {
        Text = "Print Runtime Snapshot",
        Callback = function()
            local entity = getEntityForPlayer(LocalPlayer)
            local _, humanoid = getCharacterParts(LocalPlayer)
            local state = readState(entity)
            local activeThreats = 0
            for _ in pairs(Hub.Runtime.ThreatMemory) do
                activeThreats += 1
            end
            debugPrint(
                "snapshot state=", state,
                "walkspeed=", humanoid and humanoid.WalkSpeed or "nil",
                "ping=", string.format("%.0fms", getPingSeconds() * 1000),
                "activeThreats=", activeThreats,
                "lastThreat=", Hub.Runtime.LastThreat
            )
            setStatus("Snapshot printed to console.")
        end,
    })

    local sessionSection = UI:AddSection(utilityPage, "Session")
    UI:AddButton(sessionSection, {
        Text = "Rejoin Server",
        Callback = function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end,
    })

    UI:AddButton(sessionSection, {
        Text = "Unload Hub",
        Callback = function()
            Combat:Stop()
            Movement:Stop()
            Hub.Maid:Cleanup()
            getgenv().CatboyHubTypeSoul = nil
        end,
    })
end

local function attachRespawnHooks()
    Hub.Maid:Give(LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        debugPrint("character respawned; active loops will re-read character parts")

        if Hub.Flags.AutoParry and not Hub.Runtime.AutoParryConnection then
            Combat:Start()
        end

        if Hub.Flags.MovementEnabled and not Hub.Runtime.MovementConnection then
            Movement:Start()
        end
    end))
end

if getgenv().CatboyHubTypeSoul and getgenv().CatboyHubTypeSoul.Unload then
    pcall(function()
        getgenv().CatboyHubTypeSoul.Unload()
    end)
end

function Hub.Unload()
    Combat:Stop()
    Movement:Stop()
    Hub.Maid:Cleanup()
    getgenv().CatboyHubTypeSoul = nil
end

getgenv().CatboyHubTypeSoul = Hub

buildInterface()
attachRespawnHooks()
notify("catboy hub", "Type Soul rewrite loaded", 4)
setStatus("Loaded. RightShift toggles the UI.")

return Hub
