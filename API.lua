local Globals = getgenv()
local ModuleRunning = true
local errorMessageConnection = nil
local idleConnection = nil

-- Patched shared.TDSTable check

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    local t0 = tick()
    while not Players.LocalPlayer and (tick() - t0 < 10) do
        task.wait(0.1)
    end
    LocalPlayer = Players.LocalPlayer
end

local function SmartTeleportToLobby()
    local lobbyId = 3260590327
    pcall(function()
        local platform = UserInputService:GetPlatform()
        local IsMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)
        
        if not IsMobile and Globals.PrivateCode and Globals.PrivateCode ~= "" then
            game:GetService("ExperienceService"):LaunchExperience({
                placeId = lobbyId, 
                linkCode = Globals.PrivateCode
            })
        else
            TeleportService:Teleport(lobbyId)
        end
    end)
end

local function Reconnect()
    local initialCode = GuiService:GetErrorCode()
    
    if initialCode and initialCode ~= Enum.ConnectionError.OK then
        task.wait(5)
        
        if GuiService:GetErrorCode() == initialCode then
            pcall(function()
                TeleportService:TeleportReconnect()
            end)
        end
    end
end

local function AntiStuck()
    task.spawn(function()
        local secondsStuck = 0

        while ModuleRunning do 
            task.wait(1)
            
            local attrLoading = LocalPlayer:GetAttribute("Loading") == true
            local attrTeleporting = LocalPlayer:GetAttribute("Teleporting") == true
            
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            local loadScreen = pg and pg:FindFirstChild("LoadingScreen")
            local loadContent = loadScreen and loadScreen:FindFirstChild("content")
            local isLoadVisible = loadContent and loadContent.Visible == true
            
            local countScreen = pg and pg:FindFirstChild("PlayerCountdown")
            local countFrame = countScreen and countScreen:FindFirstChild("Frame")
            local isCountVisible = countFrame and countFrame.Visible == true

            if attrLoading or attrTeleporting or isLoadVisible or isCountVisible then
                secondsStuck = secondsStuck + 1
                if secondsStuck >= 60 then
                    pcall(SmartTeleportToLobby)
                    secondsStuck = 0 
                end
            else
                secondsStuck = 0 
            end
        end
    end)
end

AntiStuck()
task.spawn(Reconnect)
errorMessageConnection = GuiService.ErrorMessageChanged:Connect(Reconnect)

if not game:IsLoaded() then game.Loaded:Wait() end

local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local mouse = LocalPlayer:GetMouse()
local RemoteFunc = ReplicatedStorage:WaitForChild("RemoteFunction")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local FileName = "API.json"
local Logger
local StartBackToLobby
local platform = UserInputService:GetPlatform()
local IsMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)

idleConnection = LocalPlayer.Idled:Connect(function()
    if not ModuleRunning then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new(0, 0))
end)

task.spawn(function()
    pcall(function()
        RemoteFunc:InvokeServer("Settings", "Update", "Show Nametags", false)
    end)
end)

local function IdentifyGameState()
    if game.PlaceId == 3260590327 then
        return "LOBBY"
    else
        return "GAME"
    end
end

local GameState = IdentifyGameState()

local function StartAntiAfk()
    task.spawn(function()
        local LobbyTimer = 0
        while ModuleRunning and GameState == "LOBBY" do 
            task.wait(1)
            LobbyTimer = LobbyTimer + 1
            if LobbyTimer >= 600 then
                SmartTeleportToLobby()
                break 
            end
        end
    end)
end

StartAntiAfk()

local SendRequest = request or http_request or httprequest
    or GetDevice and GetDevice().request

if not SendRequest then 
    warn("failure: no http function") 
    return 
end

local BackToLobbyRunning = false
local AutoSkipRunning = false
local AntiLagRunning = false
local AutoChainRunning = false
local AutoDjRunning = false
local AutoNecroRunning = false
local AutoMercenaryBaseRunning = false
local AutoMilitaryBaseRunning = false
local AutoGatlingRunning = false
local IsCurrentlyLoading = false
local LastLoadTime = 0
local IsEquippingLoadout = false

local MaxPathDistance = 300
local MilMarker = nil
local MercMarker = nil

local CurrentEquippedTowers = {"None"}

local AutoMedicRunning = false

local AllModifiers = {
    "HiddenEnemies", "Glass", "ExplodingEnemies", "Limitation", 
    "Committed", "HealthyEnemies", "Fog", "FlyingEnemies", 
    "Broke", "SpeedyEnemies", "Quarantine", "JailedTowers", "Inflation"
}

local DefaultSettings = {
    AutoSkip = false,
    AutoReady = false,
    AutoChain = false,
    AutoGatling = false,
    SupportCaravan = false,
    AutoDJ = false,
    AutoNecro = false,
    AutoRejoin = false,
    AutoRestart = false,
    AutoMercenary = false,
    AutoMilitary = false,
    AntiLag = false,
    Disable3DRendering = false,
    NoRecoil = false,
    AutoMedic = false,
	AutoReset = false,
	AutoBack = false,
	PrivateCode = "",
}

local ItemNames = {
    ["17438486690"] = "Range Flag(s)",
    ["17438486138"] = "Damage Flag(s)",
    ["17438487774"] = "Cooldown Flag(s)",
    ["17429537022"] = "Blizzard(s)",
    ["17448596749"] = "Napalm Strike(s)",
    ["18493073533"] = "Spin Ticket(s)",
    ["17429548305"] = "Supply Drop(s)",
    ["18443277308"] = "Low Grade Consumable Crate(s)",
    ["136180382135048"] = "Santa Radio(s)",
    ["18443277106"] = "Mid Grade Consumable Crate(s)",
    ["18443277591"] = "High Grade Consumable Crate(s)",
    ["132155797622156"] = "Christmas Tree(s)",
    ["124065875200929"] = "Fruit Cake(s)",
    ["17429541513"] = "Barricade(s)",
    ["110415073436604"] = "Holy Hand Grenade(s)",
    ["17429533728"] = "Frag Grenade(s)",
    ["17437703262"] = "Molotov(s)",
    ["139414922355803"] = "Present Clusters(s)"
}

local executed_actions = {}

TDS = {
    PlacedTowers = {},
    ActiveStrat = true,
    IsEquippingLoadout = false,
    LoadoutPending = false,
    MatchmakingMap = {
        ["PizzaParty"] = "halloween",
        ["Badlands"] = "badlands",
        ["PollutedWasteland"] = "polluted",
        ["DuckyEasy"] = "ducky2025",
        ["DuckyHard"] = "ducky2025"
    }
}
TDS["placed_towers"] = TDS.PlacedTowers
TDS["active_strat"] = TDS.ActiveStrat
TDS["matchmaking_map"] = TDS.MatchmakingMap

local UpgradeHistory = {}

shared.TDSTable = TDS
shared["TDS_Table"] = TDS

function TDS:ResetAllStates()
    table.clear(self.PlacedTowers)
    table.clear(UpgradeHistory)
    table.clear(executed_actions)
    if Logger and Logger.Clear then
        pcall(function()
            Logger:Clear()
        end)
    end
end

function TDS:RunStrategy()
    if Globals.activeStrategyThread then
        pcall(task.cancel, Globals.activeStrategyThread)
        Globals.activeStrategyThread = nil
    end

    Globals.activeStrategyThread = task.spawn(function()
        Globals.tdsReplaying = true
        pcall(function()
            loadstring(readfile("ADS_LastStrat.lua"))()
        end)
        Globals.tdsReplaying = false
        Globals.activeStrategyThread = nil
    end)
end

local function SaveSettings()
    local DataToSave = {}
    for key, _ in pairs(DefaultSettings) do
        DataToSave[key] = Globals[key]
    end
    writefile(FileName, HttpService:JSONEncode(DataToSave))
