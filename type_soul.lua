
getgenv().Config = {
    Invite = "discord.gg/Bg2afYsD",
    Version = "0.0",
}

getgenv().luaguardvars = {
    DiscordName = "cashfears",
}

local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/bothimee/testsoul/main/source"))()
library:init()

local Window = library.NewWindow({
    title = "catboy hub :3",
    size = UDim2.new(0, 525, 0, 650)
})

local tabs = {
    Tab1 = Window:AddTab("Tab1"),
    Settings = library:CreateSettingsTab(Window),
}

local sections = {
    Section1 = tabs.Tab1:AddSection("Section1", 1),
    Section2 = tabs.Tab1:AddSection("Section2", 2),
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local localPlayer = Players.LocalPlayer
local autoParryConnection
local autoParryCharacterConnection
local lastParryTime = 0

local attackStateLookup = {
    Action = true,
    Skill = true,
    ShikaiSkill = true,
    BankaiSkill = true,
    WeaponDrawn = false,
}

local attackAnimationKeywords = {
    "attack",
    "swing",
    "slash",
    "m1",
    "punch",
    "kick",
    "heavy",
    "feint",
    "crit",
    "uppercut",
    "skill",
}

local unsafeLocalStates = {
    PostureBroken = true,
    TrueStunned = true,
    Flashstep = true,
}

local function getCharacterParts(player)
    local character = player.Character
    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not rootPart then
        return nil
    end

    return character, humanoid, rootPart
end

local function getEntityForPlayer(player)
    local entities = workspace:FindFirstChild("Entities")
    if not entities then
        return nil
    end

    return entities:FindFirstChild(player.Name)
end

local function isEnemyAttacking(enemyCharacter, enemyEntity)
    if enemyEntity then
        local currentState = enemyEntity:GetAttribute("CurrentState")
        if attackStateLookup[currentState] then
            return true
        end
    end

    local humanoid = enemyCharacter and enemyCharacter:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        return false
    end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local name = string.lower(track.Name or "")
        local animation = track.Animation
        local animationId = animation and string.lower(animation.AnimationId or "") or ""

        for _, keyword in ipairs(attackAnimationKeywords) do
            if string.find(name, keyword, 1, true) or string.find(animationId, keyword, 1, true) then
                return true
            end
        end
    end

    return false
end

local function pressParryKey(keyCode)
    if not keyCode then
        return
    end

    local success = pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.03)
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)

    if not success then
        if keypress and keyrelease then
            keypress(keyCode.Value)
            task.wait(0.03)
            keyrelease(keyCode.Value)
        end
    end
end

local function shouldAutoParry()
    if not library.flags["Auto_Parry"] then
        return false
    end

    local _, humanoid = getCharacterParts(localPlayer)
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    local myEntity = getEntityForPlayer(localPlayer)
    if myEntity then
        local currentState = myEntity:GetAttribute("CurrentState")
        if unsafeLocalStates[currentState] then
            return false
        end
    end

    return true
end

local function startAutoParry()
    if autoParryConnection then
        autoParryConnection:Disconnect()
    end

    autoParryConnection = RunService.Heartbeat:Connect(function()
        if not shouldAutoParry() then
            return
        end

        local _, _, myRootPart = getCharacterParts(localPlayer)
        if not myRootPart then
            return
        end

        local entities = workspace:FindFirstChild("Entities")
        if not entities then
            return
        end

        local range = library.flags["Auto_Parry_Range"] or 18
        local cooldown = library.flags["Auto_Parry_Cooldown"] or 0.35

        if os.clock() - lastParryTime < cooldown then
            return
        end

        for _, enemyEntity in ipairs(entities:GetChildren()) do
            if enemyEntity.Name ~= localPlayer.Name then
                local enemyPlayer = Players:FindFirstChild(enemyEntity.Name)
                if enemyPlayer then
                    local enemyCharacter, enemyHumanoid, enemyRootPart = getCharacterParts(enemyPlayer)
                    if enemyCharacter and enemyHumanoid and enemyHumanoid.Health > 0 and enemyRootPart then
                        local distance = (enemyRootPart.Position - myRootPart.Position).Magnitude
                        if distance <= range and isEnemyAttacking(enemyCharacter, enemyEntity) then
                            lastParryTime = os.clock()
                            pressParryKey(library.flags["Auto_Parry_Bind"] or Enum.KeyCode.F)
                            break
                        end
                    end
                end
            end
        end
    end)
end

local function stopAutoParry()
    if autoParryConnection then
        autoParryConnection:Disconnect()
        autoParryConnection = nil
    end
end

autoParryCharacterConnection = localPlayer.CharacterAdded:Connect(function()
    if library.flags["Auto_Parry"] then
        task.wait(1)
        startAutoParry()
    end
end)

sections.Section1:AddToggle({
    enabled = true,
    text = "Toggle1",
    flag = "Toggle_1",
    tooltip = "Tooltip1",
    risky = true,
    callback = function(lol)
        print("Toggle Is Now Set To : ".. tostring(lol))
    end
})

