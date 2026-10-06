--!strict
--==============================================================================
-- Service Hub v9.8 [Loadstring Version]
-- Direct Cloud Execution Suite (Loads all modules directly via GitHub Cloud Loadstring)
--
-- Optimized Tower Defense Simulator (TDS) Automation Suite (Mobile & Low-End Performance Boosted)
-- Auto Coins/Gems, Auto Trials, Smart Matchmaking & Fallback System
-- Featuring Trial Farm Mode (Farm Mode | Progression Mode) & Farm Only Mode
-- Integrated with CoreRevampNewAPI & Remote Strategy Cache
--==============================================================================
-- Prevent Execution Crashes on Teleport
if not game:IsLoaded() then
    local loadedConn
    local isLoaded = false
    loadedConn = game.Loaded:Connect(function()
        isLoaded = true
        if loadedConn then loadedConn:Disconnect() end
    end)
    local t0 = tick()
    while not game:IsLoaded() and not isLoaded and (tick() - t0 < 10) do
        task.wait(0.5)
    end
    if loadedConn then pcall(function() loadedConn:Disconnect() end) end
    task.wait(0.5)
else
    task.wait(0.1) -- Fast buffer when already loaded
end

-- Global Environment Initialization
local Globals = getgenv()
Globals.GatlingManagedByMain = true
Globals.DisableAPIGatling = true

-- Forward declarations used by the unload callback. Declaring these here keeps
-- the callback from accidentally resolving nil globals on re-execution.
local Players, UserInputService, ReplicatedStorage, HttpService, TeleportService, MarketplaceService
local LocalPlayer, PlayerGui
local activeStratThread: thread? = nil
local attemptBuyMissingTowersList: (({string}?) -> boolean)? = nil
local sendEvoPurchaseWebhook: ((string, string) -> ())? = nil
local AutoGatlingRunning = false
local AutoReloadRunning = false

--==============================================================================
--==============================================================================
-- Filesystem & Network Helpers (Cloud Loadstring Engine)
--==============================================================================
local function ensureFolder(folderPath: string)
    pcall(function()
        if isfolder and not isfolder(folderPath) and makefolder then
            makefolder(folderPath)
        elseif not isfolder and makefolder then
            makefolder(folderPath)
        end
    end)
end

local function safeHttpGet(url: string, retries: number?): string?
    local maxTries = retries or 3
    for attempt = 1, maxTries do
        local success, result = pcall(function()
            return game:HttpGet(url)
        end)
        if success and type(result) == "string" and #result > 0 then
            return result
        end
        if attempt < maxTries then
            task.wait(1.5)
        end
    end
    return nil
end
local function readLocalFile(fileName: string, fallbackPaths: {string}?): (string?, string?)
    if type(readfile) ~= "function" then
        return nil, nil
    end

    local candidates = { fileName }
    if type(fallbackPaths) == "table" then
        for _, path in ipairs(fallbackPaths) do
            if type(path) == "string" and path ~= "" and path ~= fileName then
                table.insert(candidates, path)
            end
        end
    end

    for _, path in ipairs(candidates) do
        local ok, content = pcall(function()
            if type(isfile) == "function" and not isfile(path) then
                return nil
            end
            return readfile(path)
        end)
        if ok and type(content) == "string" and #content > 0 then
            return content, path
        end
    end
    return nil, nil
end

-- 2-in-1 loader for TDS Loadout Helper (readfile first -> cloud secondary)
local function loadTDSAPI(): any
    local function sanitizeAPIChunk(code: string): string
        local patched = code
        -- Neuter duplicate StartAutoGatling in API.lua so Gatling loading is exclusively handled by AutoTrailsFinal
        patched = patched:gsub("if Globals%.AutoGatling and not AutoGatlingRunning then%s*StartAutoGatling%(%)%s*end", "-- [ServiceHub] API Gatling disabled; managed by AutoTrails")
        -- Do not pattern-replace the whole function: a non-greedy match stops at
        -- the first nested `end` and can produce invalid Luau. API.lua already
        -- honors DisableAPIGatling/GatlingManagedByMain at runtime.
        return patched
    end

    Globals.GatlingManagedByMain = true
    Globals.DisableAPIGatling = true
    local function tryChunk(chunk: string?): any
        if type(chunk) ~= "string" or #chunk == 0 or chunk:find("Centurion") then
            return nil
        end
        chunk = sanitizeAPIChunk(chunk)
        local compiled, fn = pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            return loadstring(chunk)
        end)
        if not compiled or type(fn) ~= "function" then
            return nil
        end
        local executed, result = pcall(fn)
        if executed and type(result) == "table" then
            return result
        end
        return nil
    end

    local localChunk = readLocalFile("API.lua", {
        "files/API.lua",
        "[STAY]/[AutoTrailsFInal]/FinalVersion/files/API.lua",
        "[STAY]/[AutoTrailsFInal]/files/API.lua",
    })
    local localModule = tryChunk(localChunk)
    if localModule then return localModule end

    local urls = {
        "https://raw.githubusercontent.com/Atxvy/-FINALVERSION-/refs/heads/main/API.lua",
        "https://raw.githubusercontent.com/Atxvy/-ATF-/refs/heads/main/API.lua",
    }
    for _, url in ipairs(urls) do
        local cloudModule = tryChunk(safeHttpGet(url, 3))
        if cloudModule then return cloudModule end
    end
    return nil
end
local TDS: any = loadTDSAPI()
if TDS then
    Globals.TDS = TDS
    pcall(function() getgenv().TDS = TDS end)
    pcall(function() _G.TDS = TDS end)
end

if Globals.ServiceHub_Unload then
    pcall(Globals.ServiceHub_Unload)
end

local isRunning = true
Globals.IsConfigDirty = false
Globals.ServiceHub_Unload = function()
    isRunning = false
    Globals.ServiceHub_Running = false
    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
        pcall(task.cancel, activeStratThread)
        activeStratThread = nil
    end
    if TDS and typeof(TDS.RemoveIndex) == "function" then
        pcall(function() TDS:RemoveIndex() end)
    end
    if Globals.ServiceHub_ScreenGui then
        pcall(function() Globals.ServiceHub_ScreenGui:Destroy() end)
        Globals.ServiceHub_ScreenGui = nil
    end
    pcall(function()
        local getParent = function()
            if gethui then
                local ok, h = pcall(gethui)
                if ok and h then return h end
            end
            local ok, parent = pcall(function() return game:GetService("CoreGui") end)
            if ok and parent then return parent end
            return Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
        end
        local parentGui = getParent()
        if parentGui then
            for _, name in ipairs({ "ServiceHub_Window", "CyberNeon_Window", "SkyBlueUI_Window" }) do
                pcall(function()
                    local found = parentGui:FindFirstChild(name)
                    if found then found:Destroy() end
                end)
            end
        end
        local lp = Players.LocalPlayer
        local pg = lp and lp:FindFirstChild("PlayerGui")
        if pg then
            for _, name in ipairs({ "ServiceHub_Window", "CyberNeon_Window", "SkyBlueUI_Window" }) do
                pcall(function()
                    local found = pg:FindFirstChild(name)
                    if found then found:Destroy() end
                end)
            end
        end
    end)
end

do
    local defaultGlobals = {
        AutoSkip = false,
        AutoSkips = false,
        AutoRestart = false,
        AutoReady = false,
        AutoMedic = false,
        AutoChain = false,
        SupportCaravan = false,
        AutoGatling = true,
        SelectedGatling = "Gatlify",
        AutoDJ = false,
        AutoNecro = false,
        AutoRejoin = false,
        AutoMercenary = false,
        AutoReset = false,
        AutoBack = false,
        TimeScaleEnabled = false,
        TimeScaleValue = 2,
        TargetTimescale = 0,
        TimescaleUsedSession = 0,
        TrialFarmMode = "Farm Mode",
        FarmOnly = "Disabled",
        MultiplayerEnabled = true,
        MultiplayerMode = "Trial Mode",
        MultiplayerRole = "Host",
        MultiplayerIsHost = false,
        MultiplayerHostIdentifier = "",
        MultiplayerTargetP2 = "",
        MultiplayerIsP2 = false,
        MultiplayerTargetHost = "",
        PrivateServerCode = "",
        LobbyWatcherEnabled = true,
        PreferredAccessTier = "Keyless",
        BuyMissingCoinsTower = false,
        BuyMissingGemTower = false,
        BuyMissingEvoTower = false,
        BuyMissingGoldSkins = false,
        BuySkillTree = false,
    }
    for k, v in pairs(defaultGlobals) do
        if Globals[k] == nil then
            Globals[k] = v
        end
    end
end

-- Roblox Engine Services
Players = game:GetService("Players")
UserInputService = game:GetService("UserInputService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
HttpService = game:GetService("HttpService")
TeleportService = game:GetService("TeleportService")
MarketplaceService = game:GetService("MarketplaceService")

LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    local t0 = tick()
    while not Players.LocalPlayer and (tick() - t0 < 10) do
        task.wait(0.1)
    end
    LocalPlayer = Players.LocalPlayer
end
if not LocalPlayer then
    error("[ServiceHub] LocalPlayer was unavailable after waiting 10 seconds")
end
PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10) or LocalPlayer:FindFirstChild("PlayerGui")
if not PlayerGui then
    error("[ServiceHub] PlayerGui was unavailable after waiting 10 seconds")
end
local LOBBY_PLACE_ID = 3260590327

-- Configuration Directory & File Paths ([ATF] Configuration Suite)
local CONFIG_FOLDER = "[ATF]"
local TRIAL_STATE_FILE_NAME = tostring(LocalPlayer.UserId) .. "_trialstate.txt"
local SETTINGS_FILE_NAME = tostring(LocalPlayer.UserId) .. ".json"

local TRIAL_STATE_FILE = CONFIG_FOLDER .. "/" .. TRIAL_STATE_FILE_NAME
local SETTINGS_FILE = CONFIG_FOLDER .. "/" .. SETTINGS_FILE_NAME
local ACTIVE_MODE_FILE = CONFIG_FOLDER .. "/" .. tostring(LocalPlayer.UserId) .. "_active_mode.txt"
local ACTIVE_FARM_TYPE_FILE = CONFIG_FOLDER .. "/" .. tostring(LocalPlayer.UserId) .. "_active_farm_type.txt"
local VERIFIED_KEY_FILE = CONFIG_FOLDER .. "/verified_key.txt"

local TimeScaleRunning = false
local TimeScaleNoTicketsWarned = false

--==============================================================================
--==============================================================================
-- PlayerDataHandler (Loaded First as Required via Readfile / Cloud Fallback)
--==============================================================================
local PlayerDataHandler: any = nil
local playerDataLoading = false

local function createEmbeddedPlayerDataHandler(): any
--[[
    Embedded DataHandler Suite (Clean, Synchronous, Capability-Safe)
    Eliminates external network dependencies and prevents Centurion obfuscation crashes.
]]--
--[[
    CombinedData
    Description:
        Provides a single API that merges Tower Ownership, Golden Skin/Perks detection,
        Tower EXP progression, Skill‑tree extraction, and Player Stats (Level/EXP/Coins/Gems).
        • Accurate Golden tower ownership (checks Inventory.Skins, not just equipped state).
        • Active Golden perks detector (checks if perk is enabled in loadout).
        • Full Tower EXP progression for all 8 towers (progress, required, max level, uncapped).
        • Fast Cache-based Player Stats: Values.Level, Values.Experience, Experience(level + 1),
          Values.Coins, and Values.Gems with safe fallback layers.
        • Skill‑tree extraction from Workspace["1"] … Workspace["17"].
        • Lightweight, synchronous, and safe for mobile/third-party executors.
]]--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- ---------------------------------------------------------------------
-- Core helpers (LocalPlayer, PlayerGui, number parsing)
-- ---------------------------------------------------------------------
local function getLocalPlayer()
    local lp = Players.LocalPlayer
    if not lp then
        pcall(function()
            Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        end)
        lp = Players.LocalPlayer
    end
    return lp
end

local function getPlayerGui(timeout)
    timeout = timeout or 1
    local lp = getLocalPlayer()
    if not lp then return nil end
    local pgui = lp:FindFirstChild("PlayerGui")
    if not pgui and timeout > 0 then
        pgui = lp:WaitForChild("PlayerGui", timeout)
    end
    return pgui
end

local function parseNumber(str)
    if not str then return 0 end
    local cleaned = tostring(str):gsub("<[^>]+>", ""):match("[%d,]+")
    cleaned = cleaned and cleaned:gsub("%D", "") or ""
    return tonumber(cleaned) or 0
end

-- ---------------------------------------------------------------------
-- Internal Cache & Game Module Access
-- ---------------------------------------------------------------------
local Cache = nil
local Experience = nil
local TowerExpUtil = nil
local Content = nil
local InventoryController = nil
local MatchmakingTrialData = nil

pcall(function()
    Cache = require(ReplicatedStorage.Client.Modules.Cache)
end)
pcall(function()
    Experience = require(ReplicatedStorage.Shared.Modules.Experience)
end)
pcall(function()
    TowerExpUtil = require(ReplicatedStorage.Shared.Modules.TowerExpUtil)
end)
pcall(function()
    Content = require(ReplicatedStorage.Shared.Modules.Content)
end)
pcall(function()
    InventoryController = require(ReplicatedStorage.Client.Interfaces.LegacyInterface.Controllers.InventoryController)
end)
pcall(function()
    MatchmakingTrialData = require(ReplicatedStorage.Client.Interfaces.Lobby.Components.NewMatchmaking.MatchmakingTrialData)
end)

-- Helper to safely get value synchronously without yielding or dropping thread capability
local function getStat(name)
    if Cache and (type(Cache) == "table" or type(Cache) == "function") then
        local ok, val = pcall(function()
            local atom = Cache(name)
            if atom ~= nil then
                if type(atom) == "function" then
                    local fastVal = atom()
                    if fastVal ~= nil then return fastVal end
                end
                if type(atom) == "table" then
                    if type(atom.GetValue) == "function" then
                        local fastVal = atom:GetValue()
                        if fastVal ~= nil then return fastVal end
                    end
                    if type(atom.get) == "function" then
                        local fastVal = atom:get()
                        if fastVal ~= nil then return fastVal end
                    end
                    if type(atom.getState) == "function" then
                        local fastVal = atom:getState()
                        if fastVal ~= nil then return fastVal end
                    end
                    if atom._value ~= nil then return atom._value end
                    if atom.value ~= nil then return atom.value end
                    if atom.state ~= nil then return atom.state end
                end
            end
            return nil
        end)
        if ok and val ~= nil then
            return val
        end
    end
    return nil
end

local function getCacheValue(cacheName)
    return getStat(cacheName)
end

-- ---------------------------------------------------------------------
-- Main Module Definition
-- ---------------------------------------------------------------------
local CombinedData = {}
CombinedData.__index = CombinedData

local SkillTreeData = {
    [1] = { Name = "Enhanced Optics" },
    [2] = { Name = "Resourcefulness" },
    [3] = { Name = "Fortify" },
    [4] = { Name = "Over-Heal" },
    [5] = { Name = "Fight Dirty" },
    [6] = { Name = "Extreme Conditioning" },
    [7] = { Name = "Stonks" },
    [8] = { Name = "Expanded Barracks" },
    [9] = { Name = "Improved Gunpowder" },
    [10] = { Name = "Beefed Up Minions" },
    [11] = { Name = "Precision" },
    [12] = { Name = "Scavenger" },
    [13] = { Name = "Accelerator" },
    [14] = { Name = "Re-enforcements" },
    [15] = { Name = "Bigger Budget" },
    [16] = { Name = "Bandages" },
    [17] = { Name = "Scholar" },
}

CombinedData.SkillTreeData = SkillTreeData

-- List of all 8 towers with progression systems
CombinedData.ProgressionTowers = {
    "Scout",
    "Shotgunner",
    "Crook Boss",
    "Minigunner",
    "EvolvedOperator",
    "EvolvedEnforcer",
    "EvolvedKingpin",
    "EvolvedJuggernaut"
}

-- ---------------------------------------------------------------------
-- Tower Ownership (Cache -> InventoryController -> UI Scan)
-- ---------------------------------------------------------------------
local function getScrollingContainer(idx)
    local pgui = getPlayerGui()
    if not pgui then return nil end
    local path = {
        "ReactUniversalInventoryView",
        "Holder",
        "windowFrame",
        "towersInventoryFrame",
        "towerContainer",
        idx .. "scrolling"
    }
    local node = pgui
    for _, childName in ipairs(path) do
        node = node:FindFirstChild(childName)
        if not node then return nil end
    end
    return node
end

function CombinedData:IsTowerOwned(towerName)
    if not towerName or towerName == "" then return false end

    -- 1. Fast Cache Check
    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" then
        if troops[towerName] ~= nil then
            return true
        end
    end

    -- 2. InventoryController Check
    if InventoryController and type(InventoryController.getItems) == "function" then
        local success, items = pcall(function() return InventoryController:getItems() end)
        if success and items then
            for _, item in pairs(items) do
                if type(item) == "table" and item.type == "tower" and item.name == towerName then
                    return true
                end
            end
        end
    end

    -- 3. UI Scrolling Container Fallback
    for i = 1, 7 do
        local container = getScrollingContainer(i)
        if container then
            local towerNode = container:FindFirstChild(towerName)
            if towerNode then
                local main = towerNode:FindFirstChild("main")
                if main and main:FindFirstChild("amountLeft") then
                    return true
                end
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------
-- Golden Towers Ownership & Active Perks
-- ---------------------------------------------------------------------

--- Checks if the player OWNS the Golden version of a tower (even if another skin is equipped)
function CombinedData:IsGoldenOwned(towerName)
    if not towerName or towerName == "" then return false end

    -- 1. Check Inventory.Skins (Direct ownership list)
    local skins = getCacheValue("Inventory.Skins")
    if skins and type(skins) == "table" and skins[towerName] then
        for _, skin in ipairs(skins[towerName]) do
            if type(skin) == "table" and skin.Name == "Golden" then
                return true
            end
        end
    end

    -- 2. Check Inventory.Troops (Equipped / Perk state)
    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" and troops[towerName] then
        local tData = troops[towerName]
        if tData.GoldenPerks == true or tData.Skin == "Golden" then
            return true
        end
    end

    -- 3. InventoryController Fallback
    if InventoryController and type(InventoryController.getItems) == "function" then
        local success, items = pcall(function() return InventoryController:getItems() end)
        if success and items then
            for _, item in pairs(items) do
                if type(item) == "table" and item.type == "tower" and item.name == towerName then
                    if item.golden == true or item.skin == "Golden" then
                        return true
                    end
                end
            end
        end
    end

    return false
end

--- Returns a list and a set of all Golden Towers owned by the player
function CombinedData:GetGoldenOwned()
    local list = {}
    local set = {}

    local skins = getCacheValue("Inventory.Skins")
    if skins and type(skins) == "table" then
        for tower, skinList in pairs(skins) do
            if type(skinList) == "table" then
                for _, skin in ipairs(skinList) do
                    if type(skin) == "table" and skin.Name == "Golden" then
                        table.insert(list, tower)
                        set[tower] = true
                        break
                    end
                end
            end
        end
    end

    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" then
        for tower, data in pairs(troops) do
            if not set[tower] and type(data) == "table" and (data.GoldenPerks == true or data.Skin == "Golden") then
                table.insert(list, tower)
                set[tower] = true
            end
        end
    end

    table.sort(list)
    return list, set
end

--- Checks if a tower currently has its Golden Perk toggled ON
function CombinedData:IsGoldenPerkActive(towerName)
    if not towerName or towerName == "" then return false end

    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" and troops[towerName] then
        return troops[towerName].GoldenPerks == true
    end

    if InventoryController and type(InventoryController.getItems) == "function" then
        local success, items = pcall(function() return InventoryController:getItems() end)
        if success and items then
            for _, item in pairs(items) do
                if type(item) == "table" and item.type == "tower" and item.name == towerName then
                    return item.golden == true
                end
            end
        end
    end

    return false
end

--- Returns a list of all towers that currently have Golden Perks enabled
function CombinedData:GetActiveGoldenPerks()
    local activeList = {}
    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" then
        for tower, data in pairs(troops) do
            if type(data) == "table" and data.GoldenPerks == true then
                table.insert(activeList, tower)
            end
        end
    end
    table.sort(activeList)
    return activeList
end

-- ---------------------------------------------------------------------
-- Tower EXP & Progression System
-- ---------------------------------------------------------------------
local function calculateExpStats(currentExp, baseExp, growthRate, maxLevel)
    currentExp = currentExp or 0
    baseExp = baseExp or 50
    growthRate = growthRate or 1.09
    maxLevel = maxLevel or 20

    local totalRequiredForMax = 0
    local levelCosts = {}
    for i = 1, maxLevel do
        local cost = math.floor(baseExp * (growthRate ^ (i - 1)))
        totalRequiredForMax = totalRequiredForMax + cost
        levelCosts[i] = cost
    end

    local sum = 0
    local cappedLevel = 0
    for i = 1, maxLevel do
        sum = sum + levelCosts[i]
        if currentExp < sum then break end
        cappedLevel = i
    end

    local totalExpCurrentLevel = 0
    for i = 1, cappedLevel do
        totalExpCurrentLevel = totalExpCurrentLevel + levelCosts[i]
    end

    local nextLevelCost = 0
    if cappedLevel < maxLevel then
        nextLevelCost = math.floor(baseExp * (growthRate ^ cappedLevel))
    else
        nextLevelCost = levelCosts[maxLevel] or 0
    end

    local currentProgress = math.max(currentExp - totalExpCurrentLevel, 0)
    local isMax = cappedLevel >= maxLevel
    if isMax then
        currentProgress = nextLevelCost
    end

    local uncappedSum = 0
    local uncappedLevel = 0
    while true do
        local cost = math.floor(baseExp * (growthRate ^ uncappedLevel))
        if currentExp < uncappedSum + cost then break end
        uncappedSum = uncappedSum + cost
        uncappedLevel = uncappedLevel + 1
    end

    local progressDisplay = ""
    if isMax then
        progressDisplay = string.format("MAX (%d EXP)", currentExp)
    else
        progressDisplay = string.format("%d / %d EXP", currentProgress, nextLevelCost)
    end

    local overallDisplay = string.format("%d / %d EXP", currentExp, totalRequiredForMax)

    return {
        level = cappedLevel,
        uncappedLevel = uncappedLevel,
        totalRequiredForMax = totalRequiredForMax,
        currentProgress = currentProgress,
        nextLevelCost = nextLevelCost,
        progressDisplay = progressDisplay,
        overallDisplay = overallDisplay,
        isMax = isMax
    }
end

local towerProgressionStaticCache = {}

function CombinedData:GetTowerExp(towerName)
    if not towerName or towerName == "" then return nil end

    local expCache = getCacheValue("TowerExp") or {}
    local currentExp = expCache[towerName] or 0

    local staticData = towerProgressionStaticCache[towerName]
    if not staticData then
        local baseExp = 50
        local growthRate = 1.09
        local maxLevel = 20
        local evolvedTo = nil

        if Content then
            local ok, towerFolder = pcall(Content, "Tower")
            if ok and towerFolder then
                local towerInst = towerFolder:FindFirstChild(towerName)
                local stats = towerInst and towerInst:FindFirstChild("Stats")
                if stats and stats:IsA("ModuleScript") then
                    local success, mod = pcall(require, stats)
                    if success and mod and mod.Properties and mod.Properties.Progression then
                        local prog = mod.Properties.Progression
                        baseExp = prog.BaseExp or baseExp
                        growthRate = prog.GrowthRate or growthRate
                        maxLevel = prog.MaxLevel or maxLevel
                        evolvedTo = mod.Properties.EvolvedTo
                    end
                end
            end
        end

        staticData = {
            baseExp = baseExp,
            growthRate = growthRate,
            maxLevel = maxLevel,
            evolvedTo = evolvedTo,
        }
        towerProgressionStaticCache[towerName] = staticData
    end

    local statsData = calculateExpStats(currentExp, staticData.baseExp, staticData.growthRate, staticData.maxLevel)

    return {
        Name = tostring(towerName),
        Exp = currentExp,
        Level = statsData.level,
        MaxLevel = staticData.maxLevel,
        MaxExp = statsData.totalRequiredForMax,
        CurrentProgress = statsData.currentProgress,
        RequiredForNext = statsData.nextLevelCost,
        ProgressDisplay = statsData.progressDisplay or tostring(currentExp),
        OverallDisplay = statsData.overallDisplay or tostring(currentExp),
        UncappedLevel = statsData.uncappedLevel,
        IsMaxLevel = statsData.isMax,
        EvolvedTo = staticData.evolvedTo
    }
end

function CombinedData:GetAllTowerExp()
    local result = {}
    for _, towerName in ipairs(self.ProgressionTowers) do
        local data = self:GetTowerExp(towerName)
        if data then
            table.insert(result, data)
        end
    end
    table.sort(result, function(a, b) return a.Name < b.Name end)
    return result
end

function CombinedData:FormatTowerExp(towerName)
    local data = self:GetTowerExp(towerName)
    if not data then return tostring(towerName) .. ": Not found" end

    local evoText = data.EvolvedTo and (" -> Evolves to " .. data.EvolvedTo) or ""
    if data.IsMaxLevel then
        local uncapped = (data.UncappedLevel > data.MaxLevel) and string.format(" [Uncapped Lvl %d]", data.UncappedLevel) or ""
        return string.format("%-18s: Level %2d/%2d [MAX] | Total: %6d / %4d EXP%s%s",
            data.Name, data.Level, data.MaxLevel, data.Exp, data.MaxExp, uncapped, evoText)
    else
        return string.format("%-18s: Level %2d/%2d (%s to Lvl %d) | Total: %6d / %4d EXP%s",
            data.Name, data.Level, data.MaxLevel, data.ProgressDisplay, data.Level + 1, data.Exp, data.MaxExp, evoText)
    end
end

-- ---------------------------------------------------------------------
-- Coins / Gems / Level / Player EXP (Values.* Cache with Fallbacks)
-- ---------------------------------------------------------------------
local function getLobbyHud()
    local pgui = getPlayerGui(2)
    if not pgui then return nil end
    return pgui:FindFirstChild("ReactLobbyHud") or pgui:WaitForChild("ReactLobbyHud", 2)
end

function CombinedData:GetLevel()
    -- 1. Direct Cache lookup (Values.Level)
    local lvl = getStat("Values.Level")
    if lvl ~= nil and tonumber(lvl) then
        return tonumber(lvl), tostring(lvl)
    end

    -- 2. Fallback: Lobby HUD TextLabel
    local hud = getLobbyHud()
    if hud then
        local curLvl = hud:FindFirstChild("currentLevel", true)
            or (hud:FindFirstChild("Frame", true) and hud.Frame:FindFirstChild("centerElements", true) and hud.Frame.centerElements:FindFirstChild("level", true) and hud.Frame.centerElements.level:FindFirstChild("content", true) and hud.Frame.centerElements.level.content:FindFirstChild("currentLevel", true))

        if curLvl and curLvl:IsA("TextLabel") then
            local txt = curLvl.Text
            return parseNumber(txt), txt
        end
    end

    -- 3. Fallback: LocalPlayer ValueBase
    local lp = getLocalPlayer()
    if lp then
        local val = lp:FindFirstChild("Level")
        if val and val:IsA("ValueBase") then
            local v = val.Value
            return tonumber(v) or parseNumber(v), tostring(v)
        end
    end

    return 0, "0"
end

function CombinedData:GetCoins()
    -- 1. Direct Cache lookup (Values.Coins)
    local coins = getStat("Values.Coins")
    if coins ~= nil and tonumber(coins) then
        return tonumber(coins), tostring(coins)
    end

    -- 2. Fallback: Lobby HUD TextLabel
    local hud = getLobbyHud()
    if hud then
        local path = {"Frame", "leftElements", "currencies", "coins", "content", "currency", "currencyValue"}
        local node = hud
        for _, child in ipairs(path) do
            node = node:FindFirstChild(child, true) or (node and node:FindFirstChild(child))
            if not node then break end
        end
        if node and node:IsA("TextLabel") then
            local txt = node.Text
            return parseNumber(txt), txt
        end
    end

    -- 3. Fallback: LocalPlayer ValueBase
    local lp = getLocalPlayer()
    if lp then
        local val = lp:FindFirstChild("Coins") or lp:FindFirstChild("Gold")
        if val and val:IsA("ValueBase") then
            local v = val.Value
            return tonumber(v) or parseNumber(v), tostring(v)
        end
    end

    return 0, "0"
end

function CombinedData:GetGems()
    -- 1. Direct Cache lookup (Values.Gems)
    local gems = getStat("Values.Gems")
    if gems ~= nil and tonumber(gems) then
        return tonumber(gems), tostring(gems)
    end

    -- 2. Fallback: Lobby HUD TextLabel
    local hud = getLobbyHud()
    if hud then
        local path = {"Frame", "leftElements", "currencies", "gems", "content", "currency", "currencyValue"}
        local node = hud
        for _, child in ipairs(path) do
            node = node:FindFirstChild(child, true) or (node and node:FindFirstChild(child))
            if not node then break end
        end
        if node and node:IsA("TextLabel") then
            local txt = node.Text
            return parseNumber(txt), txt
        end
    end

    -- 3. Fallback: LocalPlayer ValueBase
    local lp = getLocalPlayer()
    if lp then
        local val = lp:FindFirstChild("Gems") or lp:FindFirstChild("Diamonds")
        if val and val:IsA("ValueBase") then
            local v = val.Value
            return tonumber(v) or parseNumber(v), tostring(v)
        end
    end

    return 0, "0"
end

--- Returns current player EXP, required EXP for next level, and formatted string
function CombinedData:GetPlayerExp()
    local exp = getStat("Values.Experience") or 0
    local level = self:GetLevel() or 0
    local nextLevelExp = 0

    if Experience then
        local ok, nExp = pcall(Experience, level + 1)
        if ok and nExp then
            nextLevelExp = nExp
        end
    end

    return exp, nextLevelExp, string.format("%d / %d", exp, nextLevelExp)
end

--- Returns a table containing Level, EXP, NextLevelExp, Coins, and Gems
function CombinedData:GetPlayerStats()
    local level = self:GetLevel()
    local exp, nextLevelExp, expDisplay = self:GetPlayerExp()
    local coins = self:GetCoins()
    local gems = self:GetGems()

    return {
        Level = level,
        Exp = exp,
        NextLevelExp = nextLevelExp,
        ExpDisplay = expDisplay,
        Coins = coins,
        Gems = gems
    }
end

-- ---------------------------------------------------------------------
-- Skill‑tree extraction
-- ---------------------------------------------------------------------
local skillTreeCacheFile = "ProjectOptimazation/CachedSkillTree.json"
local inMemorySkillTreeCache = {}
local lastSkillTreeDiskWrite = 0
local lastSkillTreeJson = ""

function CombinedData:GetSkillTree()
    local list = {}
    for i = 1, 17 do
        pcall(function()
            local tile = Workspace:FindFirstChild(tostring(i))
            if tile then
                local surfaceGui = tile:FindFirstChild("TileSurfaceGui")
                if surfaceGui then
                    local frame = surfaceGui:FindFirstChild("Frame")
                    if frame then
                        local nameLabel  = frame:FindFirstChild("SkillName")
                        local levelLabel = frame:FindFirstChild("SkillLevel")

                        local name = nameLabel and nameLabel:IsA("TextLabel") and nameLabel.Text or ("Skill #" .. i)
                        local lvlStr = levelLabel and levelLabel:IsA("TextLabel") and levelLabel.Text or "0"

                        local formattedLvl = lvlStr
                        local numericLvl = parseNumber(lvlStr)
                        local maxLvl = nil
                        local isMaxed = false

                        local curMatch, maxMatch = lvlStr:match("(%d+)%s*/%s*(%d+)")
                        if curMatch and maxMatch then
                            numericLvl = tonumber(curMatch) or numericLvl
                            maxLvl = tonumber(maxMatch)
                            if numericLvl >= maxLvl then
                                isMaxed = true
                            end
                        end

                        if string.upper(lvlStr):find("MAX") then
                            isMaxed = true
                            local numInFmt = string.upper(lvlStr):match("(%d+)")
                            if numInFmt then
                                maxLvl = tonumber(numInFmt) or maxLvl
                                if numericLvl == 0 or numericLvl < (maxLvl or 0) then
                                    numericLvl = maxLvl or numericLvl
                                end
                            end
                            formattedLvl = "MAX" .. (numericLvl > 0 and numericLvl or "")
                        end

                        table.insert(list, {
                            Id = tostring(i),
                            Name = name,
                            Level = numericLvl,
                            MaxLevel = maxLvl,
                            IsMaxed = isMaxed,
                            LevelFormatted = formattedLvl,
                        })
                    end
                end
            end
        end)
    end

    if #list > 0 then
        inMemorySkillTreeCache = list
        local now = os.time()
        if now - lastSkillTreeDiskWrite >= 60 then
            lastSkillTreeDiskWrite = now
            pcall(function()
                if writefile and HttpService then
                    local encoded = HttpService:JSONEncode(list)
                    if encoded ~= lastSkillTreeJson then
                        lastSkillTreeJson = encoded
                        pcall(writefile, "[ATF]/CachedSkillTree.json", encoded)
                        pcall(writefile, skillTreeCacheFile, encoded)
                    end
                end
            end)
        end
        return list
    end

    if #inMemorySkillTreeCache > 0 then
        return inMemorySkillTreeCache
    end

    local cacheCandidates = {
        "[ATF]/CachedSkillTree.json",
        "[ATF]\\CachedSkillTree.json",
        skillTreeCacheFile,
        "ProjectOptimazation\\CachedSkillTree.json",
    }
    pcall(function()
        if not (isfile and readfile and HttpService) then return end
        for _, path in ipairs(cacheCandidates) do
            local ok, exists = pcall(isfile, path)
            if ok and exists then
                local rOk, raw = pcall(readfile, path)
                if rOk and raw and raw ~= "" then
                    local dOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
                    if dOk and type(decoded) == "table" and #decoded > 0 then
                        inMemorySkillTreeCache = decoded
                        break
                    end
                end
            end
        end
    end)

    return inMemorySkillTreeCache
end

-- ---------------------------------------------------------------------
-- Requirements Validation API
-- ---------------------------------------------------------------------
function CombinedData:CheckRequirements(requirements)
    local missing = {}
    local passed = true

    -- 1. Check Player Level
    if requirements.Level then
        local currentLevel = self:GetLevel()
        if currentLevel < requirements.Level then
            passed = false
            table.insert(missing, string.format("Level: required %d, current %d", requirements.Level, currentLevel))
        end
    end

    -- 2. Check Skill Tree (supports both .Skill and .SkillTree)
    local skillReqs = requirements.SkillTree or requirements.Skill
    if skillReqs and type(skillReqs) == "table" then
        local currentSkills = {}
        for _, skill in ipairs(self:GetSkillTree()) do
            currentSkills[skill.Name] = skill.Level
        end

        for skillName, requiredLvl in pairs(skillReqs) do
            local currentLvl = currentSkills[skillName] or 0
            if currentLvl < requiredLvl then
                passed = false
                table.insert(missing, string.format("Skill '%s': required level %d, current %d", skillName, requiredLvl, currentLvl))
            end
        end
    end

    -- 3. Check Coins
    if requirements.Coins then
        local currentCoins = self:GetCoins()
        if currentCoins < requirements.Coins then
            passed = false
            table.insert(missing, string.format("Coins: required %d, current %d", requirements.Coins, currentCoins))
        end
    end

    -- 4. Check Gems
    if requirements.Gems then
        local currentGems = self:GetGems()
        if currentGems < requirements.Gems then
            passed = false
            table.insert(missing, string.format("Gems: required %d, current %d", requirements.Gems, currentGems))
        end
    end

    -- 5. Check Towers Owned
    if requirements.Towers and type(requirements.Towers) == "table" then
        for _, towerName in ipairs(requirements.Towers) do
            if not self:IsTowerOwned(towerName) then
                passed = false
                table.insert(missing, string.format("Missing Tower: %s", towerName))
            end
        end
    end

    -- 6. Check Golden Towers Owned
    if requirements.Golden and type(requirements.Golden) == "table" then
        for _, towerName in ipairs(requirements.Golden) do
            if not self:IsGoldenOwned(towerName) then
                passed = false
                table.insert(missing, string.format("Golden %s - not owned", towerName))
            end
        end
    end

    -- 7. Check Tower EXP / Levels
    if requirements.TowerExp and type(requirements.TowerExp) == "table" then
        for towerName, req in pairs(requirements.TowerExp) do
            local data = self:GetTowerExp(towerName)
            local currentExp = data and data.Exp or 0
            local currentLvl = data and data.Level or 0

            if type(req) == "number" then
                if currentExp < req then
                    passed = false
                    table.insert(missing, string.format("%s EXP: required %d, current %d", towerName, req, currentExp))
                end
            elseif type(req) == "table" then
                if req.Level and currentLvl < req.Level then
                    passed = false
                    table.insert(missing, string.format("%s Level: required %d, current %d", towerName, req.Level, currentLvl))
                end
                if req.Exp and currentExp < req.Exp then
                    passed = false
                    table.insert(missing, string.format("%s EXP: required %d, current %d", towerName, req.Exp, currentExp))
                end
            end
        end
    end

    return passed, missing
end

-- ---------------------------------------------------------------------
-- Trials Data & Progression
-- ---------------------------------------------------------------------
local currentTrialCacheFile = "ProjectOptimazation/CachedCurrentTrial.json"
local nextTrialCacheFile = "ProjectOptimazation/CachedNextTrial.json"
local inMemoryCurrentTrial = nil
local inMemoryNextTrial = nil

function CombinedData:GetCurrentTrial()
    if MatchmakingTrialData then
        local ok, res = pcall(function()
            local currentTime = os.time()
            local rotation = MatchmakingTrialData.getCurrentRotation(currentTime)
            local details = MatchmakingTrialData.resolve(rotation)
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local secondsLeft = math.max(0, (rotation.expiresAt or currentTime) - currentTime)
            local formattedTimer = MatchmakingTrialData.formatSecondsLeft(secondsLeft)
            if setthreadidentity then pcall(setthreadidentity, 8) end

            return {
                Name = rotation and rotation.trialName,
                ExpiresAt = rotation and rotation.expiresAt,
                TimeRemaining = formattedTimer,
                Map = details and details.mapName,
                Title = details and details.title,
                Subtitle = details and details.subtitle
            }
        end)
        if ok and res and res.Title then
            inMemoryCurrentTrial = res
            pcall(function()
                if writefile and HttpService then
                    writefile(currentTrialCacheFile, HttpService:JSONEncode(res))
                end
            end)
            return res
        end
    end

    if inMemoryCurrentTrial then return inMemoryCurrentTrial end

    pcall(function()
        if isfile and readfile and HttpService and isfile(currentTrialCacheFile) then
            local raw = readfile(currentTrialCacheFile)
            if raw and raw ~= "" then
                local decoded = HttpService:JSONDecode(raw)
                if type(decoded) == "table" and decoded.Title then
                    inMemoryCurrentTrial = decoded
                end
            end
        end
    end)

    return inMemoryCurrentTrial
end

function CombinedData:GetNextTrial()
    if MatchmakingTrialData then
        local ok, res = pcall(function()
            local currentTime = os.time()
            local currentRotation = MatchmakingTrialData.getCurrentRotation(currentTime)
            local timeOfNextTrial = (currentRotation and currentRotation.expiresAt or currentTime) + 1 
            local nextRotation = MatchmakingTrialData.getCurrentRotation(timeOfNextTrial)
            local nextDetails = MatchmakingTrialData.resolve(nextRotation)
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local secondsLeft = math.max(0, (currentRotation and currentRotation.expiresAt or currentTime) - currentTime)
            local formattedTimer = MatchmakingTrialData.formatSecondsLeft(secondsLeft)
            if setthreadidentity then pcall(setthreadidentity, 8) end

            return {
                Name = nextRotation and nextRotation.trialName,
                Map = nextDetails and nextDetails.mapName,
                Title = nextDetails and nextDetails.title,
                TimeRemaining = formattedTimer,
                ExpiresAt = nextRotation and nextRotation.expiresAt
            }
        end)
        if ok and res and res.Title then
            inMemoryNextTrial = res
            pcall(function()
                if writefile and HttpService then
                    writefile(nextTrialCacheFile, HttpService:JSONEncode(res))
                end
            end)
            return res
        end
    end

    if inMemoryNextTrial then return inMemoryNextTrial end

    pcall(function()
        if isfile and readfile and HttpService and isfile(nextTrialCacheFile) then
            local raw = readfile(nextTrialCacheFile)
            if raw and raw ~= "" then
                local decoded = HttpService:JSONDecode(raw)
                if type(decoded) == "table" and decoded.Title then
                    inMemoryNextTrial = decoded
                end
            end
        end
    end)

    return inMemoryNextTrial
end

local StaticTrialDefinitions = {
    { Name = "Broke", Title = "Broke", Map = "Medieval Times" },
    { Name = "Committed", Title = "Committed", Map = "Retro Zone" },
    { Name = "ExplodingEnemies", Title = "Exploding Enemies", Map = "Wrecked Battlefield II" },
    { Name = "FlyingEnemies", Title = "Flying Enemies", Map = "Sacred Mountains" },
    { Name = "Fog", Title = "Fog", Map = "Winter Abyss" },
    { Name = "Glass", Title = "Glass", Map = "Stained Temple" },
    { Name = "HealthyEnemies", Title = "Healthy Enemies", Map = "Four Seasons" },
    { Name = "HiddenEnemies", Title = "Hidden Enemies", Map = "Forgetten Docks" },
    { Name = "Inflation", Title = "Inflation", Map = "Cyber City" },
    { Name = "Jailed", Title = "Jailed", Map = "Night Station" },
    { Name = "Limitation", Title = "Limitation", Map = "Coral Deep" },
    { Name = "Quarantine", Title = "Quarantine", Map = "Dusty Bridges" },
    { Name = "SpeedyEnemies", Title = "Speedy Enemies", Map = "Wrecked Battlefield" },
}

CombinedData.StaticTrialDefinitions = StaticTrialDefinitions

local inMemoryOwnedModifiers = nil

local function getSavedOwnedModifiers()
    local candidateFiles = {
        "ServiceHub/CachedTrialsStatus.json",
        "CachedTrialsStatus.json",
        "ProjectOptimazation/CachedTrialsStatus.json"
    }
    for _, path in ipairs(candidateFiles) do
        local ok, content = pcall(function()
            if isfile and isfile(path) and readfile and HttpService then
                local raw = readfile(path)
                if raw and raw ~= "" then
                    return HttpService:JSONDecode(raw)
                end
            end
            return nil
        end)
        if ok and type(content) == "table" then
            if content.Modifiers and type(content.Modifiers) == "table" and #content.Modifiers > 0 then
                return content.Modifiers
            elseif #content > 0 then
                return content
            end
        end
    end
    return nil
end

local function persistOwnedModifiers(modsList)
    if not modsList or #modsList == 0 then return end
    pcall(function()
        if writefile and HttpService then
            local payload = HttpService:JSONEncode({ Modifiers = modsList })
            pcall(function() writefile("CachedTrialsStatus.json", payload) end)
            pcall(function()
                if makefolder and not isfolder("ServiceHub") then makefolder("ServiceHub") end
                writefile("ServiceHub/CachedTrialsStatus.json", payload)
            end)
        end
    end)
end

local function extractOwnedModifiers(): ({ [string]: boolean }, { [string]: boolean })
    local lookup: { [string]: boolean } = {}
    local normLookup: { [string]: boolean } = {}

    local function addModifier(name: any)
        if not name or name == "" then return end
        local str = tostring(name)
        lookup[str] = true
        normLookup[string.lower(string.gsub(str, "%s+", ""))] = true
    end

    local function scanTbl(tbl: any)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(k) == "string" and tonumber(k) == nil and (v == true or v == 1 or type(v) == "table" or type(v) == "number") then
                addModifier(k)
            end
            if type(v) == "string" then
                addModifier(v)
            elseif type(v) == "table" then
                if v.Name then addModifier(v.Name) end
                if v.name then addModifier(v.name) end
                if v.Title then addModifier(v.Title) end
                if v.title then addModifier(v.title) end
                if v.Id then addModifier(v.Id) end
                if v.id then addModifier(v.id) end
                if v.Modifier then addModifier(v.Modifier) end
                if v.modifier then addModifier(v.modifier) end
                if v.Item then addModifier(v.Item) end
                if v.item then addModifier(v.item) end
            end
        end
    end

    -- 1. Scan persistent cache file (instant recognition on startup/lobby)
    local savedMods = inMemoryOwnedModifiers or getSavedOwnedModifiers()
    if savedMods then
        inMemoryOwnedModifiers = savedMods
        scanTbl(savedMods)
    end

    -- 2. Scan internal client cache
    if setthreadidentity then pcall(setthreadidentity, 8) end
    local ownedModifiers = getCacheValue("Inventory.Modifiers")
    scanTbl(ownedModifiers)
    scanTbl(getCacheValue("Modifiers"))
    scanTbl(getCacheValue("Inventory.Items"))
    scanTbl(getCacheValue("Items"))
    scanTbl(getCacheValue("Trials"))
    scanTbl(getCacheValue("OwnedTrials"))
    scanTbl(getCacheValue("OwnedModifiers"))
    local inv = getCacheValue("Inventory")
    if type(inv) == "table" then
        scanTbl(inv.Modifiers or inv.modifiers or inv.Items or inv.items or inv.Trials or inv.trials)
    end
    if setthreadidentity then pcall(setthreadidentity, 8) end

    -- 3. Scan InventoryController
    if InventoryController then
        if type(InventoryController.getItems) == "function" then
            local ok, items = pcall(function() return InventoryController:getItems() end)
            if ok and type(items) == "table" then
                for _, item in pairs(items) do
                    if type(item) == "table" then
                        local iType = tostring(item.type or item.Type or item.category or item.Category or ""):lower()
                        local iName = tostring(item.name or item.Name or item.id or item.Id or item.Modifier or item.modifier or item.Item or item.item or "")
                        if iName ~= "" then
                            if iType == "modifier" or iType == "trial" or iType == "modifiers" or iType:find("mod") then
                                addModifier(iName)
                            else
                                for _, t in ipairs(StaticTrialDefinitions) do
                                    local nNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
                                    local tNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
                                    local curNorm = string.lower(string.gsub(iName, "%s+", ""))
                                    if curNorm == nNorm or curNorm == tNorm then
                                        addModifier(iName)
                                        break
                                    end
                                end
                            end
                        end
                    elseif type(item) == "string" then
                        addModifier(item)
                    end
                end
            end
        end
        if type(InventoryController.getModifiers) == "function" then
            local ok, m = pcall(function() return InventoryController:getModifiers() end)
            if ok and type(m) == "table" then scanTbl(m) end
        end
        if type(InventoryController.getInventory) == "function" then
            local ok, invTbl = pcall(function() return InventoryController:getInventory() end)
            if ok and type(invTbl) == "table" then
                scanTbl(invTbl.Modifiers or invTbl.modifiers or invTbl.Items or invTbl.items or invTbl)
            end
        end
    end

    -- 4. Scan StateReplicators (ModifierReplicator)
    pcall(function()
        local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
        local modRep = sr and sr:FindFirstChild("ModifierReplicator")
        if modRep then
            local raw = modRep:GetAttribute("Available")
            if type(raw) == "string" then
                local clean = raw:match("{.+}") or raw
                local ok, decoded = pcall(function() return HttpService:JSONDecode(clean) end)
                if ok and type(decoded) == "table" then
                    scanTbl(decoded)
                end
            elseif type(raw) == "table" then
                scanTbl(raw)
            end
            local attrs = modRep:GetAttributes()
            if attrs and type(attrs) == "table" then
                scanTbl(attrs)
            end
        end
    end)

    -- 5. Cross-match with StaticTrialDefinitions and build discovered list
    local discoveredList = {}
    for _, t in ipairs(StaticTrialDefinitions) do
        local nNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
        local tNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
        local mNorm = string.lower(string.gsub(tostring(t.Map), "%s+", ""))
        if lookup[t.Name] or lookup[t.Title] or normLookup[nNorm] or normLookup[tNorm] or normLookup[mNorm] then
            lookup[t.Name] = true
            lookup[t.Title] = true
            normLookup[nNorm] = true
            normLookup[tNorm] = true
            normLookup[mNorm] = true
            table.insert(discoveredList, t.Name)
        end
    end

    -- Persist discovered modifiers to cache files
    if #discoveredList > 0 then
        inMemoryOwnedModifiers = discoveredList
        persistOwnedModifiers(discoveredList)
    end

    return lookup, normLookup
end

function CombinedData:GetTrialsStatus()
    if setthreadidentity then pcall(setthreadidentity, 8) end
    local allTrials = nil
    if MatchmakingTrialData and type(MatchmakingTrialData.getTrialNames) == "function" then
        pcall(function()
            allTrials = MatchmakingTrialData.getTrialNames()
        end)
    end
    if setthreadidentity then pcall(setthreadidentity, 8) end

    if not allTrials or #allTrials == 0 then
        allTrials = {}
        for _, t in ipairs(StaticTrialDefinitions) do
            table.insert(allTrials, t.Name)
        end
    end

    local lookup, normLookup = extractOwnedModifiers()

    local won = {}
    local notWon = {}

    for _, trialName in ipairs(allTrials) do
        local tNorm = string.lower(string.gsub(tostring(trialName), "%s+", ""))
        if lookup[trialName] or normLookup[tNorm] then
            table.insert(won, trialName)
        else
            table.insert(notWon, trialName)
        end
    end

    return {
        Won = won,
        NotWon = notWon
    }
end

function CombinedData:GetAllTrialsList()
    local lookup, normLookup = extractOwnedModifiers()

    local list = {}
    local trialNames = nil
    if MatchmakingTrialData and type(MatchmakingTrialData.getTrialNames) == "function" then
        pcall(function()
            trialNames = MatchmakingTrialData.getTrialNames()
        end)
    end
    if setthreadidentity then pcall(setthreadidentity, 8) end

    if trialNames and #trialNames > 0 then
        for _, trialName in ipairs(trialNames) do
            local resolved = nil
            pcall(function()
                resolved = MatchmakingTrialData.resolve({ trialName = trialName })
            end)
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local title = resolved and resolved.title or trialName
            local mapName = resolved and resolved.mapName or "Unknown"
            local tNorm = string.lower(string.gsub(tostring(trialName), "%s+", ""))
            local titNorm = string.lower(string.gsub(tostring(title), "%s+", ""))
            local isWon = lookup[trialName] == true or lookup[title] == true or normLookup[tNorm] == true or normLookup[titNorm] == true
            table.insert(list, {
                Name = trialName,
                Title = title,
                Map = mapName,
                IsWon = isWon,
                Status = isWon and "YES" or "NO"
            })
        end
    else
        for _, t in ipairs(StaticTrialDefinitions) do
            local tNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
            local titNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
            local isWon = lookup[t.Name] == true or lookup[t.Title] == true or normLookup[tNorm] == true or normLookup[titNorm] == true
            table.insert(list, {
                Name = t.Name,
                Title = t.Title,
                Map = t.Map,
                IsWon = isWon,
                Status = isWon and "YES" or "NO"
            })
        end
    end

    return list
end

function CombinedData:IsTrialWon(trialName)
    if not trialName or trialName == "" then return false end
    local lookup, normLookup = extractOwnedModifiers()
    local target = string.lower(string.gsub(tostring(trialName), "%s+", ""))
    if lookup[trialName] or normLookup[target] then
        return true
    end

    for _, t in ipairs(StaticTrialDefinitions) do
        local nNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
        local titNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
        local mNorm = string.lower(string.gsub(tostring(t.Map), "%s+", ""))
        if target == nNorm or target == titNorm or target == mNorm then
            if lookup[t.Name] or lookup[t.Title] or normLookup[nNorm] or normLookup[titNorm] or normLookup[mNorm] then
                return true
            end
        end
    end

    return false
end

CombinedData.PeerData = {}

function CombinedData:GetPeerData(identifier)
    if not identifier or identifier == "" then
        for _, peer in pairs(CombinedData.PeerData) do
            if type(peer) == "table" then return peer end
        end
        return nil
    end

    local clean = string.lower(string.gsub(tostring(identifier), "%s+", ""))
    if CombinedData.PeerData[identifier] then
        return CombinedData.PeerData[identifier]
    end
    if CombinedData.PeerData[clean] then
        return CombinedData.PeerData[clean]
    end

    for key, peer in pairs(CombinedData.PeerData) do
        if type(peer) == "table" then
            local uName = string.lower(string.gsub(tostring(peer.username or peer.Username or ""), "%s+", ""))
            local uId = tostring(peer.userId or peer.UserId or "")
            if uName == clean or uId == clean then
                return peer
            end
        end
    end
    return nil
end

function CombinedData:IsPeerTrialWon(identifier, trialName)
    if not trialName or trialName == "" then return false end
    local peer = self:GetPeerData(identifier)
    if not peer then return nil end

    local target = string.lower(string.gsub(tostring(trialName), "%s+", ""))
    local ownedMap = peer.ownedModifiers or peer.OwnedModifiers or {}
    local normOwned = peer.normOwnedModifiers or peer.NormOwnedModifiers or {}

    if ownedMap[trialName] or normOwned[target] then
        return true
    end

    for _, t in ipairs(StaticTrialDefinitions) do
        local nNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
        local titNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
        local mNorm = string.lower(string.gsub(tostring(t.Map), "%s+", ""))
        if target == nNorm or target == titNorm or target == mNorm then
            if ownedMap[t.Name] or ownedMap[t.Title] or ownedMap[t.Map]
               or normOwned[nNorm] or normOwned[titNorm] or normOwned[mNorm] then
                return true
            end
        end
    end

    return false
end

function CombinedData:GetPartyTrialStatus(peerIdentifier, trialName)
    local localWon = self:IsTrialWon(trialName)
    local peerWon = self:IsPeerTrialWon(peerIdentifier, trialName)
    return {
        trialName = trialName,
        localWon = localWon,
        peerWon = peerWon,
        bothWon = (localWon == true and peerWon == true),
        anyNeeds = (localWon == false or peerWon == false),
        peerSynced = (peerWon ~= nil)
    }
end

return CombinedData


end

local function loadPlayerDataHandler(): any
    if PlayerDataHandler then return PlayerDataHandler end
    if playerDataLoading then return nil end
    playerDataLoading = true

    -- 1. Embedded clean DataHandler (Guaranteed capability-safe fallback)
    if typeof(createEmbeddedPlayerDataHandler) == "function" then
        local embOk, embMod = pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            return createEmbeddedPlayerDataHandler()
        end)
        if embOk and type(embMod) == "table" then
            PlayerDataHandler = embMod
            playerDataLoading = false
            return embMod
        end
    end

    -- 2. Cloud fallback via loadstring (strictly non-Centurion)
    local urls = {
        "https://raw.githubusercontent.com/Atxvy/-FINALVERSION-/refs/heads/main/DataHandler.lua",
        "https://raw.githubusercontent.com/Atxvy/-ATF-/refs/heads/main/DataHandler.lua",
    }
    for _, url in ipairs(urls) do
        local chunk = safeHttpGet(url, 3)
        if chunk and type(chunk) == "string" and #chunk > 0 then
            -- Strictly reject Centurion-obfuscated chunks that crash executors with lacking capability Plugin
            if not chunk:find("Centurion") then
                local execSuccess, module = pcall(function()
                    if setthreadidentity then pcall(setthreadidentity, 8) end
                    local fn, compileErr = loadstring(chunk)
                    if not fn then error(compileErr) end
                    return fn()
                end)
                if execSuccess and type(module) == "table" then
                    PlayerDataHandler = module
                    playerDataLoading = false
                    return module
                end
            end
        end
    end

    playerDataLoading = false
    return nil
end

PlayerDataHandler = loadPlayerDataHandler()
local function ensurePlayerDataReady(maxAttempts: number?): boolean
    local maxTries = maxAttempts or 20
    for _ = 1, maxTries do
        if not PlayerDataHandler then
            PlayerDataHandler = loadPlayerDataHandler()
        end
        if PlayerDataHandler then
            local ok, lvl = pcall(function()
                return PlayerDataHandler:GetLevel()
            end)
            if ok and type(lvl) == "number" and lvl > 0 then
                return true
            end
        end
        task.wait(0.1)
    end
    return PlayerDataHandler ~= nil
end

pcall(ensurePlayerDataReady, 10)

--==============================================================================
--==============================================================================
-- UI Framework Loader (CoreRevampNewAPI / UICore) - Readfile First & Cloud Fallback
--==============================================================================
local UILibrary: any
do
    local function sanitizeUIChunk(code: string): string
        local patched = code
        if patched:find("animConn = RunService.RenderStepped:Connect%(function%(dt%)") then
            patched = patched:gsub(
                "animConn = RunService.RenderStepped:Connect%(function%(dt%)",
                "animConn = RunService.RenderStepped:Connect(function(dt)\n        if setthreadidentity then pcall(setthreadidentity, 8) end"
            )
        end
        if patched:find("if not screenGui%.Parent then") then
            patched = patched:gsub(
                "if not screenGui%.Parent then",
                "local _pOk, _hasP = pcall(function() return screenGui and screenGui.Parent ~= nil end)\n        if not _pOk or not _hasP then"
            )
        end
        if patched:find("while screenGui%.Parent do") then
            patched = patched:gsub(
                "while screenGui%.Parent do",
                "while (function() local ok, p = pcall(function() return screenGui and screenGui.Parent ~= nil end); return ok and p end)() do"
            )
        end
        return patched
    end

    local function loadUILibrary(): any
        local urls = {
            "https://raw.githubusercontent.com/Atxvy/-ATF-/refs/heads/main/CoreRevampNewAPI.lua",
        }
        for _, url in ipairs(urls) do
            local chunk = safeHttpGet(url, 3)
            if chunk and type(chunk) == "string" and #chunk > 0 then
                -- Reject Centurion-obfuscated chunks that cause lag and capability issues
                if not chunk:find("Centurion") then
                    local success, lib = pcall(function()
                        if setthreadidentity then pcall(setthreadidentity, 8) end
                        local sanitized = sanitizeUIChunk(chunk)
                        local fn, compileErr = loadstring(sanitized)
                        if not fn then error(compileErr) end
                        return fn()
                    end)
                    if success and type(lib) == "table" then
                        return lib
                    end
                end
            end
        end
        return nil
    end

    UILibrary = loadUILibrary()
end
if not UILibrary then
    error("[ServiceHub] Failed to load UI Library (readfile and cloud both failed)!")
end
local UI: { [string]: any } = {}

local function logActivity(msg: string, msgType: string?)
    pcall(function()
        if UI and UI.LogConsole then
            if msgType == "warn" then
                UI.LogConsole:Warn(msg)
            elseif msgType == "error" then
                UI.LogConsole:Error(msg)
            elseif msgType == "success" then
                UI.LogConsole:Success(msg)
            elseif msgType == "info" then
                UI.LogConsole:Info(msg)
            else
                UI.LogConsole:Log(msg)
            end
        end
    end)
end

local function RunAsExecutor(fn)
    local be = Instance.new("BindableEvent")
    be.Event:Connect(function(args)
        if setthreadidentity then pcall(setthreadidentity, 8) end
        fn(unpack(args))
    end)
    return function(...) be:Fire({...}) end
end

--==============================================================================
-- Helper Utilities
--==============================================================================
local function formatNumberWithCommas(amount: number): string
    local formatted = tostring(amount or 0)
    local k
    while true do
        if not isRunning then break end
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function normalizeString(str: any): string
    if not str then return "" end
    return string.lower(string.gsub(tostring(str), "%s+", ""))
end

ensureFolder = function(folderPath: string)
    if makefolder and not isfolder(folderPath) then
        pcall(makefolder, folderPath)
    end
end

local function ensureParentFolder(filePath: string)
    local folderPath = filePath:match("^(.*)/[^/]+$")
    if folderPath and folderPath ~= "" then
        ensureFolder(folderPath)
    end
end

--==============================================================================
--==============================================================================
-- Junkie SDK Integration & Key Management (Cloud Instance)
--==============================================================================
local cachedJunkieSDK: any = nil

local function getJunkieSDK(): any
    if cachedJunkieSDK then return cachedJunkieSDK end
    local sdkChunk = readLocalFile("JunkieSDK.lua", {
    })
    if not sdkChunk or #sdkChunk == 0 then
        sdkChunk = safeHttpGet("https://jnkie.com/sdk/library.lua", 3)
    end
    if not sdkChunk then return nil end
    local success, junkie = pcall(function()
        return loadstring(sdkChunk)()
    end)
    if success and type(junkie) == "table" then
        junkie.service = "[ATF]"
        junkie.identifier = "1083049"
        junkie.provider = "[ATF]"
        cachedJunkieSDK = junkie
        return junkie
    end
    return nil
end
local fileSystemSupported = (function()
    local okWrite, hasWrite = pcall(function() return type(writefile) == "function" end)
    local okRead, hasRead = pcall(function() return type(readfile) == "function" end)
    local okIs, hasIs = pcall(function() return type(isfile) == "function" end)
    local okDel, hasDel = pcall(function() return type(delfile) == "function" end)
    return okWrite and hasWrite and okRead and hasRead and okIs and hasIs and okDel and hasDel
end)()

local function loadVerifiedKey(): string?
    if not fileSystemSupported then return nil end
    local ok, content = pcall(function()
        if isfile and isfile(VERIFIED_KEY_FILE) then
            return readfile(VERIFIED_KEY_FILE)
        elseif isfile and isfile("[AT]/verified_key.txt") then
            return readfile("[AT]/verified_key.txt")
        elseif isfile and isfile("verified_key.txt") then
            return readfile("verified_key.txt")
        end
        return nil
    end)
    if ok and content and content ~= "" then
        return (content:gsub("^%s*(.-)%s*$", "%1"))
    end
    return nil
end

local function saveVerifiedKey(key: string): boolean
    if not fileSystemSupported then return false end
    ensureFolder(CONFIG_FOLDER)
    local ok = pcall(function() writefile(VERIFIED_KEY_FILE, key) end)
    return ok
end

local isPremiumUser = false
local isKeyUser = false

pcall(function()
    local savedKey = loadVerifiedKey()
    local keyToCheck = savedKey or Globals.SCRIPT_KEY

    -- If no key exists, automatically run Keyless Mode
    if not keyToCheck or keyToCheck == "" or keyToCheck == "No Key Found" then
        Globals.PreferredAccessTier = "Keyless"
        Globals.IS_JD_PREMIUM = false
        isPremiumUser = false
        isKeyUser = false
        return
    end

    local checkKeyOnce = function(): (boolean, boolean)
        local Junkie = getJunkieSDK()
        if not Junkie then return false, false end

        local success, result = pcall(function()
            return Junkie.check_key(keyToCheck)
        end)

        if success and result and (result.valid == true) then
            saveVerifiedKey(keyToCheck)
            Globals.SCRIPT_KEY = keyToCheck
            Globals.IS_JD_PREMIUM = (result.is_premium == true or result.premium == true)
            Globals.JD_EXPIRES_AT = result.expires_at or result.expiresAt
            isKeyUser = true
            isPremiumUser = (Globals.IS_JD_PREMIUM == true)
            Globals.PreferredAccessTier = isPremiumUser and "Premium" or "Key"
            return true, isPremiumUser
        end
        return false, false
    end

    -- Fast single check for instant startup:
    -- If key exists and is valid -> Standard Mode (or Premium Mode if premium key)
    -- If key is expired or invalid -> automatically switch to Keyless Mode!
    local ok, isPrem = checkKeyOnce()
    if ok then
        isKeyUser = true
        isPremiumUser = (Globals.IS_JD_PREMIUM == true)
        Globals.PreferredAccessTier = isPremiumUser and "Premium" or "Key"
    else
        -- Key is expired or invalid -> automatically switch to Keyless Mode!
        Globals.PreferredAccessTier = "Keyless"
        Globals.IS_JD_PREMIUM = false
        isPremiumUser = false
        isKeyUser = false

        -- Non-blocking background retry in case network was temporarily slow on startup
        task.spawn(function()
            for attempt = 1, 3 do
                task.wait(2)
                if not isRunning then break end
                local retryOk, retryPrem = checkKeyOnce()
                if retryOk then
                    isKeyUser = true
                    isPremiumUser = (retryPrem == true)
                    Globals.PreferredAccessTier = isPremiumUser and "Premium" or "Key"
                    if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                        UI.Window:Notify({
                            Title = "Key Validated",
                            Desc = isPremiumUser and "Premium status unlocked in background!" or "Standard Key Mode unlocked in background! (Farms current trial over and over)",
                            Duration = 3,
                        })
                    end
                    task.defer(function()
                        pcall(function() if UI.ScreenGui then UI.ScreenGui:Destroy() end end)
                        task.wait(0.1)
                        pcall(function()
                            if setthreadidentity then pcall(setthreadidentity, 8) end
                            buildInterface()
                        end)
                    end)
                    break
                end
            end
        end)
    end
end)

local function getSavedKey(): string
    local key = loadVerifiedKey()
    return key or "No Key Found"
end

local function checkRuntimeKeyExpiration(): boolean
    if not isKeyUser and not isPremiumUser then return false end
    local expiresAt = Globals.JD_EXPIRES_AT
    if expiresAt and type(expiresAt) == "number" and expiresAt > 0 then
        if os.time() >= expiresAt then
            isKeyUser = false
            isPremiumUser = false
            Globals.IS_JD_PREMIUM = false
            Globals.PreferredAccessTier = "Keyless"
            logActivity("Key license expired -> automatically switched to Keyless Mode.", "warn")
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                UI.Window:Notify({
                    Title = "License Expired",
                    Desc = "Your key has expired. Automatically switched to Keyless Mode (farming unowned trials only).",
                    Duration = 6,
                    Type = "warning"
                })
            end
            task.defer(function()
                pcall(function() if UI.ScreenGui then UI.ScreenGui:Destroy() end end)
                task.wait(0.1)
                pcall(function()
                    if setthreadidentity then pcall(setthreadidentity, 8) end
                    buildInterface()
                end)
            end)
            return true
        end
    end
    return false
end

local function formatTimeRemaining(): string
    local expiresAt = Globals.JD_EXPIRES_AT
    if not expiresAt or type(expiresAt) ~= "number" then
        return "Permanent / N/A"
    end

    local diff = expiresAt - os.time()
    if diff <= 0 then
        if isKeyUser or isPremiumUser then
            checkRuntimeKeyExpiration()
        end
        return "Expired (Switched to Keyless)"
    end

    local days = math.floor(diff / 86400)
    local hours = math.floor((diff % 86400) / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    local seconds = diff % 60

    if days > 0 then
        return string.format("%dd %dh %dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, seconds)
    else
        return string.format("%dm %ds", minutes, seconds)
    end
end


--==============================================================================
--==============================================================================
-- Remote Strategy & Match Configuration Loader (Cloud Loadstring)
--==============================================================================
isPremiumUser = (Globals.IS_JD_PREMIUM == true)

local function loadConfigRequirements(): any
    local urls = {
        "https://raw.githubusercontent.com/Atxvy/-FINALVERSION-/refs/heads/main/PremConfigs.lua?nocache=" .. tick(),
        "https://raw.githubusercontent.com/Atxvy/AutoTrials/refs/heads/main/PremConfig.lua?nocache=" .. tick(),
    }
    for _, url in ipairs(urls) do
        local chunk = safeHttpGet(url, 3)
        if chunk and type(chunk) == "string" and #chunk > 0 then
            local success, req = pcall(function()
                local fn, compileErr = loadstring(chunk)
                if not fn then error(compileErr) end
                return fn()
            end)
            if success and type(req) == "table" then
                return req
            end
        end
    end

    local allowedPaths = {
        "PremConfigs.lua",
        "[STAY]/[AutoTrailsFInal]/FinalVersion/files/PremConfigs.lua",
        "[STAY]/[AutoTrailsFInal]/files/PremConfigs.lua",
        "files/PremConfigs.lua",
    }
    for _, path in ipairs(allowedPaths) do
        local ok, content = pcall(function()
            if isfile and isfile(path) and readfile then
                return readfile(path)
            end
            return nil
        end)
        if ok and type(content) == "string" and #content > 0 then
            local s, req = pcall(function()
                local fn, err = loadstring(content)
                if not fn then error(err) end
                return fn()
            end)
            if s and type(req) == "table" then return req end
        end
    end

    return {
        trialScripts = {},
        trialConfigs = {},
        allTrialOptions = {},
        fallbackModesList = {},
        fallbackConfigs = {},
        CrateConfigs = {},
        AutoEvoConfigs = {},
    }
end
local Requirements = loadConfigRequirements()
local RevampAutoTrials = Requirements.RevampAutoTrials
if type(RevampAutoTrials) ~= "table" or next(RevampAutoTrials) == nil then
    RevampAutoTrials = Requirements.trialConfigs or {}
end
local allTrialOptions = Requirements.allTrialOptions or {}
local fallbackModesList = Requirements.fallbackModesList or {}
local FallbackConfigs = Requirements.RevampedFallbackConfigs or Requirements.FallbackConfigs or Requirements.fallbackConfigs or {}
local CrateConfigs = Requirements.CrateConfigs or {}
local AutoEvoConfigs = Requirements.AutoEvoConfigs or (getgenv and getgenv().AutoEvoConfigs) or (shared and shared.AutoEvoConfigs) or {}

-- Forward Declarations for Priority & Fallback System
local isCoinTowersMaxed: (() -> boolean)? = nil
local isGemTowersMaxed: (() -> boolean)? = nil
local isEvoTowersMaxed: (() -> boolean)? = nil
local isGoldenSkinsMaxed: (() -> boolean)? = nil
local isSkillTreeMaxed: (() -> boolean)? = nil
local areSelectedPrioritiesMaxed: (() -> boolean)? = nil
local checkIsEverythingMaxed: (() -> boolean)? = nil
local resolveCoinFarmFallback: (() -> string)? = nil

-- Dynamic Fallback Registration (syncs Lose strat gems from PremConfig to FallbackConfigs)
local function ensureDynamicHardcoreFallback()
    if not FallbackConfigs then FallbackConfigs = {} end
    local gemsLose = (CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Lose)
        or (Requirements and Requirements.CrateConfigs and Requirements.CrateConfigs.Gems and Requirements.CrateConfigs.Gems.Lose)
    if gemsLose then
        FallbackConfigs["Hardcore"] = {
            Level = gemsLose.Level or 50,
            Mode = gemsLose.Mode or "hardcore",
            Towers = gemsLose.Towers or {"Farm", "Boomerang", "Crook Boss"},
            Golden = gemsLose.Golden or {},
            SkillTree = gemsLose.SkillTree or {},
            Maps = gemsLose.Maps or {"Wretched Front"},
            Scripts = gemsLose.Scripts or {
                ["Wretched Front"] = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Gems/Lose/WretchedFront.lua",
            },
        }
    end

    if not fallbackModesList or #fallbackModesList == 0 then
        fallbackModesList = { "Smart Auto", "Hardcore", "Fallen", "Molten" }
    else
        local hasHc = false
        for _, m in ipairs(fallbackModesList) do
            if m == "Hardcore" then hasHc = true; break end
        end
        if not hasHc then
            table.insert(fallbackModesList, 2, "Hardcore")
        end
    end
end
ensureDynamicHardcoreFallback()

local TowerList = Requirements.TowerList or {
    ["Coins"] = {
        { Name = "Scout", Cost = 0 },
        { Name = "Sniper", Cost = 50 },
        { Name = "Paintballer", Cost = 100 },
        { Name = "Demoman", Cost = 200 },
        { Name = "Boomerang", Cost = 300 },
        { Name = "Slime Trooper", Cost = 300 },
        { Name = "Soldier", Cost = 350 },
        { Name = "Freezer", Cost = 650 },
        { Name = "Militant", Cost = 800 },
        { Name = "Assassin", Cost = 800 },
        { Name = "Shotgunner", Cost = 850 },
        { Name = "Hunter", Cost = 1000 },
        { Name = "Pyromancer", Cost = 1250 },
        { Name = "Ace Pilot", Cost = 1500 },
        { Name = "Farm", Cost = 2000 },
        { Name = "Medic", Cost = 2000 },
        { Name = "Rocketeer", Cost = 2500 },
        { Name = "Electroshocker", Cost = 2500 },
        { Name = "Trapper", Cost = 3000 },
        { Name = "Pulse Trooper", Cost = 3250 },
        { Name = "Commander", Cost = 4000 },
        { Name = "Military Base", Cost = 4000 },
        { Name = "DJ Booth", Cost = 5000 },
        { Name = "Tesla", Cost = 6000 },
        { Name = "Minigunner", Cost = 8000 },
        { Name = "Ranger", Cost = 12000 },
        { Name = "Pursuit", Cost = 15000 },
        { Name = "Gatling Gun", Cost = 35000 },
    },
    ["Gems"] = {
        { Name = "Accelerator", Cost = 2500 },
        { Name = "Brawler", Cost = 1250 },
        { Name = "Necromancer", Cost = 2250 },
        { Name = "Engineer", Cost = 4500 },
        { Name = "Hacker", Cost = 5500 },
    },
    ["Evo"] = {
        { Name = "EvolvedOperator", Coins = 15000, Gems = 4500 },
        { Name = "EvolvedEnforcer", Coins = 15000, Gems = 5000 },
        { Name = "EvolvedKingpin", Coins = 15000, Gems = 5500 },
        { Name = "EvolvedJuggernaut", Coins = 15000, Gems = 6000 },
    },
    ["Golden"] = {
        { Name = "Golden Scout", Cost = 50000 },
        { Name = "Golden Demoman", Cost = 50000 },
        { Name = "Golden Soldier", Cost = 50000 },
        { Name = "Golden Pyromancer", Cost = 50000 },
        { Name = "Golden Crook Boss", Cost = 50000 },
        { Name = "Golden Minigunner", Cost = 50000 },
        { Name = "Golden Cowboy", Cost = 50000 },
    },
}

local EvoData = {
    ["Scout"] = { Evo = "EvolvedOperator", Coins = 15000, Gems = 4500 },
    ["Shotgunner"] = { Evo = "EvolvedEnforcer", Coins = 15000, Gems = 5000 },
    ["Crook Boss"] = { Evo = "EvolvedKingpin", Coins = 15000, Gems = 5500 },
    ["Minigunner"] = { Evo = "EvolvedJuggernaut", Coins = 15000, Gems = 6000 }
}

local EvoToTower = {
    ["EvolvedOperator"] = "Scout",
    ["EvolvedEnforcer"] = "Shotgunner",
    ["EvolvedKingpin"] = "Crook Boss",
    ["EvolvedJuggernaut"] = "Minigunner"
}

--==============================================================================
-- Settings Persistence System (Debounced to prevent disk thrashing)
--==============================================================================
local DefaultSettings = {
    AutoSkip = false,
    AutoRestart = true,
    AutoTrials = false,
    AutoGold = false,
    AutoEvo = false,
    TargetEvo = "All",
    EvoStrat = "Lose",
    CurrentEvoFarmType = "Coins",
    CurrentEvoGrindState = "Grinding coins...",
    CurrentEvoActiveTower = "Scout",
    Target = 1,
    Strat = "Lose",
    AutoFarmType = "Coins",
    SelectedTrials = { "Fog" },
    SelectedFallback = "Fallen",
    TrialFarmMode = "Farm Mode",
    FarmOnly = "Disabled",
    MultiplayerEnabled = true,
    MultiplayerMode = "Trial Mode",
    MultiplayerRole = "Host",
    MultiplayerIsHost = false,
    MultiplayerHostIdentifier = "",
    MultiplayerTargetP2 = "",
    MultiplayerIsP2 = false,
    MultiplayerTargetHost = "",
    PrivateServerCode = "",
    LobbyWatcherEnabled = true,
    PreferredAccessTier = "Keyless",
    BuyMissingCoinsTower = false,
    BuyMissingGemTower = false,
    BuyMissingEvoTower = false,
    BuyMissingGoldSkins = false,
    BuySkillTree = false,
    PrivateCode = "",
    AutoReloadGatling = false,
    GatlingReloadPercent = 100,
    AutoGatling = true,
    SelectedGatling = "Gatlify",
    TimeScaleEnabled = false,
    TimeScaleValue = 2,
    TargetTimescale = 0,
    TimescaleUsedSession = 0,
    TargetCoins = 0,
    TargetGems = 0,
    WebhookURL = "",
    AutoSkins = false,
    TargetCrate = "Basic Crate",
    TargetSkin = "Any",
    AutoSpecial = false,
    TargetSpecialMode = "Badlands II",
    MobileBoost = false,
}

local saveDebounceTimer: thread? = nil

local function SaveSettings(immediate: boolean?)
    local function executeSave()
        ensureFolder(CONFIG_FOLDER)
        ensureParentFolder(SETTINGS_FILE)
        local dataToSave = {}
        for key in pairs(DefaultSettings) do
            dataToSave[key] = Globals[key]
        end
        if writefile and HttpService then
            local encoded = HttpService:JSONEncode(dataToSave)
            pcall(function()
                writefile(SETTINGS_FILE, encoded)
            end)
            pcall(function()
                writefile(CONFIG_FOLDER .. "/user.json", encoded)
            end)
        end
    end

    if immediate then
        if saveDebounceTimer then
            task.cancel(saveDebounceTimer)
            saveDebounceTimer = nil
        end
        executeSave()
    else
        if saveDebounceTimer then
            task.cancel(saveDebounceTimer)
        end
        saveDebounceTimer = task.delay(0.1, function()
            saveDebounceTimer = nil
            executeSave()
        end)
    end
end

local function LoadSettings()
    ensureFolder(CONFIG_FOLDER)
    local data = {}
    local targetPath = isfile and isfile(SETTINGS_FILE) and SETTINGS_FILE or nil
    if not targetPath and isfile then
        if isfile(CONFIG_FOLDER .. "/user.json") then
            targetPath = CONFIG_FOLDER .. "/user.json"
        elseif isfile("[AT]/" .. SETTINGS_FILE_NAME) then
            targetPath = "[AT]/" .. SETTINGS_FILE_NAME
        elseif isfile("[Trial]/" .. SETTINGS_FILE_NAME) then
            targetPath = "[Trial]/" .. SETTINGS_FILE_NAME
        elseif isfile("ServiceHub/" .. SETTINGS_FILE_NAME) then
            targetPath = "ServiceHub/" .. SETTINGS_FILE_NAME
        elseif isfile("user.json") then
            targetPath = "user.json"
        end
    end

    if targetPath then
        local success, content = pcall(readfile, targetPath)
        if success and content and content ~= "" then
            pcall(function()
                data = HttpService:JSONDecode(content)
            end)
        end
    end

    for key, defaultVal in pairs(DefaultSettings) do
        if data[key] ~= nil then
            Globals[key] = data[key]
        elseif Globals[key] == nil then
            Globals[key] = defaultVal
        end
    end

    -- Backward compatibility for settings saved before Owned Mode was renamed.
    if Globals.TrialFarmMode == "Owned Mode" then
        Globals.TrialFarmMode = "Progression Mode"
    end

    -- Synchronize MultiplayerTargetP2 and MultiplayerHostIdentifier for backward compatibility
    if (not Globals.MultiplayerTargetP2 or Globals.MultiplayerTargetP2 == "") and (Globals.MultiplayerHostIdentifier and Globals.MultiplayerHostIdentifier ~= "") then
        Globals.MultiplayerTargetP2 = Globals.MultiplayerHostIdentifier
    elseif (Globals.MultiplayerTargetP2 and Globals.MultiplayerTargetP2 ~= "") and (not Globals.MultiplayerHostIdentifier or Globals.MultiplayerHostIdentifier == "") then
        Globals.MultiplayerHostIdentifier = Globals.MultiplayerTargetP2
    end

    -- Synchronize PrivateServerCode and PrivateCode
    if (not Globals.PrivateServerCode or Globals.PrivateServerCode == "") and (Globals.PrivateCode and Globals.PrivateCode ~= "") then
        Globals.PrivateServerCode = Globals.PrivateCode
    elseif (Globals.PrivateServerCode and Globals.PrivateServerCode ~= "") and (not Globals.PrivateCode or Globals.PrivateCode == "") then
        Globals.PrivateCode = Globals.PrivateServerCode
    end

    -- Role Assignment based strictly on user configuration and textboxes (no hardcoded names)
    if Globals.MultiplayerIsHost and Globals.MultiplayerIsP2 then
        Globals.MultiplayerIsP2 = false
    elseif not Globals.MultiplayerIsHost and not Globals.MultiplayerIsP2 then
        if Globals.MultiplayerTargetHost and #Globals.MultiplayerTargetHost > 0 then
            Globals.MultiplayerIsP2 = true
        elseif Globals.MultiplayerTargetP2 and #Globals.MultiplayerTargetP2 > 0 then
            Globals.MultiplayerIsHost = true
        end
    end

    SaveSettings(true)
end

LoadSettings()

-- Saved configurations in .json are strictly preserved across sessions (even if Premium expires).
-- Server / runtime checks (isPremiumUser) prevent unauthorized triggers without wiping the user's saved .json file.

--==============================================================================
-- Helper: Dynamically resolve Player instance by Username, DisplayName, or UserId
--==============================================================================
local function GetPlayerFromIdentifier(identifier)
    if not identifier or identifier == "" then return nil end
    local clean = string.gsub(tostring(identifier), "%s+", "")
    if clean == "" then return nil end

    -- 1. Exact name match
    local p = Players:FindFirstChild(clean)
    if p and p:IsA("Player") then return p end

    -- 2. User ID match (if numeric)
    local uid = tonumber(clean)
    if uid then
        local pByUid = Players:GetPlayerByUserId(uid)
        if pByUid then return pByUid end
    end

    -- 3. Case-insensitive Name or DisplayName match
    local lower = string.lower(clean)
    for _, plr in ipairs(Players:GetPlayers()) do
        if string.lower(plr.Name) == lower or (plr.DisplayName and string.lower(plr.DisplayName) == lower) then
            return plr
        end
    end

    return nil
end

--==============================================================================
-- Local Multiplayer, Party Formation & Private Server Watcher System
-- Operates directly locally on Roblox client APIs without WebSockets
--==============================================================================
local function extractPrivateCode(input)
    if not input or input == "" then return "" end
    local str = tostring(input):gsub("^%s*(.-)%s*$", "%1")
    local codeMatch = str:match("[?&]code=([%w%-]+)")
    if codeMatch then return codeMatch end
    local linkMatch = str:match("privateServerLinkCode=([%w%-]+)")
    if linkMatch then return linkMatch end
    return str
end

local function teleportToPrivateServer(code)
    local clean = extractPrivateCode(code)
    if clean == "" then return false end

    -- 1. Try ExperienceService (standard Windows client)
    local expService = game:GetService("ExperienceService")
    if expService then
        local ok = pcall(function()
            expService:LaunchExperience({
                placeId = LOBBY_PLACE_ID,
                linkCode = clean
            })
        end)
        if ok then return true end
    end

    -- 2. Try TeleportService Private Server
    local ts = game:GetService("TeleportService")
    local ok1 = pcall(function()
        ts:TeleportToPrivateServer(LOBBY_PLACE_ID, clean, { Players.LocalPlayer })
    end)
    if ok1 then return true end

    -- 3. Try TeleportToPlaceInstance
    local ok2 = pcall(function()
        ts:TeleportToPlaceInstance(LOBBY_PLACE_ID, clean, Players.LocalPlayer)
    end)
    return ok2
end

local LocalPartyManager = {
    InPartyWith = {},
    PartyStatusText = "No Party",
    PeerStatusText = "Checking server...",
    WatcherStatusText = "Idle",
    LastInviteAttempt = 0,
    LastAcceptAttempt = 0,
    LastWatcherCheck = 0,
}

function LocalPartyManager:SetPartyStatus(text)
    self.PartyStatusText = text
    if UI and UI.MultiplayerPartyStatusLabel then
        pcall(function() UI.MultiplayerPartyStatusLabel:SetDesc(text) end)
    end
end

function LocalPartyManager:SetPeerStatus(text)
    self.PeerStatusText = text
    if UI and UI.MultiplayerPeerPresenceLabel then
        pcall(function() UI.MultiplayerPeerPresenceLabel:SetDesc(text) end)
    end
end

function LocalPartyManager:SetWatcherStatus(text)
    self.WatcherStatusText = text
    if UI and UI.MultiplayerWatcherStatusLabel then
        pcall(function() UI.MultiplayerWatcherStatusLabel:SetDesc(text) end)
    end
end

function LocalPartyManager:CreateAndInvite(targetIdentifier)
    if not targetIdentifier or targetIdentifier == "" then return false end
    local p2Obj = GetPlayerFromIdentifier(targetIdentifier)
    if not p2Obj then
        self:SetPeerStatus(string.format("P2 '%s' not in this lobby", targetIdentifier))
        return false
    end

    self:SetPeerStatus(string.format("P2 '%s' is present in this lobby", p2Obj.Name))

    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if rf and rf:IsA("RemoteFunction") then
        pcall(function() rf:InvokeServer("Party", "CreateParty", nil) end)
        task.wait(0.2)
        local ok, res = pcall(function() return rf:InvokeServer("Party", "InvitePlayer", p2Obj) end)
        if ok then
            self.InPartyWith[p2Obj.Name] = true
            self:SetPartyStatus("Party Formed with " .. p2Obj.Name)
            print(string.format("[Local Multiplayer] Host invited %s to party", p2Obj.Name))
            return true
        end
    end
    return false
end

function LocalPartyManager:AcceptInviteFrom(hostIdentifier)
    if not hostIdentifier or hostIdentifier == "" then return false end
    local hostObj = GetPlayerFromIdentifier(hostIdentifier)
    if not hostObj then
        self:SetPeerStatus(string.format("Host '%s' not in this lobby", hostIdentifier))
        return false
    end

    self:SetPeerStatus(string.format("Host '%s' is present in this lobby", hostObj.Name))

    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if rf and rf:IsA("RemoteFunction") then
        local ok, res = pcall(function() return rf:InvokeServer("Party", "AcceptInvite", hostObj) end)
        if ok then
            self.InPartyWith[hostObj.Name] = true
            self:SetPartyStatus("In Party with " .. hostObj.Name)
            print(string.format("[Local Multiplayer] P2 accepted party invite from Host %s", hostObj.Name))
            return true
        end
    end
    return false
end

function LocalPartyManager:LeaveParty()
    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if rf and rf:IsA("RemoteFunction") then
        pcall(function() rf:InvokeServer("Party", "LeaveParty") end)
    end
    self.InPartyWith = {}
    self:SetPartyStatus("No Party")
    print("[Local Multiplayer] Left party.")
end

-- Fast lobby party loop: instantly groups Host & P2 when in the same lobby
task.spawn(function()
    while true do
        task.wait(1.5)
        if game.PlaceId == LOBBY_PLACE_ID and Globals.MultiplayerEnabled then
            if Globals.MultiplayerIsHost then
                local targetP2 = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
                if targetP2 ~= "" then
                    local p2Obj = GetPlayerFromIdentifier(targetP2)
                    if p2Obj then
                        LocalPartyManager:SetPeerStatus(string.format("P2 '%s' is in this lobby (Ready)", p2Obj.Name))
                        if not LocalPartyManager.InPartyWith[p2Obj.Name] and (os.time() - LocalPartyManager.LastInviteAttempt >= 4) then
                            LocalPartyManager.LastInviteAttempt = os.time()
                            LocalPartyManager:CreateAndInvite(targetP2)
                        end
                    else
                        LocalPartyManager:SetPeerStatus(string.format("P2 '%s' not found in lobby", targetP2))
                    end
                end
            elseif Globals.MultiplayerIsP2 then
                local targetHost = tostring(Globals.MultiplayerTargetHost or ""):gsub("^%s*(.-)%s*$", "%1")
                if targetHost ~= "" then
                    local hostObj = GetPlayerFromIdentifier(targetHost)
                    if hostObj then
                        LocalPartyManager:SetPeerStatus(string.format("Host '%s' is in this lobby (Ready)", hostObj.Name))
                        if not LocalPartyManager.InPartyWith[hostObj.Name] and (os.time() - LocalPartyManager.LastAcceptAttempt >= 3) then
                            LocalPartyManager.LastAcceptAttempt = os.time()
                            LocalPartyManager:AcceptInviteFrom(targetHost)
                        end
                    else
                        LocalPartyManager:SetPeerStatus(string.format("Host '%s' not found in lobby", targetHost))
                    end
                end
            end
        end
    end
end)

-- 30-Second Private Server Watcher Loop
task.spawn(function()
    local missingSince = 0
    while true do
        task.wait(2)
        if game.PlaceId == LOBBY_PLACE_ID and Globals.MultiplayerEnabled and Globals.LobbyWatcherEnabled ~= false then
            local pvCode = tostring(Globals.PrivateServerCode or Globals.PrivateCode or ""):gsub("^%s*(.-)%s*$", "%1")
            if pvCode ~= "" then
                local targetFound = false
                local targetName = ""

                if Globals.MultiplayerIsHost then
                    targetName = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
                    if targetName ~= "" and GetPlayerFromIdentifier(targetName) then
                        targetFound = true
                    end
                elseif Globals.MultiplayerIsP2 then
                    targetName = tostring(Globals.MultiplayerTargetHost or ""):gsub("^%s*(.-)%s*$", "%1")
                    if targetName ~= "" and GetPlayerFromIdentifier(targetName) then
                        targetFound = true
                    end
                end

                if targetName ~= "" then
                    if targetFound then
                        missingSince = 0
                        LocalPartyManager:SetWatcherStatus(string.format("Together in lobby with %s", targetName))
                    else
                        if missingSince == 0 then
                            missingSince = os.time()
                        end

                        local elapsed = os.time() - missingSince
                        local remaining = math.max(0, 30 - elapsed)
                        LocalPartyManager:SetWatcherStatus(string.format("%s missing | TP in %ds", targetName, remaining))

                        if elapsed >= 30 and (os.time() - LocalPartyManager.LastWatcherCheck >= 20) then
                            LocalPartyManager.LastWatcherCheck = os.time()
                            missingSince = os.time()
                            LocalPartyManager:SetWatcherStatus("Teleporting to Private Server...")
                            print(string.format("[30s Watcher] %s missing for 30s. Teleporting to private server: %s", targetName, pvCode))
                            teleportToPrivateServer(pvCode)
                        end
                    end
                else
                    missingSince = 0
                    LocalPartyManager:SetWatcherStatus("No target username configured")
                end
            else
                missingSince = 0
                LocalPartyManager:SetWatcherStatus("No Private Server Code configured")
            end
        else
            missingSince = 0
            if LocalPartyManager then
                LocalPartyManager:SetWatcherStatus("Watcher Idle (Multiplayer disabled or in match)")
            end
        end
    end
end)

--==============================================================================
-- Timescale Handlers & Helper Functions
--==============================================================================
local CoerceTimeScaleValue: (val: any, fallback: number) -> number
local ApplyTimeScaleOnce: () -> ()
local StartTimeScale: () -> ()
do
    local TimeScaleValues = { 0.5, 1, 1.5, 2 }

    local function NormalizeTimeScaleValue(val: any): number?
        local num = tonumber(val)
        if not num then return nil end
        for _, v in ipairs(TimeScaleValues) do
            if v == num then return v end
        end
        return nil
    end

    CoerceTimeScaleValue = function(val: any, fallback: number): number
        return NormalizeTimeScaleValue(val) or fallback
    end

    local function GetTimescaleFrame(): GuiObject?
        local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar")
        local frame = hotbar and hotbar:FindFirstChild("Frame")
        return frame and frame:FindFirstChild("timescale")
    end

    local function SetGameTimescale(targetVal: number)
        if game.PlaceId == LOBBY_PLACE_ID then return end

        local speedList = { 0, 0.5, 1, 1.5, 2 }
        local targetIdx = nil
        for i, v in ipairs(speedList) do
            if v == targetVal then
                targetIdx = i
                break
            end
        end
        if not targetIdx then return end

        local frame = GetTimescaleFrame()
        if not frame then return end

        local speedLabel = frame:FindFirstChild("Speed")
        if not (speedLabel and speedLabel:IsA("TextLabel")) then return end

        local currentVal = tonumber(speedLabel.Text:match("x([%d%.]+)"))
        if not currentVal then return end

        local currentIdx = nil
        for i, v in ipairs(speedList) do
            if v == currentVal then
                currentIdx = i
                break
            end
        end
        if not currentIdx or currentIdx == targetIdx then return end

        local diff = targetIdx - currentIdx
        if diff < 0 then
            diff = #speedList + diff
        end

        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
        if not rf then return end

        for _ = 1, diff do
            pcall(function()
                rf:InvokeServer("TicketsManager", "CycleTimeScale")
            end)
            task.wait(0.5)
        end
    end

    local function UnlockSpeedTickets()
        if game.PlaceId == LOBBY_PLACE_ID then return end

        local tickets = LocalPlayer:FindFirstChild("TimescaleTickets")
        if tickets and tickets.Value >= 1 then
            local frame = GetTimescaleFrame()
            local lockIcon = frame and frame:FindFirstChild("Lock")

            if lockIcon and lockIcon.Visible then
                local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                if rf then
                    pcall(function()
                        rf:InvokeServer("TicketsManager", "UnlockTimeScale")
                    end)
                    ----print(("[ServiceHub] Unlocked timescale tickets")
                end
            end
        else
            ----print(("[ServiceHub] No timescale tickets left")
        end
    end

    local currentMatchTimescaleCounted = false
    ApplyTimeScaleOnce = function()
        if not Globals.TimeScaleEnabled then return end

        local stateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")
        if not gameStateReplicator or gameStateReplicator:GetAttribute("GameStarted") ~= true then
            currentMatchTimescaleCounted = false
            return
        end

        local frame = GetTimescaleFrame()
        if not frame or not frame.Visible then return end

        local desired = CoerceTimeScaleValue(Globals.TimeScaleValue, 2)
        local lock = frame:FindFirstChild("Lock")

        if lock and lock.Visible then
            local tickets = LocalPlayer:FindFirstChild("TimescaleTickets")
            if tickets and tickets.Value < 1 then
                if not TimeScaleNoTicketsWarned then
                    ----print(("[ServiceHub] No timescale tickets left")
                    TimeScaleNoTicketsWarned = true
                end
                return
            end
            UnlockSpeedTickets()
            task.wait(0.4)
        else
            TimeScaleNoTicketsWarned = false
        end

        SetGameTimescale(desired)

        if not currentMatchTimescaleCounted then
            currentMatchTimescaleCounted = true
            SetSetting("TimescaleUsedSession", (Globals.TimescaleUsedSession or 0) + 1)
            if typeof(refreshDisplay) == "function" then
                pcall(refreshDisplay)
            end
        end
    end

    StartTimeScale = function()
        if TimeScaleRunning or not Globals.TimeScaleEnabled then return end
        TimeScaleRunning = true

        task.spawn(function()
            while Globals.TimeScaleEnabled do
                if not isRunning then break end
                ApplyTimeScaleOnce()
                task.wait(3)
            end
            TimeScaleNoTicketsWarned = false
            TimeScaleRunning = false
        end)
    end
end

local isMatchConfigDirty: () -> boolean

local function SetSetting(name: string, value: any)
    if DefaultSettings[name] ~= nil then
        if name == "TimeScaleValue" then
            value = CoerceTimeScaleValue(value, Globals.TimeScaleValue or 2)
        end
        if type(value) == "table" then
            local clone = {}
            for k, v in pairs(value) do
                clone[k] = v
            end
            Globals[name] = clone
        else
            Globals[name] = value
        end
        SaveSettings(true)

        if game.PlaceId ~= LOBBY_PLACE_ID and isMatchConfigDirty and isMatchConfigDirty() then
            if not Globals.IsConfigDirty then
                Globals.IsConfigDirty = true
                if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                    RunAsExecutor(function()
                        UI.Window:Notify({
                            Title = "CONFIG QUEUED",
                            Desc = "Change saved! Current match will finish before returning to lobby.",
                            Duration = 5,
                            Type = "info"
                        })
                    end)()
                end
            end
        end
    end
end

Globals.TimeScaleValue = CoerceTimeScaleValue(Globals.TimeScaleValue, 2)

--==============================================================================
-- State & Active Mode Persistence
--==============================================================================
local function saveTrialState(trialName: string)
    ensureFolder(CONFIG_FOLDER)
    ensureParentFolder(TRIAL_STATE_FILE)
    if writefile then
        pcall(writefile, TRIAL_STATE_FILE, trialName)
    end
end

local function loadTrialState(): string?
    local targetPath = (isfile and isfile(TRIAL_STATE_FILE)) and TRIAL_STATE_FILE or nil
    if not targetPath and isfile then
        if isfile("[ATF]/" .. TRIAL_STATE_FILE_NAME) then
            targetPath = "[ATF]/" .. TRIAL_STATE_FILE_NAME
        elseif isfile("[AT]/" .. TRIAL_STATE_FILE_NAME) then
            targetPath = "[AT]/" .. TRIAL_STATE_FILE_NAME
        elseif isfile("ServiceHub/" .. TRIAL_STATE_FILE_NAME) then
            targetPath = "ServiceHub/" .. TRIAL_STATE_FILE_NAME
        end
    end
    if targetPath and isfile and readfile then
        local ok, content = pcall(readfile, targetPath)
        if ok and content and content ~= "" then
            return content:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    return nil
end

-- [ServiceHub] clearTrialState removed (unused)

local function saveActiveMode(mode: string)
    ensureFolder(CONFIG_FOLDER)
    ensureParentFolder(ACTIVE_MODE_FILE)
    if writefile then
        pcall(writefile, ACTIVE_MODE_FILE, mode)
    end
end

local function loadActiveMode(): string?
    if isfile and isfile(ACTIVE_MODE_FILE) then
        local ok, content = pcall(readfile, ACTIVE_MODE_FILE)
        if ok and content and content ~= "" then
            return content:gsub("%s+", "")
        end
    end
    return nil
end

local function clearActiveMode()
    if delfile and isfile and isfile(ACTIVE_MODE_FILE) then
        pcall(delfile, ACTIVE_MODE_FILE)
    end
end

local function saveActiveFarmType(farmType: string)
    ensureFolder(CONFIG_FOLDER)
    ensureParentFolder(ACTIVE_FARM_TYPE_FILE)
    if writefile then
        pcall(writefile, ACTIVE_FARM_TYPE_FILE, farmType)
    end
end

local function loadActiveFarmType(): string?
    if isfile and isfile(ACTIVE_FARM_TYPE_FILE) then
        local ok, content = pcall(readfile, ACTIVE_FARM_TYPE_FILE)
        if ok and content and content ~= "" then
            return content:gsub("%s+", "")
        end
    end
    return nil
end

local function clearActiveFarmType()
    if delfile and isfile and isfile(ACTIVE_FARM_TYPE_FILE) then
        pcall(delfile, ACTIVE_FARM_TYPE_FILE)
    end
end

-- Match Mode Detection in Game
local currentMatchMode: string? = nil

--==============================================================================
-- In-Game Match State & Dirty Configuration Tracking
--==============================================================================
local originalMatchConfig: { [string]: any }? = nil
local isLateExecution = false
local initialExecutionWave = 0

local isTowerEvoComplete: (towerName: string) -> boolean
local isTowerOrEvoOwned: (towerName: string) -> boolean

local function snapshotMatchConfig()
    if game.PlaceId == LOBBY_PLACE_ID then
        originalMatchConfig = nil
        return
    end

    local startStage = nil
    local startTower = nil
    local startCoins = 0
    local startGems = 0
    local startBaseLevel = 0
    local startEvoLevel = 0

    pcall(function()
        if PlayerDataHandler then
            pcall(function() startCoins = PlayerDataHandler:GetCoins() or 0 end)
            pcall(function() startGems = PlayerDataHandler:GetGems() or 0 end)
        end

        local selected = tostring(Globals.TargetEvo or "All")
        local tList = (selected == "All") and { "Scout", "Shotgunner", "Crook Boss", "Minigunner" } or { selected }
        for _, tName in ipairs(tList) do
            if not isTowerEvoComplete(tName) then
                if selected ~= "All" or (isTowerOrEvoOwned and isTowerOrEvoOwned(tName)) then
                    startTower = tName
                    break
                end
            end
        end

        if startTower and EvoData and EvoData[startTower] then
            local eData = EvoData[startTower]
            local evoName = eData.Evo or startTower
            local ownsEvo = false
            if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                ownsEvo = PlayerDataHandler:IsTowerOwned(evoName)
            end

            if ownsEvo then
                startStage = "EvoLevel"
                local evoExp = nil
                if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                    evoExp = PlayerDataHandler:GetTowerExp(evoName)
                end
                startEvoLevel = (evoExp and type(evoExp.Level) == "number") and evoExp.Level or 0
            else
                local ownsBase = false
                if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                    ownsBase = PlayerDataHandler:IsTowerOwned(startTower)
                end
                if not ownsBase then
                    startStage = "Coins"
                else
                    local targetCoins = eData.Coins or 0
                    local targetGems = eData.Gems or 0
                    local coinsNeed = math.max(0, targetCoins - startCoins)
                    local gemsNeed = math.max(0, targetGems - startGems)
                    local expData = nil
                    if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                        expData = PlayerDataHandler:GetTowerExp(startTower)
                    end
                    startBaseLevel = (expData and type(expData.Level) == "number") and expData.Level or 0

                    if coinsNeed > 0 then
                        startStage = "Coins"
                    elseif startBaseLevel < 20 then
                        startStage = "BaseLevel"
                    elseif gemsNeed > 0 then
                        startStage = "Gems"
                    else
                        startStage = "ReadyToBuy"
                    end
                end
            end
        end
    end)

    originalMatchConfig = {
        AutoTrials = Globals.AutoTrials,
        AutoGold = Globals.AutoGold,
        AutoEvo = Globals.AutoEvo,
        AutoFarmType = tostring(Globals.AutoFarmType or "Coins"),
        TargetMode = tostring(Globals.TargetMode or "Molten"),
        Strat = tostring(Globals.Strat or "Lose"),
        TargetEvo = tostring(Globals.TargetEvo or "All"),
        EvoStrat = tostring(Globals.EvoStrat or "Lose"),
        SelectedFallback = tostring(Globals.SelectedFallback or "Smart Auto"),
        TrialFarmMode = tostring(Globals.TrialFarmMode or "Farm Mode"),
        FarmOnly = tostring(Globals.FarmOnly or "Disabled"),
        SelectedTrials = (type(Globals.SelectedTrials) == "table") and table.concat(Globals.SelectedTrials, ",") or tostring(Globals.SelectedTrials or ""),
        ActiveMode = tostring(currentMatchMode or loadActiveMode() or ""),
        EvoStartStage = startStage,
        EvoStartTower = startTower,
        EvoStartBaseLevel = startBaseLevel,
        EvoStartEvoLevel = startEvoLevel,
    }
end

isMatchConfigDirty = function(): boolean
    if game.PlaceId == LOBBY_PLACE_ID then return false end
    if Globals.IsConfigDirty then return true end
    if not originalMatchConfig then return false end

    if originalMatchConfig.AutoTrials ~= Globals.AutoTrials then return true end
    if originalMatchConfig.AutoGold ~= Globals.AutoGold then return true end
    if originalMatchConfig.AutoEvo ~= Globals.AutoEvo then return true end
    if originalMatchConfig.AutoFarmType ~= tostring(Globals.AutoFarmType or "Coins") then return true end
    if originalMatchConfig.TargetMode ~= tostring(Globals.TargetMode or "Molten") then return true end
    if originalMatchConfig.Strat ~= tostring(Globals.Strat or "Lose") then return true end
    if originalMatchConfig.TargetEvo ~= tostring(Globals.TargetEvo or "All") then return true end
    if originalMatchConfig.EvoStrat ~= tostring(Globals.EvoStrat or "Lose") then return true end
    if originalMatchConfig.SelectedFallback ~= tostring(Globals.SelectedFallback or "Smart Auto") then return true end
    if originalMatchConfig.TrialFarmMode ~= tostring(Globals.TrialFarmMode or "Farm Mode") then return true end
    if originalMatchConfig.FarmOnly ~= tostring(Globals.FarmOnly or "Disabled") then return true end
    
    local currentTrialsStr = (type(Globals.SelectedTrials) == "table") and table.concat(Globals.SelectedTrials, ",") or tostring(Globals.SelectedTrials or "")
    if originalMatchConfig.SelectedTrials ~= currentTrialsStr then return true end

    local curMode = tostring(currentMatchMode or loadActiveMode() or "")
    if originalMatchConfig.ActiveMode ~= "" and curMode ~= "" and originalMatchConfig.ActiveMode ~= curMode then
        return true
    end

    return false
end
if game.PlaceId ~= LOBBY_PLACE_ID then
    currentMatchMode = loadActiveMode()
    local isOwnedModeWithOther = (Globals.TrialFarmMode == "Progression Mode" and (Globals.AutoEvo or Globals.AutoGold))

    if not currentMatchMode or currentMatchMode == "" or (isOwnedModeWithOther and currentMatchMode == "AutoTrials") then
        local isTrial = false
        local liveTrial = ""
        pcall(function()
            local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
            if gsr then
                local gt = gsr:GetAttribute("GlobalTrial")
                if gt and tostring(gt) ~= "" and tostring(gt) ~= "None" then
                    isTrial = true
                    liveTrial = tostring(gt)
                end
            end
        end)

        if isTrial and not isOwnedModeWithOther then
            currentMatchMode = "AutoTrials"
        elseif isOwnedModeWithOther then
            if Globals.AutoEvo then
                currentMatchMode = "AutoEvo"
            else
                currentMatchMode = "AutoGold"
            end
        elseif isTrial then
            currentMatchMode = "AutoTrials"
        elseif Globals.AutoTrials then
            currentMatchMode = "AutoTrials"
        elseif Globals.AutoGold then
            currentMatchMode = "AutoGold"
        elseif Globals.AutoEvo then
            currentMatchMode = "AutoEvo"
        else
            currentMatchMode = "AutoTrials"
        end
    end
    ----print((`[ServiceHub] In-Game Active Match Mode detected: {currentMatchMode}`)
end

--==============================================================================
-- Smart Teleport & Lobby Handlers
--==============================================================================
local isTeleporting = false
local loadoutApplied = false
local teleportRetryThread = nil


--==============================================================================
-- Trial Modifier Voting System
--==============================================================================
local RemoteFunc = nil

local function CastModifierVote(ModsTable)
    if type(ModsTable) == "table" and #ModsTable == 1 and type(ModsTable[1]) == "table" then
        ModsTable = ModsTable[1]
    end

    local BulkModifiers = nil
    pcall(function()
        local net = ReplicatedStorage:WaitForChild("Network", 5)
        local mods = net and net:WaitForChild("Modifiers", 5)
        BulkModifiers = mods and mods:WaitForChild("RF:BulkVoteModifiers", 5)
    end)

    local ModRep = nil
    pcall(function()
        local sr = ReplicatedStorage:WaitForChild("StateReplicators", 5)
        ModRep = sr and sr:FindFirstChild("ModifierReplicator")
    end)

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

    if #missingMods > 0 then
        pcall(function()
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                UI.Window:Notify({
                    Title = "ADS",
                    Desc = "Locked (Skipped) modifiers: " .. table.concat(missingMods, ", "),
                    Time = 50,
                    Duration = 10,
                    Type = "error"
                })
            end
        end)
    end

    if next(SelectedMods) and BulkModifiers then
        pcall(function()
            BulkModifiers:InvokeServer(SelectedMods)
            logActivity("Successfully casted modifier votes.", "success")
        end)
    end
end

local isMapIntermissionHandling = false
local intermissionMapHandled = false
local lastVotedIntermissionMap: string? = nil

local function SmartTeleportToLobby()
    if isTeleporting then return end
    isTeleporting = true
    loadoutApplied = false
    intermissionMapHandled = false
    isMapIntermissionHandling = false
    lastVotedIntermissionMap = nil
    ----warn([ServiceHub] SmartTeleportToLobby initiating...")

    pcall(clearActiveMode)
    pcall(clearActiveFarmType)

    if teleportRetryThread then
        pcall(task.cancel, teleportRetryThread)
        teleportRetryThread = nil
    end

    teleportRetryThread = task.spawn(function()
        while true do
            if not isRunning then break end
            if game.PlaceId == LOBBY_PLACE_ID then break end

            pcall(function()
                local platform = UserInputService:GetPlatform()
                local isMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)

                if not isMobile and Globals.PrivateCode and Globals.PrivateCode ~= "" then
                    pcall(function()
                        local expService = game:GetService("ExperienceService")
                        if expService then
                            expService:LaunchExperience({
                                placeId = LOBBY_PLACE_ID,
                                linkCode = Globals.PrivateCode
                            })
                        end
                    end)
                else
                    pcall(function()
                        local shared = ReplicatedStorage:FindFirstChild("Shared")
                        local modules = shared and shared:FindFirstChild("Modules")
                        local newNet = modules and modules:FindFirstChild("NewNetwork")
                        if newNet then
                            local NewNetwork = require(newNet)
                            NewNetwork.Channel("Teleport"):fireServer("backToLobby")
                        end
                    end)

                    pcall(function()
                        local remoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent")
                        local remoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if remoteEvent and remoteEvent:IsA("RemoteEvent") then
                            remoteEvent:FireServer("Teleport", "backToLobby")
                        elseif remoteFunc and remoteFunc:IsA("RemoteFunction") then
                            remoteFunc:InvokeServer("Teleport", "backToLobby")
                        end
                    end)

                    task.delay(1.5, function()
                        pcall(function()
                            TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
                        end)
                    end)
                end
            end)
            
            task.wait(10) -- Retry teleport every 10 seconds until they are back in the lobby
        end
    end)

    task.delay(30, function()
        isTeleporting = false
    end)
end

--==============================================================================

--==============================================================================
-- Mobile & Low-End Device Performance Optimizer
--==============================================================================
local mobileBoostActive = false
local function applyMobileOptimizations(enable: boolean)
    mobileBoostActive = enable
    if not enable then return end
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
    pcall(function()
        local lighting = game:GetService("Lighting")
        lighting.GlobalShadows = false
        lighting.FogEnd = 9e9
        for _, effect in ipairs(lighting:GetChildren()) do
            if effect:IsA("PostEffect") or effect:IsA("Atmosphere") or effect:IsA("Clouds") or effect:IsA("Sky") then
                effect.Enabled = false
            end
        end
    end)
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Fire") then
                obj.Enabled = false
            end
        end
    end)
end

-- AutoGoldModule & Map Prioritization Handlers (High-Performance Single-Pass Scan)
--==============================================================================
local AutoGoldModule = {}
AutoGoldModule.Configs = FallbackConfigs
AutoGoldModule.CrateConfigs = CrateConfigs

local function resolveSmartFallback(): string
    ensureDynamicHardcoreFallback()
    if not FallbackConfigs or not next(FallbackConfigs) then
        return "Molten"
    end
    local pLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local function checkEligible(cfgName: string): boolean
        local cfg = FallbackConfigs[cfgName]
        if not cfg then return false end
        local reqLvl = cfg.Level or cfg.level or 0
        if pLevel < reqLvl then return false end
        if cfg.Towers and type(cfg.Towers) == "table" and PlayerDataHandler then
            for _, tow in ipairs(cfg.Towers) do
                if tow and tow ~= "" and not PlayerDataHandler:IsTowerOwned(tow) then
                    return false
                end
            end
        end
        return true
    end

    -- Rule: If coin towers are all owned, MOVE to Hardcore gems fallback!
    local coinTowersOwned = false
    if typeof(isCoinTowersMaxed) == "function" then
        pcall(function()
            coinTowersOwned = isCoinTowersMaxed()
        end)
    end

    if coinTowersOwned then
        if checkEligible("Hardcore") then
            return "Hardcore"
        elseif FallbackConfigs["Hardcore"] then
            return "Hardcore"
        end
    end

    -- If coins towers are not yet all owned, prefer Fallen / Molten for coins
    if checkEligible("Fallen") then
        return "Fallen"
    elseif checkEligible("Molten") then
        return "Molten"
    end

    if FallbackConfigs["Fallen"] then
        return "Fallen"
    elseif FallbackConfigs["Molten"] then
        return "Molten"
    end
    for k in pairs(FallbackConfigs) do
        if type(k) == "string" then return k end
    end
    return "Molten"
end

resolveCoinFarmFallback = function(): string
    ensureDynamicHardcoreFallback()
    local pLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local function checkEligible(cfgName: string): boolean
        local cfg = FallbackConfigs and FallbackConfigs[cfgName]
        if not cfg then return false end
        local reqLvl = cfg.Level or cfg.level or 0
        if pLevel < reqLvl then return false end
        if cfg.Towers and type(cfg.Towers) == "table" and PlayerDataHandler then
            for _, tow in ipairs(cfg.Towers) do
                if tow and tow ~= "" and not PlayerDataHandler:IsTowerOwned(tow) then
                    return false
                end
            end
        end
        return true
    end

    if checkEligible("Fallen") then
        return "Fallen"
    elseif checkEligible("Molten") then
        return "Molten"
    end

    if FallbackConfigs and FallbackConfigs["Fallen"] then
        return "Fallen"
    end
    return "Molten"
end

local analyzeAutoEvoRequirements: ((optTargetEvo: string?, optStrat: string?) -> AutoEvoAnalysis)? = nil

local function getCurrentCrateConfig(optFarmType: string?): any
    local liveGameMode = ""
    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            liveGameMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or ""):lower()
        end
    end)
    local isHardcoreMatch = (liveGameMode == "hardcore")
    local savedFarmType = (typeof(loadActiveFarmType) == "function") and loadActiveFarmType() or nil

    local isAutoEvoActive = (Globals.AutoEvo or currentMatchMode == "AutoEvo") and not Globals.AutoGold
    if Globals.TrialFarmMode == "Progression Mode" and (Globals.AutoEvo or currentMatchMode == "AutoEvo") then
        isAutoEvoActive = true
    end

    if isAutoEvoActive then
        if not optFarmType and not Globals.CurrentEvoFarmType and typeof(analyzeAutoEvoRequirements) == "function" then
            local ok, evoAnalysis = pcall(analyzeAutoEvoRequirements)
            if ok and evoAnalysis then
                if evoAnalysis.activeTower then
                    Globals.CurrentEvoActiveTower = evoAnalysis.activeTower
                end
                if evoAnalysis.farmType then
                    Globals.CurrentEvoFarmType = evoAnalysis.farmType
                end
            end
        end

        local needType = optFarmType or (isHardcoreMatch and "Gems") or Globals.CurrentEvoFarmType or savedFarmType or "Coins"
        
        -- Auto Buy Evo rule: Coins strictly uses Win (Fallen on Lay By), Gems strictly uses Lose (hardcore on Wretched Front)
        local stratChoice = (needType == "Gems" or isHardcoreMatch) and "Lose" or "Win"
        
        local category = AutoEvoConfigs[needType]
        if category and category[stratChoice] then
            return category[stratChoice]
        end
        if category and category["Win"] then return category["Win"] end
        if category and category["Lose"] then return category["Lose"] end
        return nil
    end

    local farmType = optFarmType or (isHardcoreMatch and "Gems") or savedFarmType or Globals.AutoFarmType or "Coins"

    -- Check if live match difficulty or saved trial state matches FallbackConfigs (e.g. Fallen or Molten with Lay By)
    local liveDiff = ""
    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            liveDiff = tostring(gsr:GetAttribute("Difficulty") or "")
        end
    end)
    local savedTrial = ""
    if typeof(loadTrialState) == "function" then
        pcall(function() savedTrial = tostring(loadTrialState() or "") end)
    end
    if FallbackConfigs then
        for modeName, modeConfig in pairs(FallbackConfigs) do
            if (liveDiff ~= "" and normalizeString(modeName) == normalizeString(liveDiff))
                or (savedTrial ~= "" and normalizeString(modeName) == normalizeString(savedTrial)) then
                return modeConfig
            end
        end
    end

    local stratChoice = Globals.Strat or "Lose"
    if farmType == "Gems" or isHardcoreMatch then
        stratChoice = "Lose"
    elseif stratChoice == "Fallen" then
        stratChoice = "Win"
    elseif stratChoice == "Molten" then
        stratChoice = "Lose"
    end

    local category = AutoGoldModule.CrateConfigs and AutoGoldModule.CrateConfigs[farmType] or CrateConfigs[farmType]
    if category and category[stratChoice] then
        return category[stratChoice]
    end
    if category and category["Lose"] then return category["Lose"] end
    if category and category["Win"] then return category["Win"] end

    if AutoGoldModule.CrateConfigs and AutoGoldModule.CrateConfigs[stratChoice] then
        return AutoGoldModule.CrateConfigs[stratChoice]
    end

    -- Direct fallback for Hardcore / Gems from FallbackConfigs
    if farmType == "Gems" or isHardcoreMatch then
        if FallbackConfigs and FallbackConfigs["Hardcore"] then
            return FallbackConfigs["Hardcore"]
        end
    end

    return nil
end

export type AutoGoldAnalysis = {
    farmType: string,
    stratChoice: string,
    targetMode: string,
    configFound: boolean,
    requiredLevel: number,
    playerLevel: number,
    levelPassed: boolean,
    missingTowers: { string },
    missingGold: { string },
    missingSkills: { string },
    missingParts: { string },
    isEligible: boolean,
}

local function analyzeAutoGoldRequirements(optFarmType: string?, optStrat: string?): AutoGoldAnalysis
    local farmType = optFarmType or Globals.AutoFarmType or "Coins"
    local stratChoice = optStrat or Globals.Strat or "Lose"

    local playerLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local category = AutoGoldModule.CrateConfigs and AutoGoldModule.CrateConfigs[farmType] or CrateConfigs[farmType]
    local config = category and category[stratChoice]

    if not config and AutoGoldModule.CrateConfigs then
        config = AutoGoldModule.CrateConfigs[stratChoice]
    end

    local result: AutoGoldAnalysis = {
        farmType = farmType,
        stratChoice = stratChoice,
        targetMode = config and (config.Mode or config.mode) or "Unknown",
        configFound = (config ~= nil),
        requiredLevel = config and (config.Level or config.level) or 0,
        playerLevel = playerLevel,
        levelPassed = true,
        missingTowers = {},
        missingGold = {},
        missingSkills = {},
        missingParts = {},
        isEligible = false,
    }

    if not config then
        table.insert(result.missingParts, "Config Missing")
        return result
    end

    -- 1. Level Check
    local reqLevel = config.Level or config.level or 0
    result.requiredLevel = reqLevel
    result.levelPassed = (playerLevel >= reqLevel)
    if not result.levelPassed then
        table.insert(result.missingParts, string.format("Level %d (You: %d)", reqLevel, playerLevel))
    end

    -- 2. Towers Check
    local towersConfig = config.Towers or config.towers
    if type(towersConfig) == "table" and PlayerDataHandler then
        for _, tower in ipairs(towersConfig) do
            if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                table.insert(result.missingTowers, tower)
            end
        end
        if #result.missingTowers > 0 and game.PlaceId == LOBBY_PLACE_ID then
            local boughtAny = attemptBuyMissingTowersList(result.missingTowers)
            if boughtAny then
                local remaining = {}
                for _, tower in ipairs(towersConfig) do
                    if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                        table.insert(remaining, tower)
                    end
                end
                result.missingTowers = remaining
            end
        end
    end
    if #result.missingTowers > 0 then
        table.insert(result.missingParts, "Towers: " .. table.concat(result.missingTowers, ", "))
    end

    -- 3. Golden Check
    local goldReqs = config.Golden or config.golden
    if type(goldReqs) == "table" and #goldReqs > 0 and PlayerDataHandler then
        for _, goldTower in ipairs(goldReqs) do
            if goldTower and goldTower ~= "" and not PlayerDataHandler:IsGoldenOwned(goldTower) then
                table.insert(result.missingGold, goldTower)
            end
        end
    end
    if #result.missingGold > 0 then
        table.insert(result.missingParts, "Golden: " .. table.concat(result.missingGold, ", "))
    end

    -- 4. Skill Tree Check
    local skillReqs = config.SkillTree or config["Skill Tree"] or config.skillTree
    if type(skillReqs) == "table" and next(skillReqs) and PlayerDataHandler then
        local currentSkills = {}
        if type(PlayerDataHandler.GetSkillTree) == "function" then
            pcall(function()
                for _, skill in ipairs(PlayerDataHandler:GetSkillTree()) do
                    currentSkills[skill.Name] = skill.Level
                end
            end)
        end
        for skillName, reqNodeLevel in pairs(skillReqs) do
            local haveLevel = currentSkills[skillName] or 0
            if haveLevel < reqNodeLevel then
                table.insert(result.missingSkills, string.format("%s (Need %d, Have %d)", skillName, reqNodeLevel, haveLevel))
            end
        end
    end
    if #result.missingSkills > 0 then
        table.insert(result.missingParts, "Skill Tree: " .. table.concat(result.missingSkills, ", "))
    end

    result.isEligible = result.levelPassed and (#result.missingTowers == 0) and (#result.missingGold == 0) and (#result.missingSkills == 0)
    return result
end

function AutoGoldModule.AnalyzeRequirements(stratType: string): (boolean, string)
    local analysis = analyzeAutoGoldRequirements(nil, stratType)
    if not analysis.configFound then
        return false, "Invalid strategy configuration"
    end
    if not analysis.isEligible then
        return false, table.concat(analysis.missingParts, " | ")
    end
    return true, "All strategy requirements successfully met"
end

export type AutoEvoAnalysis = {
    targetEvo: string,
    stratChoice: string,
    activeTower: string?,
    farmType: string?,
    targetMode: string?,
    configFound: boolean,
    allFinished: boolean,
    readyToBuy: boolean,
    isEligible: boolean,
    missingBase: { string },
    missingTowers: { string },
    missingGold: { string },
    missingSkills: { string },
    requiredLevel: number,
    playerLevel: number,
    levelPassed: boolean,
    missingParts: { string },
}

isTowerOrEvoOwned = function(towerName: string): boolean
    local eData = EvoData[towerName]
    local evoName = eData and eData.Evo or towerName
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        local ownsBase = false
        local ownsEvo = false
        pcall(function() ownsBase = PlayerDataHandler:IsTowerOwned(towerName) end)
        pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
        return (ownsBase == true) or (ownsEvo == true)
    end
    return true
end

isTowerEvoComplete = function(towerName: string): boolean
    local eData = EvoData[towerName]
    local evoName = eData and eData.Evo or towerName
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        local ownsEvo = false
        pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
        if ownsEvo then return true end
    end
    return false
end

analyzeAutoEvoRequirements = function(optTargetEvo: string?, optStrat: string?): AutoEvoAnalysis
    local target = optTargetEvo or Globals.TargetEvo or "All"
    local stratChoice = optStrat or Globals.EvoStrat or "Lose"

    local playerLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local coins = 0
    local gems = 0
    if PlayerDataHandler then
        if typeof(PlayerDataHandler.GetCoins) == "function" then
            pcall(function() coins = PlayerDataHandler:GetCoins() or 0 end)
        end
        if typeof(PlayerDataHandler.GetGems) == "function" then
            pcall(function() gems = PlayerDataHandler:GetGems() or 0 end)
        end
    end

    local toCheck = {}
    if target == "All" then
        for _, tName in ipairs({ "Scout", "Shotgunner", "Crook Boss", "Minigunner" }) do
            if not isTowerEvoComplete(tName) and isTowerOrEvoOwned(tName) then
                table.insert(toCheck, tName)
            end
        end
    elseif EvoData[target] then
        toCheck = { target }
    end

    local result: AutoEvoAnalysis = {
        targetEvo = target,
        stratChoice = stratChoice,
        activeTower = nil,
        farmType = nil,
        targetMode = "Unknown",
        configFound = false,
        allFinished = (#toCheck == 0),
        readyToBuy = false,
        isEligible = false,
        missingBase = {},
        missingTowers = {},
        missingGold = {},
        missingSkills = {},
        requiredLevel = 0,
        playerLevel = playerLevel,
        levelPassed = true,
        missingParts = {},
    }

    if #toCheck == 0 then
        if target == "All" then
            local allActuallyComplete = true
            for _, tName in ipairs({ "Scout", "Shotgunner", "Crook Boss", "Minigunner" }) do
                if not isTowerEvoComplete(tName) then
                    allActuallyComplete = false
                    break
                end
            end
            if allActuallyComplete then
                result.allFinished = true
                result.configFound = true
                result.isEligible = false
                return result
            else
                result.allFinished = false
                result.configFound = false
                result.isEligible = false
                table.insert(result.missingParts, "Loading tower data...")
                return result
            end
        else
            table.insert(result.missingParts, "No Target Selected")
            return result
        end
    end

    local activeTower = nil
    local activeFarmType = nil
    local activeReadyToBuy = false
    local missingBaseMap = {}

    for _, towerName in ipairs(toCheck) do
        local eData = EvoData[towerName]
        local evoName = eData and eData.Evo or towerName

        local ownsEvo = false
        if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
            pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
        end

        if not ownsEvo then
            result.allFinished = false
            local ownsBase = false
            if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                pcall(function() ownsBase = PlayerDataHandler:IsTowerOwned(towerName) end)
            end

            if not ownsBase then
                missingBaseMap[towerName] = true
                table.insert(result.missingBase, towerName)
                if not activeTower then
                    activeTower = towerName
                end
            else
                local expData = nil
                if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                    pcall(function() expData = PlayerDataHandler:GetTowerExp(towerName) end)
                end
                local baseLevel = expData and expData.Level or 0
                local reqCoins = eData and (eData.Coins or 15000) or 15000
                local reqGems = eData and (eData.Gems or 4500) or 4500
                local coinsNeed = math.max(0, reqCoins - coins)
                local gemsNeed = math.max(0, reqGems - gems)

                if not activeTower then
                    activeTower = towerName
                    if coinsNeed > 0 then
                        -- Priority 1: Coins needed -> Farm Coins
                        activeFarmType = "Coins"
                    elseif baseLevel < 20 then
                        -- Priority 2: Level missing (< 20) -> Farm Gems (Hardcore) for faster EXP + gems!
                        activeFarmType = "Gems"
                    elseif gemsNeed > 0 then
                        -- Priority 3: Gems needed -> Farm Gems (Hardcore)
                        activeFarmType = "Gems"
                    else
                        activeReadyToBuy = true
                    end
                end
            end
            -- Strictly sequential: Complete active target before moving to the next!
            break
        end
    end

    result.activeTower = activeTower
    result.farmType = activeFarmType
    result.readyToBuy = activeReadyToBuy

    -- If all targets are completely evolved & level 20:
    if result.allFinished then
        result.isEligible = false
        result.configFound = true
        return result
    end

    -- If the active tower's base tower is not owned:
    if activeTower and missingBaseMap[activeTower] then
        table.insert(result.missingParts, "Base Tower: " .. activeTower)
        result.isEligible = false
        result.configFound = true
        return result
    end

    -- If ready to evolve/buy directly in lobby:
    if activeReadyToBuy then
        result.isEligible = true
        result.configFound = true
        return result
    end

    -- Needs to farm either Coins or Gems:
    local farmType = activeFarmType or "Coins"
    local actualStrat = (farmType == "Gems") and "Lose" or "Win"
    result.farmType = farmType
    result.stratChoice = actualStrat

    local category = AutoEvoConfigs and AutoEvoConfigs[farmType]
    local config = category and (category[actualStrat] or category["Win"] or category["Lose"])

    if not config then
        table.insert(result.missingParts, "Config Missing (" .. farmType .. " " .. actualStrat .. ")")
        result.isEligible = false
        return result
    end

    result.configFound = true
    result.targetMode = config.Mode or "Unknown"

    -- 1. Level Check
    local reqLevel = config.Level or 0
    result.requiredLevel = reqLevel
    result.levelPassed = (playerLevel >= reqLevel)
    if not result.levelPassed then
        table.insert(result.missingParts, string.format("Level %d (You: %d)", reqLevel, playerLevel))
    end

    -- 2. Towers Check (Strategy Loadout)
    local towersConfig = config.Towers
    local stratTowers = {}
    if type(towersConfig) == "table" then
        if activeTower and towersConfig[activeTower] then
            stratTowers = towersConfig[activeTower]
        elseif #towersConfig > 0 then
            stratTowers = towersConfig
        end
    end

    if type(stratTowers) == "table" and PlayerDataHandler then
        for _, tower in ipairs(stratTowers) do
            if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                table.insert(result.missingTowers, tower)
            end
        end
    end
    if #result.missingTowers > 0 then
        table.insert(result.missingParts, "Towers: " .. table.concat(result.missingTowers, ", "))
    end

    -- 3. Golden Check
    local goldReqs = config.Golden or config.golden
    if type(goldReqs) == "table" and #goldReqs > 0 and PlayerDataHandler then
        for _, goldTower in ipairs(goldReqs) do
            if goldTower and goldTower ~= "" and not PlayerDataHandler:IsGoldenOwned(goldTower) then
                table.insert(result.missingGold, goldTower)
            end
        end
    end
    if #result.missingGold > 0 then
        table.insert(result.missingParts, "Golden: " .. table.concat(result.missingGold, ", "))
    end

    -- 4. Skill Tree Check
    local skillReqs = config.SkillTree or config["Skill Tree"] or config.skillTree
    if type(skillReqs) == "table" and next(skillReqs) and PlayerDataHandler then
        local currentSkills = {}
        if type(PlayerDataHandler.GetSkillTree) == "function" then
            pcall(function()
                for _, skill in ipairs(PlayerDataHandler:GetSkillTree()) do
                    currentSkills[skill.Name] = skill.Level
                end
            end)
        end
        for skillName, reqNodeLevel in pairs(skillReqs) do
            local haveLevel = currentSkills[skillName] or 0
            if haveLevel < reqNodeLevel then
                table.insert(result.missingSkills, string.format("%s (Need %d, Have %d)", skillName, reqNodeLevel, haveLevel))
            end
        end
    end
    if #result.missingSkills > 0 then
        table.insert(result.missingParts, "Skill Tree: " .. table.concat(result.missingSkills, ", "))
    end

    result.isEligible = result.levelPassed and (#result.missingTowers == 0) and (#result.missingGold == 0) and (#result.missingSkills == 0) and (#result.missingBase == 0)
    return result
end

local function checkAutoEvoMilestonesReached(): (boolean, string?)
    if not Globals.AutoEvo then return false, nil end

    local coins = 0
    local gems = 0
    if PlayerDataHandler then
        if typeof(PlayerDataHandler.GetCoins) == "function" then
            pcall(function() coins = PlayerDataHandler:GetCoins() or 0 end)
        end
        if typeof(PlayerDataHandler.GetGems) == "function" then
            pcall(function() gems = PlayerDataHandler:GetGems() or 0 end)
        end
    end

    local selected = tostring(Globals.TargetEvo or "All")
    local activeTower = nil

    if selected == "All" then
        for _, tName in ipairs({ "Scout", "Shotgunner", "Crook Boss", "Minigunner" }) do
            if not isTowerEvoComplete(tName) and isTowerOrEvoOwned(tName) then
                activeTower = tName
                break
            end
        end
        if not activeTower then
            return true, "All Evolutions Complete (Level 20 Maxed)"
        end
    elseif EvoData and EvoData[selected] then
        activeTower = selected
        if isTowerEvoComplete(selected) then
            return true, string.format("%s Evolution Complete (Level 20 Maxed)", selected)
        end
    end

    if not activeTower or not EvoData or not EvoData[activeTower] then
        return false, nil
    end

    local eData = EvoData[activeTower]
    local evoName = eData.Evo or activeTower
    local targetCoins = eData.Coins or 0
    local targetGems = eData.Gems or 0

    -- Check evolved tower ownership
    local ownsEvo = false
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
    end

    if ownsEvo then
        -- Milestone 4: evo exp 20 reached (Evolved tower level 20 maxed)
        local evoExp = nil
        if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
            pcall(function() evoExp = PlayerDataHandler:GetTowerExp(evoName) end)
        end
        local evoLevel = (evoExp and type(evoExp.Level) == "number") and evoExp.Level or 0
        if evoLevel >= 20 then
            return true, string.format("%s: evo exp 20 reached (Level %d/20)", evoName, evoLevel)
        end
        -- Still grinding evolved tower exp -> Milestone NOT reached yet!
        return false, nil
    end

    -- Check base tower ownership
    local ownsBase = false
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        pcall(function() ownsBase = PlayerDataHandler:IsTowerOwned(activeTower) end)
    end

    if not ownsBase then
        -- Player doesn't own base tower; needs coins to buy base tower
        if coins >= targetCoins then
            return true, string.format("%s: Coins Reach (Buy Base Tower)", activeTower)
        end
        return false, nil
    end

    local expData = nil
    if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
        pcall(function() expData = PlayerDataHandler:GetTowerExp(activeTower) end)
    end
    local baseLevel = (expData and type(expData.Level) == "number") and expData.Level or 0

    -- Check match start snapshot stage if recorded
    local startStage = originalMatchConfig and originalMatchConfig.EvoStartStage
    local startTower = originalMatchConfig and originalMatchConfig.EvoStartTower

    if startStage and (startTower == nil or startTower == activeTower) then
        if startStage == "Coins" then
            -- Milestone 2: Coins Reach smart Lobby
            if coins >= targetCoins then
                return true, string.format("%s: Coins Reach (%s / %s Coins)", activeTower, formatNumberWithCommas(coins), formatNumberWithCommas(targetCoins))
            end
            return false, nil
        elseif startStage == "Gems" then
            -- Milestone 3: Gems Reach smartlobby
            if gems >= targetGems then
                return true, string.format("%s: Gems Reach (%s / %s Gems)", activeTower, formatNumberWithCommas(gems), formatNumberWithCommas(targetGems))
            end
            return false, nil
        elseif startStage == "BaseLevel" then
            -- Milestone 1: Level reach 20 smart lobby
            if baseLevel >= 20 then
                return true, string.format("%s: Level reach 20 (Base Tower Level %d/20)", activeTower, baseLevel)
            end
            return false, nil
        elseif startStage == "ReadyToBuy" then
            return true, string.format("%s: Ready to Evolve (Coins, Gems & Level 20 Reached)", activeTower)
        elseif startStage == "EvoLevel" then
            return false, nil
        end
    end

    -- Fallback dynamic stage evaluation (mutually exclusive sequential progression):
    local coinsNeed = math.max(0, targetCoins - coins)
    local gemsNeed = math.max(0, targetGems - gems)

    if coinsNeed > 0 then
        -- Milestone 2: Coins Reach
        if coins >= targetCoins then
            return true, string.format("%s: Coins Reach (%s / %s Coins)", activeTower, formatNumberWithCommas(coins), formatNumberWithCommas(targetCoins))
        end
        return false, nil
    elseif baseLevel < 20 then
        -- Milestone 1: Level reach 20
        if baseLevel >= 20 then
            return true, string.format("%s: Level reach 20 (Base Tower Level %d/20)", activeTower, baseLevel)
        end
        return false, nil
    elseif gemsNeed > 0 then
        -- Milestone 3: Gems Reach
        if gems >= targetGems then
            return true, string.format("%s: Gems Reach (%s / %s Gems)", activeTower, formatNumberWithCommas(gems), formatNumberWithCommas(targetGems))
        end
        return false, nil
    else
        -- Ready to evolve in lobby!
        return true, string.format("%s: Ready to Evolve (Coins, Gems & Level 20 Reached)", activeTower)
    end
end

function AutoGoldModule.LobbyReadyUp()
    if not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo then return end

    pcall(function()
        local remoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent")
        local remoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction")
        if remoteEvent then
            remoteEvent:FireServer("LobbyVoting", "Ready")
        elseif remoteFunc then
            remoteFunc:InvokeServer("LobbyVoting", "Ready")
        end

        local gm = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("GameManager")
        local readyRemote = gm and (gm:FindFirstChild("Ready") or gm:FindFirstChild("RE:Ready"))
        if readyRemote then
            if readyRemote:IsA("RemoteEvent") then
                readyRemote:FireServer()
            elseif readyRemote:IsA("RemoteFunction") then
                readyRemote:InvokeServer()
            end
        end
    end)
end

local cachedVipStatus: boolean? = nil

local function isVipOrPrivateServer(): boolean
    if cachedVipStatus ~= nil then
        return cachedVipStatus
    end

    local isVip = false

    -- 0. Explicit globals or configuration overrides
    pcall(function()
        if Globals.VIP == true or Globals.IsVIP == true or Globals.ForceVIP == true then
            isVip = true
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 1. Standard Roblox engine properties for private / reserved servers
    pcall(function()
        if game.PrivateServerId and type(game.PrivateServerId) == "string" and game.PrivateServerId ~= "" then
            isVip = true
        end
        if game.PrivateServerOwnerId and type(game.PrivateServerOwnerId) == "number" and game.PrivateServerOwnerId ~= 0 then
            isVip = true
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 2. TDS GameStateReplicator attributes
    pcall(function()
        local stateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gsr = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            if gsr:GetAttribute("IsPrivateServer") == true
                or gsr:GetAttribute("PrivateServer") == true
                or gsr:GetAttribute("VIP") == true
                or gsr:GetAttribute("VIPServer") == true then
                isVip = true
            end
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 3. LocalPlayer attributes
    pcall(function()
        if LocalPlayer:GetAttribute("VIP") == true
            or LocalPlayer:GetAttribute("HasVIP") == true
            or LocalPlayer:GetAttribute("IsVIP") == true then
            isVip = true
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 4. MarketplaceService Gamepass 10518590 (TDS VIP Pass)
    pcall(function()
        if MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) then
            isVip = true
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 5. Intermission UI Override button check (direct visual/client proof of VIP override ability)
    pcall(function()
        local intermission = PlayerGui:FindFirstChild("ReactGameIntermission")
        if intermission then
            for _, desc in ipairs(intermission:GetDescendants()) do
                if desc:IsA("GuiButton") then
                    local dName = desc.Name:lower()
                    local dText = (desc:IsA("TextButton") and desc.Text:lower()) or ""
                    if dName:find("override") or dText:find("override") or dName:find("vip") then
                        isVip = true
                        break
                    end
                end
            end
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 6. PlayerDataHandler gamepass check
    pcall(function()
        if PlayerDataHandler and typeof(PlayerDataHandler.GetPlayerData) == "function" then
            local pData = PlayerDataHandler:GetPlayerData()
            if pData and pData.Gamepasses and (pData.Gamepasses[10518590] or pData.Gamepasses["10518590"] or pData.Gamepasses["VIP"]) then
                isVip = true
            end
        end
    end)

    if isVip then
        cachedVipStatus = true
    end
    return isVip
end

-- Intermission Map & Modifier Voting Engine
do
    local Logger = {
        Log = function(self, msg: string)
            logActivity(tostring(msg), "info")
        end
    }

    local function CastMapVote(MapId, PosVec)
        local TargetMap = MapId or "Simplicity"
        local TargetPos = PosVec or Vector3.new(0, 0, 0)
        pcall(function()
            local RemoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent") or ReplicatedStorage:WaitForChild("RemoteEvent", 5)
            if RemoteEvent then
                RemoteEvent:FireServer("LobbyVoting", "Vote", TargetMap, TargetPos)
            end
        end)
        Logger:Log("Cast map vote: " .. TargetMap)
    end

    local function LobbyReadyUp()
        pcall(function()
            local RemoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent") or ReplicatedStorage:WaitForChild("RemoteEvent", 5)
            if RemoteEvent then
                RemoteEvent:FireServer("LobbyVoting", "Ready")
            end
            Logger:Log("Lobby ready up sent")
        end)
    end

    local function SelectMapOverride(MapId, ...)
        local args = { ... }

        if args[#args] == "vip" or isVipOrPrivateServer() then
            pcall(function()
                local RemoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction") or ReplicatedStorage:WaitForChild("RemoteFunction", 5)
                if RemoteFunc then
                    RemoteFunc:InvokeServer("LobbyVoting", "Override", MapId)
                end
            end)
        end

        task.wait(3)
        CastMapVote(MapId, Vector3.new(12.59, 10.64, 52.01))
        task.wait(1)
        LobbyReadyUp()
    end

    local function IsMapAvailable(name)
        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                local t = g:FindFirstChild("Title")
                if t and (t.Text == name or normalizeString(t.Text) == normalizeString(name)) then return true end
            end
        end

        local hasVoted = false
        local startTime = os.time()

        repeat
            local IntermissionFrame = nil
            pcall(function()
                local igui = PlayerGui:WaitForChild("ReactGameIntermission", 5)
                IntermissionFrame = igui and igui:WaitForChild("Frame", 5)
            end)
            if not IntermissionFrame then break end

            local buttons = IntermissionFrame:FindFirstChild("buttons")
            local veto = buttons and buttons:FindFirstChild("veto")
            local VetoValue = veto and (veto:FindFirstChild("value") or veto:FindFirstChildWhichIsA("TextLabel"))
            local VetoText = VetoValue and VetoValue.Text or ""
            local current, total = nil, nil
            
            if VetoText ~= "" then
                if not VetoText:find("Veto") then
                    return false 
                end

                local currentStr, totalStr = VetoText:match("(%d+)/(%d+)")
                current, total = tonumber(currentStr), tonumber(totalStr)

                if not hasVoted and total and total > 0 and (current == 0 or current < total) then
                    pcall(function()
                        local RemoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent") or ReplicatedStorage:WaitForChild("RemoteEvent", 5)
                        if RemoteEvent then
                            RemoteEvent:FireServer("LobbyVoting", "Veto")
                        end
                    end)
                    hasVoted = true
                end
            end

            local found = false
            for _, g in ipairs(workspace:GetDescendants()) do
                if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                    local t = g:FindFirstChild("Title")
                    if t and (t.Text == name or normalizeString(t.Text) == normalizeString(name)) then
                        found = true
                        break
                    end
                end
            end

            task.wait(1)

            local TotalPlayer = #Players:GetChildren()
            local isFull = (VetoText == "Veto (" .. TotalPlayer .. "/" .. TotalPlayer .. ")")
                or (total and total > 0 and current and current >= total)

        until found or isFull or (os.time() - startTime > 35)

        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                local t = g:FindFirstChild("Title")
                if t and (t.Text == name or normalizeString(t.Text) == normalizeString(name)) then return true end
            end
        end

        return false
    end

    local function GetAvailableMaps()
        local available = {}
        pcall(function()
            for _, g in ipairs(workspace:GetDescendants()) do
                if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                    local t = g:FindFirstChild("Title")
                    if t and t:IsA("TextLabel") and t.Text and t.Text ~= "" then
                        local mapName = t.Text:gsub("^%s+", ""):gsub("%s+$", "")
                        available[mapName] = true
                        available[mapName:lower()] = true
                        available[normalizeString(mapName)] = true
                    end
                end
            end
        end)
        return available
    end

    AutoGoldModule.CastMapVote = CastMapVote
    AutoGoldModule.LobbyReadyUp = LobbyReadyUp
    AutoGoldModule.SelectMapOverride = SelectMapOverride
    AutoGoldModule.IsMapAvailable = IsMapAvailable
    AutoGoldModule.GetAvailableMaps = GetAvailableMaps
end

function AutoGoldModule.GameInfo(name: string?, list: { any }?): string?
    if not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo then
        return nil
    end

    if isMapIntermissionHandling then
        while isMapIntermissionHandling do
            task.wait(0.5)
        end
        return lastVotedIntermissionMap
    end

    if intermissionMapHandled and lastVotedIntermissionMap then
        return lastVotedIntermissionMap
    end

    local voteGui = PlayerGui:WaitForChild("ReactGameIntermission", 20)
    if not (voteGui and voteGui.Enabled and voteGui:WaitForChild("Frame", 5)) then return nil end
    if not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo then return nil end

    isMapIntermissionHandling = true

    local stratChoice = Globals.SelectedFallback
    if stratChoice == "Smart Auto" then
        stratChoice = resolveSmartFallback()
    end
    local isHardcoreRequest = (name and normalizeString(tostring(name)) == "hardcore")

    -- 1. Resolve matching configuration
    local config = nil
    if name and FallbackConfigs and FallbackConfigs[name] then
        config = FallbackConfigs[name]
    elseif name and AutoGoldModule.Configs and AutoGoldModule.Configs[name] then
        config = AutoGoldModule.Configs[name]
    end

    -- Do not overwrite fallback config with crate config if a specific mode is requested!
    if not config and (Globals.AutoGold or Globals.AutoEvo or currentMatchMode == "AutoGold" or currentMatchMode == "AutoEvo") then
        local crateCfg = getCurrentCrateConfig(isHardcoreRequest and "Gems" or nil)
        if crateCfg then config = crateCfg end
    end

    if not config and isHardcoreRequest then
        local crateCfg = getCurrentCrateConfig("Gems")
        if crateCfg then config = crateCfg end
    end

    if not config then
        if FallbackConfigs and FallbackConfigs[stratChoice] then
            config = FallbackConfigs[stratChoice]
        elseif AutoGoldModule.Configs and AutoGoldModule.Configs[stratChoice] then
            config = AutoGoldModule.Configs[stratChoice]
        end
    end

    -- 1b. Check if 'name' corresponds to a Trial definition in StaticTrialDefinitions
    local trialTargetMap = nil
    local trialDefinitions = PlayerDataHandler and PlayerDataHandler.StaticTrialDefinitions
    if name and type(trialDefinitions) == "table" then
        local normName = normalizeString(tostring(name))
        for _, def in ipairs(trialDefinitions) do
            if normalizeString(def.Name) == normName or normalizeString(def.Title) == normName then
                trialTargetMap = def.Map
                break
            end
        end
    end

    -- 2. Determine strictly selected map
    local selectedMap = nil
    if trialTargetMap then
        selectedMap = trialTargetMap
    elseif name and not (FallbackConfigs and FallbackConfigs[name]) and not (AutoGoldModule.Configs and AutoGoldModule.Configs[name]) and name ~= "" and normalizeString(tostring(name)) ~= "hardcore" then
        selectedMap = name
    elseif config and config.Maps and #config.Maps > 0 then
        selectedMap = config.Maps[1]
        for _, m in ipairs(config.Maps) do
            for _, g in ipairs(workspace:GetDescendants()) do
                if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                    local t = g:FindFirstChild("Title")
                    if t and (t.Text == m or normalizeString(t.Text) == normalizeString(m)) then
                        selectedMap = m
                        break
                    end
                end
            end
            if selectedMap == m then break end
        end
    elseif isHardcoreRequest then
        selectedMap = "Wretched Front"
    else
        selectedMap = "Lay By"
    end

    -- 3. Cast modifier votes
    local modifiers = (list and next(list)) and list or (config and (config.Modifiers or config.Modifers)) or Globals.Modifiers
    if typeof(CastModifierVote) == "function" then
        pcall(CastModifierVote, modifiers)
    end

    local vipActive = isVipOrPrivateServer()

    if vipActive then
        warn(string.format("[ServiceHub Map Check] VIP / Private Server detected. Overriding map: %s", tostring(selectedMap)))
        AutoGoldModule.SelectMapOverride(selectedMap, "vip")

        intermissionMapHandled = true
        isMapIntermissionHandling = false
        lastVotedIntermissionMap = selectedMap
        return selectedMap
    else
        warn(string.format("[ServiceHub Map Check] Checking availability / Vetoing for map '%s'...", tostring(selectedMap)))
        logActivity(string.format("Intermission: Checking availability for '%s'...", tostring(selectedMap)), "info")

        local isAvailable = AutoGoldModule.IsMapAvailable(selectedMap)

        if isAvailable then
            warn(string.format("[ServiceHub Map Check] Found map '%s'. Casting vote...", tostring(selectedMap)))
            logActivity(string.format("Intermission: Voting for selected map '%s'", tostring(selectedMap)), "info")
            AutoGoldModule.SelectMapOverride(selectedMap)

            intermissionMapHandled = true
            isMapIntermissionHandling = false
            lastVotedIntermissionMap = selectedMap
            return selectedMap
        else
            warn(string.format("[ServiceHub Map Check] Selected map '%s' not available after Veto. Returning to Smart Lobby...", tostring(selectedMap)))
            logActivity(string.format("Intermission: Map '%s' missing after Veto. Teleporting to Smart Lobby...", tostring(selectedMap)), "warn")
            isMapIntermissionHandling = false
            intermissionMapHandled = false
            SmartTeleportToLobby()
            return nil
        end
    end
end

function AutoGoldModule.QueueGold(stratChoice: string?, optFarmType: string?)
    if (not Globals.AutoTrials and not Globals.AutoGold and not Globals.AutoEvo) or game.PlaceId ~= LOBBY_PLACE_ID then return end
    local farmType = optFarmType or Globals.AutoFarmType or "Coins"
    if Globals.AutoEvo and not Globals.AutoGold and not Globals.AutoTrials then
        farmType = optFarmType or Globals.CurrentEvoFarmType or "Coins"
    end
    if farmType and typeof(saveActiveFarmType) == "function" then
        saveActiveFarmType(farmType)
    end
    Globals.AutoFarmType = farmType
    local config = getCurrentCrateConfig(farmType)
    if not config then return end
    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")

    if remoteFunction and remoteFunction:IsA("RemoteFunction") then
        pcall(function()
            remoteFunction:InvokeServer("Multiplayer", "v2:stop")
        end)
        task.wait(0.1)
        pcall(function()
            if farmType == "Gems" then
                return remoteFunction:InvokeServer(
                    "Multiplayer",
                    "v2:start",
                    {
                        difficulty = "Easy",
                        mode = "hardcore",
                        count = 1
                    }
                )
            else
                return remoteFunction:InvokeServer(
                    "Multiplayer",
                    "v2:start",
                    {
                        difficulty = config.Mode,
                        mode = "survival",
                        count = 1
                    }
                )
            end
        end)
    end
end

--==============================================================================
-- Match Status & Strategy Execution Handlers
--==============================================================================
local function GetMatchStatus(): string?
    local uiRoot = PlayerGui:FindFirstChild("ReactGameNewRewards")
    if not uiRoot then return nil end

    local mainFrame = uiRoot:FindFirstChild("Frame")
    if not mainFrame or not mainFrame.Visible then return nil end

    local gameOver = mainFrame:FindFirstChild("gameOver")
    if not gameOver or not gameOver.Visible then return nil end

    local rewardsScreen = gameOver:FindFirstChild("RewardsScreen")
    if not rewardsScreen or not rewardsScreen.Visible then return nil end

    local topBanner = rewardsScreen:FindFirstChild("RewardBanner")
    if not topBanner then return nil end

    local label = topBanner:FindFirstChild("textLabel") or topBanner:FindFirstChildOfClass("TextLabel")
    if not label then return nil end

    local success, txt = pcall(function() return label.Text:upper() end)
    if not success or not txt or txt == "" then return nil end

    if txt:find("TRIUMPH") or txt:find("VICTORY") or txt:find("WIN") then
        return "WIN"
    elseif txt:find("LOST") or txt:find("DEFEAT") or txt:find("FAIL") then
        return "LOSS"
    end
    return nil
end

--==============================================================================
-- Trial & Rotation Check Helpers
--==============================================================================
local function checkIsTrialWon(trialName: string?): boolean
    if not trialName or trialName == "" then return false end
    local normTarget = normalizeString(trialName)
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTrialWon) == "function" then
        local ok, won = pcall(function()
            return PlayerDataHandler:IsTrialWon(trialName)
        end)
        if ok and won == true then return true end
    end
    if PlayerDataHandler and typeof(PlayerDataHandler.GetTrialsStatus) == "function" then
        local ok, status = pcall(function()
            return PlayerDataHandler:GetTrialsStatus()
        end)
        if ok and status and type(status) == "table" and status.Won then
            for _, n in ipairs(status.Won) do
                if normalizeString(n) == normTarget then
                    return true
                end
            end
        end
    end
    local trialDefs = (PlayerDataHandler and typeof(PlayerDataHandler.StaticTrialDefinitions) == "table" and PlayerDataHandler.StaticTrialDefinitions)
        or StaticTrialDefinitions
    if type(trialDefs) == "table" then
        for _, t in ipairs(trialDefs) do
            if normalizeString(t.Name) == normTarget or normalizeString(t.Title) == normTarget or normalizeString(t.Map) == normTarget then
                if PlayerDataHandler and typeof(PlayerDataHandler.IsTrialWon) == "function" then
                    local ok, won = pcall(function()
                        return PlayerDataHandler:IsTrialWon(t.Name) or PlayerDataHandler:IsTrialWon(t.Title)
                    end)
                    if ok and won == true then return true end
                end
            end
        end
    end
    return false
end

local function shouldSwitchToUnownedTrial(): boolean
    if not (isPremiumUser and Globals.AutoTrials and Globals.TrialFarmMode == "Progression Mode") then
        return false
    end
    if not PlayerDataHandler then return false end
    local curTrial = nil
    if typeof(PlayerDataHandler.GetCurrentTrial) == "function" then
        local ok, res = pcall(function() return PlayerDataHandler:GetCurrentTrial() end)
        if ok and res and type(res) == "table" then
            curTrial = res.Name or res.title or res.Title
        end
    end
    if not curTrial then return false end
    local isWon = checkIsTrialWon(curTrial)
    if isWon then return false end

    -- Check filter
    local selectedTrials = Globals.SelectedTrials or {}
    local inFilter = false
    local normCur = normalizeString(curTrial)
    if type(selectedTrials) == "table" then
        for _, s in ipairs(selectedTrials) do
            if normalizeString(s) == normCur then
                inFilter = true
                break
            end
        end
    end
    if not inFilter then return false end

    -- Check requirements
    local config = RevampAutoTrials and (RevampAutoTrials[curTrial] or RevampAutoTrials[normCur])
    if not config then return false end
    local reqLvl = config.Level or config.level or 175
    local pLvl = PlayerDataHandler:GetLevel() or 0
    if pLvl < reqLvl then return false end

    -- Check towers
    local towersConfig = config.Towers or config.towers
    if type(towersConfig) == "table" then
        local hasDeck = false
        local decksToCheck = {}
        if towersConfig[1] then
            table.insert(decksToCheck, towersConfig)
        else
            for _, deck in pairs(towersConfig) do
                if type(deck) == "table" then
                    table.insert(decksToCheck, deck)
                end
            end
        end
        for _, deck in ipairs(decksToCheck) do
            local allOwned = true
            for _, tName in ipairs(deck) do
                if tName and tName ~= "" and not PlayerDataHandler:IsTowerOwned(tName) then
                    allOwned = false
                    break
                end
            end
            if allOwned then
                hasDeck = true
                break
            end
        end
        if not hasDeck then return false end
    end

    return true
end

local function fireSkipVoteUntilTrue(): boolean
    local Event = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteFunction")
    if not Event then return false end

    local success, result = pcall(function()
        local Result = table.pack(Event:InvokeServer(
            "Voting",
            "Skip"
        ))

        local ExpectedResult = table.unpack({
            true
        })

        return Result[1] == ExpectedResult
    end)

    return success and (result == true)
end

local function isGemsLoseMatch(): boolean
    local liveGameMode = ""
    local liveDifficulty = ""
    pcall(function()
        local gsr = game.ReplicatedStorage:FindFirstChild("StateReplicators") and game.ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            liveGameMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or ""):lower()
            liveDifficulty = tostring(gsr:GetAttribute("Difficulty") or ""):lower()
        end
    end)
    if liveGameMode == "hardcore" or liveDifficulty == "hardcore" then
        return true
    end

    local savedTrial = ""
    if typeof(loadTrialState) == "function" then
        pcall(function() savedTrial = tostring(loadTrialState() or ""):lower() end)
    end
    if savedTrial == "hardcore" then return true end

    local savedFarm = (typeof(loadActiveFarmType) == "function") and tostring(loadActiveFarmType() or ""):lower() or ""
    if savedFarm == "gems" then return true end

    if tostring(Globals.AutoFarmType or ""):lower() == "gems" then return true end
    if tostring(Globals.CurrentEvoFarmType or ""):lower() == "gems" then return true end

    return false
end

local getCurrencyAndTargets: () -> (number, number, number, number, string, string)
do
    local cachedDynamicTargetCoins = 0
    local cachedDynamicTargetGems = 0
    local lastDynamicTargetCalcTick = 0

    getCurrencyAndTargets = function(): (number, number, number, number, string, string)
    local coins = 0
    local gems = 0
    if PlayerDataHandler then
        pcall(function()
            if typeof(PlayerDataHandler.GetCoins) == "function" then
                coins = PlayerDataHandler:GetCoins() or 0
            end
            if typeof(PlayerDataHandler.GetGems) == "function" then
                gems = PlayerDataHandler:GetGems() or 0
            end
        end)
    end

    local targetCoins = tonumber(Globals.TargetCoins) or 0
    local targetGems = tonumber(Globals.TargetGems) or 0

    local nowClock = os.clock()
    if targetCoins <= 0 and targetGems <= 0 and (nowClock - lastDynamicTargetCalcTick < 4) and lastDynamicTargetCalcTick > 0 then
        targetCoins = cachedDynamicTargetCoins
        targetGems = cachedDynamicTargetGems
    else
        lastDynamicTargetCalcTick = nowClock
        -- Dynamic Target Coins resolution if manual target not specified
    if targetCoins <= 0 and PlayerDataHandler then
        if (Globals.BuyMissingCoinsTower or Globals.TrialFarmMode == "Progression Mode") and TowerList and TowerList.Coins then
            for _, t in ipairs(TowerList.Coins) do
                local clean = normalizeString(t.Name)
                if clean ~= "warden" and clean ~= "cowboy" and clean ~= "saboteur" and clean ~= "sabboteur" then
                    local isOwned = false
                    pcall(function() isOwned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                    if not isOwned then
                        targetCoins = tonumber(t.Cost) or 0
                        break
                    end
                end
            end
        end
        if targetCoins <= 0 and (Globals.AutoEvo or Globals.BuyMissingEvoTower) and TowerList and TowerList.Evo then
            for _, e in ipairs(TowerList.Evo) do
                local isOwned = false
                pcall(function()
                    if PlayerDataHandler:IsTowerOwned(e.Name) then
                        isOwned = true
                    elseif typeof(isTowerEvoComplete) == "function" then
                        local base = (EvoToTower and EvoToTower[e.Name]) or e.Name:gsub("^Evolved%s*", "")
                        if isTowerEvoComplete(e.Name) or isTowerEvoComplete(base) then
                            isOwned = true
                        end
                    end
                end)
                if not isOwned then
                    targetCoins = tonumber(e.Coins) or 15000
                    break
                end
            end
        end
        if targetCoins <= 0 and Globals.BuyMissingGoldSkins then
            local hasUnownedGold = false
            if TowerList and TowerList.Golden then
                for _, g in ipairs(TowerList.Golden) do
                    local base = g.Name:gsub("^Golden%s+", "")
                    local isOwned = false
                    pcall(function()
                        isOwned = PlayerDataHandler:IsGoldenOwned(g.Name) or PlayerDataHandler:IsGoldenOwned(base)
                    end)
                    if not isOwned then
                        hasUnownedGold = true
                        break
                    end
                end
            end
            if hasUnownedGold then
                targetCoins = 50000
            end
        end
    end

    -- Dynamic Target Gems resolution if manual target not specified
    if targetGems <= 0 and PlayerDataHandler then
        if (Globals.BuyMissingGemTower or Globals.TrialFarmMode == "Progression Mode") and TowerList and TowerList.Gems then
            for _, t in ipairs(TowerList.Gems) do
                local isOwned = false
                pcall(function() isOwned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                if not isOwned then
                    targetGems = tonumber(t.Cost) or 0
                    break
                end
            end
        end
        if targetGems <= 0 and (Globals.AutoEvo or Globals.BuyMissingEvoTower) and TowerList and TowerList.Evo then
            for _, e in ipairs(TowerList.Evo) do
                local isOwned = false
                pcall(function()
                    if PlayerDataHandler:IsTowerOwned(e.Name) then
                        isOwned = true
                    elseif typeof(isTowerEvoComplete) == "function" then
                        local base = (EvoToTower and EvoToTower[e.Name]) or e.Name:gsub("^Evolved%s*", "")
                        if isTowerEvoComplete(e.Name) or isTowerEvoComplete(base) then
                            isOwned = true
                        end
                    end
                end)
                if not isOwned then
                    targetGems = tonumber(e.Gems) or 4500
                    break
                end
            end
        end
    end
    cachedDynamicTargetCoins = targetCoins
    cachedDynamicTargetGems = targetGems
end

    local coinsStr = string.format("%s / %s", formatNumberWithCommas(coins), targetCoins > 0 and formatNumberWithCommas(targetCoins) or "0")
    local gemsStr = string.format("%s / %s", formatNumberWithCommas(gems), targetGems > 0 and formatNumberWithCommas(targetGems) or "0")

    return coins, targetCoins, gems, targetGems, coinsStr, gemsStr
    end
end

local function checkShouldExitGemsLose(): (boolean, string?)
    local isOwnedActive = (Globals.TrialFarmMode == "Progression Mode" and Globals.AutoTrials)
    if not Globals.AutoGold and not Globals.AutoEvo and not Globals.AutoTrials and not isOwnedActive and currentMatchMode ~= "AutoGold" and currentMatchMode ~= "AutoEvo" and currentMatchMode ~= "AutoTrials" then
        return true, "Automation stopped by user"
    end

    if Globals.IsConfigDirty or (isMatchConfigDirty and isMatchConfigDirty()) then
        Globals.IsConfigDirty = false
        return true, "Configuration changed mid-match"
    end

    -- "or when the next trial is up wait until get match statys check first if the trial is owned if yes stay of course"
    if typeof(shouldSwitchToUnownedTrial) == "function" and shouldSwitchToUnownedTrial() then
        return true, "Unowned rotation trial is ready in lobby!"
    end

    -- "until it reach the gems it needed"
    local coins, targetCoins, currentWalletGems, targetGems, coinsDisplay, gemsDisplay = getCurrencyAndTargets()

    if targetGems > 0 and currentWalletGems >= targetGems then
        return true, string.format("Target Gems reached (%s)", gemsDisplay)
    end

    if Globals.BuyMissingGemTower and TowerList and TowerList.Gems and PlayerDataHandler then
        local allGemOwned = (typeof(isGemTowersMaxed) == "function") and isGemTowersMaxed() or false
        if allGemOwned then
            return true, "All hardcore gem towers are owned!"
        else
            for _, t in ipairs(TowerList.Gems) do
                local owned = false
                pcall(function() owned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                if not owned then
                    local cost = tonumber(t.Cost) or 0
                    if cost > 0 and currentWalletGems >= cost then
                        return true, string.format("Reached %d gems needed for %s!", cost, t.Name)
                    end
                    break
                end
            end
        end
    end

    if (Globals.AutoEvo or Globals.BuyMissingEvoTower) then
        if typeof(checkAutoEvoMilestonesReached) == "function" then
            local milestone, reason = checkAutoEvoMilestonesReached()
            if milestone then
                return true, tostring(reason)
            end
        end
        if typeof(analyzeAutoEvoRequirements) == "function" then
            local ok, evoAnalysis = pcall(analyzeAutoEvoRequirements)
            if ok and evoAnalysis and evoAnalysis.farmType == "Gems" and evoAnalysis.gemCost then
                if currentWalletGems >= evoAnalysis.gemCost then
                    return true, string.format("Reached %d gems needed for %s evo!", evoAnalysis.gemCost, tostring(evoAnalysis.activeTower))
                end
            end
        end
    end

    return false, nil
end

local function shouldTeleportOnMatchEnd(status: string): boolean
    local mode = currentMatchMode or loadActiveMode()
    if not mode or mode == "" then
        if Globals.AutoEvo and not Globals.AutoGold and not Globals.AutoTrials then
            mode = "AutoEvo"
        elseif Globals.AutoTrials and not Globals.AutoGold then
            mode = "AutoTrials"
        elseif Globals.AutoGold and not Globals.AutoTrials then
            mode = "AutoGold"
        end
    end

    if isLateExecution then
        local reason = string.format("Mid-game re-execution at Wave %d finished", initialExecutionWave)
        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
            RunAsExecutor(function()
                UI.Window:Notify({
                    Title = "RE-EXECUTION RESET",
                    Desc = reason .. "! Teleporting to Smart Lobby for a clean fresh match.",
                    Duration = 8,
                    Type = "warning"
                })
            end)()
        end
        Globals.IsConfigDirty = false
        isLateExecution = false
        SmartTeleportToLobby()
        return true
    end

    -- Gems Lose Match Handler:
    -- On LOSS, never Smart Lobby unless gems needed reached or unowned rotation trial waiting!
    if isGemsLoseMatch() then
        if status == "WIN" then
            SmartTeleportToLobby()
            return true
        end

        local shouldExit, exitReason = checkShouldExitGemsLose()
        if shouldExit then
            logActivity("[Gems Lose] " .. tostring(exitReason) .. " -> Returning to Smart Lobby.", "info")
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "GEMS GOAL REACHED",
                        Desc = tostring(exitReason) .. "! Returning to lobby.",
                        Duration = 8,
                        Type = "success"
                    })
                end)()
            end
            SmartTeleportToLobby()
            return true
        else
            logActivity("[Gems Lose] Match ended (LOSS) -> Staying in-game to vote restart...", "info")
            return false
        end
    end

    if mode == "AutoTrials" then
        if Globals.IsConfigDirty or (isMatchConfigDirty and isMatchConfigDirty()) then
            Globals.IsConfigDirty = false
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "CONFIG CHANGED",
                        Desc = "Settings updated mid-match. Teleporting to Smart Lobby for a clean fresh match.",
                        Duration = 8,
                        Type = "warning"
                    })
                end)()
            end
            SmartTeleportToLobby()
            return true
        end

        if Globals.TrialFarmMode == "Farm Mode" and Globals.TargetTimescale and Globals.TargetTimescale > 0 and (Globals.TimescaleUsedSession or 0) >= Globals.TargetTimescale then
            logActivity(string.format("[Target Timescale] Limit of %d reached -> Returning to Smart Lobby.", Globals.TargetTimescale), "success")
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "TARGET TIMESCALE REACHED",
                        Desc = string.format("Completed %d timescale matches! Teleporting to Smart Lobby.", Globals.TargetTimescale),
                        Duration = 8,
                        Type = "success"
                    })
                end)()
            end
            SmartTeleportToLobby()
            return true
        end

        local isPlayingFallback = false
        pcall(function()
            local gsr = game.ReplicatedStorage:FindFirstChild("StateReplicators") and game.ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
            if gsr then
                local liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "None")
                if liveTrial == "None" or liveTrial == "" then
                    isPlayingFallback = true
                end
            end
        end)
        
        if isPlayingFallback then
            SmartTeleportToLobby()
            return true
        end

        if not Globals.AutoTrials then
            SmartTeleportToLobby()
            return true
        end

        -- Free user in Auto Trials:
        -- Win -> SmartLobby, Lose -> Smart Lobby
        if not isPremiumUser then
            SmartTeleportToLobby()
            return true
        end

        -- If Farm Only or Progression Mode is active, winning the trial means it has been beaten.
        -- Return to lobby instead of rematching endlessly.
        if (Globals.FarmOnly == "Farm Only" or Globals.TrialFarmMode == "Progression Mode") and status == "WIN" then
            SmartTeleportToLobby()
            return true
        end

        -- Premium User ONLY in Auto Trials:
        -- Win -> stay in-game for RE:Rematch
        -- Lose -> stay in-game for attempts 1/5
        return false

    elseif mode == "AutoGold" then
        if not isPremiumUser or (not Globals.AutoGold and not Globals.AutoEvo) then
            SmartTeleportToLobby()
            return true
        end

        -- Auto Gold: Win ALWAYS Smart Lobby
        if status == "WIN" then
            SmartTeleportToLobby()
            return true
        end

        -- In Progression Mode: If an unowned trial is waiting in rotation, return to lobby to beat it!
        if typeof(shouldSwitchToUnownedTrial) == "function" and shouldSwitchToUnownedTrial() then
            logActivity("[Progression Mode] Unowned rotation trial ready! Teleporting to lobby to queue trial.", "info")
            SmartTeleportToLobby()
            return true
        end

        local tc = tonumber(Globals.TargetCoins) or 0
        local tg = tonumber(Globals.TargetGems) or 0
        local currentWalletCoins = 0
        local currentWalletGems = 0
        if PlayerDataHandler then
            pcall(function() currentWalletCoins = PlayerDataHandler:GetCoins() or 0 end)
            pcall(function() currentWalletGems = PlayerDataHandler:GetGems() or 0 end)
        end

        -- Check Coins Reach & Gems Reach for AutoGold (Active Premium Users Only):
        if isPremiumUser and ((tc > 0 and currentWalletCoins >= tc) or (tg > 0 and currentWalletGems >= tg)) then
            Globals.AutoGold = false
            SetSetting("AutoGold", false)
            if UI and UI.AutoGoldToggle then UI.AutoGoldToggle:SetValue(false) end
            local reachedMsg = (tc > 0 and currentWalletCoins >= tc)
                and string.format("Coins Reach (%s / %s Coins)", formatNumberWithCommas(currentWalletCoins), formatNumberWithCommas(tc))
                or string.format("Gems Reach (%s / %s Gems)", formatNumberWithCommas(currentWalletGems), formatNumberWithCommas(tg))
            logActivity("AutoGold target reached (" .. reachedMsg .. ")! Teleporting to lobby.", "success")
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "TARGET REACHED",
                        Desc = reachedMsg .. "! Teleporting to Smart Lobby.",
                        Duration = 8,
                        Type = "success"
                    })
                end)()
            end
            Globals.IsConfigDirty = false
            SmartTeleportToLobby()
            return true
        end

        if Globals.IsConfigDirty or (isMatchConfigDirty and isMatchConfigDirty()) then
            Globals.IsConfigDirty = false
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "CONFIG CHANGED",
                        Desc = "Settings updated mid-match. Returning to Smart Lobby.",
                        Duration = 6,
                        Type = "info"
                    })
                end)()
            end
            SmartTeleportToLobby()
            return true
        end

        -- IF LOSE strat on LOSS: it should NOT SMART lobby !! instead it will just RETRY until target reached!
        if (Globals.Strat == "Lose" or isGemsLoseMatch()) and status == "LOSS" then
            return false
        end

        SmartTeleportToLobby()
        return true

    elseif mode == "AutoEvo" then
        if not Globals.AutoEvo then
            SmartTeleportToLobby()
            return true
        end

        -- Auto Evo: Win ALWAYS Smart Lobby
        if status == "WIN" then
            SmartTeleportToLobby()
            return true
        end

        -- In Progression Mode: If an unowned trial is waiting in rotation, return to lobby to beat it!
        if typeof(shouldSwitchToUnownedTrial) == "function" and shouldSwitchToUnownedTrial() then
            logActivity("[Progression Mode] Unowned rotation trial ready! Teleporting to lobby to queue trial.", "info")
            SmartTeleportToLobby()
            return true
        end

        -- Auto Evo Milestones Check:
        -- 1. Level reach 20 (base tower level >= 20) -> smart lobby
        -- 2. Coins Reach (coins >= required coins) -> smart lobby
        -- 3. Gems Reach (gems >= required gems) -> smart lobby
        -- 4. evo exp 20 reached (evolved tower level >= 20) -> smart lobby
        local milestoneReached, milestoneReason = checkAutoEvoMilestonesReached()
        if milestoneReached then
            logActivity("Auto Evo Milestone: " .. tostring(milestoneReason) .. "! Returning to Smart Lobby.", "success")
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "AUTO EVO MILESTONE",
                        Desc = tostring(milestoneReason) .. "! Teleporting to Smart Lobby.",
                        Duration = 8,
                        Type = "success"
                    })
                end)()
            end
            Globals.IsConfigDirty = false
            Globals.AutoEvoMilestoneReached = false
            SmartTeleportToLobby()
            return true
        end

        -- Only teleport for dirty state if user intentionally changed config mid-match
        if Globals.IsConfigDirty or (isMatchConfigDirty and isMatchConfigDirty()) then
            Globals.IsConfigDirty = false
            Globals.AutoEvoMilestoneReached = false
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "CONFIG CHANGED",
                        Desc = "Settings updated mid-match. Returning to Smart Lobby.",
                        Duration = 6,
                        Type = "info"
                    })
                end)()
            end
            SmartTeleportToLobby()
            return true
        end

        local stratChoice = Globals.EvoStrat or "Lose"
        if Globals.CurrentEvoFarmType == "Gems" and stratChoice == "Win" then stratChoice = "Lose" end

        -- IF LOSE strat on LOSS: it should NOT SMART lobby !! instead it will just RETRY until target reached!
        if (stratChoice == "Lose" or isGemsLoseMatch()) and status == "LOSS" then
            return false
        end

        SmartTeleportToLobby()
        return true

    else
        SmartTeleportToLobby()
        return true
    end

    return false
end

activeStratThread = nil
local matchStratExecuted = false
local isStrategyExecuting = false
local failureCount = 0
local MAX_FAILURES = 5
local isHandlingEndMatch = false
local trialWatcherRunning = false
local autoGoldWatcherRunning = false
local scriptCache: { [string]: string } = {}

local function fetchStrategyScript(url: string): string?
    if not url or url == "" then return nil end
    if scriptCache[url] and #scriptCache[url] > 0 then
        return scriptCache[url]
    end

    -- 1. Try reading via readfile first if url matches a local file or local script path
    local okDirect, directContent = pcall(function()
        if (type(isfile) == "function" and isfile(url)) or (type(readfile) == "function" and not isfile) then
            return readfile(url)
        end
        return nil
    end)
    if okDirect and type(directContent) == "string" and #directContent > 0 then
        scriptCache[url] = directContent
        return directContent
    end

    local scriptName = url:match("([^/]+%.lua)$")
    local relativePath = url:match("main/(.+%.lua)$")
    local candidatePaths = {}
    if scriptName then
        table.insert(candidatePaths, scriptName)
    end
    if relativePath then
        table.insert(candidatePaths, relativePath)
    end

    for _, cand in ipairs(candidatePaths) do
        local localContent, pathUsed = readLocalFile(cand, {
            "[STAY]/[AutoTrailsFInal]/" .. cand,
            "[STAY]/" .. cand,
            cand,
            "Strategies/" .. cand,
            "[STAY]/Strategies/" .. cand,
        })
        if localContent and type(localContent) == "string" and #localContent > 0 then
            scriptCache[url] = localContent
            return localContent
        end
    end

    -- 2. Cloud fallback via safeHttpGet (secondary)
    local chunk = safeHttpGet(url, 3)
    if chunk and #chunk > 0 then
        scriptCache[url] = chunk
        return chunk
    end
    return nil
end

local compiledMacroCache = {}

local function executeActiveStrategy(mapName: string)
    local isEvoMatch = (currentMatchMode == "AutoEvo") or Globals.AutoEvo
    local isOwnedActive = (Globals.TrialFarmMode == "Progression Mode" and Globals.AutoTrials)
    if not Globals.AutoGold and not Globals.AutoEvo and not isOwnedActive and currentMatchMode ~= "AutoGold" and currentMatchMode ~= "AutoEvo" then return end
    if isStrategyExecuting or matchStratExecuted then
        warn(string.format("[ServiceHub Strategy] Strategy already active/executed for '%s', skipping duplicate execution.", tostring(mapName)))
        return
    end
    isStrategyExecuting = true
    matchStratExecuted = true

    -- Detect if this match is Hardcore or on Wretched Front
    local normMap = string.lower(string.gsub(mapName or "", "[%s%p]+", ""))
    local isHardcoreMap = (normMap == "wretchedfront" or string.find(normMap, "wretched") ~= nil)
    local isHardcoreMode = false
    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            local gMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or ""):lower()
            if gMode == "hardcore" then isHardcoreMode = true end
        end
    end)
    local isHardcoreMatch = isHardcoreMap or isHardcoreMode

    local config = getCurrentCrateConfig(isHardcoreMatch and "Gems" or nil)
    if not config and isHardcoreMatch then
        config = FallbackConfigs and FallbackConfigs["Hardcore"] or (CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Lose)
    end

    -- Ensure TDS API is loaded and globally accessible
    if not TDS or not getgenv().TDS then
        TDS = loadTDSAPI()
        if TDS then
            Globals.TDS = TDS
            pcall(function() getgenv().TDS = TDS end)
            pcall(function() _G.TDS = TDS end)
        end
    end

    -- Dynamically resolve active tower for AutoEvo if missing
    local activeTower = Globals.CurrentEvoActiveTower
    if isEvoMatch and not activeTower and typeof(analyzeAutoEvoRequirements) == "function" then
        local ok, evoAnalysis = pcall(analyzeAutoEvoRequirements)
        if ok and evoAnalysis and evoAnalysis.activeTower then
            activeTower = evoAnalysis.activeTower
            Globals.CurrentEvoActiveTower = activeTower
            if evoAnalysis.farmType then
                Globals.CurrentEvoFarmType = evoAnalysis.farmType
            end
        end
    end

    local scriptUrl: string? = nil
    local resolvedTowers: {string}? = nil

    -- 1. Try resolving from config directly
    if config and config.Scripts then
        if isEvoMatch and activeTower and config.Scripts[activeTower] then
            local towerScripts = config.Scripts[activeTower]
            if type(towerScripts) == "string" then
                scriptUrl = towerScripts
            elseif type(towerScripts) == "table" then
                scriptUrl = towerScripts[mapName]
                if not scriptUrl then
                    local normTarget = string.lower(string.gsub(mapName or "", "[%s%p]+", ""))
                    for mKey, mUrl in pairs(towerScripts) do
                        local normKey = string.lower(string.gsub(tostring(mKey), "[%s%p]+", ""))
                        if normKey == normTarget or string.find(normTarget, normKey) or string.find(normKey, normTarget) then
                            scriptUrl = mUrl
                            break
                        end
                    end
                end
                if not scriptUrl then
                    for _, mUrl in pairs(towerScripts) do
                        if type(mUrl) == "string" and #mUrl > 0 then
                            scriptUrl = mUrl
                            break
                        end
                    end
                end
            end
        else
            scriptUrl = config.Scripts[mapName]
            if not scriptUrl and type(config.Scripts) == "table" then
                local normTarget = string.lower(string.gsub(mapName or "", "[%s%p]+", ""))
                for mKey, mUrl in pairs(config.Scripts) do
                    if type(mUrl) == "string" then
                        local normKey = string.lower(string.gsub(tostring(mKey), "[%s%p]+", ""))
                        if normKey == normTarget or string.find(normTarget, normKey) or string.find(normKey, normTarget) then
                            scriptUrl = mUrl
                            break
                        end
                    elseif type(mUrl) == "table" then
                        if mUrl[mapName] then
                            scriptUrl = mUrl[mapName]
                            break
                        end
                        for innerKey, innerUrl in pairs(mUrl) do
                            local normKey = string.lower(string.gsub(tostring(innerKey), "[%s%p]+", ""))
                            if normKey == normTarget or string.find(normTarget, normKey) or string.find(normKey, normTarget) then
                                scriptUrl = innerUrl
                                break
                            end
                        end
                        if scriptUrl then break end
                    end
                end
            end
        end

        if config.Towers then
            if isEvoMatch and activeTower and type(config.Towers) == "table" and config.Towers[activeTower] then
                resolvedTowers = config.Towers[activeTower]
            else
                resolvedTowers = config.Towers
            end
        end
    end

    if type(scriptUrl) == "table" then
        scriptUrl = scriptUrl[mapName] or next(scriptUrl)
    end

    -- 2. Resilient Universal Fallbacks across PremConfigs for the specific map
    if not scriptUrl or scriptUrl == "" then
        local normTarget = string.lower(string.gsub(mapName or "", "[%s%p]+", ""))

        -- Special Handling: Wretched Front (Hardcore / Gems)
        if normTarget == "wretchedfront" or string.find(normTarget, "wretched") or isHardcoreMatch then
            if isEvoMatch and AutoEvoConfigs and AutoEvoConfigs.Gems and AutoEvoConfigs.Gems.Lose then
                local evoCfg = AutoEvoConfigs.Gems.Lose
                local tKey = activeTower
                if not tKey or not evoCfg.Scripts or not evoCfg.Scripts[tKey] then
                    tKey = evoCfg.Scripts and next(evoCfg.Scripts)
                end
                if tKey and evoCfg.Scripts and evoCfg.Scripts[tKey] then
                    local sTbl = evoCfg.Scripts[tKey]
                    scriptUrl = type(sTbl) == "string" and sTbl or (sTbl[mapName] or sTbl["Wretched Front"] or next(sTbl))
                    if evoCfg.Towers and evoCfg.Towers[tKey] then
                        resolvedTowers = evoCfg.Towers[tKey]
                    end
                end
            end
            if not scriptUrl and CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Lose then
                local cfg = CrateConfigs.Gems.Lose
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Wretched Front"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl and CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Win then
                local cfg = CrateConfigs.Gems.Win
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Wretched Front"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl and FallbackConfigs and FallbackConfigs["Hardcore"] then
                local cfg = FallbackConfigs["Hardcore"]
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Wretched Front"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl then
                scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Gems/Lose/WretchedFront.lua"
            end
            if not resolvedTowers then
                resolvedTowers = {"Farm", "Boomerang", "Crook Boss"}
            end
        -- Special Handling: Lay By (Fallen / Coins Win)
        elseif normTarget == "layby" or string.find(normTarget, "layby") then
            if isEvoMatch and AutoEvoConfigs and AutoEvoConfigs.Coins and AutoEvoConfigs.Coins.Win then
                local evoCfg = AutoEvoConfigs.Coins.Win
                local tKey = activeTower
                if not tKey or not evoCfg.Scripts or not evoCfg.Scripts[tKey] then
                    tKey = evoCfg.Scripts and next(evoCfg.Scripts)
                end
                if tKey and evoCfg.Scripts and evoCfg.Scripts[tKey] then
                    local sTbl = evoCfg.Scripts[tKey]
                    scriptUrl = type(sTbl) == "string" and sTbl or (sTbl[mapName] or sTbl["Lay By"] or next(sTbl))
                    if evoCfg.Towers and evoCfg.Towers[tKey] then
                        resolvedTowers = evoCfg.Towers[tKey]
                    end
                end
            end
            if not scriptUrl and CrateConfigs and CrateConfigs.Coins and CrateConfigs.Coins.Win then
                local cfg = CrateConfigs.Coins.Win
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Lay By"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl and FallbackConfigs and FallbackConfigs["Fallen"] then
                local cfg = FallbackConfigs["Fallen"]
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Lay By"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl and FallbackConfigs and FallbackConfigs["Molten"] then
                local cfg = FallbackConfigs["Molten"]
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Lay By"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl then
                scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Trials/Fallbacks/FallenLayby.lua"
            end
            if not resolvedTowers then
                resolvedTowers = {"Gatling Gun", "Trapper", "Medic", "Mercenary Base", "Hacker"}
            end
        -- Special Handling: Simplicity (Coins Lose)
        elseif normTarget == "simplicity" or string.find(normTarget, "simplicity") then
            if isEvoMatch and AutoEvoConfigs and AutoEvoConfigs.Coins and AutoEvoConfigs.Coins.Lose then
                local evoCfg = AutoEvoConfigs.Coins.Lose
                local tKey = activeTower or (evoCfg.Scripts and next(evoCfg.Scripts))
                if tKey and evoCfg.Scripts and evoCfg.Scripts[tKey] then
                    local sTbl = evoCfg.Scripts[tKey]
                    scriptUrl = type(sTbl) == "string" and sTbl or (sTbl[mapName] or sTbl["Simplicity"] or next(sTbl))
                    if evoCfg.Towers and evoCfg.Towers[tKey] then resolvedTowers = evoCfg.Towers[tKey] end
                end
            end
            if not scriptUrl and CrateConfigs and CrateConfigs.Coins and CrateConfigs.Coins.Lose then
                local cfg = CrateConfigs.Coins.Lose
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Simplicity"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl then
                scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Coins/Lose/Simplicity.lua"
            end
            if not resolvedTowers then
                resolvedTowers = {"Assassin", "Soldier"}
            end
        -- Special Handling: Winter Abyss (Coins Lose)
        elseif normTarget == "winterabyss" or string.find(normTarget, "winter") then
            if CrateConfigs and CrateConfigs.Coins and CrateConfigs.Coins.Lose then
                local cfg = CrateConfigs.Coins.Lose
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Winter Abyss"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl then
                scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Coins/Lose/WinterAbyss.lua"
            end
            if not resolvedTowers then
                resolvedTowers = {"Assassin", "Soldier"}
            end
        end
    end

    if type(scriptUrl) == "table" then
        scriptUrl = scriptUrl[mapName] or next(scriptUrl)
    end
    
    if not scriptUrl or scriptUrl == "" then
        warn(string.format("[ServiceHub Strategy] No script URL resolved for map '%s' (ActiveTower: %s)", tostring(mapName), tostring(activeTower)))
        logActivity(string.format("[Strategy] Missing script URL for %s", tostring(mapName)), "warn")
        return
    end

    if isEvoMatch and activeTower then
        warn(string.format("[ServiceHub AutoEvo] Active Tower: %s | Map: %s | Executing Script: %s", tostring(activeTower), tostring(mapName), tostring(scriptUrl)))
        logActivity(string.format("[AutoEvo] Strategy: %s (%s)", tostring(activeTower), tostring(mapName)), "info")
    else
        warn(string.format("[ServiceHub AutoGold] Map: %s | Executing Script: %s", tostring(mapName), tostring(scriptUrl)))
        logActivity(string.format("[AutoGold] Strategy: %s", tostring(mapName)), "info")
    end

    -- Call TDS:Loadout only once per match session
    if not loadoutApplied then
        pcall(function()
            local activeTowers = resolvedTowers or (config and config.Towers)
            if isEvoMatch and activeTower and type(activeTowers) == "table" and activeTowers[activeTower] then
                activeTowers = activeTowers[activeTower]
            end
            
            if TDS and typeof(TDS.Loadout) == "function" and activeTowers and #activeTowers > 0 then
                local lOk, lErr = pcall(function()
                    TDS:Loadout(unpack(activeTowers))
                    loadoutApplied = true
                    warn("[ServiceHub Loadout] TDS:Loadout equipped once successfully: " .. table.concat(activeTowers, ", "))
                    logActivity("[Loadout] Equipped: " .. table.concat(activeTowers, ", "), "success")
                end)
                if not lOk then
                    warn("[ServiceHub Loadout] TDS:Loadout failed: " .. tostring(lErr))
                end
            end
        end)
    end

    -- Keep executing the loadstring strategy with explicit error capture
    local stratOk, stratErr = pcall(function()
        local fn = compiledMacroCache[scriptUrl]
        if not fn then
            local chunk = fetchStrategyScript(scriptUrl)
            if chunk then
                local loadedFn, compileErr = loadstring(chunk)
                if loadedFn then
                    fn = loadedFn
                    compiledMacroCache[scriptUrl] = fn
                else
                    warn(string.format("[ServiceHub Strategy] Failed to parse/compile script from %s: %s", tostring(scriptUrl), tostring(compileErr)))
                    logActivity("[Strategy] Script syntax error", "error")
                end
            else
                warn(string.format("[ServiceHub Strategy] Failed to fetch strategy script from: %s", tostring(scriptUrl)))
                logActivity("[Strategy] Failed to fetch script", "error")
            end
        end

        if fn then
            if TDS and typeof(TDS.RemoveIndex) == "function" then
                pcall(function() TDS:RemoveIndex() end)
            end
            warn(string.format("[ServiceHub Strategy] Running strategy macro for %s...", tostring(activeTower or mapName)))
            logActivity("[Strategy] Running macro...", "info")
            
            local execOk, execErr = pcall(fn)
            if not execOk then
                warn(string.format("[ServiceHub Strategy] Runtime error in strategy script: %s", tostring(execErr)))
                logActivity(string.format("[Strategy Error] %s", tostring(execErr)), "error")
            else
                warn("[ServiceHub Strategy] Strategy executed cleanly.")
                logActivity("[Strategy] Strategy active / executed", "success")
            end
        end
    end)

    if not stratOk then
        warn(string.format("[ServiceHub Strategy] Execution supervisor error: %s", tostring(stratErr)))
        logActivity("[Strategy] Supervisor error: " .. tostring(stratErr), "error")
    end
end

local function isReadyPressedOrGameStarted(): boolean
    local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
    if not sr then return false end

    local gsr = sr:FindFirstChild("GameStateReplicator")
    if gsr and (gsr:GetAttribute("GameStarted") == true or (gsr:GetAttribute("Wave") or 0) > 0) then
        return true
    end

    local vr = sr:FindFirstChild("VoteReplicator")
    if vr and (vr:GetAttribute("Enabled") == false or (vr:GetAttribute("VoteCount") or 0) > 0) then
        return true
    end

    return false
end

-- Mobile-optimized direct ready prompt detection (avoids scanning thousands of UI descendants)
local function isReadyPromptVisible(): boolean
    local found = false
    pcall(function()
        local intermission = PlayerGui:FindFirstChild("ReactGameIntermission")
        if intermission and intermission:IsA("ScreenGui") and intermission.Enabled then
            local frame = intermission:FindFirstChild("Frame")
            if frame and frame.Visible then
                found = true
                return
            end
        end

        local promptGui = PlayerGui:FindFirstChild("ReadyPrompt") or PlayerGui:FindFirstChild("PromptOverlay")
        if promptGui and promptGui:IsA("ScreenGui") and promptGui.Enabled then
            found = true
            return
        end

        -- Fast targeted check without recursive descendant tree traversal
        for _, sg in ipairs(PlayerGui:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Enabled and sg ~= UI.ScreenGui then
                local sName = sg.Name
                if sName:find("Intermission") or sName:find("Ready") or sName:find("Vote") then
                    local frame = sg:FindFirstChild("Frame") or sg:FindFirstChildWhichIsA("Frame")
                    if frame and frame.Visible then
                        found = true
                        return
                    end
                end
            end
        end
    end)
    return found
end

--==============================================================================
-- Webhook Integration
--==============================================================================
EvoData = EvoData or {
    ["Scout"] = { Evo = "EvolvedOperator", Coins = 15000, Gems = 4500 },
    ["Shotgunner"] = { Evo = "EvolvedEnforcer", Coins = 15000, Gems = 5000 },
    ["Crook Boss"] = { Evo = "EvolvedKingpin", Coins = 15000, Gems = 5500 },
    ["Minigunner"] = { Evo = "EvolvedJuggernaut", Coins = 15000, Gems = 6000 }
}

Globals.SessionStartTime = Globals.SessionStartTime or os.time()
Globals.SessionMatchesPlayed = Globals.SessionMatchesPlayed or 0
Globals.SessionTotalCoins = Globals.SessionTotalCoins or 0
Globals.SessionTotalGems = Globals.SessionTotalGems or 0

local function GetAllRewards()
    local ItemNames = {}
    local results = {
        Coins = 0, Gems = 0, XP = 0, Wave = 0, Level = 0, Time = "00:00", Status = "UNKNOWN", Others = {}
    }
    local UiRoot = PlayerGui:FindFirstChild("ReactGameNewRewards")
    local MainFrame = UiRoot and UiRoot:FindFirstChild("Frame")
    local GameOver = MainFrame and MainFrame:FindFirstChild("gameOver")
    local RewardsScreen = GameOver and GameOver:FindFirstChild("RewardsScreen")
    local GameStats = RewardsScreen and RewardsScreen:FindFirstChild("gameStats")
    local StatsList = GameStats and GameStats:FindFirstChild("stats")

    if StatsList then
        for _, frame in ipairs(StatsList:GetChildren()) do
            local l1 = frame:FindFirstChild("textLabel")
            local l2 = frame:FindFirstChild("textLabel2")
            local refLabel = l2 and l2:FindFirstChild("refLabel")
            if l1 and refLabel and l1.Text:find("Time Completed:") then
                results.Time = refLabel.Text
                break
            end
        end
    end

    local TopBanner = RewardsScreen and RewardsScreen:FindFirstChild("RewardBanner")
    if TopBanner and TopBanner:FindFirstChild("textLabel") then
        local txt = TopBanner.textLabel.Text:upper()
        results.Status = txt:find("TRIUMPH") and "WIN" or (txt:find("LOST") and "LOSS" or "UNKNOWN")
    end

    if PlayerDataHandler and typeof(PlayerDataHandler.GetLevel) == "function" then
        pcall(function() results.Level = PlayerDataHandler:GetLevel() or 0 end)
    end

    local topGameDisplay = PlayerGui:FindFirstChild("ReactGameTopGameDisplay")
    if topGameDisplay then
        pcall(function()
            local label = topGameDisplay.Frame.wave.container.value
            local WaveNum = label.Text:match("^(%d+)")
            if WaveNum then results.Wave = tonumber(WaveNum) or 0 end
        end)
    end

    local SectionRewards = RewardsScreen and RewardsScreen:FindFirstChild("RewardsSection")
    if SectionRewards then
        for _, item in ipairs(SectionRewards:GetChildren()) do
            if tonumber(item.Name) then 
                local IconId = "0"
                local img = item:FindFirstChildWhichIsA("ImageLabel", true)
                if img then IconId = img.Image:match("%d+") or "0" end
                for _, child in ipairs(item:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        local text = child.Text
                        local amt = tonumber(text:match("(%d+)")) or 0
                        if text:find("Coins") then results.Coins = amt
                        elseif text:find("Gems") then results.Gems = amt
                        elseif text:find("XP") then results.XP = amt
                        elseif text:lower():find("x%d+") then 
                            local displayName = ItemNames[IconId] or "Unknown Item (" .. IconId .. ")"
                            table.insert(results.Others, {Amount = text:match("x%d+"), Name = displayName})
                        end
                    end
                end
            end
        end
    end
    return results
end

local function sendDiscordWebhook(matchStatus: string, mode: string)
    local url = Globals.WebhookURL
    if type(url) ~= "string" or url == "" then return end

    local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httprequest then return end

    pcall(function()
        local matchData = GetAllRewards()
        matchData.Status = matchStatus
        
        Globals.SessionMatchesPlayed = Globals.SessionMatchesPlayed + 1
        Globals.SessionTotalCoins = Globals.SessionTotalCoins + matchData.Coins
        Globals.SessionTotalGems = Globals.SessionTotalGems + matchData.Gems

        local currentWalletCoins, targetCoinsVal, currentWalletGems, targetGemsVal, coinsDisplay, gemsDisplay = getCurrencyAndTargets()

        local isWin = matchStatus == "WIN"
        local modeName = mode
        if mode == "AutoTrials" then modeName = "Auto Trials"
        elseif mode == "AutoGold" then modeName = "Auto Gold"
        elseif mode == "AutoEvo" then modeName = "Auto Evo" end

        local stratType = Globals.Strat or "Unknown"
        if mode == "AutoEvo" then stratType = Globals.EvoStrat or "Unknown" end

        local timeElapsedSecs = os.time() - Globals.SessionStartTime
        local hours = math.floor(timeElapsedSecs / 3600)
        local minutes = math.floor((timeElapsedSecs % 3600) / 60)
        local sessionTimeStr = string.format("%02d:%02d:%02d", hours, minutes, timeElapsedSecs % 60)

        local missingCoins = 0
        local missingGems = 0
        local missingLvl = 0

        if mode == "AutoEvo" then
            local activeTower = Globals.CurrentEvoActiveTower or "Unknown"
            local eData = EvoData and EvoData[activeTower]
            if eData then
                missingCoins = math.max(0, eData.Coins - currentWalletCoins)
                missingGems = math.max(0, eData.Gems - currentWalletGems)
                local baseLevel = 0
                if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                    pcall(function() local d = PlayerDataHandler:GetTowerExp(activeTower); if d and type(d)=="table" then baseLevel = d.Level or 0 end end)
                end
                missingLvl = math.max(0, 20 - baseLevel)
            end
        elseif mode == "AutoGold" then
            local tc = tonumber(Globals.TargetCoins) or 0
            local tg = tonumber(Globals.TargetGems) or 0
            if tc > 0 then missingCoins = math.max(0, tc - currentWalletCoins) end
            if tg > 0 then missingGems = math.max(0, tg - currentWalletGems) end
        end

        local function formatK(num)
            if num >= 1000 then return string.format("%.1fk", num / 1000):gsub("%.0k", "k") end
            return tostring(num)
        end

        local BonusString = ""
        if #matchData.Others > 0 then
            for _, res in ipairs(matchData.Others) do BonusString = BonusString .. "🎁 **" .. res.Amount .. " " .. res.Name .. "**\n" end
        else
            BonusString = string.format("❌ **Missing:**\n🪙 Coins: `%s`\n💎 Gems: `%s`\n⭐ Tower Lvl: `%s`", formatK(missingCoins), formatK(missingGems), tostring(missingLvl))
        end

        local currentLocation = (game.PlaceId == LOBBY_PLACE_ID) and "Lobby" or "Ingame"

        local embed = {
            ["title"] = isWin and "🏆 Match Victory!" or "💀 Match Defeat...",
            ["description"] = "### 📋 Match Overview\n> **Status:** `" .. matchData.Status .. "`\n> **Time:** `" .. matchData.Time .. "`\n> **Current Level:** `" .. matchData.Level .. "`\n> **Wave:** `" .. matchData.Wave .. "`\n",
            ["color"] = isWin and 3066993 or 15158332,
            ["timestamp"] = DateTime.now():ToIsoDate(),
            ["footer"] = { ["text"] = "ServiceHub V2 • Play Smart, Not Hard", ["icon_url"] = "https://i.imgur.com/W35kZkU.png" },
            ["thumbnail"] = { ["url"] = "https://i.imgur.com/W35kZkU.png" },
            ["fields"] = {
                { ["name"] = "⚙️ Settings", ["value"] = "Mode: `" .. modeName .. "`\nStrat: `" .. stratType .. "`", ["inline"] = true },
                { ["name"] = "📈 Session Info", ["value"] = "Matches: `" .. Globals.SessionMatchesPlayed .. "`\nTime: `" .. sessionTimeStr .. "`", ["inline"] = true },
                { ["name"] = "🌍 Location", ["value"] = "State: `" .. currentLocation .. "`", ["inline"] = true },
                { ["name"] = "✨ Rewards", ["value"] = "```ansi\n\27[2;33mCoins:\27[0m +" .. matchData.Coins .. "\n\27[2;34mGems: \27[0m +" .. matchData.Gems .. "\n\27[2;32mXP:   \27[0m +" .. matchData.XP .. "```", ["inline"] = false },
                { ["name"] = "🎁 Bonus Items", ["value"] = BonusString, ["inline"] = true },
                { ["name"] = "📊 Session Totals", ["value"] = "```py\n# Total Earned\nCoins: " .. Globals.SessionTotalCoins .. "\nGems:  " .. Globals.SessionTotalGems .. "\n# User Current / Target\nCoins: " .. coinsDisplay .. "\nGems:  " .. gemsDisplay .. "```", ["inline"] = true }
            }
        }

        if mode == "AutoGold" then
            local targetCoins = tonumber(Globals.TargetCoins) or 0
            local targetGems = tonumber(Globals.TargetGems) or 0
            
            if targetCoins == 0 and targetGems == 0 then
                table.insert(embed.fields, { ["name"] = "🪙 User Current Coins", ["value"] = string.format("`%s`", coinsDisplay), ["inline"] = true })
                table.insert(embed.fields, { ["name"] = "💎 User Current Gems", ["value"] = string.format("`%s`", gemsDisplay), ["inline"] = true })
            else
                if targetCoins > 0 then
                    local current = currentWalletCoins
                    local percent = math.clamp(current / targetCoins, 0, 1)
                    local filled = math.floor(percent * 10)
                    local progressBar = string.rep("🟩", filled) .. string.rep("⬛", 10 - filled)
                    
                    local etaString = ""
                    if Globals.SessionTotalCoins > 0 and timeElapsedSecs > 60 and targetCoins > current then
                        local rate = Globals.SessionTotalCoins / timeElapsedSecs
                        local secondsLeft = (targetCoins - current) / rate
                        local hLeft = math.floor(secondsLeft / 3600)
                        local mLeft = math.floor((secondsLeft % 3600) / 60)
                        etaString = string.format("\n⏳ **ETA:** `%dh %dm`", hLeft, mLeft)
                    end
                    table.insert(embed.fields, { ["name"] = "🎯 Target Coins", ["value"] = string.format("`%s` / `%s`\n%s **%.1f%%**%s", formatNumberWithCommas(current), formatNumberWithCommas(targetCoins), progressBar, percent * 100, etaString), ["inline"] = false })
                end
                
                if targetGems > 0 then
                    local current = currentWalletGems
                    local percent = math.clamp(current / targetGems, 0, 1)
                    local filled = math.floor(percent * 10)
                    local progressBar = string.rep("🟩", filled) .. string.rep("⬛", 10 - filled)
                    
                    local etaString = ""
                    if Globals.SessionTotalGems > 0 and timeElapsedSecs > 60 and targetGems > current then
                        local rate = Globals.SessionTotalGems / timeElapsedSecs
                        local secondsLeft = (targetGems - current) / rate
                        local hLeft = math.floor(secondsLeft / 3600)
                        local mLeft = math.floor((secondsLeft % 3600) / 60)
                        etaString = string.format("\n⏳ **ETA:** `%dh %dm`", hLeft, mLeft)
                    end
                    table.insert(embed.fields, { ["name"] = "🎯 Target Gems", ["value"] = string.format("`%s` / `%s`\n%s **%.1f%%**%s", formatNumberWithCommas(current), formatNumberWithCommas(targetGems), progressBar, percent * 100, etaString), ["inline"] = false })
                end
            end
        elseif mode == "AutoTrials" then
            table.insert(embed.fields, { ["name"] = "🪙 User Current Coins", ["value"] = string.format("`%s`", coinsDisplay), ["inline"] = true })
            table.insert(embed.fields, { ["name"] = "💎 User Current Gems", ["value"] = string.format("`%s`", gemsDisplay), ["inline"] = true })
        elseif mode == "AutoEvo" then
            local activeTower = Globals.CurrentEvoActiveTower or "Unknown"
            local needType = Globals.CurrentEvoFarmType or "Coins"
            table.insert(embed.fields, { ["name"] = "🎯 Active Target", ["value"] = string.format("`%s`", activeTower), ["inline"] = true })
            
            local stateText = "Unknown"
            if needType == "Coins" then stateText = "Grinding coins / level..."
            elseif needType == "Gems" then stateText = "Grinding gems..." end
            table.insert(embed.fields, { ["name"] = "🔄 Current State", ["value"] = string.format("`%s`", stateText), ["inline"] = true })
            table.insert(embed.fields, { ["name"] = "🪙 User Current Coins", ["value"] = string.format("`%s`", coinsDisplay), ["inline"] = true })
            table.insert(embed.fields, { ["name"] = "💎 User Current Gems", ["value"] = string.format("`%s`", gemsDisplay), ["inline"] = true })

            local eData = EvoData and EvoData[activeTower]
            if eData then
                local evoName = eData.Evo
                local ownsBase = true; local baseLevel = 0; local ownsEvo = false; local evoLevel = 0
                if PlayerDataHandler then
                    if typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        pcall(function() ownsBase = PlayerDataHandler:IsTowerOwned(activeTower) end)
                        pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
                    end
                    if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                        pcall(function() local d = PlayerDataHandler:GetTowerExp(activeTower); if d and type(d)=="table" then baseLevel = d.Level or 0 end end)
                        pcall(function() local d = PlayerDataHandler:GetTowerExp(evoName); if d and type(d)=="table" then evoLevel = d.Level or 0 end end)
                    end
                end
                
                local overallPercent = 0; local cIcon, gIcon, bIcon, eIcon; local cStr, gStr, bStr, eStr
                if ownsEvo then
                    overallPercent = 75 + math.clamp((evoLevel / 20) * 25, 0, 25)
                    cIcon = "✅"; gIcon = "✅"; bIcon = "✅"; eIcon = evoLevel >= 20 and "✅" or "📊"
                    cStr = "`Paid`"; gStr = "`Paid`"; bStr = "`Maxed (20 / 20)`"; eStr = string.format("`Level %d / 20`", evoLevel)
                else
                    if ownsBase then overallPercent += 5 end
                    overallPercent += math.clamp((baseLevel / 20) * 25, 0, 25)
                    overallPercent += math.clamp((currentWalletCoins / eData.Coins) * 20, 0, 20)
                    overallPercent += math.clamp((currentWalletGems / eData.Gems) * 20, 0, 20)
                    cIcon = currentWalletCoins >= eData.Coins and "✅" or "🪙"
                    gIcon = currentWalletGems >= eData.Gems and "✅" or "💎"
                    bIcon = baseLevel >= 20 and "✅" or (ownsBase and "📊" or "❌")
                    eIcon = "🔒"
                    cStr = string.format("`%s / %s`", formatNumberWithCommas(currentWalletCoins), formatNumberWithCommas(eData.Coins))
                    gStr = string.format("`%s / %s`", formatNumberWithCommas(currentWalletGems), formatNumberWithCommas(eData.Gems))
                    bStr = ownsBase and string.format("`Level %d / 20`", baseLevel) or "`Not Owned`"
                    eStr = "`Locked`"
                end
                
                local overallFilled = math.floor((overallPercent / 100) * 10)
                local overallBar = string.rep("🟩", overallFilled) .. string.rep("⬛", 10 - overallFilled)
                
                local etaString = ""
                if Globals.EvoStartPercent == nil then Globals.EvoStartPercent = overallPercent end
                local percentGained = overallPercent - Globals.EvoStartPercent
                if percentGained > 0 and overallPercent < 100 and timeElapsedSecs > 60 then
                    local rate = percentGained / timeElapsedSecs
                    local secondsLeft = (100 - overallPercent) / rate
                    local hLeft = math.floor(secondsLeft / 3600)
                    local mLeft = math.floor((secondsLeft % 3600) / 60)
                    etaString = string.format("\n⏳ **ETA:** `%dh %dm`", hLeft, mLeft)
                end

                local desc = string.format("%s **Base (%s):** %s\n", bIcon, activeTower, bStr)
                desc = desc .. string.format("%s **Coins:** %s\n", cIcon, cStr)
                desc = desc .. string.format("%s **Gems:** %s\n", gIcon, gStr)
                desc = desc .. string.format("%s **Evo (%s):** %s\n\n", eIcon, evoName, eStr)
                desc = desc .. string.format("**Total Progress:** %s **%.1f%%**%s", overallBar, overallPercent, etaString)
                
                table.insert(embed.fields, { ["name"] = "📈 Evolution Progress Map", ["value"] = desc, ["inline"] = false })
            end
        end

        httprequest({
            Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode({ ["username"] = "ServiceHub", ["avatar_url"] = "https://i.imgur.com/W35kZkU.png", ["embeds"] = { embed } })
        })
    end)
end

--==============================================================================
-- Disconnect Tracking
--==============================================================================
local function sendDisconnectWebhook(reason)
    local url = Globals.WebhookURL
    if type(url) ~= "string" or url == "" then return end
    local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httprequest then return end

    local title = "⚠️ Disconnected"
    local lowerReason = reason:lower()
    if lowerReason:find("game guard") or lowerReason:find("unexpected client behavior") then 
        title = "🛡️ Game Guard Activated"
    elseif lowerReason:find("idle") or lowerReason:find("afk") or lowerReason:find("20 minutes") then 
        title = "💤 AFK / Idle Kick"
    end

    pcall(function()
        local embed = {
            ["title"] = title,
            ["description"] = "```\n" .. tostring(reason) .. "\n```",
            ["color"] = 16711680,
            ["timestamp"] = DateTime.now():ToIsoDate(),
            ["footer"] = { ["text"] = "ServiceHub V2 • Play Smart, Not Hard", ["icon_url"] = "https://i.imgur.com/W35kZkU.png" }
        }
        httprequest({
            Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode({ ["username"] = "ServiceHub", ["avatar_url"] = "https://i.imgur.com/W35kZkU.png", ["embeds"] = { embed } })
        })
    end)
end

task.spawn(function()
    pcall(function()
        local CoreGui = game:GetService("CoreGui")
        local promptOverlay = CoreGui:WaitForChild("RobloxPromptGui", 10)
        if promptOverlay then promptOverlay = promptOverlay:WaitForChild("promptOverlay", 10) end
        
        if promptOverlay then
            local function checkPrompt(child)
                if child.Name == "ErrorPrompt" then
                    task.wait(0.5)
                    local msgLabel = child:FindFirstChild("ErrorMessage", true)
                    local reason = msgLabel and msgLabel.Text or "Unknown Disconnection"
                    sendDisconnectWebhook(reason)
                end
            end
            promptOverlay.ChildAdded:Connect(checkPrompt)
            for _, child in ipairs(promptOverlay:GetChildren()) do checkPrompt(child) end
        end
    end)
    pcall(function()
        game:GetService("GuiService").ErrorMessageChanged:Connect(function(msg)
            sendDisconnectWebhook(msg)
        end)
    end)
end)

--==============================================================================
-- Strategy Execution & Match-End Listener for Auto Trials
--==============================================================================
local function runMatchStrategyIfSaved()
    if game.PlaceId == LOBBY_PLACE_ID then return end

    -- v9.8 Progression Mode Guard:
    -- If Progression Mode is active, ignore trial strat execution when:
    -- 1) AutoEvo or AutoGold is enabled (prioritizing currency/evo farm)
    -- 2) The trial is already won/owned
    if Globals.TrialFarmMode == "Progression Mode" then
        if Globals.AutoEvo or Globals.AutoGold then
            warn("[ServiceHub AutoTrials v9.8] Progression Mode: AutoEvo/AutoGold is active -> ignoring trial strat execution.")
            logActivity("[Progression Mode] Ignored trial strategy execution (AutoEvo/AutoGold active)", "info")
            return
        end

        local liveTrial = ""
        pcall(function()
            local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
            if gsr then
                liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "")
            end
        end)

        if liveTrial ~= "" and typeof(checkIsTrialWon) == "function" and checkIsTrialWon(liveTrial) then
            warn(string.format("[ServiceHub AutoTrials v9.8] Progression Mode: Trial '%s' is already owned -> ignoring trial strat execution.", liveTrial))
            logActivity(string.format("[Progression Mode] Ignored trial strategy (Already owned: %s)", liveTrial), "info")
            return
        end
    end

    -- Keyless Mode in-game guard:
    if not isKeyUser and not isPremiumUser then
        local liveTrial = ""
        pcall(function()
            local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
            if gsr then
                liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "")
            end
            if liveTrial == "" or liveTrial == "None" then
                local tsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                    and ReplicatedStorage.StateReplicators:FindFirstChild("TrialsStateReplicator")
                if tsr then
                    liveTrial = tostring(tsr:GetAttribute("GlobalTrial") or "")
                end
            end
            if (liveTrial == "" or liveTrial == "None") and typeof(loadTrialState) == "function" then
                liveTrial = tostring(loadTrialState() or "")
            end
        end)

        local isOwnedMatch = false
        if liveTrial ~= "" and typeof(checkIsTrialWon) == "function" and checkIsTrialWon(liveTrial) then
            isOwnedMatch = true
        else
            for configName in pairs(RevampAutoTrials) do
                if normalizeString(configName) == normalizeString(liveTrial) then
                    if checkIsTrialWon(configName) then
                        isOwnedMatch = true
                        break
                    end
                end
            end
        end

        if isOwnedMatch then
            warn(string.format("[ServiceHub AutoTrials v9.8] Keyless Mode: Trial '%s' is already owned -> returning to lobby.", liveTrial))
            logActivity(string.format("[Keyless Mode] Trial '%s' already owned -> returning to lobby", liveTrial), "info")
            pcall(function()
                if typeof(SmartTeleportToLobby) == "function" then
                    SmartTeleportToLobby()
                end
            end)
            return
        end
    end

    -- Keyless and Key modes are trial-only. Premium farming flags are ignored outside Premium.
    if not Globals.AutoTrials or (isPremiumUser and (Globals.AutoGold or Globals.AutoEvo)) or matchStratExecuted or isStrategyExecuting then return end
    isStrategyExecuting = true

    local liveTrial = ""
    local liveDifficulty = ""
    local liveGameMode = ""

    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "")
            liveDifficulty = tostring(gsr:GetAttribute("Difficulty") or "")
            liveGameMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or "")
        end
    end)

    local targetKey: string? = nil
    local normalizedTarget = normalizeString(liveTrial ~= "" and liveTrial or liveDifficulty)

    for configName in pairs(RevampAutoTrials) do
        if normalizeString(configName) == normalizedTarget then
            targetKey = configName
            break
        end
    end

    
    local currentTrialConfig = targetKey and RevampAutoTrials[targetKey] or nil
    local activeSlot = Globals.ActiveTrialSlot
    if not activeSlot and currentTrialConfig and currentTrialConfig.Towers then
        -- Fallback if they manually walked into elevator bypassing Lobby Validator
        if isPremiumUser and (currentTrialConfig.Towers["Tower Config 2"] or currentTrialConfig.Towers["Tower 2"]) then
            activeSlot = currentTrialConfig.Towers["Tower Config 2"] and "Tower Config 2" or "Tower 2"
        else
            activeSlot = currentTrialConfig.Towers["Tower Config 1"] and "Tower Config 1" or "Tower 1"
        end
    end
    activeSlot = activeSlot or "Tower Config 1"
    
    local scriptUrl = currentTrialConfig and currentTrialConfig.scripts and currentTrialConfig.scripts[activeSlot] or nil


    if not scriptUrl and isPremiumUser then
        ensureDynamicHardcoreFallback()
        local savedTrial = ""
        if typeof(loadTrialState) == "function" then
            pcall(function() savedTrial = tostring(loadTrialState() or "") end)
        end
        for modeName, modeConfig in pairs(FallbackConfigs) do
            local match = (normalizeString(modeName) == normalizedTarget)
                or (normalizeString(modeName) == normalizeString(savedTrial))
                or (normalizeString(modeName) == "hardcore" and (normalizeString(liveGameMode) == "hardcore" or normalizeString(savedTrial) == "hardcore"))
            if match then
                local availableMaps = AutoGoldModule.GetAvailableMaps()
                local mapName = modeConfig.Maps and modeConfig.Maps[1] or "Lay By"
                for _, m in ipairs(modeConfig.Maps or {}) do
                    if availableMaps[m] then
                        mapName = m
                        break
                    end
                end
                if modeConfig.Scripts then
                    scriptUrl = modeConfig.Scripts[mapName]
                    if not scriptUrl then
                        for _, sUrl in pairs(modeConfig.Scripts) do
                            if type(sUrl) == "string" and #sUrl > 0 then
                                scriptUrl = sUrl
                                break
                            end
                        end
                    end
                end
                currentTrialConfig = modeConfig
                break
            end
        end
    end

    if not scriptUrl or scriptUrl == "" then
        isStrategyExecuting = false
        return
    end

    matchStratExecuted = true
    activeStratThread = task.spawn(function()
            pcall(function()
                if not loadoutApplied then
                    if currentTrialConfig and currentTrialConfig.Towers and TDS and typeof(TDS.Loadout) == "function" then
                        local activeTowers = currentTrialConfig.Towers
                        if type(activeTowers) == "table" and not activeTowers[1] then
                            -- It's a dictionary (Trial Config)
                            activeTowers = currentTrialConfig.Towers[activeSlot]
                        end
                        
                        if type(activeTowers) == "table" and #activeTowers > 0 then
                            ----print(("[ServiceHub Loadout] Applying towers loadout:", table.concat(activeTowers, ", "))
                            TDS:Loadout(unpack(activeTowers))
                            loadoutApplied = true
                        end
                    end
                end

                ----warn([ServiceHub AutoTrials] Executing strategy script:", scriptUrl)
                local fn = compiledMacroCache[scriptUrl]
                if not fn then
                    local chunk = fetchStrategyScript(scriptUrl)
                    if chunk then
                        local loadedFn, compileErr = loadstring(chunk)
                        if loadedFn then
                            fn = loadedFn
                            compiledMacroCache[scriptUrl] = fn
                        else
                            warn(string.format("[ServiceHub Execution] Failed to parse script via loadstring: %s", tostring(compileErr)))
                        end
                    else
                        --warn(`[ServiceHub Execution] Failed to fetch strategy URL: {scriptUrl}`)
                    end
                end

                if fn then
                    if TDS and typeof(TDS.RemoveIndex) == "function" then
                        pcall(function() TDS:RemoveIndex() end)
                    end
                    fn()
                end
            end)
        end)

    if not trialWatcherRunning then
        trialWatcherRunning = true
        task.spawn(function()
            while task.wait(1) do
                if not isRunning then break end
                if game.PlaceId == LOBBY_PLACE_ID then break end

                local status = GetMatchStatus()
                if (status == "WIN" or status == "LOSS") and not isHandlingEndMatch then
                    isHandlingEndMatch = true
                    sendDiscordWebhook(status, "AutoTrials")
                    if shouldTeleportOnMatchEnd(status) then
                        isHandlingEndMatch = false
                        break
                    end

                    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                        pcall(task.cancel, activeStratThread)
                        activeStratThread = nil
                    end

                    if status == "WIN" then
                        pcall(function()
                            local gm = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("GameManager")
                            local reMatch = gm and gm:FindFirstChild("RE:Rematch")
                            if reMatch and reMatch:IsA("RemoteEvent") then
                                reMatch:FireServer()
                            end
                        end)
                        pcall(function()
                            local gui = PlayerGui:FindFirstChild("ReactGameNewRewards")
                            local playAgain = gui and gui:FindFirstChild("PlayAgain", true)
                            local btn = playAgain and (playAgain:FindFirstChild("button") or playAgain:FindFirstChildOfClass("ImageButton") or playAgain:FindFirstChildOfClass("TextButton"))
                            if btn and getconnections then
                                for _, conn in ipairs(getconnections(btn.Activated)) do conn:Fire() end
                                for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do conn:Fire() end
                            end
                        end)

                        local restartStartTime = tick()
                        local restartSuccess = false
                        while isRunning and (tick() - restartStartTime < 35) do
                            local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
                            local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
                            local isGameOver = gsr and (gsr:GetAttribute("GameOver") == true)
                            local wave = gsr and (gsr:GetAttribute("Wave") or 0) or 0
                            local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar") ~= nil

                            if (gsr and not isGameOver and (wave > 0 or hotbar)) or (GetMatchStatus() == nil and hotbar) then
                                restartSuccess = true
                                break
                            end
                            task.wait(1)
                        end

                        if not restartSuccess then
                            SmartTeleportToLobby()
                            break
                        end

                        task.wait(2) -- Buffer to allow map models to fully render
                        snapshotMatchConfig()
                        isLateExecution = false
                        initialExecutionWave = 0
                        Globals.IsConfigDirty = false

                        if not Globals.AutoTrials then
                            SmartTeleportToLobby()
                            break
                        end

                        matchStratExecuted = false
                        isStrategyExecuting = false
                        isHandlingEndMatch = false
                        runMatchStrategyIfSaved()
                    elseif status == "LOSS" then
                        local isHcLose = isGemsLoseMatch()
                        if not isHcLose then
                            failureCount += 1
                        else
                            failureCount = 0
                        end

                        if failureCount >= MAX_FAILURES then
                            SmartTeleportToLobby()
                            break
                        else
                            task.spawn(function()
                                local startVoteTime = tick()
                                while isRunning and (tick() - startVoteTime < 30) do
                                    if GetMatchStatus() == nil then break end
                                    fireSkipVoteUntilTrue()
                                    task.wait(0.5)
                                end
                            end)

                            local restartStartTime = tick()
                            local restartSuccess = false
                            while isRunning and (tick() - restartStartTime < 35) do
                                local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
                                local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
                                local isGameOver = gsr and (gsr:GetAttribute("GameOver") == true)
                                local wave = gsr and (gsr:GetAttribute("Wave") or 0) or 0
                                local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar") ~= nil

                                if (gsr and not isGameOver and (wave > 0 or hotbar)) or (GetMatchStatus() == nil and hotbar) then
                                    restartSuccess = true
                                    break
                                end
                                task.wait(1)
                            end

                            if not restartSuccess then
                                SmartTeleportToLobby()
                                break
                            end

                            task.wait(2) -- Buffer to allow map models to fully render
                            snapshotMatchConfig()
                            isLateExecution = false
                            initialExecutionWave = 0
                            Globals.IsConfigDirty = false

                            if not Globals.AutoTrials and not Globals.AutoGold and not Globals.AutoEvo then
                                SmartTeleportToLobby()
                                break
                            end

                            loadoutApplied = false
                            matchStratExecuted = false
                            isStrategyExecuting = false
                            isHandlingEndMatch = false

                            if isHcLose then
                                activeStratThread = task.spawn(function()
                                    executeActiveStrategy("Wretched Front")
                                end)
                            else
                                runMatchStrategyIfSaved()
                            end
                        end
                    end
                end
            end
            trialWatcherRunning = false
            isHandlingEndMatch = false
        end)
    end
end

-- Helper function to attempt purchasing a missing tower from the Shop
local attemptBuyMissingTower: (towerName: string) -> boolean
do
    local towerPurchaseDebounce: { [string]: number } = {}

    attemptBuyMissingTower = function(towerName: string): boolean
    if not isPremiumUser or not Globals.AutoTrials then return false end
    if not towerName or towerName == "" then return false end
    if game.PlaceId ~= LOBBY_PLACE_ID then return false end

    -- Avoid trying to buy golden tower variants or special non-shop items
    if string.find(string.lower(towerName), "golden") then return false end

    -- Check if already owned first
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        if PlayerDataHandler:IsTowerOwned(towerName) then
            return true
        end
    end

    -- Debounce: Don't spam the shop remote for the same tower (try once every 15 seconds)
    local lastAttempt = towerPurchaseDebounce[towerName] or 0
    if os.time() - lastAttempt < 15 then return false end
    towerPurchaseDebounce[towerName] = os.time()

    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if not (remoteFunction and remoteFunction:IsA("RemoteFunction")) then
        return false
    end

    logActivity(string.format("[Shop] Missing tower '%s' detected! Attempting purchase from Shop...", towerName), "info")
    if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
        RunAsExecutor(function()
            UI.Window:Notify({
                Title = "SHOP PURCHASE",
                Desc = string.format("Attempting to purchase missing tower: %s...", towerName),
                Duration = 4,
                Type = "info",
            })
        end)()
    end

    local success, result = pcall(function()
        return remoteFunction:InvokeServer("Shop", "Purchase", "Tower", towerName)
    end)

    if success then
        task.wait(0.5)
        -- Force refresh cached towers in PlayerDataHandler
        if PlayerDataHandler and typeof(PlayerDataHandler.GetTowers) == "function" then
            pcall(function() PlayerDataHandler:GetTowers() end)
        end
        local isOwnedNow = false
        if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
            isOwnedNow = PlayerDataHandler:IsTowerOwned(towerName)
        end

        if isOwnedNow then
            logActivity(string.format("[Shop] Successfully purchased tower '%s'!", towerName), "success")
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "PURCHASE SUCCESS",
                        Desc = string.format("Bought %s! Requirements may now be met.", towerName),
                        Duration = 6,
                        Type = "success",
                    })
                end)()
            end
            return true
        else
            logActivity(string.format("[Shop] Could not purchase '%s' (insufficient currency or locked).", towerName), "warn")
        end
    end

    return false
    end
end

attemptBuyMissingTowersList = function(tList: { string }?): boolean
    if not isPremiumUser or not Globals.AutoTrials then return false end
    if not tList or #tList == 0 then return false end
    if game.PlaceId ~= LOBBY_PLACE_ID then return false end

    local anyBought = false
    for _, towerName in ipairs(tList) do
        local bought = attemptBuyMissingTower(towerName)
        if bought then
            anyBought = true
        end
    end
    return anyBought
end

-- Detailed Trial & Fallback Evaluation Sequence
--==============================================================================
export type AnalysisResult = {
    trialName: string,
    nextTrialName: string,
    currentMap: string,
    nextTrialMap: string,
    timeRemaining: string,
    nextTimeRemaining: string,
    configFound: boolean,
    requiredLevel: number,
    playerLevel: number,
    levelPassed: boolean,
    missingTowers: { string },
    missingGold: { string },
    missingSkills: { string },
    isEligible: boolean,
    isSelectedInFilter: boolean,
    isOwned: boolean,
    useFallback: boolean,
    fallbackMode: string,
}


local function analyzeCurrentTrial(): AnalysisResult
    local currentTrialTitle = "None"
    local upcomingTrialTitle = "None"
    local currentMap = "Unknown"
    local nextTrialMap = "Unknown"
    local timeLeft = "00:00:00"
    local nextTimeLeft = "00:00:00"

    -- Fetch from PlayerDataHandler (Direct MatchmakingTrialData extraction)
    if PlayerDataHandler then
        if typeof(PlayerDataHandler.GetCurrentTrial) == "function" then
            local ok, cur = pcall(function() return PlayerDataHandler:GetCurrentTrial() end)
            if ok and type(cur) == "table" then
                if cur.Title and cur.Title ~= "" then
                    currentTrialTitle = tostring(cur.Title)
                elseif cur.Name and cur.Name ~= "" then
                    currentTrialTitle = tostring(cur.Name)
                end
                if cur.Map and cur.Map ~= "" then
                    currentMap = tostring(cur.Map)
                end
                if cur.TimeRemaining and cur.TimeRemaining ~= "" then
                    timeLeft = tostring(cur.TimeRemaining)
                end
            end
        end

        if typeof(PlayerDataHandler.GetNextTrial) == "function" then
            local ok, nxt = pcall(function() return PlayerDataHandler:GetNextTrial() end)
            if ok and type(nxt) == "table" then
                if nxt.Title and nxt.Title ~= "" then
                    upcomingTrialTitle = tostring(nxt.Title)
                elseif nxt.Name and nxt.Name ~= "" then
                    upcomingTrialTitle = tostring(nxt.Name)
                end
                if nxt.Map and nxt.Map ~= "" then
                    nextTrialMap = tostring(nxt.Map)
                end
                if nxt.TimeRemaining and nxt.TimeRemaining ~= "" then
                    nextTimeLeft = tostring(nxt.TimeRemaining)
                else
                    nextTimeLeft = timeLeft
                end
            end
        end
    end

    -- Fallback to StateReplicators if current title wasn't found
    if currentTrialTitle == "None" then
        pcall(function()
            local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
            local trialsRep = stateReps and stateReps:FindFirstChild("TrialsStateReplicator")
            if trialsRep then
                local gt = trialsRep:GetAttribute("GlobalTrial")
                if gt and tostring(gt) ~= "" and tostring(gt) ~= "None" then
                    currentTrialTitle = tostring(gt)
                end
            end
        end)
    end

    local normalizedCurrent = normalizeString(currentTrialTitle)
    local matchedKey: string? = nil

    for configName in pairs(RevampAutoTrials) do
        if normalizeString(configName) == normalizedCurrent then
            matchedKey = configName
            break
        end
    end

    local finalTrialName = matchedKey or currentTrialTitle

    local normalizedUpcoming = normalizeString(upcomingTrialTitle)
    local matchedNextKey: string? = nil
    for configName in pairs(RevampAutoTrials) do
        if normalizeString(configName) == normalizedUpcoming then
            matchedNextKey = configName
            break
        end
    end
    local finalNextTrialName = matchedNextKey or upcomingTrialTitle

    local pLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local selectedFallback = isPremiumUser and (Globals.SelectedFallback or "None") or "None"

    local isWonTrial = checkIsTrialWon(finalTrialName)
        or (matchedKey and checkIsTrialWon(matchedKey))
        or checkIsTrialWon(currentTrialTitle)
        or (currentMap ~= "Unknown" and checkIsTrialWon(currentMap))
        or false

    local effectiveFallback = selectedFallback
    if selectedFallback == "Smart Auto" then
        effectiveFallback = resolveSmartFallback()
    end

    local result: AnalysisResult = {
        trialName = finalTrialName,
        nextTrialName = finalNextTrialName,
        currentMap = currentMap,
        nextTrialMap = nextTrialMap,
        timeRemaining = timeLeft,
        nextTimeRemaining = nextTimeLeft,
        configFound = (matchedKey ~= nil),
        requiredLevel = 175,
        playerLevel = pLevel,
        levelPassed = false,
        missingTowers = {},
        missingGold = {},
        missingSkills = {},
        isEligible = false,
        isSelectedInFilter = false,
        isOwned = isWonTrial,
        useFallback = false,
        fallbackMode = effectiveFallback,
    }

    local selectedTrials = Globals.SelectedTrials or {}
    if isPremiumUser then
        if type(selectedTrials) == "table" then
            for _, selectedItem in ipairs(selectedTrials) do
                if normalizeString(selectedItem) == normalizedCurrent then
                    result.isSelectedInFilter = true
                    break
                end
            end
        end
    else
        result.isSelectedInFilter = true
    end

    if not matchedKey or not RevampAutoTrials[matchedKey] then
        if isPremiumUser and selectedFallback ~= "None" then
            result.useFallback = true
        end
        return result
    end

    local config = RevampAutoTrials[matchedKey]
    local reqLevel = config.Level or config.level or 175
    result.requiredLevel = reqLevel
    result.levelPassed = (result.playerLevel >= reqLevel)

    -- Golden requirement check
    local missingGold = {}
    local goldReqs = config.Golden or config.golden
    if goldReqs and type(goldReqs) == "table" and #goldReqs > 0 and PlayerDataHandler then
        for _, goldTower in ipairs(goldReqs) do
            if goldTower and goldTower ~= "" and not PlayerDataHandler:IsGoldenOwned(goldTower) then
                table.insert(missingGold, goldTower)
            end
        end
    end

    -- Skill Tree requirement check
    local missingSkills = {}
    local skillReqs = config.SkillTree or config["Skill Tree"] or config.skillTree
    if skillReqs and type(skillReqs) == "table" and next(skillReqs) and PlayerDataHandler then
        local currentSkills = {}
        if type(PlayerDataHandler.GetSkillTree) == "function" then
            pcall(function()
                for _, skill in ipairs(PlayerDataHandler:GetSkillTree()) do
                    currentSkills[skill.Name] = skill.Level
                end
            end)
        end
        for skillName, reqNodeLevel in pairs(skillReqs) do
            local haveLevel = currentSkills[skillName] or 0
            if haveLevel < reqNodeLevel then
                table.insert(missingSkills, string.format("%s (Need %d, Have %d)", skillName, reqNodeLevel, haveLevel))
            end
        end
    end

    -- Towers requirement check across slots
    local towersConfig = config.Towers or config.towers or {}
    local slotKeys = {}
    if type(towersConfig) == "table" then
        if isPremiumUser then
            if towersConfig["Tower Config 2"] then table.insert(slotKeys, "Tower Config 2") end
            if towersConfig["Tower 2"] then table.insert(slotKeys, "Tower 2") end
        end
        if towersConfig["Tower Config 1"] then table.insert(slotKeys, "Tower Config 1") end
        if towersConfig["Tower 1"] then table.insert(slotKeys, "Tower 1") end
        if #slotKeys == 0 and #towersConfig > 0 then
            table.insert(slotKeys, "__array__")
        end
    end

    local function getSlotTowers(sKey)
        if sKey == "__array__" then return towersConfig end
        return towersConfig[sKey]
    end

    local matchedSlot = nil
    local bestMissingTowers = nil
    local bestSlotKey = nil

    for _, sKey in ipairs(slotKeys) do
        local tList = getSlotTowers(sKey)
        if type(tList) == "table" then
            local missing = {}
            if PlayerDataHandler then
                for _, tower in ipairs(tList) do
                    if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                        table.insert(missing, tower)
                    end
                end
            end

            if #missing == 0 then
                matchedSlot = (sKey == "__array__") and "Tower 1" or sKey
                bestMissingTowers = {}
                bestSlotKey = matchedSlot
                break
            else
                if bestMissingTowers == nil or #missing < #bestMissingTowers then
                    bestMissingTowers = missing
                    bestSlotKey = (sKey == "__array__") and "Tower 1" or sKey
                end
            end
        end
    end

    if matchedSlot == nil and bestMissingTowers and #bestMissingTowers > 0 and game.PlaceId == LOBBY_PLACE_ID then
        local boughtAny = attemptBuyMissingTowersList(bestMissingTowers)
        if boughtAny then
            for _, sKey in ipairs(slotKeys) do
                local tList = getSlotTowers(sKey)
                if type(tList) == "table" then
                    local missing = {}
                    if PlayerDataHandler then
                        for _, tower in ipairs(tList) do
                            if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                                table.insert(missing, tower)
                            end
                        end
                    end
                    if #missing == 0 then
                        matchedSlot = (sKey == "__array__") and "Tower 1" or sKey
                        bestMissingTowers = {}
                        bestSlotKey = matchedSlot
                        break
                    else
                        if #missing < #bestMissingTowers then
                            bestMissingTowers = missing
                            bestSlotKey = (sKey == "__array__") and "Tower 1" or sKey
                        end
                    end
                end
            end
        end
    end

    Globals.ActiveTrialSlot = bestSlotKey or "Tower 1"
    result.missingTowers = bestMissingTowers or {}
    result.missingGold = missingGold
    result.missingSkills = missingSkills

    local towersPassed = (matchedSlot ~= nil)
    local goldPassed = (#missingGold == 0)
    local skillsPassed = (#missingSkills == 0)

    result.isEligible = result.levelPassed and towersPassed and goldPassed and skillsPassed

    local isFarmOnlyActive = isPremiumUser and (Globals.FarmOnly == "Farm Only")
    local isOwnedModeActive = isPremiumUser and (Globals.TrialFarmMode == "Progression Mode")

    if not result.isEligible or not result.isSelectedInFilter or (isOwnedModeActive and result.isOwned) then
        if not isFarmOnlyActive and isPremiumUser and selectedFallback ~= "None" then
            result.useFallback = true
        end
    end

    if isFarmOnlyActive then
        result.useFallback = false
    end

    return result
end


--==============================================================================
-- Matchmaking Queue Helpers
--==============================================================================
local lastQueueAttemptTime = 0

local function triggerTrialsQueue(trialName: string)
    if not Globals.AutoTrials or game.PlaceId ~= LOBBY_PLACE_ID then return end

    -- Keyless Ownership Guard (Solo & Multiplayer)
    if not isKeyUser and not isPremiumUser then
        if checkIsTrialWon(trialName) then
            warn(string.format("[ServiceHub AutoTrials] Keyless Mode blocked queue for owned trial: %s (waiting in lobby)", tostring(trialName)))
            return
        end
    end

    if os.time() - lastQueueAttemptTime < 3 then return end
    lastQueueAttemptTime = os.time()

    saveTrialState(trialName)
    saveActiveMode("AutoTrials")

    local isMultiHost = Globals.MultiplayerEnabled and Globals.MultiplayerIsHost
    local partyCount = isMultiHost and 2 or 1

    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if remoteFunction and remoteFunction:IsA("RemoteFunction") then
        pcall(function()
            remoteFunction:InvokeServer("Multiplayer", "v2:stop")
        end)
        task.wait(0.1)
        pcall(function()
            remoteFunction:InvokeServer("Multiplayer", "v2:start", {
                count = partyCount,
                mode = "Trials"
            })
        end)
    end
end

local function triggerFallbackQueue(modeName: string)
    if not isPremiumUser or not Globals.AutoTrials or game.PlaceId ~= LOBBY_PLACE_ID then return end
    if os.time() - lastQueueAttemptTime < 3 then return end
    lastQueueAttemptTime = os.time()

    ensureDynamicHardcoreFallback()

    if modeName == "Smart Auto" then
        modeName = resolveSmartFallback()
    end

    saveTrialState(modeName)
    saveActiveMode("AutoTrials")

    local fallbackModeConfig = FallbackConfigs[modeName]
    local isHardcore = (normalizeString(modeName) == "hardcore")
        or (fallbackModeConfig and fallbackModeConfig.Mode and normalizeString(fallbackModeConfig.Mode) == "hardcore")

    local targetDifficulty = fallbackModeConfig and fallbackModeConfig.Mode or modeName
    if fallbackModeConfig and fallbackModeConfig.Towers and type(fallbackModeConfig.Towers) == "table" then
        local missingFb = {}
        if PlayerDataHandler then
            for _, tower in ipairs(fallbackModeConfig.Towers) do
                if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                    table.insert(missingFb, tower)
                end
            end
        end
        if #missingFb > 0 then
            attemptBuyMissingTowersList(missingFb)
        end
    end

    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if remoteFunction and remoteFunction:IsA("RemoteFunction") then
        pcall(function()
            remoteFunction:InvokeServer("Multiplayer", "v2:stop")
        end)
        task.wait(0.1)
        pcall(function()
            if isHardcore then
                return remoteFunction:InvokeServer("Multiplayer", "v2:start", {
                    difficulty = "Easy",
                    mode = "hardcore",
                    count = 1
                })
            else
                return remoteFunction:InvokeServer("Multiplayer", "v2:start", {
                    difficulty = targetDifficulty,
                    mode = "survival",
                    count = 1
                })
            end
        end)
    end
end

--==============================================================================
-- Forward Declarations
--==============================================================================
local isRequirementLocked = false
local buyingEvoDebounce = false
local refreshDisplay: () -> ()
local handleAutoGoldExecution: () -> ()
local fastQueueLobby: () -> ()
local AutoSkipRunning = false
local StartAutoSkip: () -> ()
local StartAutoGatling: () -> ()
local StartAutoReloadGatling: () -> ()

local staticTrialDefs = {
    { Name = "Broke", Title = "Broke", Map = "Medieval Times" },
    { Name = "Committed", Title = "Committed", Map = "Retro Zone" },
    { Name = "ExplodingEnemies", Title = "Exploding Enemies", Map = "Wrecked Battlefield II" },
    { Name = "FlyingEnemies", Title = "Flying Enemies", Map = "Sacred Mountains" },
    { Name = "Fog", Title = "Fog", Map = "Winter Abyss" },
    { Name = "Glass", Title = "Glass", Map = "Stained Temple" },
    { Name = "HealthyEnemies", Title = "Healthy Enemies", Map = "Four Seasons" },
    { Name = "HiddenEnemies", Title = "Hidden Enemies", Map = "Forgetten Docks" },
    { Name = "Inflation", Title = "Inflation", Map = "Cyber City" },
    { Name = "Jailed", Title = "Jailed", Map = "Night Station" },
    { Name = "Limitation", Title = "Limitation", Map = "Coral Deep" },
    { Name = "MysteryEnemies", Title = "Mystery Enemies", Map = "Winter Bridges" },
    { Name = "Quarantine", Title = "Quarantine", Map = "Dusty Bridges" },
    { Name = "SpeedyEnemies", Title = "Speedy Enemies", Map = "Autumn Falling" },
    { Name = "StunAbuse", Title = "Stun Abuse", Map = "Gilded Path" },
}

local function ensurePlayerData(): ()
    if not PlayerDataHandler and typeof(loadPlayerDataHandler) == "function" then
        pcall(function() PlayerDataHandler = loadPlayerDataHandler() end)
    end
end

local function areAllStaticTrialsWon(): boolean
    if setthreadidentity then pcall(setthreadidentity, 8) end
    for _, tDef in ipairs(staticTrialDefs) do
        if not checkIsTrialWon(tDef.Name) and not checkIsTrialWon(tDef.Title) then
            return false
        end
    end
    return true
end

isCoinTowersMaxed = function(): boolean
    ensurePlayerData()
    if not TowerList or not TowerList.Coins then return true end
    if not PlayerDataHandler or typeof(PlayerDataHandler.IsTowerOwned) ~= "function" then return false end
    for _, t in ipairs(TowerList.Coins) do
        local clean = normalizeString(t.Name)
        if clean ~= "warden" and clean ~= "cowboy" and clean ~= "saboteur" and clean ~= "sabboteur" then
            local owned = false
            pcall(function() owned = PlayerDataHandler:IsTowerOwned(t.Name) end)
            if not owned then
                return false
            end
        end
    end
    return true
end

isGemTowersMaxed = function(): boolean
    ensurePlayerData()
    if not TowerList or not TowerList.Gems then return true end
    if not PlayerDataHandler or typeof(PlayerDataHandler.IsTowerOwned) ~= "function" then return false end
    for _, t in ipairs(TowerList.Gems) do
        local owned = false
        pcall(function() owned = PlayerDataHandler:IsTowerOwned(t.Name) end)
        if not owned then
            return false
        end
    end
    return true
end

isEvoTowersMaxed = function(): boolean
    ensurePlayerData()
    if not TowerList or not TowerList.Evo then return true end
    if not PlayerDataHandler or typeof(PlayerDataHandler.IsTowerOwned) ~= "function" then return false end
    for _, e in ipairs(TowerList.Evo) do
        local owned = false
        pcall(function()
            if PlayerDataHandler:IsTowerOwned(e.Name) then
                owned = true
            elseif typeof(isTowerEvoComplete) == "function" then
                local baseName = EvoToTower[e.Name] or e.Name:gsub("^Evolved", "")
                if isTowerEvoComplete(e.Name) or isTowerEvoComplete(baseName) then
                    owned = true
                end
            end
        end)
        if not owned then
            return false
        end
    end
    return true
end

isGoldenSkinsMaxed = function(): boolean
    ensurePlayerData()
    if not TowerList or not TowerList.Golden then return true end
    if not PlayerDataHandler or typeof(PlayerDataHandler.IsGoldenOwned) ~= "function" then return false end
    for _, g in ipairs(TowerList.Golden) do
        local base = g.Name:gsub("^Golden%s+", "")
        local owned = false
        pcall(function()
            owned = PlayerDataHandler:IsGoldenOwned(g.Name) or PlayerDataHandler:IsGoldenOwned(base)
        end)
        if not owned then
            return false
        end
    end
    return true
end

local SkillNameToId = {
    ["Enhanced Optics"] = "1",
    ["Resourcefulness"] = "2",
    ["Fortify"] = "3",
    ["Over-Heal"] = "4",
    ["Fight Dirty"] = "5",
    ["Extreme Conditioning"] = "6",
    ["Stonks"] = "7",
    ["Expanded Barracks"] = "8",
    ["Improved Gunpowder"] = "9",
    ["Beefed Up Minions"] = "10",
    ["Precision"] = "11",
    ["Scavenger"] = "12",
    ["Accelerator"] = "13",
    ["Re-enforcements"] = "14",
    ["Bigger Budget"] = "15",
    ["Bandages"] = "16",
    ["Scholar"] = "17",
}

local function parseSkillInfo(sk: any, fallbackId: number?): { Id: string, Name: string, Level: number, MaxLevel: number, IsMaxed: boolean, LevelFormatted: string }
    local SkillDefinitions = {
        [1]  = { Name = "Enhanced Optics",      MaxLevel = 20 },
        [2]  = { Name = "Resourcefulness",       MaxLevel = 25 },
        [3]  = { Name = "Fortify",               MaxLevel = 40 },
        [4]  = { Name = "Over-Heal",             MaxLevel = 25 },
        [5]  = { Name = "Fight Dirty",           MaxLevel = 25 },
        [6]  = { Name = "Extreme Conditioning",  MaxLevel = 25 },
        [7]  = { Name = "Stonks",                MaxLevel = 20 },
        [8]  = { Name = "Expanded Barracks",     MaxLevel = 20 },
        [9]  = { Name = "Improved Gunpowder",    MaxLevel = 25 },
        [10] = { Name = "Beefed Up Minions",     MaxLevel = 25 },
        [11] = { Name = "Precision",             MaxLevel = 15 },
        [12] = { Name = "Scavenger",             MaxLevel = 20 },
        [13] = { Name = "Accelerator",           MaxLevel = 25 },
        [14] = { Name = "Re-enforcements",       MaxLevel = 10 },
        [15] = { Name = "Bigger Budget",         MaxLevel = 25 },
        [16] = { Name = "Bandages",              MaxLevel = 25 },
        [17] = { Name = "Scholar",               MaxLevel = 20 },
    }
    local idNum = (sk and tonumber(sk.Id)) or fallbackId or 1
    local def = SkillDefinitions[idNum] or { Name = "Skill #" .. tostring(idNum), MaxLevel = 25 }
    local name = (sk and sk.Name) or def.Name
    local curLvl = (sk and tonumber(sk.Level)) or 0
    local maxLvl = (sk and tonumber(sk.MaxLevel)) or def.MaxLevel
    local fmt = sk and tostring(sk.LevelFormatted or "") or ""
    local upperFmt = string.upper(fmt)

    local curMatch, maxMatch = fmt:match("(%d+)%s*/%s*(%d+)")
    if curMatch and maxMatch then
        curLvl = tonumber(curMatch) or curLvl
        maxLvl = tonumber(maxMatch) or maxLvl
    elseif upperFmt:find("MAX") then
        local numInFmt = upperFmt:match("(%d+)")
        if numInFmt then
            maxLvl = tonumber(numInFmt) or maxLvl
            curLvl = maxLvl
        else
            curLvl = maxLvl
        end
    end

    local isMaxed = false
    if sk and sk.IsMaxed == true then
        isMaxed = true
    elseif upperFmt:find("MAX") then
        isMaxed = true
    elseif curLvl >= maxLvl then
        isMaxed = true
    end

    if isMaxed and curLvl < maxLvl then
        curLvl = maxLvl
    end

    return {
        Id = tostring(idNum),
        Name = name,
        Level = curLvl,
        MaxLevel = maxLvl,
        IsMaxed = isMaxed,
        LevelFormatted = isMaxed and ("MAX" .. tostring(maxLvl)) or string.format("%d/%d", curLvl, maxLvl),
    }
end

isSkillTreeMaxed = function(): boolean
    ensurePlayerData()
    if not PlayerDataHandler or typeof(PlayerDataHandler.GetSkillTree) ~= "function" then return false end
    local skills = nil
    pcall(function() skills = PlayerDataHandler:GetSkillTree() end)
    if not skills or #skills == 0 then return false end

    local skillMap = {}
    for _, sk in ipairs(skills) do
        local idNum = tonumber(sk.Id)
        if not idNum and sk.Name and SkillNameToId[sk.Name] then
            idNum = tonumber(SkillNameToId[sk.Name])
        end
        if idNum then
            skillMap[idNum] = parseSkillInfo(sk, idNum)
        end
    end

    for id = 1, 17 do
        local info = skillMap[id] or parseSkillInfo(nil, id)
        if not info.IsMaxed then
            return false
        end
    end
    return true
end

areSelectedPrioritiesMaxed = function(): boolean
    local hasCoins = Globals.BuyMissingCoinsTower == true
    local hasGems = Globals.BuyMissingGemTower == true
    local hasEvo = Globals.BuyMissingEvoTower == true
    local hasGold = Globals.BuyMissingGoldSkins == true
    local hasSkill = Globals.BuySkillTree == true

    local anyToggleActive = hasCoins or hasGems or hasEvo or hasGold or hasSkill

    if anyToggleActive then
        if hasCoins and not isCoinTowersMaxed() then return false end
        if hasGems and not isGemTowersMaxed() then return false end
        if hasEvo and not isEvoTowersMaxed() then return false end
        if hasGold and not isGoldenSkinsMaxed() then return false end
        if hasSkill and not isSkillTreeMaxed() then return false end
        return true
    else
        return isCoinTowersMaxed() and isGemTowersMaxed() and isEvoTowersMaxed() and isGoldenSkinsMaxed() and isSkillTreeMaxed()
    end
end

checkIsEverythingMaxed = function(): boolean
    if setthreadidentity then pcall(setthreadidentity, 8) end
    ensurePlayerData()

    local analysis = analyzeCurrentTrial()
    local isCurTrialOwned = areAllStaticTrialsWon() or analysis.isOwned or checkIsTrialWon(analysis.trialName)
    if not isCurTrialOwned then
        return false
    end

    return areSelectedPrioritiesMaxed()
end

local function evaluateOwnedModeAction(analysis: AnalysisResult): (string, string?, string?, string?)
    ensurePlayerData()
    ensureDynamicHardcoreFallback()

    -- 0. Check unowned trial in rotation: if eligible and in filter, beat it first
    if analysis.isSelectedInFilter and not analysis.isOwned and analysis.isEligible and not isRequirementLocked then
        return "BeatUnownedTrial", analysis.trialName, nil, nil
    end

    -- Priority progression sequence:
    -- Coin tower > Hardcore tower > Evo Tower > Gold Crates / skin > Skill tree
    -- Rule: "it will not move to next if Coin towers are not yet owned all"

    local coinTowersDone = (typeof(isCoinTowersMaxed) == "function") and isCoinTowersMaxed() or false

    -- If Coin towers are NOT all owned:
    -- It will NOT move to next (Hardcore tower, Evo Tower, Gold Crates, or Skill tree)!
    if not coinTowersDone then
        if Globals.BuyMissingCoinsTower or Globals.BuyMissingGemTower or Globals.BuyMissingEvoTower or Globals.BuyMissingGoldSkins or Globals.BuySkillTree then
            local stratChoice = resolveCoinFarmFallback and resolveCoinFarmFallback() or "Molten"
            return "FarmCoins", stratChoice, "Coins", nil
        end
        if isPremiumUser and (analysis.useFallback or analysis.isOwned) and analysis.fallbackMode ~= "None" then
            local fbMode = analysis.fallbackMode
            if fbMode == "Smart Auto" then
                fbMode = resolveCoinFarmFallback and resolveCoinFarmFallback() or "Molten"
            end
            return "Fallback", fbMode, nil, nil
        end
        return "IdleWaiting", nil, nil, nil
    end

    -- From here, Coin towers are confirmed ALL OWNED!
    -- 1. Coin tower priority is completed.

    -- 2. Priority: Buy missing gem tower (Hardcore Towers)
    if Globals.BuyMissingGemTower and not isGemTowersMaxed() then
        return "FarmGems", "Lose", "Gems", nil
    end

    -- 3. Priority: Buy missing Evo tower
    if Globals.BuyMissingEvoTower and not isEvoTowersMaxed() then
        local evoAnalysis = (typeof(analyzeAutoEvoRequirements) == "function") and analyzeAutoEvoRequirements() or nil
        if evoAnalysis then
            if evoAnalysis.readyToBuy then
                return "EvoReadyInLobby", evoAnalysis.activeTower, nil, nil
            else
                local needType = evoAnalysis.farmType or "Coins"
                local stratChoice = (needType == "Gems") and "Lose" or "Win"
                return "FarmEvo", stratChoice, needType, evoAnalysis.activeTower
            end
        end
    end

    -- 4. Priority: Buy missing Gold skins (50,000 Coins)
    if Globals.BuyMissingGoldSkins and not isGoldenSkinsMaxed() then
        local stratChoice = resolveCoinFarmFallback and resolveCoinFarmFallback() or "Molten"
        return "FarmGoldSkins", stratChoice, "Coins", nil
    end

    -- 5. Priority: Buy Skill tree (Sequential ID 1 to 17)
    if Globals.BuySkillTree and not isSkillTreeMaxed() then
        local stratChoice = resolveCoinFarmFallback and resolveCoinFarmFallback() or "Molten"
        return "FarmSkillTree", stratChoice, "Coins", nil
    end

    -- If all selected priorities are maxed, use chosen fallback (defaults to Hardcore if Smart Auto):
    if areSelectedPrioritiesMaxed() or checkIsEverythingMaxed() then
        if isPremiumUser then
            local fbMode = analysis.fallbackMode
            if fbMode == "Smart Auto" then
                fbMode = "Hardcore"
            end
            if fbMode and fbMode ~= "None" then
                return "Fallback", fbMode, nil, nil
            end
            return "Fallback", "Hardcore", nil, nil
        end
    end

    -- If no priority action triggered, check fallback:
    if isPremiumUser and (analysis.useFallback or analysis.isOwned) and analysis.fallbackMode ~= "None" then
        local fbMode = analysis.fallbackMode
        if fbMode == "Smart Auto" then
            fbMode = resolveSmartFallback()
        end
        return "Fallback", fbMode, nil, nil
    end

    return "IdleWaiting", nil, nil, nil
end

--==============================================================================
-- Shop & Skill Tree Auto-Purchasing Engine (Progression Mode Priority System)
--==============================================================================
local function getNextUnmaxedSkill(): (string?, string?, number?, number?)
    ensurePlayerData()
    local skillList = (PlayerDataHandler and typeof(PlayerDataHandler.GetSkillTree) == "function") and PlayerDataHandler:GetSkillTree() or {}
    local skillMap = {}
    if skillList and #skillList > 0 then
        for _, sk in ipairs(skillList) do
            local idNum = tonumber(sk.Id)
            if not idNum and sk.Name and SkillNameToId[sk.Name] then
                idNum = tonumber(SkillNameToId[sk.Name])
            end
            if idNum then
                skillMap[idNum] = parseSkillInfo(sk, idNum)
            end
        end
    end

    -- Strictly start at ID 1. If maxed, move to ID 2, then ID 3, ..., up to ID 17
    for id = 1, 17 do
        local skInfo = skillMap[id] or parseSkillInfo(nil, id)
        if not skInfo.IsMaxed then
            return tostring(id), skInfo.Name, skInfo.Level, skInfo.MaxLevel
        end
    end

    return nil, nil, nil, nil
end

local processAutoPurchases: () -> ()
do
    local lastTowerPurchaseTime = 0
    local lastHardcorePurchaseTime = 0
    local lastEvoPurchaseTime = 0
    local lastGoldSkinPurchaseTime = 0
    local lastSkillPurchaseTime = 0
    local lastProcessAutoPurchasesTime = 0

    processAutoPurchases = function()
    if not isPremiumUser or not Globals.AutoTrials or game.PlaceId ~= LOBBY_PLACE_ID then return end
    local anyPurchaseToggle = Globals.BuyMissingCoinsTower or Globals.BuyMissingGemTower or Globals.BuyMissingEvoTower or Globals.BuyMissingGoldSkins or Globals.BuySkillTree
    if Globals.TrialFarmMode ~= "Progression Mode" and not anyPurchaseToggle then return end

    local now = os.time()
    if now - lastProcessAutoPurchasesTime < 5 then return end
    lastProcessAutoPurchasesTime = now

    ensurePlayerData()
    if not PlayerDataHandler then return end
    local playerCoins = 0
    local playerGems = 0
    pcall(function()
        if typeof(PlayerDataHandler.GetCoins) == "function" then
            playerCoins = PlayerDataHandler:GetCoins() or 0
        end
        if typeof(PlayerDataHandler.GetGems) == "function" then
            playerGems = PlayerDataHandler:GetGems() or 0
        end
    end)

    local isOwnedActive = (Globals.TrialFarmMode == "Progression Mode")

    -- Priority completion checks:
    local coinTowersDone = (typeof(isCoinTowersMaxed) == "function") and isCoinTowersMaxed() or false
    local gemTowersDone = (typeof(isGemTowersMaxed) == "function") and isGemTowersMaxed() or false
    local evoTowersDone = (typeof(isEvoTowersMaxed) == "function") and isEvoTowersMaxed() or false
    local goldSkinsDone = (typeof(isGoldenSkinsMaxed) == "function") and isGoldenSkinsMaxed() or false
    local skillTreeDone = (typeof(isSkillTreeMaxed) == "function") and isSkillTreeMaxed() or false

    local anyPurchased = false

    -- 1. Priority: Buy missing coins tower
    if (Globals.BuyMissingCoinsTower or isOwnedActive) and not coinTowersDone then
        if Globals.BuyMissingCoinsTower and (now - lastTowerPurchaseTime >= 3) and TowerList and TowerList.Coins then
            local targetTowerToBuy = nil
            local targetTowerCost = 0
            for _, t in ipairs(TowerList.Coins) do
                local clean = normalizeString(t.Name)
                if clean ~= "warden" and clean ~= "cowboy" and clean ~= "saboteur" and clean ~= "sabboteur" then
                    local isOwned = false
                    pcall(function() isOwned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                    if not isOwned then
                        local cost = tonumber(t.Cost) or 0
                        if playerCoins >= cost then
                            targetTowerToBuy = t.Name
                            targetTowerCost = cost
                            break
                        end
                    end
                end
            end

            if targetTowerToBuy then
                lastTowerPurchaseTime = now
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if rf and rf:IsA("RemoteFunction") then
                        rf:InvokeServer("Shop", "Purchase", "Tower", targetTowerToBuy)
                        anyPurchased = true
                        logActivity(string.format("[Auto Buy] Purchased coin tower '%s' (%s Coins)", targetTowerToBuy, formatNumberWithCommas(targetTowerCost)), "success")
                        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                            UI.Window:Notify({
                                Title = "Tower Purchased",
                                Desc = string.format("Purchased %s for %s Coins!", targetTowerToBuy, formatNumberWithCommas(targetTowerCost)),
                                Duration = 4,
                                Type = "success"
                            })
                        end
                    end
                end)
            end
        end
        -- STRICT PRIORITY: Coin towers are not yet all owned -> do not proceed to later priorities (Gems, Evo, Gold, Skill Tree)
        return
    end

    -- 2. Priority: Buy missing gem tower (Hardcore Towers)
    -- Coin towers are confirmed completed.
    if (Globals.BuyMissingGemTower or isOwnedActive) and not gemTowersDone then
        if Globals.BuyMissingGemTower and (now - lastHardcorePurchaseTime >= 3) and TowerList and TowerList.Gems then
            local targetHcToBuy = nil
            local targetHcCost = 0
            for _, t in ipairs(TowerList.Gems) do
                local isOwned = false
                pcall(function() isOwned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                if not isOwned then
                    local cost = tonumber(t.Cost) or 0
                    if playerGems >= cost then
                        targetHcToBuy = t.Name
                        targetHcCost = cost
                        break
                    end
                end
            end

            if targetHcToBuy then
                lastHardcorePurchaseTime = now
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if rf and rf:IsA("RemoteFunction") then
                        rf:InvokeServer("Shop", "Purchase", "Tower", targetHcToBuy)
                        anyPurchased = true
                        logActivity(string.format("[Auto Buy] Purchased hardcore tower '%s' (%s Gems)", targetHcToBuy, formatNumberWithCommas(targetHcCost)), "success")
                        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                            UI.Window:Notify({
                                Title = "Hardcore Tower Purchased",
                                Desc = string.format("Purchased %s for %s Gems!", targetHcToBuy, formatNumberWithCommas(targetHcCost)),
                                Duration = 4,
                                Type = "success"
                            })
                        end
                    end
                end)
            end
        end
        -- STRICT PRIORITY: Gem towers are not yet all owned -> do not proceed to later priorities (Evo, Gold, Skill Tree)
        return
    end

    -- 3. Priority: Buy missing Evo tower
    -- Coin towers AND Gem towers are confirmed completed.
    if (Globals.BuyMissingEvoTower or isOwnedActive) and not evoTowersDone then
        if Globals.BuyMissingEvoTower and (now - lastEvoPurchaseTime >= 4) and TowerList and TowerList.Evo then
            local targetEvoToBuy = nil
            local targetBaseTower = nil
            for _, e in ipairs(TowerList.Evo) do
                local isOwned = false
                pcall(function()
                    if PlayerDataHandler:IsTowerOwned(e.Name) then
                        isOwned = true
                    elseif typeof(isTowerEvoComplete) == "function" then
                        local base = EvoToTower[e.Name] or e.Name:gsub("^Evolved", "")
                        if isTowerEvoComplete(e.Name) or isTowerEvoComplete(base) then
                            isOwned = true
                        end
                    end
                end)
                if not isOwned then
                    local base = EvoToTower[e.Name] or e.Name:gsub("^Evolved", "")
                    local expData = nil
                    if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                        pcall(function() expData = PlayerDataHandler:GetTowerExp(base) end)
                    end
                    local lvl = (expData and type(expData.Level) == "number") and expData.Level or 0
                    local reqCoins = tonumber(e.Coins) or 15000
                    local reqGems = tonumber(e.Gems) or 4500
                    if lvl >= 20 and playerCoins >= reqCoins and playerGems >= reqGems then
                        targetEvoToBuy = e.Name
                        targetBaseTower = base
                        break
                    else
                        -- Strict sequential progression: First unowned tower must reach Level 20 and evolve before moving to the next!
                        break
                    end
                end
            end

            if targetBaseTower then
                lastEvoPurchaseTime = now
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if rf and rf:IsA("RemoteFunction") then
                        if typeof(sendEvoPurchaseWebhook) == "function" then
                            pcall(sendEvoPurchaseWebhook, targetBaseTower, targetEvoToBuy)
                        end
                        rf:InvokeServer("Shop", "EvolveTower", targetBaseTower)
                        anyPurchased = true
                        logActivity(string.format("[Auto Buy] Evolved tower '%s' into '%s'!", targetBaseTower, targetEvoToBuy), "success")
                        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                            UI.Window:Notify({
                                Title = "Tower Evolved",
                                Desc = string.format("Successfully evolved %s!", targetBaseTower),
                                Duration = 5,
                                Type = "success"
                            })
                        end
                    end
                end)
            end
        end
        -- STRICT PRIORITY: Evo towers are not yet all completed -> do not proceed to Gold Crates or Skill Tree
        return
    end

    -- 4. Priority: Buy missing Gold skins (50,000 Coins)
    -- Coin towers, Gem towers, AND Evo towers are confirmed completed.
    if (Globals.BuyMissingGoldSkins or isOwnedActive) and not goldSkinsDone then
        if Globals.BuyMissingGoldSkins and (now - lastGoldSkinPurchaseTime >= 5) and TowerList and TowerList.Golden then
            local hasUnownedGold = false
            for _, g in ipairs(TowerList.Golden) do
                local base = g.Name:gsub("^Golden%s+", "")
                local isOwned = false
                pcall(function()
                    isOwned = PlayerDataHandler:IsGoldenOwned(g.Name) or PlayerDataHandler:IsGoldenOwned(base)
                end)
                if not isOwned then
                    hasUnownedGold = true
                    break
                end
            end

            if hasUnownedGold and playerCoins >= 50000 then
                lastGoldSkinPurchaseTime = now
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if rf and rf:IsA("RemoteFunction") then
                        rf:InvokeServer("Shop", "Purchase", "Crate", "Golden Crate")
                        task.wait(0.5)
                        rf:InvokeServer("Shop", "Open", "Crate", "Golden Crate")
                        anyPurchased = true
                        logActivity("[Auto Buy] Purchased & opened Golden Crate (50,000 Coins)", "success")
                        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                            UI.Window:Notify({
                                Title = "Golden Crate Purchased",
                                Desc = "Purchased and opened Golden Crate for 50,000 Coins!",
                                Duration = 5,
                                Type = "success"
                            })
                        end
                    end
                end)
            end
        end
        -- STRICT PRIORITY: Gold skins are not yet maxed (need 50,000 coins) -> do not spend coins on Skill Tree!
        return
    end

    -- 5. Priority: Buy Skill tree (Strictly Sequential ID 1 to 17) - AT THE VERY LAST!
    -- Coin towers, Gem towers, Evo towers, AND Gold skins MUST ALL BE COMPLETED before Skill Tree can spend coins!
    if Globals.BuySkillTree and not skillTreeDone and (now - lastSkillPurchaseTime >= 3) then
        local nextId, nextName, nextLvl, maxLvl = getNextUnmaxedSkill()
        if nextId then
            lastSkillPurchaseTime = now
            pcall(function()
                local net = ReplicatedStorage:FindFirstChild("Network")
                local skills = net and net:FindFirstChild("Skills")
                local rf = skills and skills:FindFirstChild("RF:Purchase")
                if rf and rf:IsA("RemoteFunction") then
                    rf:InvokeServer(tostring(nextId))
                    anyPurchased = true
                    local targetLvl = (nextLvl or 0) + 1
                    local totalMax = maxLvl or 20
                    logActivity(string.format("[Auto Buy] Upgraded Skill '%s' (ID %s, Lvl %d/%d)", nextName, nextId, targetLvl, totalMax), "success")
                    if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                        UI.Window:Notify({
                            Title = "Skill Upgraded",
                            Desc = string.format("Upgraded %s (ID %s: %d/%d)!", nextName, nextId, targetLvl, totalMax),
                            Duration = 4,
                            Type = "success"
                        })
                    end
                end
            end)
        end
    end

    if anyPurchased then
        task.wait(0.5)
        pcall(function()
            if PlayerDataHandler and typeof(PlayerDataHandler.GetTowers) == "function" then
                PlayerDataHandler:GetTowers()
            end
        end)
    end
    end
end

--==============================================================================
-- Build User Interface (Auto Trials V9)
--==============================================================================
local coinsTrackerLabel: any = nil
local gemsTrackerLabel: any = nil

local function buildInterface()
    if setthreadidentity then pcall(setthreadidentity, 8) end
    pcall(function()
        local getParent = function()
            if gethui then
                local ok, h = pcall(gethui)
                if ok and h then return h end
            end
            local ok, parent = pcall(function() return game:GetService("CoreGui") end)
            if ok and parent then return parent end
            return LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        end
        local parentGui = getParent()
        if parentGui then
            for _, name in ipairs({ "ServiceHub_Window", "CyberNeon_Window", "SkyBlueUI_Window" }) do
                local old = parentGui:FindFirstChild(name)
                if old then pcall(function() old:Destroy() end) end
            end
        end
        local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, name in ipairs({ "ServiceHub_Window", "CyberNeon_Window", "SkyBlueUI_Window" }) do
                local old = pg:FindFirstChild(name)
                if old then pcall(function() old:Destroy() end) end
            end
        end
    end)

    local executorName = "Unknown Executor"
    if identifyexecutor then
        executorName = identifyexecutor()
    elseif syn then
        executorName = "Synapse X"
    elseif KRNL_LOADED then
        executorName = "KRNL"
    elseif fluxus then
        executorName = "Fluxus"
    end

    local Window = UILibrary:Window({
        Name = "ServiceHub_Window",
        Title = "Service Hub v9.8 [Optimized]",
        Subtitle = (game.PlaceId == LOBBY_PLACE_ID) and "LOBBY : Idle / Queuing" or "IN GAME : Active Strategy",
        Icon = "Logo",
        BorderAnimation = false,       -- Mobile Optimization: Stops 60 FPS RenderStepped border rotation
        BackgroundAnimation = false,   -- Mobile Optimization: Stops 60 FPS RenderStepped gradient wave
        Keybind = Enum.KeyCode.RightShift,
        Theme = "SkyBlue",
    })
    UI.Window = Window
    UI.ScreenGui = Window.ScreenGui
    Globals.ServiceHub_ScreenGui = UI.ScreenGui

    local keyTierText = isPremiumUser and "PREMIUM" or (isKeyUser and "KEY" or "KEYLESS")
    local timeRemainingText = formatTimeRemaining()

    Window:UserProfile({
        Username = LocalPlayer.Name,
        Badge = keyTierText,
        TimeLeft = timeRemainingText,
        AvatarId = LocalPlayer.UserId,
    })

    -- =================== Overview Tab ===================
    local OverviewTab = Window:Tab({
        Title = "Overview",
        Subtitle = "System & Player Dashboard",
        Icon = "Home",
    })

    OverviewTab:Banner({
        Type = isPremiumUser and "Success" or "Info",
        Title = isPremiumUser and "Auto Trials V9.5 • Premium Active" or (isKeyUser and "Auto Trials V9.5 • Key Mode" or "Auto Trials V9.5 • Keyless Mode"),
        Desc = isPremiumUser and "Full VIP automation active. Multi-trial queues, smart rematching, and auto evolutions ready."
            or (isKeyUser and "Key Mode runs eligible trials repeatedly using the classic trial-only loop."
                or "Keyless Mode clears eligible unowned trials once, then waits for the next rotation.")
    })

    UI.OverviewGrid = OverviewTab:MetricGrid({
        Cols = 3,
        Items = {
            { Title = "ACCESS TIER", Value = keyTierText, Trend = isPremiumUser and "VIP" or (isKeyUser and "KEY" or "KEYLESS") },
            { Title = "LOCATION", Value = (game.PlaceId == LOBBY_PLACE_ID) and "LOBBY" or "MATCH", Sub = (game.PlaceId == LOBBY_PLACE_ID) and "Idle / Queue" or "In Game" },
            { Title = "EXECUTOR", Value = executorName:sub(1, 10), Sub = "Verified" },
        }
    })

    OverviewTab:Divider({ Height = 8 })

    UI.CurrencyGrid = OverviewTab:MetricGrid({
        Cols = 2,
        Items = {
            { Title = "USER CURRENT COINS", Value = "0 / 0", Sub = "Current / Target Coins" },
            { Title = "USER CURRENT GEMS", Value = "0 / 0", Sub = "Current / Target Gems" },
        }
    })

    OverviewTab:Divider({ Height = 10 })

    local SessionSection = OverviewTab:Section({ Title = "Session Information", Order = 1 })

    coinsTrackerLabel = SessionSection:Label({ Title = "User Current Coins", Desc = "0 / 0", Image = "Coins" })
    gemsTrackerLabel = SessionSection:Label({ Title = "User Current Gems", Desc = "0 / 0", Image = "Gem" })

    SessionSection:Label({ Title = "Username", Desc = LocalPlayer.Name, Image = "User" })
    SessionSection:Label({ Title = "Description", Desc = "Active Service Hub v9.8 session (Cloud Loadstring Edition)", Image = "Terminal" })
    SessionSection:Label({ Title = "Access", Desc = isPremiumUser and "Premium Active" or (isKeyUser and "Key Mode Active" or "Keyless Mode Active"), Image = "Key" })
    SessionSection:Label({ Title = "Session Expiry", Desc = tostring(Globals.JD_EXPIRES_AT or "Never / Permanent"), Image = "Clock" })

    SessionSection:Button({
        Title = "Buy Key / Upgrade",
        Desc = "Purchase or renew your premium access",
        Image = "Globe",
        Callback = function()
            if setclipboard then
                setclipboard("https://yourshoplink.com")
                Window:Notify({ Title = "Link Copied", Desc = "Store link copied to clipboard!", Duration = 2 })
            end
        end
    })

    SessionSection:Button({
        Title = "Discord Community",
        Desc = "Join our community for updates and support",
        Image = "Chat",
        Callback = function()
            if setclipboard then
                setclipboard("https://discord.gg/yourinvite")
                Window:Notify({ Title = "Link Copied", Desc = "Discord invite copied to clipboard!", Duration = 2 })
            end
        end
    })

    local LicenseSection = OverviewTab:Section({ Title = "Access Tiers", Order = 2 })

    LicenseSection:SelectionBox({
        Selections = { "Keyless", "Key", "Premium" },
        Value = isPremiumUser and "Premium" or (isKeyUser and "Key" or "Keyless"),
        Descriptions = {
            ["Keyless"] = "unowned trials only",
            ["Key"] = "classic repeat-trial mode",
            ["Premium"] = "full automation access"
        },
        Checklist = {
            ["Keyless"] = { "Queues eligible unowned trials", "Waits in lobby after a trial is owned", "No key required" },
            ["Key"] = { "Valid standard or Premium key required", "Classic trial-only automation", "Repeats eligible owned trials" },
            ["Premium"] = { "Multi-trial filters and fallbacks", "Progression Mode and auto-purchases", "Multiplayer Mode and instant rematching" }
        },
        ButtonTexts = { ["Keyless"] = "Use Keyless", ["Key"] = "Enter Key", ["Premium"] = "Get Premium" },
        Callbacks = {
            ["Keyless"] = function()
                isKeyUser = false
                isPremiumUser = false
                Globals.SCRIPT_KEY = nil
                SetSetting("PreferredAccessTier", "Keyless")
                Window:Notify({ Title = "Keyless Mode", Desc = "Switched to Keyless Mode. Runs unowned trials only.", Duration = 3 })
                task.defer(function()
                    pcall(function()
                        if UI.ScreenGui then UI.ScreenGui:Destroy() end
                    end)
                    task.wait(0.1)
                    pcall(function()
                        if setthreadidentity then pcall(setthreadidentity, 8) end
                        buildInterface()
                    end)
                end)
            end,
            ["Key"] = function()
                local savedKey = loadVerifiedKey()
                if savedKey and #savedKey > 0 and not isKeyUser then
                    Window:Notify({ Title = "Auto Loading Key", Desc = "Attempting to auto-load saved key...", Duration = 2 })
                    task.spawn(function()
                        local Junkie = getJunkieSDK()
                        if Junkie then
                            local ok, result = pcall(function() return Junkie.check_key(savedKey) end)
                            if ok and result and result.valid then
                                saveVerifiedKey(savedKey)
                                Globals.SCRIPT_KEY = savedKey
                                Globals.IS_JD_PREMIUM = (result.is_premium == true or result.premium == true)
                                Globals.JD_EXPIRES_AT = result.expires_at or result.expiresAt
                                isKeyUser = true
                                isPremiumUser = (Globals.IS_JD_PREMIUM == true)
                                SetSetting("PreferredAccessTier", isPremiumUser and "Premium" or "Key")
                                Window:Notify({ Title = "Key Validated", Desc = isPremiumUser and "Premium status unlocked!" or "Standard Key Mode unlocked! (Farms current trial repeatedly)", Duration = 3 })
                                task.defer(function()
                                    pcall(function() if UI.ScreenGui then UI.ScreenGui:Destroy() end end)
                                    task.wait(0.1)
                                    pcall(function()
                                        if setthreadidentity then pcall(setthreadidentity, 8) end
                                        buildInterface()
                                    end)
                                end)
                                return
                            end
                        end
                        Window:Notify({ Title = "Key Required", Desc = "Open the Key tab to enter your standard or Premium key.", Duration = 3 })
                    end)
                else
                    Window:Notify({ Title = "Key Required", Desc = "Open the Key tab and enter a valid standard or Premium key.", Duration = 3 })
                end
            end,
            ["Premium"] = function()
                if setclipboard then setclipboard("https://yourshoplink.com"); Window:Notify({ Title = "Link Copied", Desc = "Premium shop link copied to clipboard! Enter your key in the Key tab.", Duration = 3 }) end
            end
        }
    })

    local SystemSection = OverviewTab:Section({ Title = "System Information", Order = 3 })
    SystemSection:Label({ Title = "Detected Executor", Desc = executorName, Image = "Terminal" })

    -- =================== Farm Tab ===================
    local FarmTab = Window:Tab({
        Title = "Farm",
        Subtitle = "Trial & Fallback Farming",
        Icon = "Repeat",
    })

    local FarmSec = FarmTab:Section({ Title = "Farm Controls" })

    local farmToggleTitle = isPremiumUser and "Enable Farm Mode" or (isKeyUser and "Enable Auto Trials (Repeat Mode)" or "Enable Auto Trials (Keyless Mode)")
    local farmToggleDesc = isPremiumUser and "Continuously farm selected trials and fallback modes" or (isKeyUser and "Repeats current eligible trials continuously (Key Mode)" or "Farms eligible unowned trials only; waits when already owned (Keyless)")

    local isInitializingFarm = true
    local farmToggle = FarmSec:Toggle({
        Title = farmToggleTitle,
        Desc = farmToggleDesc,
        Value = (Globals.AutoTrials == true and Globals.TrialFarmMode ~= "Progression Mode"),
        Callback = RunAsExecutor(function(val)
            if isInitializingFarm then return end
            if isRequirementLocked and val then
                if UI.FarmToggle then UI.FarmToggle:SetValue(false) end
                Window:Notify({ Title = "REQUIREMENT LOCKED", Desc = "Level/Towers required!", Duration = 4 })
                return
            end

            if val then
                -- Mutual exclusion: turn off Progression and Auto Evo so they don't override
                if UI.ProgressionToggle then
                    pcall(function() UI.ProgressionToggle:SetValue(false) end)
                end
                if UI.AutoEvoToggle then
                    pcall(function() UI.AutoEvoToggle:SetValue(false) end)
                end
                if UI.AutoGoldToggle and Globals.AutoGold then
                    pcall(function() UI.AutoGoldToggle:SetValue(false) end)
                end

                Globals.TrialFarmMode = "Farm Mode"
                Globals.AutoTrials = true
                Globals.AutoEvo = false
                Globals.AutoGold = false
                SetSetting("TrialFarmMode", "Farm Mode")
                SetSetting("AutoTrials", true)
                SetSetting("AutoEvo", false)
                SetSetting("AutoGold", false)
                currentMatchMode = "AutoTrials"

                local modeMsg = isPremiumUser and "Farm Mode: ENABLED" or (isKeyUser and "Key Mode: ENABLED (Repeat Trials)" or "Keyless Mode: ENABLED (Unowned Trials Only)")
                logActivity(modeMsg, "success")

                if game.PlaceId == LOBBY_PLACE_ID then
                    task.spawn(fastQueueLobby)
                else
                    Globals.IsConfigDirty = true
                end
            else
                Globals.AutoTrials = false
                SetSetting("AutoTrials", false)
                local modeMsg = isPremiumUser and "Farm Mode: DISABLED" or (isKeyUser and "Key Mode: DISABLED" or "Keyless Mode: DISABLED")
                logActivity(modeMsg, "warn")
                if game.PlaceId == LOBBY_PLACE_ID then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if rf then rf:InvokeServer("Multiplayer", "v2:stop") end
                    end)
                else
                    Globals.IsConfigDirty = true
                end
            end

            lastQueueAttemptTime = 0
            task.spawn(function() pcall(refreshDisplay) end)
        end)
    })
    task.defer(function()
        isInitializingFarm = false
    end)
    UI.FarmToggle = farmToggle
    UI.AutoToggle = farmToggle
    UI.FarmStatusLabel = FarmSec:Label({ Title = "Status", Desc = "Checking..." })
    UI.StatusLabel = UI.FarmStatusLabel

    local trialOptionsList = {}
    if RevampAutoTrials then
        for trialName, _ in pairs(RevampAutoTrials) do
            table.insert(trialOptionsList, trialName)
        end
        table.sort(trialOptionsList)
    end
    if #trialOptionsList == 0 then
        trialOptionsList = { "Fog", "Quarantine", "Exploding Enemies" }
    end

    FarmSec:Dropdown({
        Title = "Selected Trials",
        Desc = "Choose targeted trial configurations",
        IsPrem = isPremiumUser,
        Searchable = true,
        Options = trialOptionsList,
        Multi = true,
        Value = (function()
            local c = {}
            for _, v in ipairs(Globals.SelectedTrials or { "Fog" }) do
                table.insert(c, v)
            end
            return c
        end)(),
        Callback = function(selectedItems)
            local cleanList = {}
            if type(selectedItems) == "table" then
                for _, item in ipairs(selectedItems) do
                    table.insert(cleanList, item)
                end
            end
            SetSetting("SelectedTrials", cleanList)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    FarmSec:Dropdown({
        Title = "Fallback",
        Desc = "Choose fallback mode (Fallen or Molten) when trials are unavailable",
        IsPrem = isPremiumUser,
        Searchable = false,
        Options = { "Fallen", "Molten" },
        Value = tostring(Globals.SelectedFallback or "Fallen"),
        Callback = function(val)
            SetSetting("SelectedFallback", tostring(val))
        end,
    })

    FarmSec:Textbox({
        Title = "Target Timescale",
        Desc = "0 = Infinite. If set (e.g. 100), stops and returns to Smart Lobby once reached",
        IsPrem = isPremiumUser,
        Placeholder = "0",
        Value = tostring(Globals.TargetTimescale or 0),
        Callback = function(text)
            local num = tonumber(tostring(text):match("%d+")) or 0
            SetSetting("TargetTimescale", num)
            logActivity(string.format("Target Timescale set to: %d (%s)", num, num == 0 and "Infinite" or "Auto Smart Lobby after limit"), "info")
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    FarmSec:Button({
        Title = "Reset Timescale Counter",
        Desc = "Reset completed timescale matches count back to 0",
        Callback = function()
            SetSetting("TimescaleUsedSession", 0)
            if UI.TimescaleSessionLabel then
                local targetLimit = (Globals.TargetTimescale and Globals.TargetTimescale > 0) and tostring(Globals.TargetTimescale) or "Infinite"
                UI.TimescaleSessionLabel:SetDesc(string.format("Timescale Matches: 0 / %s", targetLimit))
            end
            if Window and Window.Notify then
                Window:Notify({ Title = "Counter Reset", Desc = "Timescale matches reset to 0.", Duration = 3 })
            end
        end,
    })

    local FarmRotSec = FarmTab:Section({ Title = "Rotation & Session Info" })
    UI.CurrentTrial = FarmRotSec:Label({ Title = "Current Trial", Desc = "Loading rotation data..." })
    UI.NextTrial = FarmRotSec:Label({ Title = "Next Trial", Desc = "Loading rotation data..." })
    UI.TimescaleSessionLabel = FarmRotSec:Label({
        Title = "Timescale Progress",
        Desc = string.format("Timescale Matches: %d / %s", Globals.TimescaleUsedSession or 0, (Globals.TargetTimescale and Globals.TargetTimescale > 0) and tostring(Globals.TargetTimescale) or "Infinite")
    })

    if game.PlaceId ~= LOBBY_PLACE_ID then
        local GuardSec = FarmTab:Section({ Title = "In-Game Ready Guard" })
        UI.ReadyGuard = GuardSec:Label({ Title = "Ready Button Guard (30s)", Desc = "Monitoring match status..." })
        UI.ReadyGuardBar = GuardSec:ProgressBar({
            Title = "Ready Countdown",
            Progress = 1.0,
            Status = "30s remaining"
        })
    end

    -- =================== Progression Tab ===================
    local ProgressionTab = Window:Tab({
        Title = "Progression",
        Subtitle = "Unowned Trials & Priority Buying",
        Icon = "TrendingUp",
    })

    local ProgControlSec = ProgressionTab:Section({ Title = "Progression Controls" })

    local isInitializingProg = true
    local progressionToggle = ProgControlSec:Toggle({
        Title = "Enable Progression Mode",
        Desc = "Prioritizes clearing unowned trials, auto-buying missing towers/skills",
        IsPrem = isPremiumUser,
        Value = (Globals.AutoTrials == true and Globals.TrialFarmMode == "Progression Mode"),
        Callback = RunAsExecutor(function(val)
            if isInitializingProg then return end
            if val and checkIsEverythingMaxed() then
                if UI.ProgressionToggle then UI.ProgressionToggle:SetValue(false) end
                if Window and Window.Notify then
                    Window:Notify({
                        Title = "Progression Mode",
                        Desc = "Everything is Maxed! Please select Farm Mode.",
                        Duration = 4
                    })
                end
                return
            end

            if isRequirementLocked and val then
                if UI.ProgressionToggle then UI.ProgressionToggle:SetValue(false) end
                Window:Notify({ Title = "REQUIREMENT LOCKED", Desc = "Level/Towers required!", Duration = 4 })
                return
            end

            if val then
                -- Mutual exclusion: turn off Farm and Auto Evo so they don't override
                if UI.FarmToggle then
                    pcall(function() UI.FarmToggle:SetValue(false) end)
                end
                if UI.AutoEvoToggle then
                    pcall(function() UI.AutoEvoToggle:SetValue(false) end)
                end
                if UI.AutoGoldToggle and Globals.AutoGold then
                    pcall(function() UI.AutoGoldToggle:SetValue(false) end)
                end

                Globals.TrialFarmMode = "Progression Mode"
                Globals.AutoTrials = true
                Globals.AutoEvo = false
                Globals.AutoGold = false
                SetSetting("TrialFarmMode", "Progression Mode")
                SetSetting("AutoTrials", true)
                SetSetting("AutoEvo", false)
                SetSetting("AutoGold", false)
                currentMatchMode = "AutoTrials"
                logActivity("Progression Mode: ENABLED", "success")

                if game.PlaceId == LOBBY_PLACE_ID then
                    task.spawn(fastQueueLobby)
                else
                    Globals.IsConfigDirty = true
                end
            else
                Globals.AutoTrials = false
                SetSetting("AutoTrials", false)
                logActivity("Progression Mode: DISABLED", "warn")
                if game.PlaceId == LOBBY_PLACE_ID then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if rf then rf:InvokeServer("Multiplayer", "v2:stop") end
                    end)
                else
                    Globals.IsConfigDirty = true
                end
            end

            lastQueueAttemptTime = 0
            task.spawn(function() pcall(refreshDisplay) end)
        end)
    })
    task.defer(function()
        isInitializingProg = false
    end)
    UI.ProgressionToggle = progressionToggle
    UI.ProgStatusLabel = ProgControlSec:Label({ Title = "Status", Desc = "Checking..." })

    local PrioritySec = ProgressionTab:Section({ Title = "Priority Buying" })

    PrioritySec:Toggle({
        Title = "Buy missing coins tower",
        Desc = "Auto-purchase missing coin towers (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuyMissingCoinsTower == true,
        Callback = function(val)
            SetSetting("BuyMissingCoinsTower", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    PrioritySec:Toggle({
        Title = "Buy missing gem tower",
        Desc = "Auto-purchase missing gem/hardcore towers (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuyMissingGemTower == true,
        Callback = function(val)
            SetSetting("BuyMissingGemTower", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    PrioritySec:Toggle({
        Title = "Auto Farm & Buy Missing Evolutions",
        Desc = "Farm required coins, gems, and EXP, then purchase missing evolutions (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuyMissingEvoTower == true,
        Callback = function(val)
            SetSetting("BuyMissingEvoTower", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    PrioritySec:Toggle({
        Title = "Buy missing Gold skins",
        Desc = "Auto-purchase missing golden skins (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuyMissingGoldSkins == true,
        Callback = function(val)
            SetSetting("BuyMissingGoldSkins", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    PrioritySec:Toggle({
        Title = "Buy Skill tree",
        Desc = "Auto-purchase/upgrade skill tree nodes (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuySkillTree == true,
        Callback = function(val)
            SetSetting("BuySkillTree", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    local ProgSec = ProgressionTab:Section({ Title = "Progression & Missing Indicators" })
    UI.ProgCurrency = ProgSec:Label({
        Title = "User Current Currency",
        Desc = "Coins: 0 / 0\nGems: 0 / 0"
    })
    UI.ProgCoinTowers = ProgSec:Label({
        Title = "Coin Towers (Checking...)",
        Desc = "Scanning inventory..."
    })
    UI.ProgGemTowers = ProgSec:Label({
        Title = "Hardcore Towers (Checking...)",
        Desc = "Scanning inventory..."
    })
    UI.ProgEvoTowers = ProgSec:Label({
        Title = "Evolved Towers (Checking...)",
        Desc = "Scanning evolution progress..."
    })
    UI.ProgGoldenSkins = ProgSec:Label({
        Title = "Golden Skins (Checking...)",
        Desc = "Scanning inventory..."
    })
    UI.ProgSkillTree = ProgSec:Label({
        Title = "Skill Tree (Checking...)",
        Desc = "Scanning skill tree..."
    })

    local OwnedTrialsSec = ProgressionTab:Section({ Title = "Owned Trials" })
    UI.OwnedTrialLabels = {}

    if setthreadidentity then pcall(setthreadidentity, 8) end

    for _, tDef in ipairs(staticTrialDefs) do
        UI.OwnedTrialLabels[tDef.Name] = OwnedTrialsSec:Label({
            Title = tDef.Title,
            Desc = string.format("Map: %s | Owned: Checking...", tDef.Map)
        })
    end

    -- =================== Auto Evo Tab (Standalone) ===================
    local AutoEvoTab = Window:Tab({
        Title = "Auto Evo",
        Subtitle = "Automated Tower Evolution",
        Icon = "Zap",
    })

    local EvoControlSec = AutoEvoTab:Section({ Title = "Evolution Controls" })

    local isInitializingAutoEvo = true

    UI.AutoEvoToggle = EvoControlSec:Toggle({
        Title = "Enable Auto Evo",
        Desc = "Automatically evolve selected towers when currency allows",
        IsPrem = isPremiumUser,
        Value = Globals.AutoEvo == true,
        Callback = RunAsExecutor(function(val)
            if isInitializingAutoEvo then return end
            local evoAnalysis = (typeof(analyzeAutoEvoRequirements) == "function") and analyzeAutoEvoRequirements()
            if val and evoAnalysis and not evoAnalysis.isEligible then
                if evoAnalysis.allFinished then
                    if UI.AutoEvoToggle then UI.AutoEvoToggle:SetValue(false) end
                    Window:Notify({ Title = "AUTO EVO COMPLETE", Desc = "All target evolutions are already complete!", Duration = 4 })
                    return
                elseif #evoAnalysis.missingParts > 0 and evoAnalysis.missingParts[1] ~= "Loading tower data..." then
                    local desc = table.concat(evoAnalysis.missingParts, ", ")
                    Window:Notify({ Title = "REQUIREMENT LOCKED", Desc = desc, Duration = 4 })
                end
            end

            if val then
                -- Mutual exclusion: turn off Farm and Progression so they don't override
                if UI.FarmToggle then
                    pcall(function() UI.FarmToggle:SetValue(false) end)
                end
                if UI.ProgressionToggle then
                    pcall(function() UI.ProgressionToggle:SetValue(false) end)
                end
                if UI.AutoGoldToggle and Globals.AutoGold then
                    pcall(function() UI.AutoGoldToggle:SetValue(false) end)
                end

                Globals.AutoTrials = false
                Globals.AutoEvo = true
                Globals.AutoGold = false
                SetSetting("AutoTrials", false)
                SetSetting("AutoEvo", true)
                SetSetting("AutoGold", false)
                logActivity("Auto Evolution: ENABLED", "success")
                currentMatchMode = "AutoEvo"

                if game.PlaceId == LOBBY_PLACE_ID then
                    task.spawn(fastQueueLobby)
                else
                    Globals.IsConfigDirty = true
                end
            else
                Globals.AutoEvo = false
                SetSetting("AutoEvo", false)
                logActivity("Auto Evolution: DISABLED", "warn")
                if game.PlaceId == LOBBY_PLACE_ID then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if rf then rf:InvokeServer("Multiplayer", "v2:stop") end
                    end)
                else
                    Globals.IsConfigDirty = true
                end
            end

            task.spawn(function() pcall(refreshDisplay) end)
        end),
    })

    task.defer(function()
        isInitializingAutoEvo = false
    end)

    EvoControlSec:Dropdown({
        Title = "Target Evo",
        Desc = "Select the target evolution",
        IsPrem = isPremiumUser,
        Searchable = true,
        Options = { "All", "Scout", "Shotgunner", "Crook Boss", "Minigunner" },
        Value = tostring(Globals.TargetEvo or "All"),
        Callback = function(val)
            SetSetting("TargetEvo", tostring(val))
            task.spawn(function() pcall(refreshDisplay) end)
            if game.PlaceId ~= LOBBY_PLACE_ID then
                Globals.IsConfigDirty = true
            end
        end,
    })

    EvoControlSec:Dropdown({
        Title = "Win / Lose Strategy",
        Desc = "Select outcome preference for Auto Evo",
        IsPrem = isPremiumUser,
        Searchable = false,
        Options = { "Win", "Lose" },
        Value = tostring(Globals.EvoStrat or "Lose"),
        Callback = function(val)
            SetSetting("EvoStrat", tostring(val))
            task.spawn(function() pcall(refreshDisplay) end)
            if game.PlaceId ~= LOBBY_PLACE_ID then
                Globals.IsConfigDirty = true
            end
        end,
    })

    UI.AutoEvoStatusLabel = EvoControlSec:Label({
        Title = "Status",
        Desc = "Checking..."
    })
    UI.EvoStatusLabel = UI.AutoEvoStatusLabel

    UI.AutoEvoMissingLabel = EvoControlSec:Label({
        Title = "Missing:",
        Desc = "Checking..."
    })

    local EvoTrackerSec = AutoEvoTab:Section({ Title = "Evolution Trackers" })

    UI.EvoCoinsGemsLabel = EvoTrackerSec:Label({
        Title = "Coins & Gems Tracker",
        Desc = "Waiting for data..."
    })

    UI.EvoTowersLabel = EvoTrackerSec:Label({
        Title = "Towers Level",
        Desc = "Waiting for data..."
    })

    -- =================== Multiplayer Mode Tab ===================
    -- Matchmaking behavior and tower requirements will be connected when
    -- multiplayer definitions are added to PremConfigs.lua.
    local MultiplayerTab = Window:Tab({
        Title = "Multiplayer Mode",
        Subtitle = "Local Coordinated Runs (Host & Joiner)",
        Icon = "User",
    })

    -- 1. Setup & Meeting Point Section
    local MeetingSec = MultiplayerTab:Section({ Title = "Multiplayer Setup & Meeting Point" })

    MeetingSec:Toggle({
        Title = "Enable Multiplayer Mode",
        Desc = "Coordinates party formation and matchmaking between Host and P2",
        Value = Globals.MultiplayerEnabled == true,
        Callback = function(val)
            SetSetting("MultiplayerEnabled", val)
        end,
    })

    MeetingSec:Dropdown({
        Title = "Multiplayer Role",
        Desc = "Host creates the party and queues; P2 follows and joins",
        Searchable = false,
        Options = { "Host (Party Leader)", "P2 / Joiner (Party Follower)" },
        Value = Globals.MultiplayerIsHost and "Host (Party Leader)" or "P2 / Joiner (Party Follower)",
        Callback = function(val)
            if val == "Host (Party Leader)" then
                SetSetting("MultiplayerIsHost", true)
                SetSetting("MultiplayerIsP2", false)
            else
                SetSetting("MultiplayerIsHost", false)
                SetSetting("MultiplayerIsP2", true)
            end
        end,
    })

    MeetingSec:Textbox({
        Title = "Private Server Code / Link",
        Desc = "Enter VIP link or linkCode. If separated, both players automatically TP here every 30s to meet",
        Placeholder = "https://roblox.com/share?code=... or linkCode",
        Value = tostring(Globals.PrivateServerCode or Globals.PrivateCode or ""),
        Callback = function(text)
            local clean = tostring(text):gsub("^%s*(.-)%s*$", "%1")
            SetSetting("PrivateServerCode", clean)
            SetSetting("PrivateCode", clean)
        end,
    })

    MeetingSec:Toggle({
        Title = "Enable 30s Server Watcher",
        Desc = "Automatically teleports to Private Server if peer is missing for 30 seconds",
        Value = Globals.LobbyWatcherEnabled ~= false,
        Callback = function(val)
            SetSetting("LobbyWatcherEnabled", val)
        end,
    })

    -- 2. Host Configuration Section
    local HostSec = MultiplayerTab:Section({ Title = "Host Configuration (Party Leader)" })

    HostSec:Textbox({
        Title = "Target P2 Username / User ID",
        Desc = "Roblox Username or numeric User ID of P2 / Joiner",
        Placeholder = "Enter P2 username...",
        Value = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""),
        Callback = function(text)
            local clean = tostring(text):gsub("^%s*(.-)%s*$", "%1")
            SetSetting("MultiplayerTargetP2", clean)
            SetSetting("MultiplayerHostIdentifier", clean)
        end,
    })

    HostSec:Button({
        Title = "Invite P2 Now",
        Desc = "Creates in-game party and invites player in Target P2 textbox",
        Callback = function()
            local target = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
            if target == "" then
                warn("[Local Multiplayer] Target P2 textbox is empty!")
                return
            end
            LocalPartyManager:CreateAndInvite(target)
        end,
    })

    -- 3. P2 / Joiner Configuration Section
    local P2Sec = MultiplayerTab:Section({ Title = "P2 / Joiner Configuration (Party Follower)" })

    P2Sec:Textbox({
        Title = "Target Host Username / User ID",
        Desc = "Roblox Username or numeric User ID of Host to join",
        Placeholder = "Enter Host username...",
        Value = tostring(Globals.MultiplayerTargetHost or ""),
        Callback = function(text)
            SetSetting("MultiplayerTargetHost", tostring(text):gsub("^%s*(.-)%s*$", "%1"))
        end,
    })

    P2Sec:Button({
        Title = "Accept Host Invite Now",
        Desc = "Accepts in-game party invite from Host specified above",
        Callback = function()
            local target = tostring(Globals.MultiplayerTargetHost or ""):gsub("^%s*(.-)%s*$", "%1")
            if target == "" then
                warn("[Local Multiplayer] Target Host textbox is empty!")
                return
            end
            LocalPartyManager:AcceptInviteFrom(target)
        end,
    })

    -- 4. Live Status & Party Controls Section
    local StatusSec = MultiplayerTab:Section({ Title = "Live Status & Controls" })

    UI.MultiplayerPartyStatusLabel = StatusSec:Label({
        Title = "In-Game Party Status",
        Desc = LocalPartyManager and LocalPartyManager.PartyStatusText or "No Party"
    })

    UI.MultiplayerPeerPresenceLabel = StatusSec:Label({
        Title = "Target Peer Presence",
        Desc = LocalPartyManager and LocalPartyManager.PeerStatusText or "Checking server..."
    })

    UI.MultiplayerWatcherStatusLabel = StatusSec:Label({
        Title = "30s Server Watcher",
        Desc = LocalPartyManager and LocalPartyManager.WatcherStatusText or "Watcher Idle"
    })

    StatusSec:Button({
        Title = "Leave Current Party",
        Desc = "Disbands or leaves in-game party",
        Callback = function()
            LocalPartyManager:LeaveParty()
        end,
    })

    StatusSec:Button({
        Title = "Teleport to Private Server Now",
        Desc = "Immediately teleports this account to the configured Private Server",
        Callback = function()
            local code = tostring(Globals.PrivateServerCode or Globals.PrivateCode or ""):gsub("^%s*(.-)%s*$", "%1")
            if code == "" then
                warn("[Local Multiplayer] Private Server Code is empty!")
                return
            end
            teleportToPrivateServer(code)
        end,
    })

    local KeyTab = Window:Tab({
        Title = "Key",
        Subtitle = "Keyless, Standard Key, & Premium Access",
        Icon = "Key",
    })

    local KeySec = KeyTab:Section({ Title = "Access Tier Status" })
    KeySec:Label({ Title = "Engine Status", Desc = "Active & Running" })
    KeySec:Label({
        Title = "Current Mode",
        Desc = isPremiumUser and "Premium Active" or (isKeyUser and "Standard Key Mode Active" or "Keyless Mode Active")
    })

    local modeExplanation = "Keyless Mode: Farms unowned trials only. If the current trial is already owned (e.g. Fog), it strictly stays in the lobby and waits for the next rotation."
    if isPremiumUser then
        modeExplanation = "Premium Mode: Full automation unlocked (Progression Mode, multi-trial queue filters, fallbacks, auto tower purchases, auto evolutions)."
    elseif isKeyUser then
        modeExplanation = "Standard Key Mode: Classic repeat-trial mode. Farms the current rotation trial continuously over and over if eligible, even if already owned."
    end
    KeySec:Label({ Title = "Mode Description", Desc = modeExplanation })

    local currentKeyDisplay = getSavedKey()
    local hasSavedDiskKey = (currentKeyDisplay ~= "No Key Found" and currentKeyDisplay ~= nil and #currentKeyDisplay > 0)
    local maskedKey = currentKeyDisplay
    if hasSavedDiskKey and #currentKeyDisplay > 8 then
        maskedKey = currentKeyDisplay:sub(1, 4) .. "..." .. currentKeyDisplay:sub(-4)
    elseif not hasSavedDiskKey then
        maskedKey = "None (Running Keyless)"
    end

    KeySec:Label({ Title = "Current Active Key", Desc = maskedKey })

    local UnlockSec = KeyTab:Section({ Title = "Key Management & Actions" })

    -- Helper to apply validated key
    local function applyValidatedKey(cleanKey, result)
        saveVerifiedKey(cleanKey)
        Globals.SCRIPT_KEY = cleanKey
        Globals.IS_JD_PREMIUM = (result.is_premium == true or result.premium == true)
        Globals.JD_EXPIRES_AT = result.expires_at or result.expiresAt
        isKeyUser = true
        isPremiumUser = (Globals.IS_JD_PREMIUM == true)
        SetSetting("PreferredAccessTier", isPremiumUser and "Premium" or "Key")

        local reqModule = loadConfigRequirements()
        if reqModule then
            Requirements = reqModule
            RevampAutoTrials = Requirements.RevampAutoTrials
            if type(RevampAutoTrials) ~= "table" or next(RevampAutoTrials) == nil then
                RevampAutoTrials = Requirements.trialConfigs or {}
            end
            allTrialOptions = Requirements.allTrialOptions or {}
            fallbackModesList = Requirements.fallbackModesList or {}
            FallbackConfigs = Requirements.RevampedFallbackConfigs or Requirements.FallbackConfigs or Requirements.fallbackConfigs or {}
            CrateConfigs = Requirements.CrateConfigs or {}
            AutoEvoConfigs = Requirements.AutoEvoConfigs or (getgenv and getgenv().AutoEvoConfigs) or (shared and shared.AutoEvoConfigs) or {}
            ensureDynamicHardcoreFallback()
            AutoGoldModule.Configs = FallbackConfigs
            AutoGoldModule.CrateConfigs = CrateConfigs
        end

        Window:Notify({
            Title = isPremiumUser and "Premium Validated!" or "Standard Key Validated!",
            Desc = isPremiumUser and "Premium status unlocked successfully!" or "Standard Key Mode unlocked! (Farms current trial over and over)",
            Duration = 3,
        })

        task.defer(function()
            pcall(function()
                if UI.ScreenGui then UI.ScreenGui:Destroy() end
            end)
            task.wait(0.1)
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                buildInterface()
            end)
        end)
    end

    -- Auto-Load Saved Key Button:
    -- If currently in Keyless Mode, and a saved key exists on disk, offer the one-click auto-load button!
    if not isKeyUser and hasSavedDiskKey then
        UnlockSec:Button({
            Title = "Auto-Load Saved Key",
            Desc = "Validate and load saved key to unlock Standard Key Mode or Premium Mode",
            Image = "Key",
            Callback = function()
                local diskKey = loadVerifiedKey() or currentKeyDisplay
                if not diskKey or diskKey == "" or diskKey == "No Key Found" then
                    Window:Notify({ Title = "No Key Found", Desc = "No saved key was found on disk.", Duration = 3 })
                    return
                end

                Window:Notify({
                    Title = "Validating Saved Key",
                    Desc = "Checking key with Junkie SDK...",
                    Duration = 2,
                })

                task.spawn(function()
                    local Junkie = getJunkieSDK()
                    if not Junkie then
                        Window:Notify({ Title = "Validation Error", Desc = "Unable to reach Junkie SDK service.", Duration = 3 })
                        return
                    end

                    local success, result = pcall(function()
                        return Junkie.check_key(diskKey)
                    end)

                    if success and result and result.valid then
                        applyValidatedKey(diskKey, result)
                    else
                        Window:Notify({
                            Title = "Invalid Saved Key",
                            Desc = "Saved key is expired or invalid. Please enter a valid key below.",
                            Duration = 3,
                        })
                    end
                end)
            end,
        })
    end

    -- Switch to Keyless Mode Button (Available when in Standard Key or Premium Mode)
    if isKeyUser or isPremiumUser then
        UnlockSec:Button({
            Title = "Switch to Keyless Mode",
            Desc = "Return to Keyless Mode (farms unowned trials only, stays in lobby for owned trials)",
            Image = "LogOut",
            Callback = function()
                isKeyUser = false
                isPremiumUser = false
                Globals.IS_JD_PREMIUM = false
                Globals.SCRIPT_KEY = nil
                SetSetting("PreferredAccessTier", "Keyless")
                Window:Notify({
                    Title = "Keyless Mode Active",
                    Desc = "Switched to Keyless Mode. Will only farm unowned trials and stay in lobby when owned.",
                    Duration = 3,
                })
                task.defer(function()
                    pcall(function()
                        if UI.ScreenGui then UI.ScreenGui:Destroy() end
                    end)
                    task.wait(0.1)
                    pcall(function()
                        if setthreadidentity then pcall(setthreadidentity, 8) end
                        buildInterface()
                    end)
                end)
            end,
        })
    end

    UnlockSec:Textbox({
        Title = (isKeyUser or isPremiumUser) and "Upgrade / Change Key" or "Enter Standard / Premium Key",
        Desc = "Enter a Standard key (farms current trial over and over) or Premium key (full automation)",
        Placeholder = "Enter license key here...",
        Value = "",
        Callback = RunAsExecutor(function(newKey)
            local cleanKey = newKey:gsub("^%s*(.-)%s*$", "%1")
            if cleanKey == "" then return end

            Window:Notify({
                Title = "Validating Key",
                Desc = "Checking key with Junkie SDK...",
                Duration = 2,
            })

            task.spawn(function()
                local Junkie = getJunkieSDK()
                if not Junkie then
                    Window:Notify({ Title = "Validation Error", Desc = "Unable to reach Junkie SDK service.", Duration = 3 })
                    return
                end

                local success, result = pcall(function()
                    return Junkie.check_key(cleanKey)
                end)

                if success and result and result.valid then
                    applyValidatedKey(cleanKey, result)
                else
                    Window:Notify({
                        Title = "Invalid Key",
                        Desc = "The key provided is invalid or expired.",
                        Duration = 3,
                    })
                end
            end)
        end),
    })

    local InfoSec = KeyTab:Section({ Title = "Mode Breakdown & Differences" })
    InfoSec:Label({
        Title = "Keyless Mode",
        Desc = "• Free access\n• ONLY farms trials you do NOT own (e.g. if Fog is owned, stays in lobby)\n• Automatically advances your trial collection safely"
    })
    InfoSec:Label({
        Title = "Standard Key Mode",
        Desc = "• Unlocked with Standard Key\n• Classic repeat-trial mode: farms the current rotation trial continuously over and over if eligible\n• Repeats trials even if already owned"
    })
    InfoSec:Label({
        Title = "Premium Key Mode",
        Desc = "• Unlocked with Premium Key\n• Full automation: Progression Mode (Evo leveling, Coin/Gem farming, Skill Tree, Golden Skins)\n• Multi-trial filters, smart fallbacks, and auto tower purchases"
    })

    -- =================== Misc Tab ===================
    local MiscTab = Window:Tab({ Title = "Misc", Subtitle = "Webhooks & Options", Icon = "Gear" })

    local PrivateServerSec = MiscTab:Section({ Title = "Private Server Settings" })
    PrivateServerSec:Textbox({
        Title = "Private Server Code",
        Desc = "Enter private server link code for smart lobby teleporting",
        Placeholder = "Enter code here...",
        Value = tostring(Globals.PrivateCode or ""),
        Callback = function(text)
            SetSetting("PrivateCode", text:gsub("^%s*(.-)%s*$", "%1"))
        end,
    })

    local UtilitiesSec = MiscTab:Section({ Title = "Utilities" })

    UtilitiesSec:Toggle({
        Title = "Mobile Low Graphics Boost",
        Desc = "Disables shadows, particles, and post-processing for smooth FPS on budget mobile devices",
        Value = Globals.MobileBoost or false,
        Callback = function(val)
            SetSetting("MobileBoost", val)
            applyMobileOptimizations(val)
        end,
    })

    UtilitiesSec:Toggle({
        Title = "Auto Skip",
        Desc = "Automatically vote to skip waves when vote prompt appears",
        Value = Globals.AutoSkip or false,
        Callback = function(val)
            SetSetting("AutoSkip", val)
            if val and not AutoSkipRunning then
                StartAutoSkip()
            end
        end,
    })

    UtilitiesSec:Toggle({
        Title = "Enable Auto Gatling",
        Desc = "Automatically load Gatling assistant script in match",
        Value = Globals.AutoGatling or false,
        Callback = function(val)
            SetSetting("AutoGatling", val)
            if val and not AutoGatlingRunning then
                StartAutoGatling()
            end
        end,
    })

    UtilitiesSec:Dropdown({
        Title = "Gatling Loader",
        Desc = "Choose default script to load for Gatling Gun",
        Searchable = false,
        Options = { "Gatlify", "Gatling Gun" },
        Value = Globals.SelectedGatling or "Gatlify",
        Callback = function(val)
            SetSetting("SelectedGatling", tostring(val))
        end,
    })

    UtilitiesSec:Toggle({
        Title = "Auto Reload Gatling",
        Desc = "Automatically handle gatling reloading based on percentage",
        IsPrem = isPremiumUser,
        Value = Globals.AutoReloadGatling or false,
        Callback = function(val)
            SetSetting("AutoReloadGatling", val)
            if val and not AutoReloadRunning and typeof(StartAutoReloadGatling) == "function" then
                StartAutoReloadGatling()
            end
        end,
    })

    UtilitiesSec:Slider({
        Title = "Reload Percentage",
        Desc = "Percentage threshold till reload (100% = full reload)",
        IsPrem = isPremiumUser,
        Min = 0,
        Max = 100,
        Step = 5,
        Suffix = "%",
        Value = Globals.GatlingReloadPercent or 100,
        Callback = function(val)
            SetSetting("GatlingReloadPercent", val)
        end,
    })

    UI.AutoReloadStatusLabel = UtilitiesSec:Label({
        Title = "Gatling Reload Status",
        Desc = "Status: Idle"
    })

    UtilitiesSec:Toggle({
        Title = "Enable Auto Timescale",
        Desc = "Automatically unlock and apply timescale multipliers",
        Value = Globals.TimeScaleEnabled or false,
        Callback = function(v)
            SetSetting("TimeScaleEnabled", v)
            if v and not TimeScaleRunning then
                StartTimeScale()
            end
        end,
    })

    UtilitiesSec:Slider({
        Title = "Timescale Target Speed",
        Desc = "Select the game speed multiplier to maintain (0.5x to 2.0x)",
        Min = 0.5,
        Max = 2.0,
        Step = 0.5,
        Suffix = "x",
        Value = Globals.TimeScaleValue or 2,
        Callback = function(choice)
            local value = tonumber(choice) or 2
            SetSetting("TimeScaleValue", value)
            if Globals.TimeScaleEnabled then
                ApplyTimeScaleOnce()
            end
        end,
    })

    local InterfaceSec = MiscTab:Section({ Title = "Interface & Keybind" })
    InterfaceSec:Keybind({
        Title = "Toggle UI Keybind",
        Desc = "Press any key to rebind the GUI toggle shortcut",
        Default = Window.Keybind or Enum.KeyCode.RightShift,
        Callback = function(newKey, keyName)
            Window.Keybind = newKey
            Window:Notify({ Title = "Keybind Updated", Desc = "GUI toggle set to [ " .. keyName .. " ]", Duration = 2 })
            logActivity("UI toggle keybind changed to " .. keyName, "info")
        end
    })

    local QuickActionsSec = MiscTab:Section({ Title = "Quick Actions" })
    QuickActionsSec:Button({
        Title = "Smart Lobby Teleport",
        Desc = "Safely return to a clean lobby instance with fail-safes",
        Image = "Globe",
        Callback = function()
            Window:Dialog({
                Title = "Return to Lobby?",
                Content = "Are you sure you want to teleport back to the lobby? In-game match will be abandoned.",
                ConfirmText = "Teleport",
                CancelText = "Stay In Game",
                Danger = true,
                OnConfirm = function()
                    logActivity("Manual smart lobby teleport initiated.", "warn")
                    Window:Notify({ Title = "Teleporting", Desc = "Searching for optimal lobby...", Duration = 3 })
                    SmartTeleportToLobby()
                end
            })
        end
    })

    local WebhookSec = MiscTab:Section({ Title = "Discord Webhook Integration" })
    WebhookSec:Textbox({
        Title = "Webhook URL",
        Desc = "Discord webhook link for status notifications",
        Placeholder = "Paste Discord Webhook URL here...",
        Value = Globals.WebhookURL or "",
        Callback = function(text)
            SetSetting("WebhookURL", text:gsub("^%s*(.-)%s*$", "%1"))
        end,
    })

    -- =================== Console Tab ===================
    local ConsoleTab = Window:Tab({
        Title = "Console",
        Subtitle = "Live Activity & Logs",
        Icon = "Terminal",
    })

    local ConsoleSec = ConsoleTab:Section({ Title = "Engine Feed" })
    UI.LogConsole = ConsoleSec:LogConsole({
        Title = "Service Hub v9.8 Live Feed",
        Height = 220,
        AutoScroll = true
    })
    UI.LogConsole:Success("Service Hub v9.8 initialized (Cloud Loadstring Edition).")
    UI.LogConsole:Info("CoreRevampNewAPI connected.")
    if isPremiumUser then
        UI.LogConsole:Success("License: Premium Verified (VIP Access).")
    else
        UI.LogConsole:Log("License: Standard Edition.")
    end

    task.spawn(function()
        task.wait(0.2)
        pcall(function()
            if not PlayerDataHandler then
                PlayerDataHandler = loadPlayerDataHandler()
            end
            if typeof(refreshDisplay) == "function" then
                refreshDisplay()
            end
        end)
    end)
end

sendEvoPurchaseWebhook = function(towerName, evoName)
    local url = Globals.WebhookURL
    if type(url) ~= "string" or url == "" then return end
    local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httprequest then return end

    local currentState = "Lobby"
    if game.PlaceId ~= LOBBY_PLACE_ID then currentState = "Ingame" end

    pcall(function()
        local embed = {
            ["title"] = "🛒 Evolution Purchase",
            ["description"] = "Attempting to evolve a tower.",
            ["color"] = 16776960,
            ["timestamp"] = DateTime.now():ToIsoDate(),
            ["footer"] = { ["text"] = "ServiceHub V2 • Play Smart, Not Hard", ["icon_url"] = "https://i.imgur.com/W35kZkU.png" },
            ["fields"] = {
                { ["name"] = "Purchase", ["value"] = "waiting....", ["inline"] = false },
                { ["name"] = "Purchased", ["value"] = "check [ " .. (evoName or towerName) .. " ]", ["inline"] = false },
                { ["name"] = "State", ["value"] = currentState, ["inline"] = false }
            }
        }
        httprequest({
            Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode({ ["username"] = "ServiceHub", ["avatar_url"] = "https://i.imgur.com/W35kZkU.png", ["embeds"] = { embed } })
        })
    end)
end

--==============================================================================
-- Main Display & Auto-Queue Update Engine
--==============================================================================
local lastRefreshDisplayTick = 0
refreshDisplay = function()
    local nowClock = os.clock()
    if nowClock - lastRefreshDisplayTick < 2.5 then return end
    lastRefreshDisplayTick = nowClock
    if setthreadidentity then pcall(setthreadidentity, 8) end
    pcall(checkRuntimeKeyExpiration)
    if not PlayerDataHandler then return end

    local coins, targetCoins, gems, targetGems, coinsDisplay, gemsDisplay = getCurrencyAndTargets()

    if coinsTrackerLabel then
        pcall(function() coinsTrackerLabel:SetDesc(coinsDisplay) end)
    end

    if gemsTrackerLabel then
        pcall(function() gemsTrackerLabel:SetDesc(gemsDisplay) end)
    end

    if UI and UI.CurrencyGrid then
        pcall(function()
            UI.CurrencyGrid:UpdateItem(1, coinsDisplay, "Current / Target Coins")
            UI.CurrencyGrid:UpdateItem(2, gemsDisplay, "Current / Target Gems")
        end)
    end

    if UI and UI.ProgCurrency then
        pcall(function()
            UI.ProgCurrency:SetDesc(string.format("Coins: %s\nGems: %s", coinsDisplay, gemsDisplay))
        end)
    end

    if game.PlaceId == LOBBY_PLACE_ID then
        pcall(processAutoPurchases)
    end

    if Globals.AutoGold and isPremiumUser then
        local targetCoins = tonumber(Globals.TargetCoins) or 0
        local targetGems = tonumber(Globals.TargetGems) or 0
        if (targetCoins > 0 and coins >= targetCoins) or (targetGems > 0 and gems >= targetGems) then
            Globals.AutoGold = false
            SetSetting("AutoGold", false)
            if UI.AutoGoldToggle then UI.AutoGoldToggle:SetValue(false) end
            
            if targetCoins > 0 and coins >= targetCoins then
                SetSetting("TargetCoins", 0)
                if UI.TargetCoinsBox then UI.TargetCoinsBox:SetValue("0") end
            end
            if targetGems > 0 and gems >= targetGems then
                SetSetting("TargetGems", 0)
                if UI.TargetGemsBox then UI.TargetGemsBox:SetValue("0") end
            end
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "Target Reached",
                        Desc = (game.PlaceId == LOBBY_PLACE_ID) and "AutoGold stopped and targets reset to 0." or "Target reached! Match will conclude before returning to lobby.",
                        Duration = 5
                    })
                end)()
            end
            
            if game.PlaceId == LOBBY_PLACE_ID then
                SmartTeleportToLobby()
            else
                Globals.IsConfigDirty = true
            end
        end
    end
    
    local selected = tostring(Globals.TargetEvo or "All")
    local toCheck = {}
    local activeTowerFound = nil

    if selected == "All" then
        for _, tName in ipairs({ "Scout", "Shotgunner", "Crook Boss", "Minigunner" }) do
            if not isTowerEvoComplete(tName) and isTowerOrEvoOwned(tName) then
                if not activeTowerFound then
                    activeTowerFound = tName
                end
            end
        end
        if activeTowerFound then
            toCheck = { activeTowerFound }
        else
            toCheck = {}
        end
    elseif EvoData[selected] then
        toCheck = { selected }
        activeTowerFound = selected
    end
    
    if UI.EvoCoinsGemsLabel then
        local coinsStr, gemsStr
        if #toCheck == 0 then
            coinsStr = "Coins: " .. coinsDisplay .. " (Complete)"
            gemsStr = "Gems: " .. gemsDisplay .. " (Complete)"
        elseif activeTowerFound and EvoData[activeTowerFound] then
            local evoInfo = EvoData[activeTowerFound]
            local ownsActiveEvo = typeof(PlayerDataHandler.IsTowerOwned) == "function" and PlayerDataHandler:IsTowerOwned(evoInfo.Evo)
            if ownsActiveEvo then
                coinsStr = "Coins: " .. coinsDisplay .. " (" .. activeTowerFound .. " Owned)"
                gemsStr = "Gems: " .. gemsDisplay .. " (Grinding Level)"
            else
                coinsStr = string.format("Coins: %s / %s", formatNumberWithCommas(coins), formatNumberWithCommas(evoInfo.Coins))
                gemsStr = string.format("Gems: %s / %s", formatNumberWithCommas(gems), formatNumberWithCommas(evoInfo.Gems))
            end
        else
            coinsStr = "Coins: " .. coinsDisplay
            gemsStr = "Gems: " .. gemsDisplay
        end
        
        UI.EvoCoinsGemsLabel:SetDesc(coinsStr .. "\n" .. gemsStr)
    end
    
    if UI.EvoTowersLabel then
        local towersText = ""
        local grindState = "Idle / Finished"
        local stateFound = false
        
        if #toCheck > 0 then
            local lines = {}
            for _, towerName in ipairs(toCheck) do
                local eData = EvoData[towerName]
                local evoName = eData and eData.Evo or towerName
               
                
                local ownsEvo = typeof(PlayerDataHandler.IsTowerOwned) == "function" and PlayerDataHandler:IsTowerOwned(evoName)
                if ownsEvo then
                    table.insert(lines, towerName .. ": Complete!")
                    if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                        local evoExp = PlayerDataHandler:GetTowerExp(evoName)
                        if evoExp then
                            if evoExp.Level < 20 then
                                table.insert(lines, string.format("%s: Level %d/20 (%s)", evoName, evoExp.Level, evoExp.ProgressDisplay))
                                if not stateFound then grindState = "Grinding level..."; stateFound = true; Globals.CurrentEvoActiveTower = towerName end
                            else
                                table.insert(lines, evoName .. ": Complete!")
                            end
                        else
                            table.insert(lines, evoName .. ": (Waiting for data)")
                        end
                    end
                else
                    if typeof(PlayerDataHandler.IsTowerOwned) == "function" and not PlayerDataHandler:IsTowerOwned(towerName) then
                        table.insert(lines, towerName .. ": Tower not owned")
                        table.insert(lines, evoName .. ": Locked")
                        if not stateFound then grindState = "Grinding coins..."; stateFound = true; Globals.CurrentEvoActiveTower = towerName end
                    else
                        if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                            local expData = PlayerDataHandler:GetTowerExp(towerName)
                            if expData then
                                local coinsNeed = math.max(0, eData.Coins - coins)
                                local gemsNeed = math.max(0, eData.Gems - gems)
                                
                                if expData.Level < 20 then
                                    table.insert(lines, string.format("%s: Level %d/20 (%s)", towerName, expData.Level, expData.ProgressDisplay))
                                end
                                
                                if coinsNeed == 0 and gemsNeed == 0 then
                                    if expData.Level < 20 then
                                        if not stateFound then grindState = "Grinding level..."; stateFound = true; Globals.CurrentEvoActiveTower = towerName end
                                    else
                                        table.insert(lines, towerName .. ": Complete!")
                                        if not stateFound then grindState = "Buying Selected Evo...."; stateFound = true; Globals.CurrentEvoActiveTower = towerName end
                                        
                                        if Globals.AutoEvo and not buyingEvoDebounce then
                                            buyingEvoDebounce = true
                                            task.spawn(function()
                                                pcall(function()
                                                    local rf = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteFunction")
                                                    if rf then
                                                        sendEvoPurchaseWebhook(towerName, evoName)
                                                        rf:InvokeServer("Shop", "EvolveTower", towerName)
                                                    end
                                                end)
                                                task.wait(4)
                                                buyingEvoDebounce = false
                                            end)
                                        end
                                    end
                                else
                                    local reqStr = {}
                                    if coinsNeed > 0 then table.insert(reqStr, formatNumberWithCommas(coinsNeed) .. " Coins") end
                                    if gemsNeed > 0 then table.insert(reqStr, formatNumberWithCommas(gemsNeed) .. " Gems") end
                                    table.insert(lines, string.format("%s: Needs %s", towerName, table.concat(reqStr, ", ")))
                                    
                                    if not stateFound then
                                        if coinsNeed > 0 then
                                            grindState = "Grinding coins..."
                                        elseif expData.Level < 20 then
                                            grindState = "Grinding level..."
                                        else
                                            grindState = "Grinding gems..."
                                        end
                                        stateFound = true
                                        Globals.CurrentEvoActiveTower = towerName
                                    end
                                end
                            else
                                table.insert(lines, towerName .. ": (Waiting for data)")
                            end
                            table.insert(lines, evoName .. ": Locked (Requires Base)")
                        else
                            table.insert(lines, towerName .. ": (Update DataHandler)")
                        end
                    end
                end
                table.insert(lines, "") -- blank line separator
            end
            towersText = table.concat(lines, "\n"):gsub("\n$", "")
        else
            local allActuallyComplete = true
            for _, tName in ipairs({ "Scout", "Shotgunner", "Crook Boss", "Minigunner" }) do
                if not isTowerEvoComplete(tName) then
                    allActuallyComplete = false
                    break
                end
            end
            if selected == "All" then
                if allActuallyComplete then
                    towersText = "All Evolutions Complete!"
                    grindState = "Idle / Finished"
                else
                    towersText = "Loading evolution data..."
                    grindState = "Loading data..."
                end
            else
                local isComplete = (EvoData[selected] and isTowerEvoComplete(selected))
                towersText = isComplete and (selected .. " Evolution Complete!") or "(No target selected)"
                grindState = isComplete and "Idle / Finished" or "No target selected"
            end
        end
        
        UI.EvoTowersLabel:SetDesc(towersText)
        
        Globals.CurrentEvoGrindState = grindState
        SetSetting("CurrentEvoGrindState", grindState)

        if grindState == "Grinding coins..." then
            Globals.CurrentEvoFarmType = "Coins"
            SetSetting("CurrentEvoFarmType", "Coins")
        elseif grindState == "Grinding gems..." or grindState == "Grinding level..." then
            Globals.CurrentEvoFarmType = "Gems"
            SetSetting("CurrentEvoFarmType", "Gems")
        else
            Globals.CurrentEvoFarmType = nil
            SetSetting("CurrentEvoFarmType", nil)
            Globals.CurrentEvoActiveTower = nil
            if Globals.AutoEvo and isPremiumUser and grindState == "Idle / Finished" then
                Globals.AutoEvo = false
                SetSetting("AutoEvo", false)
                if UI.AutoEvoToggle then UI.AutoEvoToggle:SetValue(false) end
                
                if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                    RunAsExecutor(function()
                        UI.Window:Notify({ Title = "Auto Evo Complete", Desc = "All target evolutions are fully leveled!", Duration = 5 })
                    end)()
                end
                if game.PlaceId ~= LOBBY_PLACE_ID then
                    Globals.IsConfigDirty = true
                    Globals.AutoEvoMilestoneReached = true
                end
            end
        end
        
        SetSetting("CurrentEvoActiveTower", Globals.CurrentEvoActiveTower)

        if game.PlaceId ~= LOBBY_PLACE_ID and Globals.AutoEvo then
            -- Live check if Coins, Gems, Level 20, or Evo Exp 20 milestone was reached
            local milestoneReached, milestoneReason = checkAutoEvoMilestonesReached()
            if milestoneReached then
                Globals.IsConfigDirty = true
                if not Globals.AutoEvoMilestoneReached then
                    Globals.AutoEvoMilestoneReached = true
                    if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                        RunAsExecutor(function()
                            UI.Window:Notify({
                                Title = "AUTO EVO MILESTONE",
                                Desc = tostring(milestoneReason) .. "! Match will finish before returning to Smart Lobby.",
                                Duration = 6,
                                Type = "info"
                            })
                        end)()
                    end
                end
            end
        end
        Globals.PreviousEvoGrindState = Globals.CurrentEvoGrindState
        Globals.PreviousEvoFarmType = Globals.CurrentEvoFarmType
    end

    if not PlayerDataHandler then
        PlayerDataHandler = loadPlayerDataHandler()
    end

    if game.PlaceId ~= LOBBY_PLACE_ID then
        if UI.Window and UI.Window.SetSubtitle then
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                UI.Window:SetSubtitle("IN-GAME : Active Match")
            end)
        end
    end

    local analysis = analyzeCurrentTrial()
    local playerLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0

    local missingParts = {}
    if not analysis.levelPassed then
        table.insert(missingParts, string.format("Level %d (You: %d)", analysis.requiredLevel, playerLevel))
    end
    if #analysis.missingTowers > 0 then
        table.insert(missingParts, "Towers: " .. table.concat(analysis.missingTowers, ", "))
    end
    if #analysis.missingGold > 0 then
        table.insert(missingParts, "Golden: " .. table.concat(analysis.missingGold, ", "))
    end
    if #analysis.missingSkills > 0 then
        table.insert(missingParts, "Skill Tree: " .. table.concat(analysis.missingSkills, ", "))
    end

    local wasLocked = isRequirementLocked
    isRequirementLocked = (#missingParts > 0 or not analysis.configFound)

    if wasLocked and not isRequirementLocked then
        if UI.FarmToggle then UI.FarmToggle:SetValue(Globals.AutoTrials == true and Globals.TrialFarmMode == "Farm Mode") end
        if UI.ProgressionToggle then UI.ProgressionToggle:SetValue(Globals.AutoTrials == true and Globals.TrialFarmMode == "Progression Mode") end
    end

    if setthreadidentity then pcall(setthreadidentity, 8) end

    if UI.CurrentTrial then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            if analysis.currentMap and analysis.currentMap ~= "Unknown" then
                UI.CurrentTrial:SetDesc(string.format("%s | Map: %s | Time Left: %s", analysis.trialName, analysis.currentMap, analysis.timeRemaining))
            else
                UI.CurrentTrial:SetDesc(string.format("%s | Time Left: %s", analysis.trialName, analysis.timeRemaining))
            end
        end)
    end

    if UI.NextTrial then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            if analysis.nextTrialMap and analysis.nextTrialMap ~= "Unknown" then
                UI.NextTrial:SetDesc(string.format("%s | Map: %s | Time Left: %s", analysis.nextTrialName, analysis.nextTrialMap, analysis.nextTimeRemaining))
            else
                UI.NextTrial:SetDesc(string.format("%s | Time Left: %s", analysis.nextTrialName, analysis.nextTimeRemaining))
            end
        end)
    end

    if UI.OwnedTrialLabels then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local trialsList = nil
            if PlayerDataHandler and typeof(PlayerDataHandler.GetAllTrialsList) == "function" then
                trialsList = PlayerDataHandler:GetAllTrialsList()
            end
            if trialsList and #trialsList > 0 then
                for _, tInfo in ipairs(trialsList) do
                    local lbl = UI.OwnedTrialLabels[tInfo.Name] or UI.OwnedTrialLabels[tInfo.Title]
                    if not lbl then
                        for k, v in pairs(UI.OwnedTrialLabels) do
                            if normalizeString(k) == normalizeString(tInfo.Name) or normalizeString(k) == normalizeString(tInfo.Title) then
                                lbl = v
                                break
                            end
                        end
                    end
                    if lbl then
                        local stat = tInfo.Status
                        if stat == "✓" or stat == true or tostring(stat):find("✓") then
                            stat = "YES"
                        elseif stat == "✗" or stat == false or tostring(stat):find("✗") then
                            stat = "NO"
                        end
                        lbl:SetDesc(string.format("Map: %s | Owned: %s", tInfo.Map, stat))
                    end
                end
            else
                local status = PlayerDataHandler and typeof(PlayerDataHandler.GetTrialsStatus) == "function" and PlayerDataHandler:GetTrialsStatus()
                local wonLookup = {}
                if status and status.Won then
                    for _, n in ipairs(status.Won) do
                        wonLookup[n] = true
                        wonLookup[normalizeString(n)] = true
                    end
                end
                for _, tDef in ipairs(staticTrialDefs) do
                    local lbl = UI.OwnedTrialLabels[tDef.Name] or UI.OwnedTrialLabels[tDef.Title]
                    if not lbl then
                        for k, v in pairs(UI.OwnedTrialLabels) do
                            if normalizeString(k) == normalizeString(tDef.Name) or normalizeString(k) == normalizeString(tDef.Title) then
                                lbl = v
                                break
                            end
                        end
                    end
                    if lbl then
                        local isWon = false
                        if PlayerDataHandler and typeof(PlayerDataHandler.IsTrialWon) == "function" then
                            isWon = PlayerDataHandler:IsTrialWon(tDef.Name) or PlayerDataHandler:IsTrialWon(tDef.Title)
                        elseif wonLookup[tDef.Name] or wonLookup[tDef.Title] or wonLookup[normalizeString(tDef.Name)] then
                            isWon = true
                        end
                        lbl:SetDesc(string.format("Map: %s | Owned: %s", tDef.Map, isWon and "YES" or "NO"))
                    end
                end
            end
        end)
    end

    if UI.ProgCoinTowers or UI.ProgGemTowers or UI.ProgEvoTowers or UI.ProgGoldenSkins or UI.ProgSkillTree then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end

            -- 1. Coin Towers
            if UI.ProgCoinTowers and TowerList and TowerList.Coins then
                local totalCoins = #TowerList.Coins
                local ownedCoins = 0
                local missingCoins = {}
                local totalMissingCoinsCost = 0

                for _, t in ipairs(TowerList.Coins) do
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        isOwned = PlayerDataHandler:IsTowerOwned(t.Name)
                    end
                    if isOwned then
                        ownedCoins = ownedCoins + 1
                    else
                        table.insert(missingCoins, t.Name)
                        totalMissingCoinsCost = totalMissingCoinsCost + (t.Cost or 0)
                    end
                end

                if ownedCoins >= totalCoins then
                    UI.ProgCoinTowers:SetTitle(string.format("Coin Towers (%d/%d)", totalCoins, totalCoins))
                    UI.ProgCoinTowers:SetDesc("✓ All Coin Towers Owned")
                else
                    UI.ProgCoinTowers:SetTitle(string.format("Coin Towers (%d/%d)", ownedCoins, totalCoins))
                    if #missingCoins <= 3 then
                        UI.ProgCoinTowers:SetDesc(string.format("Missing: %s | Cost: %s Coins", table.concat(missingCoins, ", "), formatNumberWithCommas(totalMissingCoinsCost)))
                    else
                        UI.ProgCoinTowers:SetDesc(string.format("Missing: %d Towers | Cost: %s Coins", #missingCoins, formatNumberWithCommas(totalMissingCoinsCost)))
                    end
                end
            end

            -- 2. Hardcore Towers
            if UI.ProgGemTowers and TowerList and TowerList.Gems then
                local totalGems = #TowerList.Gems
                local ownedGems = 0
                local missingGems = {}
                local totalMissingGemsCost = 0

                for _, t in ipairs(TowerList.Gems) do
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        isOwned = PlayerDataHandler:IsTowerOwned(t.Name)
                    end
                    if isOwned then
                        ownedGems = ownedGems + 1
                    else
                        table.insert(missingGems, t.Name)
                        totalMissingGemsCost = totalMissingGemsCost + (t.Cost or 0)
                    end
                end

                if ownedGems >= totalGems then
                    UI.ProgGemTowers:SetTitle(string.format("Hardcore Towers (%d/%d)", totalGems, totalGems))
                    UI.ProgGemTowers:SetDesc("✓ All Hardcore Towers Owned")
                else
                    UI.ProgGemTowers:SetTitle(string.format("Hardcore Towers (%d/%d)", ownedGems, totalGems))
                    UI.ProgGemTowers:SetDesc(string.format("Missing: %s | Cost: %s Gems", table.concat(missingGems, ", "), formatNumberWithCommas(totalMissingGemsCost)))
                end
            end

            -- 3. Evolved Towers
            if UI.ProgEvoTowers then
                local evoDefs = {
                    { Base = "Scout", Evo = "EvolvedOperator", Coins = 15000, Gems = 4500 },
                    { Base = "Shotgunner", Evo = "EvolvedEnforcer", Coins = 15000, Gems = 5000 },
                    { Base = "Crook Boss", Evo = "EvolvedKingpin", Coins = 15000, Gems = 5500 },
                    { Base = "Minigunner", Evo = "EvolvedJuggernaut", Coins = 15000, Gems = 6000 },
                }
                local totalEvo = #evoDefs
                local ownedEvo = 0
                local activeTarget = nil
                local activeExpData = nil
                local missingEvoBases = {}

                for _, def in ipairs(evoDefs) do
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        isOwned = PlayerDataHandler:IsTowerOwned(def.Evo)
                    end
                    if not isOwned and typeof(isTowerEvoComplete) == "function" then
                        isOwned = isTowerEvoComplete(def.Evo) or isTowerEvoComplete(def.Base)
                    end

                    if isOwned then
                        ownedEvo = ownedEvo + 1
                    else
                        table.insert(missingEvoBases, def.Base)
                        if not activeTarget then
                            activeTarget = def
                            if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                                pcall(function()
                                    activeExpData = PlayerDataHandler:GetTowerExp(def.Base)
                                end)
                            end
                        end
                    end
                end

                if ownedEvo >= totalEvo then
                    UI.ProgEvoTowers:SetTitle(string.format("Evolved Towers (%d/%d)", totalEvo, totalEvo))
                    UI.ProgEvoTowers:SetDesc("✓ All Evolved Towers Owned & Complete")
                elseif activeTarget then
                    UI.ProgEvoTowers:SetTitle(string.format("Evolved Towers (%d/%d)", ownedEvo, totalEvo))

                    local baseLvl = (activeExpData and type(activeExpData.Level) == "number") and activeExpData.Level or 0
                    local curExp = (activeExpData and type(activeExpData.Exp) == "number") and activeExpData.Exp or 0
                    local maxExp = (activeExpData and type(activeExpData.MaxExp) == "number") and activeExpData.MaxExp or 0
                    local missingExp = math.max(0, maxExp - curExp)

                    if baseLvl < 20 then
                        if maxExp > 0 then
                            UI.ProgEvoTowers:SetDesc(string.format("[%s] Lvl %d/20 (%s/%s EXP | -%s EXP) | Needs %sk C, %sk G",
                                activeTarget.Base, baseLvl, formatNumberWithCommas(curExp), formatNumberWithCommas(maxExp), formatNumberWithCommas(missingExp),
                                tostring(activeTarget.Coins / 1000), tostring(activeTarget.Gems / 1000)))
                        else
                            UI.ProgEvoTowers:SetDesc(string.format("[%s] Lvl %d/20 (EXP: %s) | Needs %sk C, %sk G",
                                activeTarget.Base, baseLvl, formatNumberWithCommas(curExp),
                                tostring(activeTarget.Coins / 1000), tostring(activeTarget.Gems / 1000)))
                        end
                    else
                        local playerCoins = 0
                        local playerGems = 0
                        pcall(function()
                            if typeof(PlayerDataHandler.GetCoins) == "function" then playerCoins = PlayerDataHandler:GetCoins() or 0 end
                            if typeof(PlayerDataHandler.GetGems) == "function" then playerGems = PlayerDataHandler:GetGems() or 0 end
                        end)
                        local coinsNeed = math.max(0, activeTarget.Coins - playerCoins)
                        local gemsNeed = math.max(0, activeTarget.Gems - playerGems)
                        if coinsNeed == 0 and gemsNeed == 0 then
                            UI.ProgEvoTowers:SetDesc(string.format("[%s] Lvl 20 Reached! Ready to Evolve in Lobby!", activeTarget.Base))
                        else
                            local needParts = {}
                            if coinsNeed > 0 then table.insert(needParts, formatNumberWithCommas(coinsNeed) .. " Coins") end
                            if gemsNeed > 0 then table.insert(needParts, formatNumberWithCommas(gemsNeed) .. " Gems") end
                            UI.ProgEvoTowers:SetDesc(string.format("[%s] Lvl 20 Reached! Needs: %s to Evolve", activeTarget.Base, table.concat(needParts, ", ")))
                        end
                    end
                else
                    UI.ProgEvoTowers:SetTitle(string.format("Evolved Towers (%d/%d)", ownedEvo, totalEvo))
                    UI.ProgEvoTowers:SetDesc(string.format("Missing: %s", table.concat(missingEvoBases, ", ")))
                end
            end

            -- 3. Golden Skins
            if UI.ProgGoldenSkins and TowerList and TowerList.Golden then
                local totalGold = #TowerList.Golden
                local ownedGold = 0
                local missingGold = {}
                local totalMissingGoldCost = 0

                for _, g in ipairs(TowerList.Golden) do
                    local baseTower = g.Name:gsub("^Golden%s+", "")
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsGoldenOwned) == "function" then
                        isOwned = PlayerDataHandler:IsGoldenOwned(g.Name) or PlayerDataHandler:IsGoldenOwned(baseTower)
                    end
                    if isOwned then
                        ownedGold = ownedGold + 1
                    else
                        table.insert(missingGold, g.Name)
                        totalMissingGoldCost = totalMissingGoldCost + (g.Cost or 50000)
                    end
                end

                if ownedGold >= totalGold then
                    UI.ProgGoldenSkins:SetTitle(string.format("Golden Skins (%d/%d)", totalGold, totalGold))
                    UI.ProgGoldenSkins:SetDesc("✓ All Golden Skins Owned")
                else
                    UI.ProgGoldenSkins:SetTitle(string.format("Golden Skins (%d/%d)", ownedGold, totalGold))
                    if #missingGold <= 2 then
                        UI.ProgGoldenSkins:SetDesc(string.format("Missing: %s | Cost: %s Coins", table.concat(missingGold, ", "), formatNumberWithCommas(totalMissingGoldCost)))
                    else
                        UI.ProgGoldenSkins:SetDesc(string.format("Missing: %d Skins | Cost: %s Coins", #missingGold, formatNumberWithCommas(totalMissingGoldCost)))
                    end
                end
            end

            -- 4. Skill Tree
            if UI.ProgSkillTree then
                local totalSkills = 17
                local maxedSkills = 0
                local skills = (PlayerDataHandler and typeof(PlayerDataHandler.GetSkillTree) == "function") and PlayerDataHandler:GetSkillTree() or {}
                local skillMap = {}
                for _, sk in ipairs(skills) do
                    local idNum = tonumber(sk.Id)
                    if not idNum and sk.Name and SkillNameToId[sk.Name] then
                        idNum = tonumber(SkillNameToId[sk.Name])
                    end
                    if idNum then
                        skillMap[idNum] = parseSkillInfo(sk, idNum)
                    end
                end

                local activeUnmaxed = nil
                for id = 1, totalSkills do
                    local info = skillMap[id] or parseSkillInfo(nil, id)
                    if info.IsMaxed then
                        maxedSkills = maxedSkills + 1
                    elseif not activeUnmaxed then
                        activeUnmaxed = info
                    end
                end

                if maxedSkills >= totalSkills then
                    UI.ProgSkillTree:SetTitle(string.format("Skill Tree (%d/%d)", totalSkills, totalSkills))
                    UI.ProgSkillTree:SetDesc("✓ All Skills Maxed")
                else
                    UI.ProgSkillTree:SetTitle(string.format("Skill Tree (%d/%d Maxed)", maxedSkills, totalSkills))
                    if activeUnmaxed then
                        UI.ProgSkillTree:SetDesc(string.format("ID %s: %d / %d (%s)", activeUnmaxed.Id, activeUnmaxed.Level, activeUnmaxed.MaxLevel, activeUnmaxed.Name))
                    else
                        UI.ProgSkillTree:SetDesc(string.format("Missing: %d Skills", totalSkills - maxedSkills))
                    end
                end
            end
        end)
    end

    if UI.TimescaleSessionLabel then
        pcall(function()
            local targetLimit = (Globals.TargetTimescale and Globals.TargetTimescale > 0) and tostring(Globals.TargetTimescale) or "Infinite"
            UI.TimescaleSessionLabel:SetDesc(string.format("Timescale Matches: %d / %s", Globals.TimescaleUsedSession or 0, targetLimit))
        end)
    end

    if UI.StatusLabel or UI.FarmStatusLabel then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local sTitle = "Status: Checking..."
            local sDesc = ""
            if not analysis.configFound then
                sTitle = "Status: Config Missing"
                sDesc = "No configuration for: " .. tostring(analysis.trialName)
            elseif #missingParts > 0 then
                sTitle = "Status: Missing Requirements"
                sDesc = table.concat(missingParts, " | ")
            elseif not analysis.isSelectedInFilter then
                if isPremiumUser and analysis.useFallback and analysis.fallbackMode ~= "None" then
                    sTitle = "Status: Fallback Activated"
                    sDesc = Globals.AutoTrials and ("Switching to fallback mode: " .. analysis.fallbackMode) or "Fallback ready."
                else
                    sTitle = "Status: Trial Skipped"
                    sDesc = tostring(analysis.trialName) .. " not in selected filter."
                end
            else
                -- All requirements met and trial selected in filter!
                if game.PlaceId == LOBBY_PLACE_ID then
                    if Globals.AutoTrials and not Globals.AutoGold then
                        sTitle = "Status: Queuing Trial"
                        sDesc = "Queuing for matched trial: " .. tostring(analysis.trialName)
                    else
                        sTitle = "Status: Trial Eligible"
                        sDesc = "All requirements met for " .. tostring(analysis.trialName)
                    end
                else
                    -- In Game!
                    sTitle = "Status: Ready (In Match)"
                    if analysis.currentMap and analysis.currentMap ~= "Unknown" then
                        sDesc = string.format("Match Active: %s | Map: %s", tostring(analysis.trialName), tostring(analysis.currentMap))
                    else
                        sDesc = "Match Active: " .. tostring(analysis.trialName)
                    end
                end
            end

            if UI.FarmStatusLabel then
                UI.FarmStatusLabel:SetTitle(sTitle)
                UI.FarmStatusLabel:SetDesc(sDesc)
            end
            if UI.StatusLabel and UI.StatusLabel ~= UI.FarmStatusLabel then
                UI.StatusLabel:SetTitle(sTitle)
                UI.StatusLabel:SetDesc(sDesc)
            end
        end)
    end

    if UI.AutoGoldStatusLabel or UI.AutoGoldMissingLabel then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local goldAnalysis = analyzeAutoGoldRequirements()
            local selectedModeStr = string.format("%s (%s)", goldAnalysis.farmType, goldAnalysis.stratChoice)

            if UI.AutoGoldStatusLabel then
                UI.AutoGoldStatusLabel:SetTitle("Status: " .. selectedModeStr)
                if not goldAnalysis.configFound then
                    UI.AutoGoldStatusLabel:SetDesc("Config Missing")
                elseif not goldAnalysis.isEligible then
                    UI.AutoGoldStatusLabel:SetDesc("🔒 Locked (Missing Requirements)")
                elseif game.PlaceId == LOBBY_PLACE_ID then
                    if Globals.AutoGold then
                        UI.AutoGoldStatusLabel:SetDesc("Queuing for " .. tostring(goldAnalysis.targetMode) .. " (" .. goldAnalysis.farmType .. ")...")
                    else
                        UI.AutoGoldStatusLabel:SetDesc("Ready (Automation Off)")
                    end
                else
                    -- In Game!
                    UI.AutoGoldStatusLabel:SetDesc("In Match: " .. tostring(goldAnalysis.targetMode) .. " (" .. selectedModeStr .. ")")
                end
            end

            if UI.AutoGoldMissingLabel then
                UI.AutoGoldMissingLabel:SetTitle("Missing:")
                if #goldAnalysis.missingParts > 0 then
                    UI.AutoGoldMissingLabel:SetDesc(table.concat(goldAnalysis.missingParts, " | "))
                else
                    UI.AutoGoldMissingLabel:SetDesc("None (All requirements met)")
                end
            end
        end)
    end

    if UI.AutoEvoStatusLabel or UI.AutoEvoMissingLabel then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local evoAnalysis = analyzeAutoEvoRequirements()
            local displayTarget = evoAnalysis.targetEvo
            if evoAnalysis.targetEvo == "All" and evoAnalysis.activeTower then
                displayTarget = "All [" .. evoAnalysis.activeTower .. "]"
            end
            local selectedModeStr = string.format("%s (%s)", displayTarget, evoAnalysis.stratChoice)

            if UI.AutoEvoStatusLabel then
                UI.AutoEvoStatusLabel:SetTitle("Status: " .. selectedModeStr)
                if evoAnalysis.allFinished then
                    UI.AutoEvoStatusLabel:SetDesc("Finished (All Evolutions Complete)")
                elseif not evoAnalysis.configFound and not evoAnalysis.readyToBuy then
                    UI.AutoEvoStatusLabel:SetDesc("Config Missing")
                elseif not evoAnalysis.isEligible then
                    UI.AutoEvoStatusLabel:SetDesc("🔒 Locked (Missing Requirements)")
                elseif evoAnalysis.readyToBuy then
                    if Globals.AutoEvo then
                        UI.AutoEvoStatusLabel:SetDesc("Buying Evolution: " .. tostring(evoAnalysis.activeTower) .. "...")
                    else
                        UI.AutoEvoStatusLabel:SetDesc("Ready (Can Evolve " .. tostring(evoAnalysis.activeTower) .. ")")
                    end
                elseif game.PlaceId == LOBBY_PLACE_ID then
                    if Globals.AutoEvo then
                        UI.AutoEvoStatusLabel:SetDesc(string.format("Queuing: %s - %s (%s)...", tostring(evoAnalysis.activeTower), tostring(evoAnalysis.targetMode), tostring(evoAnalysis.farmType)))
                    else
                        UI.AutoEvoStatusLabel:SetDesc("Ready (Automation Off)")
                    end
                else
                    -- In Game!
                    UI.AutoEvoStatusLabel:SetDesc(string.format("In Match: %s - %s (%s)", tostring(evoAnalysis.activeTower), tostring(evoAnalysis.targetMode), tostring(evoAnalysis.farmType)))
                end
            end

            if UI.AutoEvoMissingLabel then
                UI.AutoEvoMissingLabel:SetTitle("Missing:")
                if evoAnalysis.allFinished then
                    UI.AutoEvoMissingLabel:SetDesc("None (All targets complete)")
                elseif #evoAnalysis.missingParts > 0 then
                    UI.AutoEvoMissingLabel:SetDesc(table.concat(evoAnalysis.missingParts, " | "))
                else
                    UI.AutoEvoMissingLabel:SetDesc("None (All requirements met)")
                end
            end
        end)
    end

    if game.PlaceId ~= LOBBY_PLACE_ID then
        if UI.Window and UI.Window.SetSubtitle then
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                UI.Window:SetSubtitle("IN-GAME : " .. tostring(analysis.trialName))
            end)
        end
        return
    end

    if not Globals.AutoTrials then
        if Globals.AutoEvo then
            local evoAnalysis = (typeof(analyzeAutoEvoRequirements) == "function") and analyzeAutoEvoRequirements()
            if evoAnalysis then
                if evoAnalysis.readyToBuy then
                    if UI.Window and UI.Window.SetSubtitle then
                        UI.Window:SetSubtitle(string.format("LOBBY : Ready to Evolve (%s)", tostring(evoAnalysis.activeTower or "Tower")))
                    end
                elseif evoAnalysis.allFinished then
                    if UI.Window and UI.Window.SetSubtitle then
                        UI.Window:SetSubtitle("LOBBY : Auto Evo Complete (All Evolved)")
                    end
                elseif evoAnalysis.isEligible then
                    local stratChoice = evoAnalysis.stratChoice or "Win"
                    local needType = evoAnalysis.farmType or "Coins"
                    local activeTower = evoAnalysis.activeTower or "Tower"
                    local targetMode = evoAnalysis.targetMode or "Fallen"
                    if UI.Window and UI.Window.SetSubtitle then
                        UI.Window:SetSubtitle(string.format("LOBBY : Queuing %s (%s - %s)", tostring(activeTower), tostring(targetMode), tostring(needType)))
                    end
                    saveActiveMode("AutoEvo")
                    AutoGoldModule.QueueGold(stratChoice, needType)
                else
                    if UI.Window and UI.Window.SetSubtitle then
                        UI.Window:SetSubtitle("LOBBY : Auto Evo Locked (Missing Requirements)")
                    end
                end
            end
            return
        else
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                if UI.Window and UI.Window.SetSubtitle then
                    UI.Window:SetSubtitle("LOBBY : Automation Disabled (Idle)")
                end
                if UI.FarmStatusLabel then
                    UI.FarmStatusLabel:SetTitle("Status: Automation Paused")
                    UI.FarmStatusLabel:SetDesc("Farm Mode is turned OFF.")
                end
                if UI.ProgStatusLabel then
                    UI.ProgStatusLabel:SetTitle("Status: Automation Paused")
                    UI.ProgStatusLabel:SetDesc("Progression Mode is turned OFF.")
                end
                if UI.StatusLabel and UI.StatusLabel ~= UI.FarmStatusLabel then
                    UI.StatusLabel:SetTitle("Status: Automation Paused")
                    UI.StatusLabel:SetDesc("Auto Trials is turned OFF.")
                end
            end)
            return
        end
    end

    if Globals.TrialFarmMode == "Farm Mode" and Globals.TargetTimescale and Globals.TargetTimescale > 0 and (Globals.TimescaleUsedSession or 0) >= Globals.TargetTimescale then
        Globals.AutoTrials = false
        SetSetting("AutoTrials", false)
        if UI.FarmToggle then UI.FarmToggle:SetValue(false) end
        if UI.AutoToggle then UI.AutoToggle:SetValue(false) end
        if UI.Window and UI.Window.SetSubtitle then
            UI.Window:SetSubtitle(string.format("LOBBY : Target Timescale Reached (%d/%d)", Globals.TimescaleUsedSession or 0, Globals.TargetTimescale))
        end
        if UI.FarmStatusLabel then
            UI.FarmStatusLabel:SetTitle("Status: Target Reached")
            UI.FarmStatusLabel:SetDesc(string.format("Completed %d/%d timescale matches. Farm paused in Smart Lobby.", Globals.TimescaleUsedSession or 0, Globals.TargetTimescale))
        end
        logActivity(string.format("[Target Timescale] Reached %d matches. Paused in Smart Lobby.", Globals.TargetTimescale), "warn")
        return
    end

    local isFarmOnlyActive = isPremiumUser and (Globals.FarmOnly == "Farm Only")
    local isOwnedModeActive = isPremiumUser and (Globals.TrialFarmMode == "Progression Mode")

    pcall(processAutoPurchases)

    -- Lobby Subtitle and Matchmaking Trigger
    if isRequirementLocked and (not isOwnedModeActive or (not Globals.AutoGold and not Globals.AutoEvo)) then
        if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : 🔒 Missing Requirements") end
    elseif not isKeyUser then
        local isTrialOwned = analysis.isOwned or checkIsTrialWon(analysis.trialName)
        if isTrialOwned then
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Keyless - Trial Owned (Waiting Next)") end
            if UI.FarmStatusLabel then UI.FarmStatusLabel:SetTitle("Status: Keyless Waiting"); UI.FarmStatusLabel:SetDesc("Current trial is already owned. Waiting for the next rotation.") end
            if UI.StatusLabel and UI.StatusLabel ~= UI.FarmStatusLabel then UI.StatusLabel:SetTitle("Status: Keyless Waiting"); UI.StatusLabel:SetDesc("Current trial is already owned. Waiting for the next rotation.") end
        elseif analysis.isEligible and analysis.isSelectedInFilter and not isRequirementLocked then
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Keyless - Queuing " .. analysis.trialName) end
            if UI.FarmStatusLabel then UI.FarmStatusLabel:SetTitle("Status: Queuing Trial"); UI.FarmStatusLabel:SetDesc("Keyless: Queuing unowned trial: " .. tostring(analysis.trialName)) end
            if UI.StatusLabel and UI.StatusLabel ~= UI.FarmStatusLabel then UI.StatusLabel:SetTitle("Status: Queuing Trial"); UI.StatusLabel:SetDesc("Keyless: Queuing unowned trial: " .. tostring(analysis.trialName)) end
            if Globals.AutoTrials then saveActiveMode("AutoTrials"); triggerTrialsQueue(analysis.trialName) end
        else
            local failReason = not analysis.isEligible and "Requirements Unmet" or "Trial Skipped"
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Keyless - Criteria Unmet / Waiting") end
            if UI.FarmStatusLabel then UI.FarmStatusLabel:SetTitle("Status: " .. failReason); UI.FarmStatusLabel:SetDesc("Requirements unmet for current trial.") end
            if UI.StatusLabel and UI.StatusLabel ~= UI.FarmStatusLabel then UI.StatusLabel:SetTitle("Status: " .. failReason); UI.StatusLabel:SetDesc("Requirements unmet for current trial.") end
        end
    elseif isFarmOnlyActive then
        if analysis.isOwned then
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Trial Owned (Waiting Next)") end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Trial Owned (Waiting)")
                UI.StatusLabel:SetDesc("Farm Only: " .. tostring(analysis.trialName) .. " already owned. Waiting for rotation.")
            end
        elseif analysis.isEligible and analysis.isSelectedInFilter then
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Queuing Trial " .. analysis.trialName) or ("LOBBY : Ready (" .. analysis.trialName .. ")"))
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoTrials")
                triggerTrialsQueue(analysis.trialName)
            end
        else
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Farm Only (Waiting Rotation)") end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Farm Only Waiting")
                UI.StatusLabel:SetDesc("Current trial not selected/eligible. Waiting for next rotation.")
            end
        end
    elseif isOwnedModeActive then
        pcall(processAutoPurchases)
        local function setProgressionStatus(title, desc)
            pcall(function()
                if UI.ProgStatusLabel then
                    UI.ProgStatusLabel:SetTitle(title)
                    UI.ProgStatusLabel:SetDesc(desc)
                end
                if UI.FarmStatusLabel then
                    UI.FarmStatusLabel:SetTitle("Status: Progression Active")
                    UI.FarmStatusLabel:SetDesc(desc)
                end
                if UI.StatusLabel and UI.StatusLabel ~= UI.FarmStatusLabel then
                    UI.StatusLabel:SetTitle(title)
                    UI.StatusLabel:SetDesc(desc)
                end
            end)
        end
        local action, arg1, arg2, arg3 = evaluateOwnedModeAction(analysis)

        if action == "EverythingMaxed" then
            action = "Fallback"
            arg1 = (analysis.fallbackMode and analysis.fallbackMode ~= "Smart Auto" and analysis.fallbackMode ~= "None") and analysis.fallbackMode or "Hardcore"
        end

        if action == "BeatUnownedTrial" then
            local trialName = arg1 or analysis.trialName
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Beating Unowned " .. trialName) or ("LOBBY : Ready (" .. trialName .. ")"))
            end
            setProgressionStatus("Status: Queuing Unowned Trial", "Beating unowned trial: " .. tostring(trialName))
            if Globals.AutoTrials then
                saveActiveMode("AutoTrials")
                triggerTrialsQueue(trialName)
            end
        elseif action == "FarmCoins" then
            local stratChoice = arg1 or "Molten"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Farming Coins (" .. stratChoice .. ")") or "LOBBY : Priority (Coin Towers)")
            end
            setProgressionStatus("Status: Farming Coins", "Progression Mode: Grinding coins for missing coin towers.")
            if Globals.AutoTrials then
                saveActiveMode("AutoGold")
                AutoGoldModule.QueueGold(stratChoice, "Coins")
            end
        elseif action == "FarmGems" then
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and "LOBBY : Farming Gems (Hardcore Lose)" or "LOBBY : Priority (Hardcore Towers)")
            end
            setProgressionStatus("Status: Farming Gems", "Progression Mode: Grinding gems (Hardcore Lose) for hardcore towers.")
            if Globals.AutoTrials then
                saveActiveMode("AutoGold")
                AutoGoldModule.QueueGold("Lose", "Gems")
            end
        elseif action == "EvoReadyInLobby" then
            local activeTower = arg1 or "Tower"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle("LOBBY : Ready to Evolve (" .. activeTower .. ")")
            end
            setProgressionStatus("Status: Evolving Tower", "Progression Mode: Level 20 reached! Evolving " .. activeTower .. " in lobby.")
        elseif action == "FarmEvo" then
            local stratChoice = arg1 or "Lose"
            local needType = arg2 or "Coins"
            local activeTower = arg3 or "Scout"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and string.format("LOBBY : Leveling Evo (%s - %s)", activeTower, needType) or string.format("LOBBY : Evo Ready (%s)", activeTower))
            end
            setProgressionStatus("Status: Leveling Evo Tower", string.format("Progression Mode: Grinding %s / EXP for %s.", needType, activeTower))
            if Globals.AutoTrials then
                saveActiveMode("AutoEvo")
                AutoGoldModule.QueueGold(stratChoice, needType)
            end
        elseif action == "FarmGoldSkins" then
            local stratChoice = arg1 or "Molten"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Farming Gold Skins (" .. stratChoice .. ")") or "LOBBY : Priority (Golden Skins)")
            end
            setProgressionStatus("Status: Farming Coins", "Progression Mode: Grinding 50,000 coins for Golden Crates.")
            if Globals.AutoTrials then
                saveActiveMode("AutoGold")
                AutoGoldModule.QueueGold(stratChoice, "Coins")
            end
        elseif action == "FarmSkillTree" then
            local stratChoice = arg1 or "Molten"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Farming Skill Tree (" .. stratChoice .. ")") or "LOBBY : Priority (Skill Tree)")
            end
            setProgressionStatus("Status: Farming Currency", "Progression Mode: Grinding currency for Skill Tree upgrades.")
            if Globals.AutoTrials then
                saveActiveMode("AutoGold")
                AutoGoldModule.QueueGold(stratChoice, "Coins")
            end
        elseif action == "Fallback" then
            local fbMode = arg1 or "Molten"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Fallback -> " .. fbMode) or "LOBBY : Fallback Ready")
            end
            setProgressionStatus("Status: Running Fallback", "Progression Mode: Trial already owned -> Running fallback: " .. fbMode)
            if Globals.AutoTrials then
                saveActiveMode("AutoTrials")
                triggerFallbackQueue(fbMode)
            end
        else
            local reason = analysis.isOwned and "Trial Owned (Waiting)" or "Criteria Unmet"
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : " .. reason) end
            setProgressionStatus("Status: " .. reason, analysis.isOwned and "Current trial already owned. Waiting for rotation." or "Missing requirements or filter unmet.")
        end
    elseif analysis.isEligible and analysis.isSelectedInFilter then
        if UI.Window and UI.Window.SetSubtitle then
            UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Queuing Trial " .. analysis.trialName) or ("LOBBY : Ready (" .. analysis.trialName .. ")"))
        end
        if UI.FarmStatusLabel then
            UI.FarmStatusLabel:SetTitle(Globals.AutoTrials and "Status: Queuing Trial" or "Status: Trial Ready")
            UI.FarmStatusLabel:SetDesc(isKeyUser and ("Key Mode: Repeating " .. tostring(analysis.trialName)) or ("Queuing " .. tostring(analysis.trialName)))
        end
        if UI.StatusLabel and UI.StatusLabel ~= UI.FarmStatusLabel then
            UI.StatusLabel:SetTitle(Globals.AutoTrials and "Status: Queuing Trial" or "Status: Trial Ready")
            UI.StatusLabel:SetDesc(isKeyUser and ("Key Mode: Repeating " .. tostring(analysis.trialName)) or ("Queuing " .. tostring(analysis.trialName)))
        end
        if Globals.AutoTrials and (not Globals.AutoGold or not isPremiumUser) then
            saveActiveMode("AutoTrials")
            triggerTrialsQueue(analysis.trialName)
        end
    elseif isPremiumUser and analysis.useFallback and analysis.fallbackMode ~= "None" then
        if UI.Window and UI.Window.SetSubtitle then
            UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Fallback -> " .. analysis.fallbackMode) or ("LOBBY : Fallback Ready"))
        end
        if Globals.AutoTrials and not Globals.AutoGold then
            saveActiveMode("AutoTrials")
            triggerFallbackQueue(analysis.fallbackMode)
        end
    else
        if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Criteria Unmet / Waiting") end
    end
end

--==============================================================================
-- Lobby Fast Check Data & Fast Queue Routine
--==============================================================================
fastQueueLobby = function()
    if setthreadidentity then pcall(setthreadidentity, 8) end
    if game.PlaceId ~= LOBBY_PLACE_ID then return end
    if not Globals.AutoTrials and not Globals.AutoEvo then return end

    if Globals.TrialFarmMode == "Farm Mode" and Globals.TargetTimescale and Globals.TargetTimescale > 0 and (Globals.TimescaleUsedSession or 0) >= Globals.TargetTimescale then
        Globals.AutoTrials = false
        SetSetting("AutoTrials", false)
        if UI.FarmToggle then UI.FarmToggle:SetValue(false) end
        if UI.AutoToggle then UI.AutoToggle:SetValue(false) end
        if UI.Window and UI.Window.SetSubtitle then
            UI.Window:SetSubtitle(string.format("LOBBY : Target Timescale Reached (%d/%d)", Globals.TimescaleUsedSession or 0, Globals.TargetTimescale))
        end
        if UI.FarmStatusLabel then
            UI.FarmStatusLabel:SetTitle("Status: Target Reached")
            UI.FarmStatusLabel:SetDesc(string.format("Completed %d/%d timescale matches. Paused in Smart Lobby.", Globals.TimescaleUsedSession or 0, Globals.TargetTimescale))
        end
        logActivity(string.format("[Target Timescale] Reached %d matches. Paused in Smart Lobby.", Globals.TargetTimescale), "warn")
        return
    end

    ensurePlayerDataReady(20)
    if not PlayerDataHandler then
        PlayerDataHandler = loadPlayerDataHandler()
    end

    if PlayerDataHandler then
        refreshDisplay()
    end

    if not Globals.AutoTrials then
        if Globals.AutoEvo then
            local evoAnalysis = (typeof(analyzeAutoEvoRequirements) == "function") and analyzeAutoEvoRequirements()
            if evoAnalysis and evoAnalysis.isEligible and not evoAnalysis.readyToBuy and not evoAnalysis.allFinished then
                local stratChoice = evoAnalysis.stratChoice or "Win"
                local needType = evoAnalysis.farmType or "Coins"
                lastQueueAttemptTime = 0
                saveActiveMode("AutoEvo")
                AutoGoldModule.QueueGold(stratChoice, needType)
            end
        end
        return
    end

    if Globals.MultiplayerEnabled and Globals.MultiplayerIsP2 then
        -- P2 follows Host matchmaking; do not start solo queue in lobby
        return
    end

    local isFarmOnlyActive = isPremiumUser and (Globals.FarmOnly == "Farm Only")
    local isOwnedModeActive = isPremiumUser and (Globals.TrialFarmMode == "Progression Mode")

    local analysis = analyzeCurrentTrial()
    local isTrialWon = analysis.isOwned or checkIsTrialWon(analysis.trialName) or false

    local isKeylessMode = not isKeyUser
    if isKeylessMode then
        if Globals.MultiplayerEnabled and Globals.MultiplayerIsHost then
            local p2Target = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
            local shouldQueue = not isTrialWon

            if p2Target ~= "" then
                local client_obj = GetPlayerFromIdentifier(p2Target)
                if client_obj then
                    if not (LocalPartyManager and LocalPartyManager.InPartyWith[client_obj.Name]) then
                        LocalPartyManager:CreateAndInvite(p2Target)
                    end
                else
                    -- P2 is not in server yet; wait for P2 before queueing
                    shouldQueue = false
                end
            end

            if shouldQueue and analysis.isSelectedInFilter and analysis.isEligible and not isRequirementLocked then
                lastQueueAttemptTime = 0
                saveActiveMode("AutoTrials")
                triggerTrialsQueue(analysis.trialName)
            end
        else
            -- Single-Player Keyless Guard:
            if analysis.isSelectedInFilter and not isTrialWon and analysis.isEligible and not isRequirementLocked then
                lastQueueAttemptTime = 0
                saveActiveMode("AutoTrials")
                triggerTrialsQueue(analysis.trialName)
            end
        end
    elseif isFarmOnlyActive then
        -- Farm Only: Fallbacks are ignored. Only farm trials in filter and ONLY ONCE.
        -- When already owned, just do nothing and wait for next trial.
        if analysis.isSelectedInFilter and not isTrialWon and analysis.isEligible and not isRequirementLocked then
            lastQueueAttemptTime = 0
            saveActiveMode("AutoTrials")
            triggerTrialsQueue(analysis.trialName)
        end
    elseif isOwnedModeActive then
        pcall(processAutoPurchases)
        local action, arg1, arg2, arg3 = evaluateOwnedModeAction(analysis)

        if action == "EverythingMaxed" then
            action = "Fallback"
            arg1 = (analysis.fallbackMode and analysis.fallbackMode ~= "Smart Auto" and analysis.fallbackMode ~= "None") and analysis.fallbackMode or "Hardcore"
        end

        if action == "BeatUnownedTrial" then
            local trialName = arg1 or analysis.trialName
            lastQueueAttemptTime = 0
            saveActiveMode("AutoTrials")
            triggerTrialsQueue(trialName)
        elseif action == "FarmCoins" or action == "FarmGoldSkins" or action == "FarmSkillTree" then
            local stratChoice = arg1 or "Molten"
            lastQueueAttemptTime = 0
            saveActiveMode("AutoGold")
            AutoGoldModule.QueueGold(stratChoice, "Coins")
        elseif action == "FarmGems" then
            lastQueueAttemptTime = 0
            saveActiveMode("AutoGold")
            AutoGoldModule.QueueGold("Lose", "Gems")
        elseif action == "FarmEvo" then
            local stratChoice = arg1 or "Lose"
            local needType = arg2 or "Coins"
            lastQueueAttemptTime = 0
            saveActiveMode("AutoEvo")
            AutoGoldModule.QueueGold(stratChoice, needType)
        elseif action == "Fallback" then
            local fbMode = arg1 or "Molten"
            lastQueueAttemptTime = 0
            saveActiveMode("AutoTrials")
            triggerFallbackQueue(fbMode)
        end
    else
        -- Standard Farm Mode:
        if not isRequirementLocked then
            if analysis.isEligible and analysis.isSelectedInFilter then
                lastQueueAttemptTime = 0
                saveActiveMode("AutoTrials")
                triggerTrialsQueue(analysis.trialName)
            elseif isPremiumUser and analysis.useFallback and analysis.fallbackMode ~= "None" then
                lastQueueAttemptTime = 0
                saveActiveMode("AutoTrials")
                triggerFallbackQueue(analysis.fallbackMode)
            end
        end
    end
end

--==============================================================================
-- In-Game Ready Guard
--==============================================================================
local function runInGameGuard()
    if game.PlaceId == LOBBY_PLACE_ID then return end

    task.spawn(function()
        pcall(function()
            if Globals.AutoTrials and not Globals.AutoGold and isPremiumUser then
                ensureDynamicHardcoreFallback()
                local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 15)
                local gsr = stateReplicators and stateReplicators:WaitForChild("GameStateReplicator", 15)
                if gsr then
                    local liveDifficulty = ""
                    local liveGameMode = ""
                    local savedTrial = ""
                    if typeof(loadTrialState) == "function" then
                        pcall(function() savedTrial = tostring(loadTrialState() or "") end)
                    end

                    local t0 = tick()
                    while tick() - t0 < 10 do
                        liveDifficulty = tostring(gsr:GetAttribute("Difficulty") or "")
                        liveGameMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or "")
                        if liveDifficulty ~= "" or liveGameMode ~= "" or savedTrial ~= "" then
                            break
                        end
                        task.wait(0.5)
                    end

                    for modeName, modeConfig in pairs(FallbackConfigs) do
                        local match = (liveDifficulty ~= "" and normalizeString(modeName) == normalizeString(liveDifficulty))
                            or (savedTrial ~= "" and normalizeString(modeName) == normalizeString(savedTrial))
                            or (normalizeString(modeName) == "hardcore" and (normalizeString(liveGameMode) == "hardcore" or normalizeString(savedTrial) == "hardcore"))
                        if match then
                            local mods = modeConfig.Modifiers or modeConfig.Modifers
                            if type(mods) == "table" and #mods == 1 and type(mods[1]) == "table" then
                                mods = mods[1]
                            end
                            local votedMap = AutoGoldModule.GameInfo(modeName, mods or {})
                            if not votedMap then return end
                            AutoGoldModule.LobbyReadyUp()
                            break
                        end
                    end
                end
            end
        end)
    end)

    task.spawn(function()
        local startTime = os.time()
        local readyPromptSeen = false
        while task.wait(1) do
            if not isRunning then break end
            if not (UI.ReadyGuard and UI.ReadyGuard.SetTitle) then break end

            if not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo then
                UI.ReadyGuard:SetTitle("Ready Guard: Paused")
                UI.ReadyGuard:SetDesc("Automation toggled off.")
                startTime = os.time()
                continue
            end

            local shouldRunTrialGuard = (currentMatchMode == "AutoTrials" or (Globals.AutoTrials and not Globals.AutoGold and not Globals.AutoEvo))
            if Globals.TrialFarmMode == "Progression Mode" and (currentMatchMode == "AutoGold" or currentMatchMode == "AutoEvo" or Globals.AutoEvo or Globals.AutoGold) then
                shouldRunTrialGuard = false
            end

            if shouldRunTrialGuard and not matchStratExecuted and not isStrategyExecuting then
                task.spawn(runMatchStrategyIfSaved)
            end

            local readyDone = isReadyPressedOrGameStarted()
            if readyDone then
                UI.ReadyGuard:SetTitle("Ready Guard: Confirmed YES")
                UI.ReadyGuard:SetDesc("Match in progress")
                if UI.ReadyGuardBar then
                    UI.ReadyGuardBar:SetProgress(1.0, "Match in progress (Active)")
                end
                if UI.Window and UI.Window.SetSubtitle then
                    UI.Window:SetSubtitle("IN GAME : Running Match")
                end
                startTime = os.time()
                readyPromptSeen = false
                continue
            end

            if isReadyPromptVisible() then
                if not readyPromptSeen then
                    readyPromptSeen = true
                    startTime = os.time()
                end
                
                -- Wait for map voting / intermission handling to conclude before readying up
                if not isMapIntermissionHandling and (intermissionMapHandled or (not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo)) then
                    if not (Globals.AutoEvo and not Globals.AutoGold and not Globals.AutoTrials) then
                        AutoGoldModule.LobbyReadyUp()
                    end
                end
            end

            local elapsed = os.time() - startTime
            -- Give 45 seconds timeout so the game can natively force-start the match without us teleporting
            local timeLeft = math.max(0, 45 - elapsed)

            if timeLeft > 0 then
                UI.ReadyGuard:SetTitle(string.format("Ready Guard: Waiting (%ds)", timeLeft))
                UI.ReadyGuard:SetDesc("Ready button not pressed. Counting down...")
                if UI.ReadyGuardBar then
                    UI.ReadyGuardBar:SetProgress(timeLeft / 45, string.format("%ds remaining", timeLeft))
                end
            else
                UI.ReadyGuard:SetTitle("Ready Guard: Teleporting")
                UI.ReadyGuard:SetDesc("Timeout! Returning to lobby...")
                if UI.ReadyGuardBar then
                    UI.ReadyGuardBar:SetProgress(0, "Timeout - Teleporting")
                end
                logActivity("Ready Guard timeout! Returning to lobby.", "warn")
                SmartTeleportToLobby()
                break
            end
        end
    end)
end

--==============================================================================
-- Auto Gold In-Game Execution Handler
--==============================================================================
handleAutoGoldExecution = function()
    if game.PlaceId == LOBBY_PLACE_ID or not isPremiumUser then return end

    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
        task.cancel(activeStratThread)
        activeStratThread = nil
    end

    local isOwnedActive = (Globals.TrialFarmMode == "Progression Mode" and Globals.AutoTrials)
    if not Globals.AutoGold and not Globals.AutoEvo and not isOwnedActive and currentMatchMode ~= "AutoGold" and currentMatchMode ~= "AutoEvo" then return end

    local isAutoEvoMatch = (currentMatchMode == "AutoEvo") or (Globals.AutoEvo and (not Globals.AutoGold or Globals.TrialFarmMode == "Progression Mode"))
    if not isAutoEvoMatch and (Globals.AutoGold or currentMatchMode == "AutoGold") then
        local goldAnalysis = analyzeAutoGoldRequirements()
        if not goldAnalysis.isEligible then
            Globals.AutoGold = false
            SetSetting("AutoGold", false)
            if UI.AutoGoldToggle then UI.AutoGoldToggle:SetValue(false) end
            if game.PlaceId == LOBBY_PLACE_ID then
                SmartTeleportToLobby()
            else
                Globals.IsConfigDirty = true
                if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                    RunAsExecutor(function()
                        UI.Window:Notify({
                            Title = "REQUIREMENTS LOCKED",
                            Desc = "Missing requirements for current farm type. Match will conclude before returning to lobby.",
                            Duration = 6,
                            Type = "warning"
                        })
                    end)()
                end
            end
            return
        end
    elseif Globals.AutoEvo or isAutoEvoMatch then
        local evoAnalysis = analyzeAutoEvoRequirements()
        if evoAnalysis and #evoAnalysis.missingParts > 0 and evoAnalysis.missingParts[1] == "Loading tower data..." then
            return
        end
        if not evoAnalysis.isEligible then
            Globals.AutoEvo = false
            SetSetting("AutoEvo", false)
            if UI.AutoEvoToggle then UI.AutoEvoToggle:SetValue(false) end
            if game.PlaceId == LOBBY_PLACE_ID then
                SmartTeleportToLobby()
            else
                Globals.IsConfigDirty = true
                if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                    RunAsExecutor(function()
                        UI.Window:Notify({
                            Title = "REQUIREMENTS LOCKED",
                            Desc = "Missing requirements for selected evolution. Match will conclude before returning to lobby.",
                            Duration = 6,
                            Type = "warning"
                        })
                    end)()
                end
            end
            return
        end
        if evoAnalysis.activeTower then
            Globals.CurrentEvoActiveTower = evoAnalysis.activeTower
            SetSetting("CurrentEvoActiveTower", evoAnalysis.activeTower)
        end
        if evoAnalysis.farmType then
            Globals.CurrentEvoFarmType = evoAnalysis.farmType
            SetSetting("CurrentEvoFarmType", evoAnalysis.farmType)
        end
        logActivity(string.format("[AutoEvo] Farming: %s (%s)", tostring(Globals.CurrentEvoActiveTower), tostring(Globals.CurrentEvoFarmType)), "info")
    end

    local config = getCurrentCrateConfig()
    local activeMap = config and config.Maps[1] or "Lay By"

    if config and config.Maps and #config.Maps > 0 then
        local mods = config.Modifiers or {}
        local votedMap = AutoGoldModule.GameInfo(config.Maps[1], mods)
        if type(votedMap) == "string" then
            activeMap = votedMap
            ----print(("[ServiceHub] Strategy map dynamically updated to:", activeMap)
        else
            return
        end
    end

    local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 10)
    local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")

    if gameStateReplicator then
        repeat
            task.wait(1)
            if not Globals.AutoGold and not Globals.AutoEvo and not isOwnedActive and currentMatchMode ~= "AutoGold" and currentMatchMode ~= "AutoEvo" then return end
        until (gameStateReplicator:GetAttribute("GameStarted") == true)
            or ((gameStateReplicator:GetAttribute("Wave") or 0) > 0)
            or PlayerGui:FindFirstChild("ReactUniversalHotbar")
    else
        task.wait(5)
    end

    if not Globals.AutoGold and not Globals.AutoEvo and not isOwnedActive and currentMatchMode ~= "AutoGold" and currentMatchMode ~= "AutoEvo" then return end

    AutoGoldModule.LobbyReadyUp()

    activeStratThread = task.spawn(function()
        executeActiveStrategy(activeMap)
    end)

    if not autoGoldWatcherRunning then
        autoGoldWatcherRunning = true
        task.spawn(function()
            while true do
                task.wait(1)
                if not isRunning then break end
                if game.PlaceId == LOBBY_PLACE_ID then break end

                if not Globals.AutoGold and not Globals.AutoEvo and not isOwnedActive then
                    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                        task.cancel(activeStratThread)
                        activeStratThread = nil
                    end
                end

                local currentStatus = GetMatchStatus()
                if (currentStatus == "LOSS" or currentStatus == "WIN") and not isHandlingEndMatch then
                    isHandlingEndMatch = true
                    local modeName = isAutoEvoMatch and "AutoEvo" or "AutoGold"
                    sendDiscordWebhook(currentStatus, modeName)

                    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                        pcall(task.cancel, activeStratThread)
                        activeStratThread = nil
                    end

                    if currentStatus == "WIN" or shouldTeleportOnMatchEnd(currentStatus) then
                        if currentStatus == "WIN" then
                            SmartTeleportToLobby()
                        end
                        autoGoldWatcherRunning = false
                        return
                    end

                    -- Auto Restart handling for Lose strat thread:
                    task.spawn(function()
                        local startVoteTime = tick()
                        while isRunning and (tick() - startVoteTime < 30) do
                            if GetMatchStatus() == nil then break end
                            fireSkipVoteUntilTrue()
                            task.wait(0.5)
                        end
                    end)

                    local waitStart = tick()
                    local restartSuccess = false
                    while isRunning and (tick() - waitStart < 35) do
                        if not Globals.AutoGold and not Globals.AutoEvo and not isOwnedActive and currentMatchMode ~= "AutoGold" and currentMatchMode ~= "AutoEvo" then break end
                        if GetMatchStatus() == nil then
                            restartSuccess = true
                            break
                        end
                        task.wait(0.5)
                    end

                    if not restartSuccess then
                        warn("[ServiceHub] Auto-Restart timed out waiting for rewards screen to close. Returning to lobby.")
                        SmartTeleportToLobby()
                        autoGoldWatcherRunning = false
                        return
                    end

                    local stateReps = ReplicatedStorage:WaitForChild("StateReplicators", 5)
                    local newGameStateReplicator = stateReps and stateReps:FindFirstChild("GameStateReplicator")

                    if newGameStateReplicator then
                        local readyStart = tick()
                        while (Globals.AutoGold or Globals.AutoEvo or isOwnedActive or currentMatchMode == "AutoGold" or currentMatchMode == "AutoEvo") do
                            if not isRunning then break end
                            local wave = newGameStateReplicator:GetAttribute("Wave") or 0
                            local uibar = PlayerGui:FindFirstChild("ReactUniversalHotbar") ~= nil
                            if uibar or wave > 0 then 
                                task.wait(2) -- Buffer to allow map models to fully render
                                break 
                            end
                            if tick() - readyStart > 25 then
                                break
                            end
                            task.wait(0.5)
                        end
                    else
                        task.wait(2)
                    end

                    snapshotMatchConfig()
                    isLateExecution = false
                    initialExecutionWave = 0
                    Globals.IsConfigDirty = false
                    isHandlingEndMatch = false
                    matchStratExecuted = false
                    isStrategyExecuting = false

                    if (Globals.AutoGold or Globals.AutoEvo or isOwnedActive or currentMatchMode == "AutoGold" or currentMatchMode == "AutoEvo") then
                        loadoutApplied = false -- Reset so TDS:Loadout can re-apply if needed
                        activeStratThread = task.spawn(function()
                            executeActiveStrategy(activeMap)
                        end)
                    else
                        SmartTeleportToLobby()
                    end
                end
            end
            autoGoldWatcherRunning = false
        end)
    end
end


--==============================================================================
-- Auto Gatling Integration
--==============================================================================
AutoGatlingRunning = false
do
    local GatlingExecuted = (Globals.GatlingLoaderLoaded == true)

    local function isGatlingEligible(): boolean
    if Globals.GatlingLoaderLoaded then return false end
    if Globals.AutoTrials then
        return true
    elseif Globals.AutoGold and tostring(Globals.Strat or "") == "Win" then
        return true
    elseif Globals.AutoEvo and tostring(Globals.EvoStrat or "") == "Win" then
        return true
    end
    local equippedTowers = Globals.EquippedTowers or {}
    for _, t in ipairs(equippedTowers) do
        if tostring(t):find("Gatling") then
            return true
        end
    end
    if PlayerGui:FindFirstChild("ReactUniversalHotbar") then
        local hotbar = PlayerGui.ReactUniversalHotbar:FindFirstChild("Frame")
        if hotbar then
            for _, child in ipairs(hotbar:GetChildren()) do
                if child:IsA("GuiObject") and child.Name:find("Gatling") then
                    return true
                end
            end
        end
    end
    return Globals.AutoGatling == true
end

    StartAutoGatling = function()
        if Globals.GatlingLoaderLoaded or GatlingExecuted then return end
        if AutoGatlingRunning or not Globals.AutoGatling then return end

        AutoGatlingRunning = true
        task.spawn(function()
            while Globals.AutoGatling and isRunning do
                if Globals.GatlingLoaderLoaded or GatlingExecuted then
                    break
                end

                local GameState = "LOBBY"
                if game.PlaceId ~= LOBBY_PLACE_ID then
                    local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
                    local gsr = sr and sr:FindFirstChild("GameStateReplicator")
                    if gsr and gsr:GetAttribute("GameStarted") == true then
                        GameState = "GAME"
                    end
                end

                if GameState == "GAME" and isGatlingEligible() then
                    if not Globals.GatlingLoaderLoaded and not GatlingExecuted then
                        GatlingExecuted = true 
                        Globals.GatlingLoaderLoaded = true
                        task.spawn(function()
                            local selected = Globals.SelectedGatling or "Gatlify"
                            local scriptFileName = (selected == "Gatling Gun") and "autogutlin.lua" or "Gatlify.lua"
                            local scriptUrl = (selected == "Gatling Gun")
                                and "https://raw.githubusercontent.com/avtryxz/autogutlin/refs/heads/main/autogutlin.lua"
                                or "https://raw.githubusercontent.com/avtryxz/Gatlify/refs/heads/main/Gatlify.lua"

                            local gatlingChunk = readLocalFile(scriptFileName, {
                                "[STAY]/[AutoTrailsFInal]/FinalVersion/" .. scriptFileName,
                                "[STAY]/[AutoTrailsFInal]/" .. scriptFileName,
                                "[STAY]/" .. scriptFileName,
                                scriptFileName,
                            })
                            if not gatlingChunk or #gatlingChunk == 0 then
                                gatlingChunk = safeHttpGet(scriptUrl, 3)
                            end
                            if gatlingChunk then
                                local success, func = pcall(loadstring, gatlingChunk)
                                if success and func then
                                    pcall(func)
                                    logActivity(string.format("[Gatling] Loaded %s macro successfully (One-time load).", selected), "success")
                                else
                                    warn(string.format("[ServiceHub Gatling] Failed to execute %s", selected))
                                    Globals.GatlingLoaderLoaded = false
                                    GatlingExecuted = false
                                end
                            else
                                Globals.GatlingLoaderLoaded = false
                                GatlingExecuted = false
                            end
                        end)
                        break -- The Gatling Loader should only load once!
                    end
                end
                task.wait(1)
            end
            AutoGatlingRunning = false
        end)
    end
end

-- Auto Reload Gatling Logic
AutoReloadRunning = false
do
    local function hasLeadStatus(npc)
    local StatusEffects = npc:FindFirstChild("StatusEffects")
    if StatusEffects then
        local attributes = StatusEffects:GetAttributes()
        for _, val in pairs(attributes) do
            if type(val) == "string" and (string.find(val, '"definitionName":"Lead"') or string.find(val, '"id":"se_15"')) then
                return true
            end
        end
    end
    return false
end

local function isAliveNPC(npc): boolean
    local hpAttr = npc:GetAttribute("Health")
    if hpAttr ~= nil then
        local hpNum = tonumber(hpAttr)
        if hpNum ~= nil then
            return hpNum > 0
        end
    end

    local hum = npc:FindFirstChildOfClass("Humanoid")
    if hum then
        return hum.Health > 0
    end

    local valObj = npc:FindFirstChild("Health")
    if valObj and valObj:IsA("ValueBase") then
        local v = tonumber(valObj.Value)
        if v ~= nil then
            return v > 0
        end
    end

    return true
end

local function checkGatlingAmmo()
    local TowersFolder = workspace:FindFirstChild("Towers")
    local DefaultFolder = TowersFolder and TowersFolder:FindFirstChild("Default")

    if not DefaultFolder then return false, "No Towers Folder" end

    local myGatlingFound = false
    local ammoIsLow = false
    local details = ""
    local MyUserId = LocalPlayer.UserId

    for _, replicator in ipairs(DefaultFolder:GetChildren()) do
        if replicator.Name == "TowerReplicator" then
            local owner = replicator:GetAttribute("OwnerId")
            local towerName = replicator:GetAttribute("Name")

            if tonumber(owner) == MyUserId and towerName == "Gatling Gun" then
                myGatlingFound = true

                local currentAmmo = tonumber(replicator:GetAttribute("Ammo"))
                local maxAmmoAttr = tonumber(replicator:GetAttribute("MaxAmmo"))

                if currentAmmo and maxAmmoAttr and maxAmmoAttr > 0 then
                    local currentPercent = math.round((currentAmmo / maxAmmoAttr) * 100)
                    local threshold = Globals.GatlingReloadPercent or 100

                    if currentAmmo == maxAmmoAttr then
                        details = "Ammo full (100%)"
                    elseif currentPercent <= threshold then
                        ammoIsLow = true
                        details = string.format("Ammo low (%d%% <= %d%%)", currentPercent, threshold)
                    else
                        details = string.format("Ammo high (%d%% > %d%%)", currentPercent, threshold)
                    end
                else
                    details = "Missing Ammo Attributes"
                end
                break
            end
        end
    end

    if not myGatlingFound then
        return false, "Waiting for gatling..."
    elseif not ammoIsLow then
        return false, details
    end

    return true, "All Clear"
end

StartAutoReloadGatling = function()
    if AutoReloadRunning then return end
    AutoReloadRunning = true

    task.spawn(function()
        local clearTimer = 0
        local isCurrentlyReloading = false
        local reloadCooldown = 0
        local lastStatusDesc = ""
        local function updateReloadStatus(newDesc: string)
            if lastStatusDesc ~= newDesc then
                lastStatusDesc = newDesc
                if UI.AutoReloadStatusLabel then
                    UI.AutoReloadStatusLabel:SetDesc(newDesc)
                end
            end
        end

        while isRunning do
            task.wait(0.35) -- Mobile Optimization: Throttled from 0.1s to 0.35s

            if Globals.AutoReloadGatling and isPremiumUser then
                local GameState = "LOBBY"
                if game.PlaceId ~= LOBBY_PLACE_ID then
                    local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
                    local gsr = sr and sr:FindFirstChild("GameStateReplicator")
                    if gsr and gsr:GetAttribute("GameStarted") == true then
                        GameState = "GAME"
                    end
                end

                if GameState == "GAME" then
                    -- If we recently fired reload, wait for reload animation & ammo replenish
                    if isCurrentlyReloading then
                        reloadCooldown = reloadCooldown - 0.35
                        if UI.AutoReloadStatusLabel then
                            UI.AutoReloadStatusLabel:SetDesc(string.format("Status: Reloading in progress... (%.1fs)", math.max(0, reloadCooldown)))
                        end

                        local passesCheck = checkGatlingAmmo()
                        -- Once ammo is refilled or cooldown expires, reset reload lock
                        if not passesCheck or reloadCooldown <= 0 then
                            isCurrentlyReloading = false
                            clearTimer = 0
                        end
                        continue
                    end

                    -- Check 1: Tower ammo percentage
                    local passesTowerCheck, towerError = checkGatlingAmmo()
                    if not passesTowerCheck then
                        clearTimer = 0
                        if UI.AutoReloadStatusLabel then
                            UI.AutoReloadStatusLabel:SetDesc("Status: " .. towerError)
                        end
                        continue
                    end

                    -- Check 2: Check for standard (non-lead) NPCs on the map
                    local hasStandardNPC = false
                    local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
                    if sr then
                        for _, npc in ipairs(sr:GetChildren()) do
                            if npc.Name == "NPCReplicator" and isAliveNPC(npc) and not hasLeadStatus(npc) then
                                hasStandardNPC = true
                                break
                            end
                        end
                    end

                    if hasStandardNPC then
                        clearTimer = 0
                        if UI.AutoReloadStatusLabel then
                            UI.AutoReloadStatusLabel:SetDesc("Status: Locked (Standard NPCs Present)")
                        end
                    else
                        -- Map is clear of standard enemies! Count down 1.0 second
                        clearTimer = clearTimer + 0.35
                        local remaining = math.max(0, 1.0 - clearTimer)

                        if remaining > 0 then
                            if UI.AutoReloadStatusLabel then
                                UI.AutoReloadStatusLabel:SetDesc(string.format("Status: Safe window (%.1fs remaining)...", remaining))
                            end
                        else
                            -- 1 second is OUT! Fire the reload!
                            clearTimer = 0
                            isCurrentlyReloading = true
                            reloadCooldown = 3.0 -- Give 3 seconds for reload animation and server ammo update

                            if UI.AutoReloadStatusLabel then
                                UI.AutoReloadStatusLabel:SetDesc("Status: Reloading Active...")
                            end

                            pcall(function()
                                local event = ReplicatedStorage:FindFirstChild("Network")
                                if event then event = event:FindFirstChild("GatlingGun") end
                                if event then event = event:FindFirstChild("RE:Reload") end
                                if event then event:FireServer() end
                            end)
                        end
                    end
                else
                    clearTimer = 0
                    isCurrentlyReloading = false
                    if UI.AutoReloadStatusLabel then
                        UI.AutoReloadStatusLabel:SetDesc("Status: Waiting for game...")
                    end
                    task.wait(1)
                end
            else
                clearTimer = 0
                isCurrentlyReloading = false
                if UI.AutoReloadStatusLabel then
                    if not isPremiumUser then
                        UI.AutoReloadStatusLabel:SetDesc("Status: 🔒 Locked (Premium Only)")
                    else
                        UI.AutoReloadStatusLabel:SetDesc("Status: Idle")
                    end
                end
                task.wait(1)
            end
        end
        AutoReloadRunning = false
    end)
    end
end

do
    local function RunVoteSkip()
        local RemoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction")
        while true do
            if not isRunning or not Globals.AutoSkip then break end
            if not RemoteFunc then
                RemoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction")
            end
            local success = pcall(function()
                if RemoteFunc then
                    RemoteFunc:InvokeServer("Voting", "Skip")
                end
            end)
            if success then break end
            task.wait(0.1)
        end
    end

    StartAutoSkip = function()
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

            task.wait(0.4) -- Mobile Optimization: Throttled from 0.1s to 0.4s
        end

        AutoSkipRunning = false
    end)
    end
end

--==============================================================================
-- Execution Bootstrap & Unified Background Loops
--==============================================================================
do
    local buildOk, buildErr = pcall(function()
        if setthreadidentity then pcall(setthreadidentity, 8) end
        buildInterface()
    end)
    if not buildOk then
        warn(string.format("[ServiceHub] Error initializing GUI: %s", tostring(buildErr)))
    end
end

if Globals.MobileBoost then
    task.spawn(function()
        task.wait(1.5)
        applyMobileOptimizations(true)
    end)
end

if Globals.TimeScaleEnabled and not TimeScaleRunning then
    StartTimeScale()
end

if Globals.AutoGatling and not AutoGatlingRunning then
    StartAutoGatling()
end

if Globals.AutoReloadGatling and not AutoReloadRunning and typeof(StartAutoReloadGatling) == "function" then
    StartAutoReloadGatling()
end

if Globals.AutoSkip and not AutoSkipRunning then
    StartAutoSkip()
end

if game.PlaceId ~= LOBBY_PLACE_ID then
    -- In-Game Execution Flow
    snapshotMatchConfig()

    -- Check if script was executed or re-executed mid-game (not wave 0 or wave 1)
    pcall(function()
        local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
        if gsr then
            initialExecutionWave = gsr:GetAttribute("Wave") or 0
        else
            local pgui = LocalPlayer:FindFirstChild("PlayerGui")
            local topDisplay = pgui and pgui:FindFirstChild("TopGameDisplay")
            if topDisplay and topDisplay:FindFirstChild("Frame") and topDisplay.Frame:FindFirstChild("wave") then
                local label = topDisplay.Frame.wave:FindFirstChild("container") and topDisplay.Frame.wave.container:FindFirstChild("value")
                if label and label:IsA("TextLabel") then
                    local waveNum = label.Text:match("^(%d+)")
                    if waveNum then initialExecutionWave = tonumber(waveNum) or 0 end
                end
            end
        end
    end)

    if initialExecutionWave > 1 then
        isLateExecution = true
        Globals.IsConfigDirty = true
        task.spawn(function()
            task.wait(1.5)
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "MID-GAME RE-EXECUTION",
                        Desc = string.format("Detected start at Wave %d. Match will finish, then teleport to Smart Lobby!", initialExecutionWave),
                        Duration = 8,
                        Type = "warning"
                    })
                end)()
            end
        end)
    end

    pcall(function()
        if not PlayerDataHandler then
            PlayerDataHandler = loadPlayerDataHandler()
        end
        if typeof(refreshDisplay) == "function" then
            refreshDisplay()
        end
    end)

    if Globals.AutoSkip and not AutoSkipRunning then
        StartAutoSkip()
    end

    local isOwnedActive = isPremiumUser and (Globals.TrialFarmMode == "Progression Mode")
    local shouldRunTrialStrat = (currentMatchMode == "AutoTrials" or (Globals.AutoTrials and (not isPremiumUser or (not Globals.AutoGold and not Globals.AutoEvo))))
    if isOwnedActive and (currentMatchMode == "AutoGold" or currentMatchMode == "AutoEvo" or Globals.AutoEvo or Globals.AutoGold) then
        shouldRunTrialStrat = false
    end

    if shouldRunTrialStrat then
        runMatchStrategyIfSaved()
    elseif currentMatchMode == "AutoGold" or currentMatchMode == "AutoEvo" or Globals.AutoEvo or Globals.AutoGold then
        task.spawn(function()
            task.wait(1)
            handleAutoGoldExecution()
        end)
    end

    runInGameGuard()

    -- In-Game Match Completion Supervisor (ensures GetMatchStatus is tracked even if mode watchers are idle)
    task.spawn(function()
        while isRunning do
            task.wait(1)
            if game.PlaceId == LOBBY_PLACE_ID then break end

            local currentStatus = GetMatchStatus()
            if (currentStatus == "LOSS" or currentStatus == "WIN") and not isHandlingEndMatch then
                -- Only supervise if mode watchers are NOT actively running
                if not autoGoldWatcherRunning and not trialWatcherRunning then
                    local evoMilestone, evoReason = false, nil
                    if Globals.AutoEvo then
                        pcall(function()
                            evoMilestone, evoReason = checkAutoEvoMilestonesReached()
                        end)
                    end
                    if Globals.IsConfigDirty or Globals.AutoEvoMilestoneReached or evoMilestone or (isMatchConfigDirty and isMatchConfigDirty()) then
                        isHandlingEndMatch = true
                        if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                            pcall(task.cancel, activeStratThread)
                            activeStratThread = nil
                        end
                        shouldTeleportOnMatchEnd(currentStatus)
                        break
                    end
                end
            end
        end
    end)

    task.spawn(function()
        while isRunning do
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local hasGui = false
            pcall(function()
                hasGui = UI.ScreenGui and UI.ScreenGui.Parent ~= nil
            end)
            if not hasGui then break end

            task.wait(5)
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                if not PlayerDataHandler then
                    PlayerDataHandler = loadPlayerDataHandler()
                end
                if PlayerDataHandler and typeof(refreshDisplay) == "function" then
                    refreshDisplay()
                end
            end)
        end
    end)
else
    -- Lobby Unified Management Flow
    task.spawn(fastQueueLobby)

    -- Single consolidated background monitor loop for the Lobby
    task.spawn(function()
        local lastQueueTick = 0
        while isRunning do
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local hasGui = false
            pcall(function()
                hasGui = UI.ScreenGui and UI.ScreenGui.Parent ~= nil
            end)
            if not hasGui then break end

            task.wait(5)
            if game.PlaceId ~= LOBBY_PLACE_ID then break end

            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                if not PlayerDataHandler then
                    PlayerDataHandler = loadPlayerDataHandler()
                end

                if PlayerDataHandler then
                    refreshDisplay()
                end

                local now = os.time()
                if now - lastQueueTick >= 5 then
                    lastQueueTick = now
                    fastQueueLobby()
                end
            end)
        end
    end)
end

return UI.ScreenGui