end

local function LoadSettings()
    local data = {}
    if isfile(FileName) then
        pcall(function()
            data = HttpService:JSONDecode(readfile(FileName))
        end)
    end

    for key, DefaultVal in pairs(DefaultSettings) do
        if Globals[key] == nil then
            if data[key] ~= nil then
                Globals[key] = data[key]
            else
                Globals[key] = DefaultVal
            end
        end
    end
    
    SaveSettings()
end

local function SetSetting(name, value)
    if DefaultSettings[name] ~= nil then
        Globals[name] = value
        SaveSettings()
    end
end

local function Apply3dRendering()
    if Globals.Disable3DRendering then
        game:GetService("RunService"):Set3dRenderingEnabled(false)
    else
        RunService:Set3dRenderingEnabled(true)
    end
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local gui = PlayerGui and PlayerGui:FindFirstChild("ADS_BlackScreen")
    if Globals.Disable3DRendering then
        if PlayerGui and not gui then
            gui = Instance.new("ScreenGui")
            gui.Name = "ADS_BlackScreen"
            gui.IgnoreGuiInset = true
            gui.ResetOnSpawn = false
            gui.DisplayOrder = -1000
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            gui.Parent = PlayerGui
            local frame = Instance.new("Frame")
            frame.Name = "Cover"
            frame.BackgroundColor3 = Color3.new(0, 0, 0)
            frame.BorderSizePixel = 0
            frame.Size = UDim2.fromScale(1, 1)
            frame.ZIndex = 0
            frame.Parent = gui
        end
        gui.Enabled = true
    else
        if gui then
            gui.Enabled = false
        end
    end
end

LoadSettings()
Apply3dRendering()

local function FindPath()
    local MapFolder = workspace:FindFirstChild("Map")
    if not MapFolder then return nil end
    local PathsFolder = MapFolder:FindFirstChild("Paths")
    if not PathsFolder then return nil end
    local PathFolder = PathsFolder:GetChildren()[1]
    if not PathFolder then return nil end

    local PathNodes = {}
    for _, node in ipairs(PathFolder:GetChildren()) do
        if node:IsA("BasePart") then
            table.insert(PathNodes, node)
        end
    end

    table.sort(PathNodes, function(a, b)
        local NumA = tonumber(a.Name:match("%d+"))
        local NumB = tonumber(b.Name:match("%d+"))
        if NumA and NumB then return NumA < NumB end
        return a.Name < b.Name
    end)

    return PathNodes
end

local function TotalLength(PathNodes)
    local TotalLength = 0
    for i = 1, #PathNodes - 1 do
        TotalLength = TotalLength + (PathNodes[i + 1].Position - PathNodes[i].Position).Magnitude
    end
    return TotalLength
end

local MercenarySlider
local MilitarySlider
local MaxLenght

local function CalcLength()
    local map = workspace:FindFirstChild("Map")

    if GameState == "GAME" and map then
        local PathNodes = FindPath()

        if PathNodes and #PathNodes > 0 then
            MaxPathDistance = TotalLength(PathNodes)

            if MercenarySlider then
                MercenarySlider:SetMax(MaxPathDistance) 
            end

            if MilitarySlider then
                MilitarySlider:SetMax(MaxPathDistance)
            end

            if MaxLenght then
                MaxLenght = MaxPathDistance
            end
            return true
        end
    end
    return false
end