sections.Section1:AddToggle({
    enabled = true,
    text = "Walkspeed Legit",
    flag = "Walkspeed_Legit",
    tooltip = "Makes your sprinting and weapon walkspeed faster xd not blatant",
    risky = false,
    callback = function(lol)
        local plr = game.Players.LocalPlayer
        local conn
        local respawnConn

        local function setup()
            local char = plr.Character or plr.CharacterAdded:Wait()
            local humanoid = char:WaitForChild("Humanoid")
            local entities = workspace:WaitForChild("Entities")
            local myEntity = entities:WaitForChild(plr.Name)

            local baseWalkspeed = myEntity:GetAttribute("BaseWalkspeed") or 16

            myEntity:GetAttributeChangedSignal("BaseWalkspeed"):Connect(function()
                baseWalkspeed = myEntity:GetAttribute("BaseWalkspeed") or 16
            end)

            local function updateWalkSpeed()
                local state = myEntity:GetAttribute("CurrentState")
                if state == "Flashstep" then
                    print("Flashstep → No WalkSpeed change")
                    return
                elseif state == "Skill" then
                    print("Skill → No WalkSpeed change")
                    return
                elseif state == "PostureBroken" then
                    print("PostureBroken → No WalkSpeed change")
                    return
                elseif state == "TrueStunned" then
                    print("TrueStunned → No WalkSpeed change")
                    return
                elseif state == "ShikaiSkill" then
                    print("ShikaiSkill → No WalkSpeed change")
                    return
                elseif state == "Action" then
                    print("Action → No WalkSpeed change")
                    return
                elseif state == "Sprinting" then
                    humanoid.WalkSpeed = 25
                    print("Sprinting → WalkSpeed = 25")
                elseif state == "WeaponDrawn" then
                    humanoid.WalkSpeed = 20
                    print("WeaponDrawn → WalkSpeed = 20")
                else
                    humanoid.WalkSpeed = baseWalkspeed
                    print("Reset → WalkSpeed = " .. baseWalkspeed .. " (State: " .. tostring(state) .. ")")
                end
            end

            conn = myEntity:GetAttributeChangedSignal("CurrentState"):Connect(updateWalkSpeed)
            updateWalkSpeed()
        end

        if lol then
            setup()
            respawnConn = plr.CharacterAdded:Connect(function()
                task.wait(1)
                setup()
            end)
        else
            if conn then conn:Disconnect() end
            if respawnConn then respawnConn:Disconnect() end
            warn("Walkspeed Legit toggled OFF.")
        end
    end
})

local flashstepConn
local plr = game.Players.LocalPlayer

local function setupFlashstep()
    if flashstepConn then flashstepConn:Disconnect() end
    local char = plr.Character or plr.CharacterAdded:Wait()
    local humanoid = char:WaitForChild("Humanoid")
    local myEntity = workspace:WaitForChild("Entities"):WaitForChild(plr.Name)

    flashstepConn = myEntity:GetAttributeChangedSignal("CurrentState"):Connect(function()
        if library.flags["Flashstep_Speed"] then
            local state = myEntity:GetAttribute("CurrentState")
            if state == "Flashstep" then
                local speed = library.flags["Flashstep_Slider"] or 100
                humanoid.WalkSpeed = speed
            end
        end
    end)
end

-- Set up on load
setupFlashstep()
-- Set up on respawn
plr.CharacterAdded:Connect(function()
    task.wait(1)
    setupFlashstep()
end)

-- UI
sections.Section1:AddToggle({
    enabled = true,
    text = "Flashstep Speed",
    flag = "Flashstep_Speed",
    tooltip = "Enables Flashstep Speed Control",
    risky = true,
    callback = function() end
})

sections.Section1:AddSlider({
    text = "Flashstep Speed Slider",
    flag = "Flashstep_Slider",
    suffix = "",
    value = 100,
    min = 50,
    max = 300,
    increment = 1,
    tooltip = "Set WalkSpeed during Flashstep",
    risky = false,
    callback = function(v)
        print("Flashstep speed set to:", v)
    end
})

sections.Section1:AddSeparator({
    text = "Combat"
})

sections.Section1:AddToggle({
    enabled = false,
    text = "Auto Parry",
    flag = "Auto_Parry",
    tooltip = "Attempts to parry nearby enemy swings automatically",
    risky = true,
    callback = function(enabled)
        if enabled then
            startAutoParry()
        else
            stopAutoParry()
        end
    end
})

sections.Section1:AddSlider({
    text = "Auto Parry Range",
    flag = "Auto_Parry_Range",
    suffix = " studs",
    value = 18,
    min = 6,
    max = 35,
    increment = 1,
    tooltip = "How close an enemy must be before auto parry can trigger",
    risky = false,
    callback = function(v)
        print("Auto parry range set to:", v)
    end
})

