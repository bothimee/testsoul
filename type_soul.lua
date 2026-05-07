getgenv().Config = {
    Invite = "discord.gg/Bg2afYsD",
    Version = "0.1",
}

getgenv().luaguardvars = {
    DiscordName = "cashfears",
}

local SOURCE_URL = "https://raw.githubusercontent.com/bothimee/testsoul/main/source.lua"
local DEFAULT_PARRY_KEY = Enum.KeyCode.F

local function showLoadError(message)
    warn("[catboy hub] " .. tostring(message))

    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "catboy hub load failed",
            Text = tostring(message),
            Duration = 10
        })
    end)
end

local ok, libraryOrError = pcall(function()
    local sourceCode = game:HttpGet(SOURCE_URL)
    local chunk = loadstring(sourceCode)

    if not chunk then
        error("loadstring returned nil for source.lua")
    end

    local loadedLibrary = chunk()
    if type(loadedLibrary) ~= "table" then
        error("source.lua did not return a library table")
    end

    if not Drawing or not Drawing.new then
        error("executor is missing Drawing support")
    end

    loadedLibrary:init()
    return loadedLibrary
end)

if not ok then
    showLoadError(libraryOrError)
    return
end

local library = libraryOrError
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local AssetService = game:GetService("AssetService")

local localPlayer = Players.LocalPlayer
local autoParryConnection
local movementConnection
local selectedPlaceId
local subplaceDropdown
local lastParryTime = 0

local attackStateLookup = {
    Action = true,
    Skill = true,
    ShikaiSkill = true,
    BankaiSkill = true,
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

local blockedMovementStates = {
    Flashstep = true,
    PostureBroken = true,
    TrueStunned = true,
    Skill = true,
    ShikaiSkill = true,
    Action = true,
}

local function notify(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5
        })
    end)
end

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

local function pressKey(keyCode)
    local sent = pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.03)
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)

    if not sent and keypress and keyrelease then
        keypress(keyCode.Value)
        task.wait(0.03)
        keyrelease(keyCode.Value)
    end
end

local function getDesiredWalkspeed()
    local _, _, _ = getCharacterParts(localPlayer)
    local myEntity = getEntityForPlayer(localPlayer)
    if not myEntity then
        return nil
    end

    local currentState = myEntity:GetAttribute("CurrentState")
    local baseWalkspeed = myEntity:GetAttribute("BaseWalkspeed") or 16

    if library.flags.Flashstep_Speed and currentState == "Flashstep" then
        return library.flags.Flashstep_Slider or 100
    end

    if library.flags.Walkspeed_Legit then
        if currentState == "Sprinting" then
            return library.flags.Sprint_Walkspeed or 25
        end

        if currentState == "WeaponDrawn" then
            return library.flags.Weapon_Walkspeed or 20
        end

        if not blockedMovementStates[currentState] then
            return baseWalkspeed
        end
    end

    return nil
end

local function stopMovementLoop()
    if movementConnection then
        movementConnection:Disconnect()
        movementConnection = nil
    end
end

local function startMovementLoop()
    stopMovementLoop()

    movementConnection = RunService.Heartbeat:Connect(function()
        if not library.flags.Walkspeed_Legit and not library.flags.Flashstep_Speed then
            return
        end

        local _, humanoid = getCharacterParts(localPlayer)
        local myEntity = getEntityForPlayer(localPlayer)
        if not humanoid or not myEntity then
            return
        end

        local desiredSpeed = getDesiredWalkspeed()
        if not desiredSpeed then
            return
        end

        humanoid.WalkSpeed = desiredSpeed

        pcall(function()
            if myEntity:GetAttribute("BaseWalkspeed") ~= desiredSpeed and myEntity:GetAttribute("CurrentState") ~= "Flashstep" then
                myEntity:SetAttribute("BaseWalkspeed", desiredSpeed)
            end
        end)
    end)
end

local function isEnemyAttacking(enemyCharacter, enemyEntity)
    if enemyEntity and attackStateLookup[enemyEntity:GetAttribute("CurrentState")] then
        return true
    end

    local humanoid = enemyCharacter and enemyCharacter:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        return false
    end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local animationName = string.lower(track.Name or "")
        local animationId = string.lower((track.Animation and track.Animation.AnimationId) or "")

        for _, keyword in ipairs(attackAnimationKeywords) do
            if string.find(animationName, keyword, 1, true) or string.find(animationId, keyword, 1, true) then
                return true
            end
        end
    end

    return false
end

local function isThreatening(enemyRootPart, myRootPart)
    local toMe = (myRootPart.Position - enemyRootPart.Position)
    if toMe.Magnitude == 0 then
        return false
    end

    local facingDot = enemyRootPart.CFrame.LookVector:Dot(toMe.Unit)
    return facingDot > 0.35