local function GetPointAtDistance(PathNodes, distance)
    if not PathNodes or #PathNodes < 2 then return nil end

    local CurrentDist = 0
    for i = 1, #PathNodes - 1 do
        local StartPos = PathNodes[i].Position
        local EndPos = PathNodes[i+1].Position
        local SegmentLen = (EndPos - StartPos).Magnitude

        if CurrentDist + SegmentLen >= distance then
            local remaining = distance - CurrentDist
            local direction = (EndPos - StartPos).Unit
            return StartPos + (direction * remaining)
        end
        CurrentDist = CurrentDist + SegmentLen
    end
    return PathNodes[#PathNodes].Position
end

local function UpdatePathVisuals()
    if not Globals.PathVisuals then
        if MilMarker then 
            MilMarker:Destroy() 
            MilMarker = nil 
        end
        if MercMarker then 
            MercMarker:Destroy() 
            MercMarker = nil 
        end
        return
    end

    local PathNodes = FindPath()
    if not PathNodes then return end

    if not MilMarker then
        MilMarker = Instance.new("Part")
        MilMarker.Name = "MilVisual"
        MilMarker.Shape = Enum.PartType.Cylinder
        MilMarker.Size = Vector3.new(0.3, 3, 3)
        MilMarker.Color = Color3.fromRGB(0, 255, 0)
        MilMarker.Material = Enum.Material.Plastic
        MilMarker.Anchored = true
        MilMarker.CanCollide = false
        MilMarker.Orientation = Vector3.new(0, 0, 90)
        MilMarker.Parent = workspace
    end

    if not MercMarker then
        MercMarker = MilMarker:Clone()
        MercMarker.Name = "MercVisual"
        MercMarker.Color = Color3.fromRGB(255, 0, 0)
        MercMarker.Parent = workspace
    end

    local MilPos = GetPointAtDistance(PathNodes, Globals.MilitaryPath or 0)
    local MercPos = GetPointAtDistance(PathNodes, Globals.MercenaryPath or 0)

    if MilPos then
        MilMarker.Position = MilPos + Vector3.new(0, 0.2, 0)
        MilMarker.Transparency = 0.7
    end
    if MercPos then
        MercMarker.Position = MercPos + Vector3.new(0, 0.2, 0)
        MercMarker.Transparency = 0.7
    end
end

local function MissionsUIFix()
    task.spawn(function()
        while task.wait(1) do
            pcall(function()
                local MissionsScrollingFrame = game:GetService("Players").LocalPlayer.PlayerGui.ReactLobbyQuests.quests.missions.scrollingFrame
                local MissionsListLayout = MissionsScrollingFrame.listLayout
                local MissionFrame = MissionsScrollingFrame["1"]
                if MissionFrame.AbsoluteSize.Y > 0 then
                    local UIScaleRatio = MissionFrame.AbsoluteSize.Y / MissionFrame.Size.Y.Offset
                    local CurrentCanvasSize = MissionsScrollingFrame.CanvasSize
                    local CanvasHeight = (MissionsListLayout.AbsoluteContentSize.Y / UIScaleRatio) + 25
                    MissionsScrollingFrame.CanvasSize = UDim2.new(CurrentCanvasSize.X.Scale, CurrentCanvasSize.X.Offset, CurrentCanvasSize.Y.Scale, CanvasHeight)
                end
            end)
        end
    end)
end

local function GetEquippedTowers()
    local towers = {}
    local StateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")

    if StateReplicators then
        for _, folder in ipairs(StateReplicators:GetChildren()) do
            if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                local equipped = folder:GetAttribute("EquippedTowers")
                if type(equipped) == "string" then
                    local CleanedJson = equipped:match("%[.*%]") 
                    local success, TowerTable = pcall(function()
                        return HttpService:JSONDecode(CleanedJson)
                    end)

                    if success and type(TowerTable) == "table" then
                        for i = 1, 5 do
                            if TowerTable[i] then
                                table.insert(towers, TowerTable[i])
                            end
                        end
                    end
                end
            end
        end
    end
    return #towers > 0 and towers or {"None"}
end

CurrentEquippedTowers = GetEquippedTowers()

local function RunVoteSkip()
    while true do
        local success = pcall(function()
            RemoteFunc:InvokeServer("Voting", "Skip")
        end)
        if success then break end
        task.wait(0.1)
    end
end

AutoReadyRunning = false

local function StartAutoReady()
    if AutoReadyRunning or not Globals.AutoReady or GameState ~= "GAME" then return end
    AutoReadyRunning = true

    task.spawn(function()
        local voteReplicator = ReplicatedStorage:WaitForChild("StateReplicators"):WaitForChild("VoteReplicator")
        
        repeat 
            task.wait(0.1) 
            if not Globals.AutoReady then 
                AutoReadyRunning = false
                return 
            end
        until voteReplicator:GetAttribute("Enabled") == true and voteReplicator:GetAttribute("Title") == "Ready?"
        
        if not Globals.AutoReady then
            AutoReadyRunning = false
            return
        end

        RunVoteSkip()
        
        repeat 
            task.wait(0.1) 
        until voteReplicator:GetAttribute("Enabled") == false or not Globals.AutoReady
        
        AutoReadyRunning = false
    end)
end

local function CheckResOk(data)
    if data == true then return true end
    if type(data) == "table" and data.Success == true then return true end

    local success, IsModel = pcall(function()
        return data and data:IsA("Model")
    end)

    if success and IsModel then return true end
    if type(data) == "userdata" then return true end

    return false
end

local function RejoinMatch()
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
    local success = false
    local res

    if Globals.PrivateCode and Globals.PrivateCode ~= "" and not IsMobile then
        SmartTeleportToLobby()
        task.wait(9e9)
        return
    end

    repeat
        local StateFolder = ReplicatedStorage:FindFirstChild("State")
        local CurrentMode = StateFolder and StateFolder.Difficulty.Value
        if not CurrentMode or CurrentMode == "" then
            CurrentMode = TDS.SavedDifficulty
        end

        if CurrentMode and CurrentMode ~= "" then
            local ok, result = pcall(function()
                local payload
                local EventMode = StateFolder:FindFirstChild("Mode") and StateFolder.Mode.Value

                if CurrentMode == "PizzaParty" then
                    payload = {
                        mode = "halloween",
                        count = 1
                    }
                elseif tostring(EventMode or ""):lower() == "hardcore" then
                    payload = {
                        difficulty = CurrentMode,
                        mode = "hardcore",
                        count = 1
                    }
                elseif CurrentMode == "PollutedWasteland" then
                    payload = {
                        mode = "polluted",
                        count = 1
                    }
                elseif CurrentMode == "Badlands" then
                    payload = {
                        mode = "badlands",
                        count = 1
                    }
                elseif EventMode == "DuckEvent" then
                    payload = {
                        difficulty = CurrentMode,
                        mode = "ducky2025",
                        count = 1
                    }
                elseif CurrentMode == "Trial" then
                    SmartTeleportToLobby()
                    return true
                else
                    payload = {
                        difficulty = CurrentMode,
                        mode = "survival",
                        count = 1
                    }
                end

                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)

            if ok and CheckResOk(result) then
                success = true
                res = result
            else
                task.wait(0.5) 
            end
        else
            task.wait(1)
        end
    until success

    return res
end

local function MatchReadyUp()
    local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators")
    local voteReplicator = stateReplicators:WaitForChild("VoteReplicator")
    local gameStateReplicator = stateReplicators:WaitForChild("GameStateReplicator")

    if gameStateReplicator:GetAttribute("GameStarted") == true then
        return
    end
    
    local voteTitle = voteReplicator:GetAttribute("Title")
    if voteTitle == "Ready?" and voteReplicator:GetAttribute("Enabled") == true then
        RunVoteSkip()
        return
    end

    local yieldSignal = Instance.new("BindableEvent")
    local voteConnection
    local gameStartedConnection

    voteConnection = voteReplicator.AttributeChanged:Connect(function(attributeName)
        if attributeName == "Enabled" and voteReplicator:GetAttribute("Enabled") == true then
            if voteReplicator:GetAttribute("Title") == "Ready?" then
                RunVoteSkip()
                yieldSignal:Fire()
            end
        elseif attributeName == "Title" and voteReplicator:GetAttribute("Title") ~= "Ready?" then
            yieldSignal:Fire()
        elseif attributeName == "VoteCount" or attributeName == "MaxVotes" then
            local currentVotes = voteReplicator:GetAttribute("VoteCount")
            local maxVotesRequired = voteReplicator:GetAttribute("MaxVotes")
            if currentVotes and maxVotesRequired and maxVotesRequired > 0 and currentVotes >= maxVotesRequired then
                yieldSignal:Fire()
            end
        end
    end)

    gameStartedConnection = gameStateReplicator:GetAttributeChangedSignal("GameStarted"):Connect(function()
        if gameStateReplicator:GetAttribute("GameStarted") == true then
            yieldSignal:Fire()
        end
    end)

    yieldSignal.Event:Wait()

    if voteConnection then
        voteConnection:Disconnect()
    end
    if gameStartedConnection then
        gameStartedConnection:Disconnect()
    end
    yieldSignal:Destroy()
end

local function CastMapVote(MapId, PosVec)
    local TargetMap = MapId or "Simplicity"
    local TargetPos = PosVec or Vector3.new(0,0,0)
    RemoteEvent:FireServer("LobbyVoting", "Vote", TargetMap, TargetPos)
end

local function LobbyReadyUp()
    pcall(function()
        RemoteEvent:FireServer("LobbyVoting", "Ready")
    end)
end

local function SelectMapOverride(MapId, ...)
    local args = {...}

    if args[#args] == "vip" then
        RemoteFunc:InvokeServer("LobbyVoting", "Override", MapId)
    end

    task.wait(3)
    CastMapVote(MapId, Vector3.new(12.59, 10.64, 52.01))
    task.wait(1)
    LobbyReadyUp()
end

local function CastModifierVote(ModsTable)
    local BulkModifiers = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Modifiers"):WaitForChild("RF:BulkVoteModifiers")
    local ModRep = ReplicatedStorage:WaitForChild("StateReplicators"):FindFirstChild("ModifierReplicator")

    local Available = {}
    if ModRep then
        local raw = ModRep:GetAttribute("Available")
        if type(raw) == "string" then
            local clean = raw:match("{.+}")
            if clean then
                pcall(function()
                    Available = HttpService:JSONDecode(clean)
                end)
            end
        end
    end

    local SelectedMods = {}
    local missingMods = {}

    if ModsTable then
        for k, v in pairs(ModsTable) do
            local modName = type(k) == "string" and k or v
            
            if type(modName) == "string" then
                if Available[modName] == true then
                    SelectedMods[modName] = true
                else
                    table.insert(missingMods, modName)
                end
            end
        end
    end

    if next(SelectedMods) then
        pcall(function()
            BulkModifiers:InvokeServer(SelectedMods)
        end)
    end
end

local function IsMapAvailable(name)
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end

    local hasVoted = false

    repeat
        local IntermissionFrame = PlayerGui:WaitForChild("ReactGameIntermission"):WaitForChild("Frame")
        local VetoValue = IntermissionFrame.buttons.veto.value
        local VetoText = VetoValue.Text
        
        if VetoText ~= "" then
            if not VetoText:find("Veto") then
                return false 
            end

            local currentStr, totalStr = VetoText:match("(%d+)/(%d+)")
            local current, total = tonumber(currentStr), tonumber(totalStr)

            if not hasVoted and total and total > 0 and current == 0 then
                RemoteEvent:FireServer("LobbyVoting", "Veto")
                hasVoted = true
            end
        end

        local found = false
        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                local t = g:FindFirstChild("Title")
                if t and t.Text == name then
                    found = true
                    break
                end
            end
        end

        task.wait(1)

        local TotalPlayer = #Players:GetChildren()
        local isFull = VetoText == "Veto ("..TotalPlayer.."/"..TotalPlayer..")"

    until found or isFull

    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end

    return false
end

local function TriggerRestart()
    local UiRoot = PlayerGui:WaitForChild("ReactGameNewRewards")
    local FoundSection = false

    repeat
        task.wait(0.3)
        local f = UiRoot:FindFirstChild("Frame")
        local g = f and f:FindFirstChild("gameOver")
        local s = g and g:FindFirstChild("RewardsScreen")
        if s and s:FindFirstChild("RewardsSection") then
            FoundSection = true
        end
    until FoundSection

    task.wait(3)
    RunVoteSkip()
end

local function GetCurrentWave()
    local label

    repeat
        task.wait(0.5)
        label = PlayerGui:FindFirstChild("ReactGameTopGameDisplay", true) 
            and PlayerGui.ReactGameTopGameDisplay.Frame.wave.container:FindFirstChild("value")
    until label ~= nil

    local text = label.Text
    local WaveNum = text:match("(%d+)")

    return tonumber(WaveNum) or 0
end

local function DoPlaceTower(TName, TPos)
    local retries = 0
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Place", {
                Rotation = CFrame.new(),
                Position = TPos
            }, TName)
        end)
 
        if ok and CheckResOk(res) then return true end
        retries = retries + 1
        if retries == 10 or (retries > 10 and retries % 20 == 0) then
            warn(string.format("[TDS:Place] Waiting to place '%s' (attempt %d)...", tostring(TName), retries))
        end
        task.wait(0.25)
    end