sections.Section1:AddSlider({
    text = "Auto Parry Cooldown",
    flag = "Auto_Parry_Cooldown",
    suffix = "s",
    value = 0.35,
    min = 0.1,
    max = 1,
    increment = 0.05,
    tooltip = "Minimum delay between auto parry attempts",
    risky = false,
    callback = function(v)
        print("Auto parry cooldown set to:", v)
    end
})

sections.Section1:AddBind({
    text = "Auto Parry Key",
    flag = "Auto_Parry_Bind",
    nomouse = true,
    noindicator = true,
    tooltip = "Key the script will tap when it detects an incoming attack",
    mode = "hold",
    bind = Enum.KeyCode.F,
    risky = false,
    keycallback = function()
        print("Auto parry key changed")
    end
})


sections.Section1:AddButton({
    enabled = true,
    text = "Button1",
    flag = "Button_1",
    tooltip = "Tooltip1",
    risky = false,
    confirm = false,
    callback = function(v)
        print(v)
    end
})

sections.Section1:AddSeparator({
    text = "Misc"
})

local selectedPlaceId = nil

sections.Section1:AddButton({
    enabled = true,
    text = "Fetch Subplaces",
    flag = "Fetch_Subplaces",
    tooltip = "Get subplaces of this game",
    risky = false,
    confirm = false,
    callback = function()
        local places = {}
        local pages = game:GetService("AssetService"):GetGamePlacesAsync()
        while true do
            for _, place in pairs(pages:GetCurrentPage()) do
                table.insert(places, place.Name .. " (ID: " .. place.PlaceId .. ")")
            end
            if pages.IsFinished then break end
            pages:AdvanceToNextPageAsync()
        end
        library.flags.Place_Dropdown = nil -- reset selection
        dropdown:SetOptions(places)
    end
})

local dropdown = sections.Section1:AddList({
    text = "Select Subplace",
    flag = "Place_Dropdown",
    tooltip = "Choose a subplace to teleport to",
    values = {},
    callback = function(v)
        selectedPlaceId = v:match("ID: (%d+)")
    end
})

sections.Section1:AddButton({
    enabled = true,
    text = "Teleport to Subplace",
    flag = "Teleport_Subplace",
    tooltip = "Teleport to selected subplace",
    risky = false,
    confirm = false,
    callback = function()
        if selectedPlaceId then
            game:GetService("TeleportService"):Teleport(tonumber(selectedPlaceId), game.Players.LocalPlayer)
        else
            warn("No subplace selected!")
        end
    end
})

sections.Section1:AddButton({
    enabled = true,
    text = "Full Mode Bar [TSBG]",
    flag = "Mode_Bar",
    tooltip = "gives you full mode bar [TSBG ONLY]",
    risky = false,
    confirm = false,
    callback = function(v)
        local part = workspace:FindFirstChild("Heal Bankai Bar")
        if part then
            local clickDetector = part:FindFirstChildOfClass("ClickDetector")
            if clickDetector then
                fireclickdetector(clickDetector)
                print("Clicked Heal Bankai Bar.")
            else
                warn("No ClickDetector found in Heal Bankai Bar.")
            end
        else
            warn("Heal Bankai Bar not found in Workspace.")
        end
    end
})

sections.Section1:AddSeparator({ text = "Test" })

sections.Section1:AddSlider({
    text = "Slider", 
    flag = 'Slider_1', 
    suffix = "", 
    value = 0.000,
    min = 0.1, 
    max = 0.999,
    increment = 0.001,
    tooltip = "Tooltip1",
    risky = false,
    callback = function(v) 
        print("Slider Value Is Now : ".. v)
    end
})

sections.Section1:AddBind({
    text = "Keybind",
    flag = "Key_1",
    nomouse = true,
    noindicator = true,
    tooltip = "Tooltip1",
    mode = "toggle",
    bind = Enum.KeyCode.Q,
    risky = false,
    keycallback = function(v)
        print("Keybind Changed!")
    end
})

sections.Section1:AddList({
    enabled = true,
    text = "List",
    flag = "List_1",
    multi = false,
    tooltip = "Tooltip1",
    risky = false,
    dragging = false,
    focused = false,
    value = "1",
    values = {
        "1", "2", "3"
    },
    callback = function(v)
        print("List Value Is Now : "..v)
    end
})

sections.Section1:AddBox({
    enabled = true,
    focused = true,
    text = "TextBox1",
    input = "PlaceHolder1",
    flag = "Text_1",
    risky = false,
    callback = function(v)
        print(v)
    end
})

sections.Section1:AddText({
    enabled = true,
    text = "Text1",
    flag = "Text_1",
    risky = false,
})

sections.Section1:AddColor({
    enabled = true,
    text = "ColorPicker1",
    flag = "Color_1",
    tooltip = "ToolTip1",
    color = Color3.new(255, 255, 255),
    trans = 0,
    open = false,
    callback = function() end
})

library:SendNotification("Notification", 5, Color3.new(255, 0, 0))