end

local function stopAutoParry()
    if autoParryConnection then
        autoParryConnection:Disconnect()
        autoParryConnection = nil
    end
end

local function canAutoParry()
    if not library.flags.Auto_Parry then
        return false
    end

    local _, humanoid = getCharacterParts(localPlayer)
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    local myEntity = getEntityForPlayer(localPlayer)
    if not myEntity then
        return false
    end

    return not blockedMovementStates[myEntity:GetAttribute("CurrentState")]
end

local function startAutoParry()
    stopAutoParry()

    autoParryConnection = RunService.Heartbeat:Connect(function()
        if not canAutoParry() then
            return
        end

        local _, _, myRootPart = getCharacterParts(localPlayer)
        local entities = workspace:FindFirstChild("Entities")
        if not myRootPart or not entities then
            return
        end

        local range = library.flags.Auto_Parry_Range or 18
        local cooldown = library.flags.Auto_Parry_Cooldown or 0.35
        if os.clock() - lastParryTime < cooldown then
            return
        end

        for _, enemyEntity in ipairs(entities:GetChildren()) do
            if enemyEntity.Name ~= localPlayer.Name then
                local enemyPlayer = Players:FindFirstChild(enemyEntity.Name)
                local enemyCharacter, enemyHumanoid, enemyRootPart = enemyPlayer and getCharacterParts(enemyPlayer) or nil

                if enemyCharacter and enemyHumanoid and enemyHumanoid.Health > 0 and enemyRootPart then
                    local distance = (enemyRootPart.Position - myRootPart.Position).Magnitude
                    local attacking = isEnemyAttacking(enemyCharacter, enemyEntity)
                    local threatening = distance <= math.max(7, range * 0.45) and isThreatening(enemyRootPart, myRootPart)

                    if distance <= range and (attacking or threatening) then
                        lastParryTime = os.clock()
                        pressKey(DEFAULT_PARRY_KEY)
                        break
                    end
                end
            end
        end
    end)
end

local function stopLegitWalkspeed()
    if not library.flags.Flashstep_Speed then
        stopMovementLoop()
    end
end

local function setupLegitWalkspeed()
    startMovementLoop()
end

local function setupFlashstep()
    startMovementLoop()
end

local function refreshSubplaces()
    local places = {}
    local pages = AssetService:GetGamePlacesAsync()

    while true do
        for _, place in pairs(pages:GetCurrentPage()) do
            table.insert(places, place.Name .. " (ID: " .. place.PlaceId .. ")")
        end

        if pages.IsFinished then
            break
        end

        pages:AdvanceToNextPageAsync()
    end

    table.sort(places)
    selectedPlaceId = nil
    library.flags.Place_Dropdown = nil
    if subplaceDropdown then
        subplaceDropdown:SetOptions(places)
    end
end

local Window = library.NewWindow({
    title = "catboy hub : type soul",
    size = UDim2.new(0, 525, 0, 650)
})

local tabs = {
    Combat = Window:AddTab("Combat"),
    Movement = Window:AddTab("Movement"),
    Utility = Window:AddTab("Utility"),
    Settings = library:CreateSettingsTab(Window),
}

local sections = {
    CombatMain = tabs.Combat:AddSection("Defense", 1),
    CombatInfo = tabs.Combat:AddSection("Info", 2),
    MovementMain = tabs.Movement:AddSection("Mobility", 1),
    MovementInfo = tabs.Movement:AddSection("Notes", 2),
    UtilityMain = tabs.Utility:AddSection("Travel", 1),
    UtilityInfo = tabs.Utility:AddSection("Misc", 2),
}

sections.CombatMain:AddToggle({
    enabled = false,
    text = "Auto Parry",
    flag = "Auto_Parry",
    tooltip = "Auto taps parry when a nearby enemy attacks",
    risky = true,
    callback = function(enabled)
        if enabled then
            startAutoParry()
        else
            stopAutoParry()
        end
    end
})

sections.CombatMain:AddSlider({
    text = "Parry Range",
    flag = "Auto_Parry_Range",
    suffix = " studs",
    value = 18,
    min = 6,
    max = 35,
    increment = 1,
    tooltip = "How close an enemy must be before auto parry triggers",
    risky = false,
    callback = function() end
})

sections.CombatMain:AddSlider({
    text = "Parry Cooldown",
    flag = "Auto_Parry_Cooldown",
    suffix = "s",
    value = 0.35,
    min = 0.1,
    max = 1,
    increment = 0.05,
    tooltip = "Minimum time between parries",
    risky = false,
    callback = function() end
})

sections.CombatInfo:AddText({
    enabled = true,
    text = "Auto Parry runs from the toggle and sliders only",
    flag = "Combat_Info_Parry",
    risky = false,
})