end

local function DoUpgradeTower(TObj, PathId)
    if not TObj then
        warn("[TDS:Upgrade] Error: Attempted to upgrade a nil tower object!")
        return false
    end
    local retries = 0
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {
                Troop = TObj,
                Path = PathId
            })
        end)
        if ok and CheckResOk(res) then return true end
        retries = retries + 1
        if retries == 10 or (retries > 10 and retries % 20 == 0) then
            warn(string.format("[TDS:Upgrade] Waiting to upgrade tower (attempt %d)...", retries))
        end
        task.wait(0.25)
    end
end

local function DoSellTower(TObj)
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Sell", { Troop = TObj })
        end)
        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoSetOption(TObj, OptName, OptVal, ReqWave)
    if ReqWave then
        repeat task.wait(0.3) until GetCurrentWave() >= ReqWave
    end

    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Option", "Set", {
                Troop = TObj,
                Name = OptName,
                Value = OptVal
            })
        end)
        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoActivateAbility(TObj, AbName, AbData, IsLooping)
    if type(AbData) == "boolean" then
        IsLooping = AbData
        AbData = nil
    end

    AbData = type(AbData) == "table" and AbData or nil

    local positions
    if AbData and type(AbData.towerPosition) == "table" then
        positions = AbData.towerPosition
    end

    local CloneIdx = AbData and AbData.towerToClone
    local TargetIdx = AbData and AbData.towerTarget

    local function attempt()
        while true do
            local ok, res = pcall(function()
                local data

                if AbData then
                    data = table.clone(AbData)

                    if positions and #positions > 0 then
                        data.towerPosition = positions[math.random(#positions)]
                    end

                    if type(CloneIdx) == "number" then
                        data.towerToClone = TDS.PlacedTowers[CloneIdx]
                    end

                    if type(TargetIdx) == "number" then
                        data.towerTarget = TDS.PlacedTowers[TargetIdx]
                    end
                end

                return RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    {
                        Troop = TObj,
                        Name = AbName,
                        Data = data
                    }
                )
            end)

            if ok and CheckResOk(res) then
                return true
            end

            task.wait(0.25)
        end
    end

    if IsLooping then
        local active = true
        task.spawn(function()
            while active do
                attempt()
                task.wait(1)
            end
        end)
        return function() active = false end
    end

    return attempt()
end

function TDS:Mode(difficulty, code)
    self.SavedDifficulty = difficulty
    local targetCode = ""

    if IsMobile then
        if (code and code ~= "") or (Globals.PrivateCode and Globals.PrivateCode ~= "") then
        end
    else
        if code and code ~= "" then
            targetCode = code
        elseif Globals.PrivateCode then
            targetCode = Globals.PrivateCode
        end
    end

    self.PrivateCode = tostring(targetCode)

    if GameState ~= "LOBBY" then 
        return false 
    end

    if targetCode ~= "" and not MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) then
        local ServerType = game:GetService('RobloxReplicatedStorage').GetServerType:InvokeServer()
        
        if ServerType ~= "VIPServer" then
            game:GetService("ExperienceService"):LaunchExperience({
                placeId = game.PlaceId, 
                linkCode = tostring(targetCode)
            })
            return true
        end
    end

    if difficulty == "Trial" then
        local Elevators = workspace:WaitForChild("TrialElevators")
        local Network = ReplicatedStorage:WaitForChild("Network")
        
        if Elevators and Network then
            local targetElevator = nil
            
            repeat
                for _, v in pairs(Elevators:GetChildren()) do
                    if v.Name:match("Elevator") then
                        targetElevator = v
                        break
                    end
                end
                if not targetElevator then task.wait(0.5) end
            until targetElevator

            task.spawn(function()
                local ElevatorsNet = Network:WaitForChild("Elevators")
                local EnterRemote = ElevatorsNet:WaitForChild("RF:Enter")
                local SetSizeRemote = ElevatorsNet:WaitForChild("RF:SetSize")
                local SetReadyRemote = ElevatorsNet:WaitForChild("RF:SetReady")
                
                pcall(function() EnterRemote:InvokeServer(targetElevator) end)
                pcall(function() SetSizeRemote:InvokeServer(1) end)
                pcall(function() SetReadyRemote:InvokeServer(true) end)
            end)
            
            return true
        end
    end

    local LobbyHud = PlayerGui:WaitForChild("ReactLobbyHud", 30)
    local frame = LobbyHud and LobbyHud:WaitForChild("Frame", 30)
    local MatchMaking = frame and frame:WaitForChild("matchmaking", 30)

    if MatchMaking then
        local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
        local success = false
        repeat
            local ok, result = pcall(function()
                local mode = TDS.MatchmakingMap[difficulty]
                local payload

                if difficulty == "Hardcore" then
                    payload = {
                        mode = "hardcore",
                        difficulty = "Easy",
                        count = 1
                    }
                elseif difficulty == "Voidcore" then
                    payload = {
                        mode = "hardcore",
                        difficulty = "Hard",
                        count = 1
                    }
                elseif mode then
                    payload = {
                        mode = mode,
                        count = 1
                    }
                    if difficulty:match("Ducky") then
                        payload.difficulty = difficulty:gsub("Ducky", "")
                    end
                else
                    payload = {
                        difficulty = difficulty,
                        mode = "survival",
                        count = 1
                    }
                end

                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)

            if ok and CheckResOk(result) then
                success = true
            else
                task.wait(0.5) 
            end
        until success
    end

    return true
end

function TDS:Loadout(...)
    if game.PlaceId == 3260590327 then
        return
    end

    while IsCurrentlyLoading do
        task.wait(0.2)
    end

    IsCurrentlyLoading = true
    IsEquippingLoadout = true
    self.IsEquippingLoadout = true

    local rawArgs = {...}
    local towers = {}
    if #rawArgs == 1 and type(rawArgs[1]) == "table" then
        for _, t in ipairs(rawArgs[1]) do
            if type(t) == "string" and t ~= "" and t ~= "None" then
                table.insert(towers, t)
            end
        end
    else
        for _, t in ipairs(rawArgs) do
            if type(t) == "string" and t ~= "" and t ~= "None" then
                table.insert(towers, t)
            end
        end
    end

    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvent")

    local function normalizeTower(name: any): (string, string)
        if type(name) ~= "string" then return "", "" end
        local trimmed = name:gsub("^%s*(.-)%s*$", "%1")
        local lower = trimmed:lower()
        local base = lower:gsub("^golden%s+", "")
        return lower, base
    end

    local function readEquipped(): {string}
        local eq = {}
        local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
        if stateReps then
            for _, folder in ipairs(stateReps:GetChildren()) do
                if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                    local equippedAttr = folder:GetAttribute("EquippedTowers")
                    if type(equippedAttr) == "string" then
                        local cleanedJson = equippedAttr:match("%[.*%]")
                        if cleanedJson then
                            local ok, decoded = pcall(function()
                                return HttpService:JSONDecode(cleanedJson)
                            end)
                            if ok and type(decoded) == "table" then
                                for _, name in ipairs(decoded) do
                                    if type(name) == "string" and name ~= "None" and name ~= "" then
                                        table.insert(eq, name)
                                    end
                                end
                            end
                        end
                    end
                    break
                end
            end
        end

        -- Fallback 1: Legacy InventoryController (Lobby)
        if #eq == 0 then
            pcall(function()
                local client = ReplicatedStorage:FindFirstChild("Client")
                local interfaces = client and client:FindFirstChild("Interfaces")
                local legacy = interfaces and interfaces:FindFirstChild("LegacyInterface")
                local controllers = legacy and legacy:FindFirstChild("Controllers")
                local invCtrlMod = controllers and controllers:FindFirstChild("InventoryController")
                if invCtrlMod then
                    local InvCtrl = require(invCtrlMod)
                    if InvCtrl and type(InvCtrl.getItems) == "function" then
                        local items = InvCtrl:getItems()
                        if items then
                            for _, item in pairs(items) do
                                if type(item) == "table" and item.type == "tower" and item.equipped == true and item.name then
                                    table.insert(eq, item.name)
                                end
                            end
                        end
                    end
                end
            end)
        end

        -- Fallback 2: Cache Troops
        if #eq == 0 then
            pcall(function()
                local client = ReplicatedStorage:FindFirstChild("Client")
                local modules = client and client:FindFirstChild("Modules")
                local cacheMod = modules and modules:FindFirstChild("Cache")
                if cacheMod then
                    local Cache = require(cacheMod)
                    local atom = Cache and Cache("Inventory.Troops")
                    local troops = atom and atom:GetValue()
                    if type(troops) == "table" then
                        for tName, tData in pairs(troops) do
                            if type(tData) == "table" and tData.Equipped == true then
                                table.insert(eq, tName)
                            end
                        end
                    end
                end
            end)
        end

        return eq
    end

    local success = pcall(function()
        local CurrentlyEquipped = readEquipped()
        if #CurrentlyEquipped == 0 then
            for _ = 1, 5 do
                task.wait(0.2)
                CurrentlyEquipped = readEquipped()
                if #CurrentlyEquipped > 0 then break end
            end
        end

        local function getExactTowerName(tName)
            if not tName or tName == "" or tName == "None" then return tName end
            local lowerT = string.lower(tostring(tName))
            local resolved = tName
            pcall(function()
                local client = ReplicatedStorage:FindFirstChild("Client")
                local modules = client and client:FindFirstChild("Modules")
                local cacheMod = modules and modules:FindFirstChild("Cache")
                if cacheMod then
                    local Cache = require(cacheMod)
                    local atom = Cache and Cache("Inventory.Troops")
                    local troops = atom and atom:GetValue()
                    if type(troops) == "table" then
                        for realName, _ in pairs(troops) do
                            if string.lower(tostring(realName)) == lowerT then
                                resolved = realName
                                return
                            end
                        end
                    end
                end
            end)
            return resolved
        end

        local matchedCurrentIndices = {}
        local matchedTargetIndices = {}

        -- Pass 1: Exact case-insensitive name match
        for tIdx, targetName in ipairs(towers) do
            local tLower = normalizeTower(targetName)
            if tLower ~= "" then
                for cIdx, currentName in ipairs(CurrentlyEquipped) do
                    if not matchedCurrentIndices[cIdx] and not matchedTargetIndices[tIdx] then
                        local cLower = normalizeTower(currentName)
                        if cLower == tLower then
                            matchedCurrentIndices[cIdx] = true
                            matchedTargetIndices[tIdx] = true
                            break
                        end
                    end
                end
            end
        end

        -- Pass 2: Base tower match (e.g. Scout vs Golden Scout)
        for tIdx, targetName in ipairs(towers) do
            if not matchedTargetIndices[tIdx] then
                local _, tBase = normalizeTower(targetName)
                if tBase ~= "" then
                    for cIdx, currentName in ipairs(CurrentlyEquipped) do
                        if not matchedCurrentIndices[cIdx] and not matchedTargetIndices[tIdx] then
                            local _, cBase = normalizeTower(currentName)
                            if cBase == tBase then
                                matchedCurrentIndices[cIdx] = true
                                matchedTargetIndices[tIdx] = true
                                break
                            end
                        end
                    end
                end
            end
        end

        -- Towers currently equipped that are not needed in target loadout
        local toUnequip = {}
        for cIdx, currentName in ipairs(CurrentlyEquipped) do
            if not matchedCurrentIndices[cIdx] then
                table.insert(toUnequip, currentName)
            end
        end

        -- Target towers that need to be equipped
        local toEquip = {}
        for tIdx, targetName in ipairs(towers) do
            if not matchedTargetIndices[tIdx] then
                table.insert(toEquip, targetName)
            end
        end

        -- If all target towers are already equipped and no unwanted towers exist, skip swap!
        if #toUnequip == 0 and #toEquip == 0 then
            warn("[TDS:Loadout] Target towers already equipped, no swap needed.")
            return true
        end

        -- Unequip only towers that are not needed
        for _, currentTower in ipairs(toUnequip) do
            local unequipDone = false
            local attempts = 0
            repeat
                attempts = attempts + 1
                local ok = pcall(function()
                    remote:FireServer("Inventory", "Unequip", "Tower", currentTower)
                    task.wait(0.3)
                end)
                if ok then unequipDone = true else task.wait(0.2) end
            until unequipDone or attempts >= 5
        end

        if #toUnequip > 0 then
            task.wait(0.4)
        end

        -- Equip only towers that are missing from current loadout
        for _, rawTowerName in ipairs(toEquip) do
            local towerName = getExactTowerName(rawTowerName)
            local equipSuccess = false
            local attempts = 0
            repeat
                attempts = attempts + 1
                local ok = pcall(function()
                    remote:FireServer("Inventory", "Equip", "Tower", towerName)
                    task.wait(0.3)
                end)
                if ok then equipSuccess = true else task.wait(0.2) end
            until equipSuccess or attempts >= 5
        end

        if #toEquip > 0 then
            task.wait(0.4)
        end

        return true
    end)

    IsCurrentlyLoading = false
    IsEquippingLoadout = false
    self.IsEquippingLoadout = false
    self.LoadoutPending = false
    LastLoadTime = os.clock()

    return success
end

function TDS:VoteSkip(StartWave, EndWave)
    task.spawn(function()
        local CurrentWave = GetCurrentWave()
        
        self.LastVoteSkipTarget = self.LastVoteSkipTarget or 0
        
        if not StartWave then
            if self.LastVoteSkipTarget < CurrentWave then
                self.LastVoteSkipTarget = CurrentWave
            else
                self.LastVoteSkipTarget = self.LastVoteSkipTarget + 1
            end
            StartWave = self.LastVoteSkipTarget
            EndWave = StartWave
        else
            EndWave = EndWave or StartWave
            self.LastVoteSkipTarget = EndWave
        end

        for wave = StartWave, EndWave do
            while GetCurrentWave() < wave do
                task.wait(1)
            end

            local TargetNextWave = wave + 1
            
            while GetCurrentWave() < TargetNextWave do
                local VoteUi = PlayerGui:FindFirstChild("ReactOverridesVote")
                local VoteButton = VoteUi 
                    and VoteUi:FindFirstChild("Frame") 
                    and VoteUi.Frame:FindFirstChild("votes") 
                    and VoteUi.Frame.votes:FindFirstChild("vote", true)

                if VoteButton and VoteButton.Position == UDim2.new(0.5, 0, 0.5, 0) then
                    pcall(function()
                        RemoteFunc:InvokeServer("Voting", "Skip")
                    end)
                end
                
                task.wait(0.5)
            end
        end
    end)