sections.CombatInfo:AddText({
    enabled = true,
    text = "Range controls detection distance, cooldown controls how often it retries",
    flag = "Combat_Info_Tuning",
    risky = false,
})

sections.MovementMain:AddToggle({
    enabled = false,
    text = "Legit Walkspeed",
    flag = "Walkspeed_Legit",
    tooltip = "Boosts sprint and weapon drawn speeds only",
    risky = false,
    callback = function(enabled)
        if enabled then
            setupLegitWalkspeed()
        else
            stopLegitWalkspeed()
        end
    end
})

sections.MovementMain:AddSlider({
    text = "Sprint Speed",
    flag = "Sprint_Walkspeed",
    suffix = "",
    value = 25,
    min = 16,
    max = 40,
    increment = 1,
    tooltip = "WalkSpeed while sprinting",
    risky = false,
    callback = function()
        if library.flags.Walkspeed_Legit then
            startMovementLoop()
        end
    end
})

sections.MovementMain:AddSlider({
    text = "Weapon Speed",
    flag = "Weapon_Walkspeed",
    suffix = "",
    value = 20,
    min = 16,
    max = 32,
    increment = 1,
    tooltip = "WalkSpeed while weapon is drawn",
    risky = false,
    callback = function()
        if library.flags.Walkspeed_Legit then
            startMovementLoop()
        end
    end
})

sections.MovementMain:AddToggle({
    enabled = false,
    text = "Flashstep Speed",
    flag = "Flashstep_Speed",
    tooltip = "Overrides WalkSpeed only during Flashstep",
    risky = true,
    callback = function(enabled)
        if enabled then
            setupFlashstep()
        elseif not library.flags.Walkspeed_Legit then
            stopMovementLoop()
        end
    end
})

sections.MovementMain:AddSlider({
    text = "Flashstep Speed",
    flag = "Flashstep_Slider",
    suffix = "",
    value = 100,
    min = 50,
    max = 300,
    increment = 1,
    tooltip = "WalkSpeed while Flashstep is active",
    risky = false,
    callback = function()
        if library.flags.Flashstep_Speed then
            startMovementLoop()
        end
    end
})

sections.MovementInfo:AddText({
    enabled = true,
    text = "Movement edits react to Type Soul entity states instead of forcing speed nonstop",
    flag = "Movement_Info_States",
    risky = false,
})

sections.MovementInfo:AddText({
    enabled = true,
    text = "If the game swaps states oddly after death, respawn once and the hooks reattach",
    flag = "Movement_Info_Respawn",
    risky = false,
})

sections.UtilityMain:AddButton({
    enabled = true,
    text = "Refresh Subplaces",
    flag = "Fetch_Subplaces",
    tooltip = "Fetches all subplaces for this game",
    risky = false,
    confirm = false,
    callback = refreshSubplaces
})

subplaceDropdown = sections.UtilityMain:AddList({
    text = "Subplace",
    flag = "Place_Dropdown",
    tooltip = "Select a subplace to teleport to",
    values = {},
    callback = function(value)
        selectedPlaceId = value and value:match("ID: (%d+)") or nil
    end
})

sections.UtilityMain:AddButton({
    enabled = true,
    text = "Teleport To Subplace",
    flag = "Teleport_Subplace",
    tooltip = "Teleports you to the selected subplace",
    risky = false,
    confirm = false,
    callback = function()
        if not selectedPlaceId then
            warn("No subplace selected.")
            return
        end

        TeleportService:Teleport(tonumber(selectedPlaceId), localPlayer)
    end
})

sections.UtilityInfo:AddButton({
    enabled = true,
    text = "Fill TSBG Mode Bar",
    flag = "Mode_Bar",
    tooltip = "Clicks the Heal Bankai Bar if it exists",
    risky = false,
    confirm = false,
    callback = function()
        local part = workspace:FindFirstChild("Heal Bankai Bar")
        if not part then
            warn("Heal Bankai Bar not found.")
            return
        end

        local clickDetector = part:FindFirstChildOfClass("ClickDetector")
        if not clickDetector then
            warn("No ClickDetector found in Heal Bankai Bar.")
            return
        end

        fireclickdetector(clickDetector)
    end
})

sections.UtilityInfo:AddText({
    enabled = true,
    text = "Random placeholder binds and junk controls have been removed",
    flag = "Utility_Info_Clean",
    risky = false,
})

localPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if library.flags.Walkspeed_Legit or library.flags.Flashstep_Speed then
        startMovementLoop()
    end

    if library.flags.Auto_Parry then
        startAutoParry()
    end
end)

notify("catboy hub", "Type Soul loaded", 5)