end

function TDS:GameInfo(name, list)
    if game.PlaceId == 3260590327 then return false end

    local VoteGui = PlayerGui:WaitForChild("ReactGameIntermission", 30)
    if not (VoteGui and VoteGui.Enabled and VoteGui:WaitForChild("Frame", 5)) then return end

    local modifiers = (list and next(list)) and list or Globals.Modifiers

    CastModifierVote(modifiers)

    local stateReplicators = game:GetService("ReplicatedStorage"):WaitForChild("StateReplicators", 5)
    local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")

    if MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) or (gameStateReplicator and gameStateReplicator:GetAttribute("IsPrivateServer") == true) then
        SelectMapOverride(name, "vip")
        repeat task.wait(1) until PlayerGui:FindFirstChild("ReactUniversalHotbar")
        return true 
    elseif IsMapAvailable(name) then
        SelectMapOverride(name)
        repeat task.wait(1) until PlayerGui:FindFirstChild("ReactUniversalHotbar")
        return true
    else
        RejoinMatch()
        repeat task.wait(9999) until false
    end
end

function TDS:StartGame()
    LobbyReadyUp()
end

function TDS:Ready()
    if game.PlaceId == 3260590327 then
        return false 
    end
    MatchReadyUp()
    return true
end

function TDS:GetWave()
    return GetCurrentWave()
end

function TDS:WaitForWave(targetWave)
    if game.PlaceId == 3260590327 then return false end
    while self:GetWave() < targetWave do
        task.wait(0.5)
    end
    return true
end

function TDS:RestartGame()
    TriggerRestart()
end

function TDS:Place(TName, px, py, pz, ...)
    local args = {...}
    local stack = false
 
    if args[#args] == "stack" or args[#args] == true then
        py = py+25
    end
    if game.PlaceId == 3260590327 then
        return false 
    end
 
    local towersFolder = workspace:FindFirstChild("Towers") or workspace:WaitForChild("Towers", 5)
    local existing = {}
    if towersFolder then
        for _, child in ipairs(towersFolder:GetChildren()) do
            for _, SubChild in ipairs(child:GetChildren()) do
                if SubChild.Name == "Owner" and SubChild.Value == LocalPlayer.UserId then
                    existing[child] = true
                    break
                end
            end
        end
    end
 
    DoPlaceTower(TName, Vector3.new(px, py, pz))
 
    local NewT
    local waitStart = os.time()
    repeat
        local curTowers = workspace:FindFirstChild("Towers")
        if curTowers then
            for _, child in ipairs(curTowers:GetChildren()) do
                if not existing[child] then
                    for _, SubChild in ipairs(child:GetChildren()) do
                        if SubChild.Name == "Owner" and SubChild.Value == LocalPlayer.UserId then
                            NewT = child
                            break
                        end
                    end
                end
                if NewT then break end
            end
        end
        if not NewT then task.wait(0.05) end
    until NewT or (os.time() - waitStart > 10)
 
    if NewT then
        table.insert(self.PlacedTowers, NewT)
    end
    return #self.PlacedTowers
end

function TDS:Upgrade(idx, PId)
    local t = self.PlacedTowers[idx]
    if t then
        DoUpgradeTower(t, PId or 1)
        UpgradeHistory[idx] = (UpgradeHistory[idx] or 0) + 1
    end
end

function TDS:SetTarget(idx, TargetType, ReqWave)
    if ReqWave then
        repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
    end

    local t = self.PlacedTowers[idx]
    if not t then return end

    pcall(function()
        RemoteFunc:InvokeServer("Troops", "Target", "Set", {
            Troop = t,
            Target = TargetType
        })
    end)
end

function TDS:Sell(idx, ReqWave)
    if ReqWave then
        repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
    end
    local t = self.PlacedTowers[idx]
    if t and DoSellTower(t) then
        return true
    end
    return false
end

function TDS:SellAll(ReqWave)
    task.spawn(function()
        if ReqWave then
            repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
        end

        local TowersCopy = {unpack(self.PlacedTowers)}
        for idx, t in ipairs(TowersCopy) do
            if DoSellTower(t) then
                for i, OrigT in ipairs(self.PlacedTowers) do
                    if OrigT == t then
                        table.remove(self.PlacedTowers, i)
                        break
                    end
                end
            end
        end

        return true
    end)
end

function TDS:Ability(idx, name, data, loop)
    local t = self.PlacedTowers[idx]
    if not t then return false end
    return DoActivateAbility(t, name, data, loop)
end

function TDS:AutoChain(...)
    local TowerIndices = {...}
    if #TowerIndices == 0 then return end

    local running = true

    task.spawn(function()
        local i = 1
        while running do
            local idx = TowerIndices[i]
            local tower = TDS.PlacedTowers[idx]

            if tower then
                DoActivateAbility(tower, "Call Of Arms")
            end

            task.wait(10.5)

            i += 1
            if i > #TowerIndices then
                i = 1
            end
        end
    end)

    return function()
        running = false
    end
end

function TDS:SetOption(idx, name, val, ReqWave)
    local t = self.PlacedTowers[idx]
    if t then
        return DoSetOption(t, name, val, ReqWave)
    end
    return false
end

if GameState == "LOBBY" and Globals.AutoRejoin and isfile("ADS_LastStrat.lua") then
    pcall(delfile, "ADS_LastStrat.lua")
end

if GameState == "GAME" and Globals.AutoRejoin and isfile("ADS_LastStrat.lua") then
    local stratContent = pcall(readfile, "ADS_LastStrat.lua") and readfile("ADS_LastStrat.lua") or ""
    if stratContent:find(":Loadout%(") then
        TDS.LoadoutPending = true
    end
    task.spawn(function()
        task.wait(2)
        TDS:RunStrategy()
    end)
end

local function IsVoidCharm(obj)
    return math.abs(obj.Position.Y) > 999999
end

local function GetRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function StartAutoGatling()
    if Globals.DisableAPIGatling or Globals.GatlingManagedByMain or Globals.GatlingLoaderLoaded then return end
    if AutoGatlingRunning or not Globals.AutoGatling then return end
    AutoGatlingRunning = true
    task.spawn(function()
        while Globals.AutoGatling and not Globals.DisableAPIGatling and not Globals.GatlingManagedByMain do
            if GameState == "GAME" then
                if not GatlingExecuted and not Globals.GatlingLoaderLoaded then
                    GatlingExecuted = true 
                    Globals.GatlingLoaderLoaded = true
                    task.spawn(function()
                        pcall(function()
                            local selected = Globals.SelectedGatling or "Gatlify"
                            if selected == "Gatling Gun" then
                                loadstring(game:HttpGet("https://raw.githubusercontent.com/avtryxz/autogutlin/refs/heads/main/autogutlin.lua"))()
                            else
                                loadstring(game:HttpGet("https://raw.githubusercontent.com/avtryxz/Gatlify/refs/heads/main/Gatlify.lua"))()
                            end
                        end)
                    end)
                end
            else
                GatlingExecuted = false 
            end
            task.wait(1)
        end
        AutoGatlingRunning = false
    end)
end

local function StartAutoSkip()
    if AutoSkipRunning or not Globals.AutoSkip then return end
    AutoSkipRunning = true

    task.spawn(function()
        while Globals.AutoSkip do
            local SkipVisible =
                PlayerGui:FindFirstChild("ReactOverridesVote")
                and PlayerGui.ReactOverridesVote:FindFirstChild("Frame")
                and PlayerGui.ReactOverridesVote.Frame:FindFirstChild("votes")
                and PlayerGui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")

            if SkipVisible and SkipVisible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                RunVoteSkip()
            end

            task.wait(0.1)
        end

        AutoSkipRunning = false
    end)
end

local function HandlePostMatch(forceRestart)
    if forceRestart == true or Globals.AutoRestart then
        TriggerRestart()
    else
        SmartTeleportToLobby()
    end
end

function StartBackToLobby()
    if game.PlaceId == 3260590327 then return end
    if BackToLobbyRunning then return end
    BackToLobbyRunning = true

    task.spawn(function()
        local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 30)
        local gameStateReplicator = stateReplicators and stateReplicators:WaitForChild("GameStateReplicator", 30)
        local voteReplicator = stateReplicators and stateReplicators:WaitForChild("VoteReplicator", 30)
        
        if not gameStateReplicator or not voteReplicator then
            while true do
                if not Globals.AutoRejoin and not Globals.AutoRestart then break end
                pcall(HandlePostMatch)
                task.wait(1)
            end
            BackToLobbyRunning = false
            return
        end

        while Globals.AutoRejoin or Globals.AutoRestart do
            local isGameOver = gameStateReplicator:GetAttribute("GameOver") == true
            if isGameOver then
                local health = gameStateReplicator:GetAttribute("Health") or 0
                if health > 0 then
                    if Globals.AutoRejoin then
                        if isfile("ADS_LastStrat.lua") then
                            pcall(delfile, "ADS_LastStrat.lua")
                        end
                        pcall(HandlePostMatch)
                        break
                    end
                else
                    if Globals.AutoRestart then
                        task.spawn(pcall, HandlePostMatch, true)
                        local lastVoteTime = 0
                        while Globals.AutoRestart do
                            local title = voteReplicator:GetAttribute("Title")
                            local enabled = voteReplicator:GetAttribute("Enabled")
                            
                            if enabled == true and title == "Restart?" then
                                if os.clock() - lastVoteTime > 3 then
                                    pcall(function()
                                        RemoteFunc:InvokeServer("Voting", "Skip")
                                    end)
                                    lastVoteTime = os.clock()
                                end
                            end
                            
                            if title == "Ready?" or gameStateReplicator:GetAttribute("GameOver") == false then
                                break
                            end
                            task.wait(0.5)
                        end
                        
                        if not Globals.AutoRestart then break end
                        
                        if isfile("ADS_LastStrat.lua") then
                            task.spawn(function()
                                repeat
                                    task.wait(0.1)
                                    local towersFolder = workspace:FindFirstChild("Towers")
                                until (towersFolder and #towersFolder:GetChildren() == 0) or not Globals.AutoRestart
                                
                                if not Globals.AutoRestart then return end
                                TDS:ResetAllStates()
                                TDS:RunStrategy()
                            end)
                        end
                        
                        repeat task.wait(1) until gameStateReplicator:GetAttribute("GameOver") == false or not Globals.AutoRestart
                    elseif Globals.AutoRejoin then
                        if isfile("ADS_LastStrat.lua") then
                            pcall(delfile, "ADS_LastStrat.lua")
                        end
                        pcall(HandlePostMatch)
                        break
                    end
                end
            end
            task.wait(1)
        end
        BackToLobbyRunning = false
    end)
end

local function StartAntiLag()
    if AntiLagRunning or not Globals.AntiLag then return end
    AntiLagRunning = true

    local settings = settings().Rendering
    settings.QualityLevel = Enum.QualityLevel.Level01

    task.spawn(function()
        while Globals.AntiLag do
            local TowersFolder = workspace:FindFirstChild("Towers")
            local ClientUnits = workspace:FindFirstChild("ClientUnits")

            if TowersFolder then
                for _, tower in ipairs(TowersFolder:GetChildren()) do
                    local anims = tower:FindFirstChild("Animations")
                    local weapon = tower:FindFirstChild("Weapon")
                    local projectiles = tower:FindFirstChild("Projectiles")

                    if anims then anims:Destroy() end
                    if projectiles then projectiles:Destroy() end
                    if weapon then weapon:Destroy() end
                end
            end
            if ClientUnits then
                for _, unit in ipairs(ClientUnits:GetChildren()) do
                    unit:Destroy()
                end
            end
            
            task.wait(0.5)
        end
        AntiLagRunning = false
    end)
end

local function StartAutoChain()
    if AutoChainRunning or not Globals.AutoChain then return end
    AutoChainRunning = true

    task.spawn(function()
        local idx = 1

        while Globals.AutoChain do
            local commander = {}
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if not Globals.AutoChain then break end
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Commander"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 2 then
                        commander[#commander + 1] = towers.Parent
                    end
                end
            end

            if not Globals.AutoChain then break end

            if #commander >= 3 then
                if idx > #commander then idx = 1 end

                local CurrentCommander = commander[idx]
                local replicator = CurrentCommander and CurrentCommander:FindFirstChild("TowerReplicator")
                local UpgradeLevel = replicator and replicator:GetAttribute("Upgrade") or 0

                if UpgradeLevel >= 4 and Globals.SupportCaravan then
                    RemoteFunc:InvokeServer(
                        "Troops",
                        "Abilities",
                        "Activate",
                        { Troop = CurrentCommander, Name = "Support Caravan", Data = {} }
                    )
                    task.wait(0.1) 
                end

                if not Globals.AutoChain then break end

                local response = RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = CurrentCommander, Name = "Call Of Arms", Data = {} }
                )

                if response then
                    idx += 1
                    task.wait(10.3)
                else
                    task.wait(0.5)
                end
            else
                task.wait(1)
            end
        end

        AutoChainRunning = false
    end)
end

local function StartAutoDjBooth()
    if AutoDjRunning or not Globals.AutoDJ then return end
    AutoDjRunning = true

    task.spawn(function()
        while Globals.AutoDJ do
            local DJ = nil
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if not Globals.AutoDJ then break end
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "DJ Booth"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 3 then
                        DJ = towers.Parent
                    end
                end
            end

            if not Globals.AutoDJ then break end

            if DJ then
                RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = DJ, Name = "Drop The Beat", Data = {} }
                )
            end

            task.wait(1)
        end

        AutoDjRunning = false
    end)
end

local function StartAutoNecro()
    if AutoNecroRunning or not Globals.AutoNecro then return end
    AutoNecroRunning = true

    local lastActivation = 0
    local ownerId = game.Players.LocalPlayer.UserId

    local function getNecros(towersFolder)
        local list = {}
        if not towersFolder then
            return list
        end
        for _, rep in ipairs(towersFolder:GetDescendants()) do
            if not Globals.AutoNecro then break end
            if rep:IsA("Folder") and rep.Name == "TowerReplicator"
            and rep:GetAttribute("Name") == "Necromancer"
            and rep:GetAttribute("OwnerId") == ownerId then
                list[#list + 1] = rep.Parent
            end
        end
        return list
    end

    local function pickMaxGraves(rep, graveStore, up)
        local maxGraves = rep and rep:GetAttribute("Max_Graves")
        if graveStore then
            local gMax = graveStore:GetAttribute("Max_Graves")
            if type(gMax) == "number" and gMax > 0 then
                maxGraves = gMax
            end
        end
        if not maxGraves or maxGraves < 2 then
            if up >= 4 then
                maxGraves = 9
            elseif up >= 2 then
                maxGraves = 6
            else
                maxGraves = 3
            end
        end
        return maxGraves
    end

    local function countGraves(graveStore)
        if not graveStore then
            return 0
        end
        local cnt = 0
        for k, v in pairs(graveStore:GetAttributes()) do
            if type(k) == "string" and #k > 20 then
                local isDestroy = false
                if type(v) == "table" then
                    for _, elem in pairs(v) do
                        if tostring(elem) == "Destroy" then
                            isDestroy = true
                            break
                        end
                    end
                elseif tostring(v):find("Destroy") then
                    isDestroy = true
                end
                if isDestroy then
                    graveStore:SetAttribute(k, nil)
                else
                    cnt += 1
                end
            end
        end
        return cnt
    end

    local function cleanAllGraves(list)
        for _, necro in ipairs(list) do
            if not Globals.AutoNecro then break end
            local rep = necro and necro:FindFirstChild("TowerReplicator")
            local store = rep and rep:FindFirstChild("GraveStone")
            if store then
                countGraves(store)
            end
        end
    end

    task.spawn(function()
        local idx = 1

        while Globals.AutoNecro do
            local TowersFolder = workspace:FindFirstChild("Towers")
            local necromancer = getNecros(TowersFolder)
            cleanAllGraves(necromancer)

            if not Globals.AutoNecro then break end

            if #necromancer >= 1 then
                if idx > #necromancer then idx = 1 end
                local CurrentNecromancer = necromancer[idx]
                local replicator = CurrentNecromancer and CurrentNecromancer:FindFirstChild("TowerReplicator")

                local up = replicator and (replicator:GetAttribute("Upgrade") or 0) or 0
                local graveStore = replicator and replicator:FindFirstChild("GraveStone")
                local maxGraves = pickMaxGraves(replicator, graveStore, up)
                local graveCount = countGraves(graveStore)
                local debounce = (replicator and replicator:GetAttribute("AbilityDebounce")) or 5
                local now = os.clock()

                if maxGraves and graveCount >= maxGraves and (now - lastActivation >= debounce) then
                    if not Globals.AutoNecro then break end
                    local response = RemoteFunc:InvokeServer(
                        "Troops",
                        "Abilities",
                        "Activate",
                        { Troop = CurrentNecromancer, Name = "Raise The Dead", Data = {} }
                    )

                    if response then 
                        lastActivation = now
                        idx += 1
                        task.wait(1)
                    else
                        task.wait(0.5)
                    end
                else
                    task.wait(0.1)
                end
            else
                task.wait(1)
            end
        end

        AutoNecroRunning = false
    end)
end

local function StartAutoMercenary()
    if not Globals.AutoMercenary then return end

    if AutoMercenaryBaseRunning then return end
    AutoMercenaryBaseRunning = true

    task.spawn(function()
        while Globals.AutoMercenary do
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if not Globals.AutoMercenary then break end
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Mercenary Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 5 then

                        RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { 
                                Troop = towers.Parent, 
                                Name = "Air-Drop", 
                                Data = {
                                    pathName = 1, 
                                    directionCFrame = CFrame.new(), 
                                    dist = Globals.MercenaryPath or 195
                                } 
                            }
                        )

                        task.wait(0.5)

                        if not Globals.AutoMercenary then break end
                    end
                end
            end

            task.wait(0.5)
        end

        AutoMercenaryBaseRunning = false
    end)
end

local function StartAutoMilitary()
    if not Globals.AutoMilitary then return end

    if AutoMilitaryBaseRunning then return end
    AutoMilitaryBaseRunning = true

    task.spawn(function()
        while Globals.AutoMilitary do
            local TowersFolder = workspace:FindFirstChild("Towers")
            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if not Globals.AutoMilitary then break end
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Military Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 4 then

                        RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { 
                                Troop = towers.Parent, 
                                Name = "Airstrike", 
                                Data = {
                                    pathName = 1, 
                                    pointToEnd = CFrame.new(), 
                                    dist = Globals.MilitaryPath or 195
                                } 
                            }
                        )

                        task.wait(0.5)

                        if not Globals.AutoMilitary then break end
                    end
                end
            end

            task.wait(0.5)
        end

        AutoMilitaryBaseRunning = false
    end)
end

local AutoMedicModule = nil

local function StartMedicChain()
    if Globals.AutoMedic then
        if AutoMedicModule and AutoMedicModule.State and AutoMedicModule.State.Running then 
            return 
        end

        local myMedics = {}
        repeat
            if not Globals.AutoMedic then return end
            myMedics = {}
            local towersFolder = game:GetService("Workspace"):FindFirstChild("Towers")
            
            if towersFolder then
                for _, tower in ipairs(towersFolder:GetChildren()) do
                    if not Globals.AutoMedic then return end
                    local replicator = tower:FindFirstChild("TowerReplicator")
                    if replicator then
                        local ownerId = replicator:GetAttribute("OwnerId")
                        local ownerName = replicator:GetAttribute("OwnerName")
                        local towerName = replicator:GetAttribute("Name")

                        local localPlayer = game:GetService("Players").LocalPlayer
                        local isOwner = (ownerId and ownerId == localPlayer.UserId) or (ownerName and ownerName == localPlayer.Name)

                        if isOwner and towerName and string.lower(towerName) == "medic" then
                            table.insert(myMedics, tower)
                        end
                    end
                end
            end

            if #myMedics < 4 then
                task.wait(1)
            end
        until #myMedics >= 4 or not Globals.AutoMedic

        if not Globals.AutoMedic then return end

        if not AutoMedicModule then
            local success, loadedLib = pcall(function()
                local url = "https://raw.githubusercontent.com/AmonguszzZ/ModdedAether/refs/heads/main/AutoAbilities/AutoMedicNew.lua"
                return loadstring(game:HttpGet(url))()
            end)
            if success and loadedLib then
                AutoMedicModule = loadedLib
            end
        end
        if AutoMedicModule and Globals.AutoMedic then
            AutoMedicModule.Chaining()
        end
    else
        if AutoMedicModule and AutoMedicModule.State then
            AutoMedicModule.State.Running = false
        end
    end
end

function TDS:Rejoin()
    SmartTeleportToLobby()
end

function TDS:RemoveIndex()
    ModuleRunning = false
    if errorMessageConnection then
        pcall(function() errorMessageConnection:Disconnect() end)
        errorMessageConnection = nil
    end
    if idleConnection then
        pcall(function() idleConnection:Disconnect() end)
        idleConnection = nil
    end

	self.PlacedTowers = {}
    self.PlacedTraps = {}
    self.MapInteractions = {}
  
    if UpgradeHistory then
        table.clear(UpgradeHistory)
    end
	
end

task.spawn(function()
    task.wait(2)
    while ModuleRunning do

        if Globals.AutoSkip and not AutoSkipRunning then
            StartAutoSkip()
        end

        if Globals.AutoChain and not AutoChainRunning then
            StartAutoChain()
        end

        if Globals.AutoDJ and not AutoDjRunning then
            StartAutoDjBooth()
        end

        if Globals.AutoNecro and not AutoNecroRunning then
            StartAutoNecro()
        end

        if Globals.AutoMercenary and not AutoMercenaryBaseRunning then
            StartAutoMercenary()
        end

        if Globals.AutoMilitary and not AutoMilitaryBaseRunning then
            StartAutoMilitary()
        end

        if Globals.AntiLag and not AntiLagRunning then
            StartAntiLag()
        end

        if (Globals.AutoRejoin or Globals.AutoRestart) and not BackToLobbyRunning then
            StartBackToLobby()
        end

        if Globals.AutoGatling and not AutoGatlingRunning and not Globals.DisableAPIGatling and not Globals.GatlingManagedByMain then
            StartAutoGatling()
        end

        if Globals.AutoReady and not AutoReadyRunning then
            StartAutoReady()
        end

        if Globals.AutoMedic and not AutoMedicRunning then
            StartMedicChain()
        end
		
        task.wait(1)
    end
end)

MissionsUIFix()

return TDS
