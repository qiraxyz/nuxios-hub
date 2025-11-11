-- // NuxiosHub - General (Auto Summit) + Misc (Camera Zoom)
-- // Paste as LocalScript / AutoExecute

--== Services
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local TweenService= game:GetService("TweenService")
local StarterGui  = game:GetService("StarterGui")
local LP          = Players.LocalPlayer

--== Rayfield
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "NuxiosHub",
    Icon = 0,
    LoadingTitle = "Universal Mount script",
    LoadingSubtitle = "by Kerlolio",
    ShowText = "NuxiosHub",
    Theme = "DarkBlue",

    ToggleUIKeybind = "K",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = false,

    ConfigurationSaving = {
        Enabled   = true,
        FolderName= "NuxiosHub",
        FileName  = "NuxiosHub_Config"
    },

    Discord = { Enabled = false, Invite = "noinvitelink", RememberJoins = true },
    KeySystem = false,
    KeySettings = { Title = "Untitled", Subtitle = "Key System", Note = "No method of obtaining the key is provided", FileName = "Key", SaveKey = true, GrabKeyFromSite = false, Key = {"Hello"} }
})

----------------------------------------------------------------------
-- TAB: GENERAL  (Auto Summit – Mount Nganu)
----------------------------------------------------------------------
local TabGeneral = Window:CreateTab("General", "aperture")
local SecSummit  = TabGeneral:CreateSection("Auto Summit – Mount Nganu")
TabGeneral:CreateDivider()

-- ================== STATE & HELPERS (AUTO SUMMIT) ===================
local function getChar()
    local plr = LP
    local ch  = plr.Character or plr.CharacterAdded:Wait()
    local hrp = ch:WaitForChild("HumanoidRootPart")
    local hum = ch:FindFirstChildOfClass("Humanoid") or ch:WaitForChild("Humanoid")
    return ch, hrp, hum
end

local function safeWait(t) if t and t>0 then task.wait(t) end end

-- noclip handler
local noclipConn
local function setNoClip(enabled)
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if not enabled then return end
    noclipConn = RunService.Stepped:Connect(function()
        local ch = LP.Character
        if not ch then return end
        for _,p in ipairs(ch:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end

local function zeroVelocity(hrp, hum)
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.new()
        hrp.AssemblyAngularVelocity = Vector3.new()
        if hum and hum.RootPart then
            hum:ChangeState(Enum.HumanoidStateType.Physics) -- momentarily calm
            task.wait()
        end
    end)
end

local function keepUprightCFrame(current, targetPosY, keepYawFrom)
    -- keep yaw from current HRP, but move to target position (X,Z) + offsetY, upright orientation
    local pos = Vector3.new(current.Position.X, targetPosY, current.Position.Z)
    local look = keepYawFrom.CFrame.LookVector
    local cf = CFrame.new(pos, pos + Vector3.new(look.X, 0, look.Z))
    return cf
end

-- UI CONFIG DEFAULTS
local AutoSummitEnabled = false
local SummitLoopConn

local summitMode      = "Count"      -- "Count" | "Infinite"
local summitRuns      = 1
local cpStart         = 0
local cpEnd           = 10
local delayPerTP      = 2.0
local useTween        = false
local tweenTime       = 0.5
local offsetY         = 0
local env_NoClip      = false
local env_KeepUpright = true
local env_ZeroVel     = true
local env_AntiReset   = true

-- ================== UI (GENERAL) ===================
-- Mode
local ModeDropdown = TabGeneral:CreateDropdown({
    Name = "Loop Mode",
    Options = {"Count","Infinite"},
    CurrentOption = "Count",
    Flag = "Nux_SummitMode",
    Callback = function(opt) summitMode = opt end
})

-- Run Count
local RunCountSlider = TabGeneral:CreateSlider({
    Name = "Run Count",
    Range = {1, 999},
    Increment = 1,
    CurrentValue = 1,
    Flag = "Nux_SummitRuns",
    Callback = function(v) summitRuns = math.floor(tonumber(v) or 1) end
})

TabGeneral:CreateDivider()
-- CP Range
local CPStartSlider = TabGeneral:CreateSlider({
    Name = "Start CP",
    Range = {0, 99},
    Increment = 1,
    CurrentValue = 0,
    Flag = "Nux_CPStart",
    Callback = function(v) cpStart = math.floor(v) end
})
local CPEndSlider = TabGeneral:CreateSlider({
    Name = "End CP",
    Range = {0, 99},
    Increment = 1,
    CurrentValue = 10,
    Flag = "Nux_CPEnd",
    Callback = function(v) cpEnd = math.floor(v) end
})

-- Delay & movement
local DelaySlider = TabGeneral:CreateSlider({
    Name = "Delay per TP (sec)",
    Range = {0, 5},
    Increment = 0.1,
    CurrentValue = 2.0,
    Flag = "Nux_DelayTP",
    Callback = function(v) delayPerTP = tonumber(v) or 0 end
})

local TweenToggle = TabGeneral:CreateToggle({
    Name = "Use Tween (smooth TP)",
    CurrentValue = false,
    Flag = "Nux_TweenToggle",
    Callback = function(v) useTween = v end
})

local TweenTimeSlider = TabGeneral:CreateSlider({
    Name = "Tween Time (sec)",
    Range = {0.05, 3},
    Increment = 0.05,
    CurrentValue = 0.5,
    Flag = "Nux_TweenTime",
    Callback = function(v) tweenTime = tonumber(v) or 0.5 end
})

local OffsetYSlider = TabGeneral:CreateSlider({
    Name = "Offset Y",
    Range = {-20, 20},
    Increment = 0.5,
    CurrentValue = 0,
    Flag = "Nux_OffsetY",
    Callback = function(v) offsetY = tonumber(v) or 0 end
})

TabGeneral:CreateDivider()
local EnvSec = TabGeneral:CreateSection("Custom Environment")
local NoClipToggle = TabGeneral:CreateToggle({
    Name = "NoClip while running",
    CurrentValue = false,
    Flag = "Nux_NoClip",
    Callback = function(v) env_NoClip = v; setNoClip(v) end
})
local KeepUprightToggle = TabGeneral:CreateToggle({
    Name = "Keep Upright (preserve yaw)",
    CurrentValue = true,
    Flag = "Nux_KeepUpright",
    Callback = function(v) env_KeepUpright = v end
})
local ZeroVelToggle = TabGeneral:CreateToggle({
    Name = "Zero Velocity on TP",
    CurrentValue = true,
    Flag = "Nux_ZeroVel",
    Callback = function(v) env_ZeroVel = v end
})
local AntiResetToggle = TabGeneral:CreateToggle({
    Name = "Anti-Reset Orientation",
    CurrentValue = true,
    Flag = "Nux_AntiReset",
    Callback = function(v) env_AntiReset = v end
})

TabGeneral:CreateDivider()

-- START/STOP
local function summitOnce()
    -- your given baseline loop CP0..CP10 but configurable:
    local folder = workspace:WaitForChild("Checkpoints")
    -- normalize range
    local s, e = cpStart, cpEnd
    if s > e then s, e = e, s end

    local ch, hrp, hum = getChar()
    for i = s, e do
        if not AutoSummitEnabled then return false end

        -- refresh references each step for safety
        ch, hrp, hum = getChar()

        local cpName = "CP" .. i
        local checkpoint = folder:WaitForChild(cpName)
        local targetCF = checkpoint.CFrame * CFrame.new(0, offsetY, 0)

        -- custom environment handling
        if env_ZeroVel then zeroVelocity(hrp, hum) end

        if env_KeepUpright then
            -- use current yaw, but move to target XYZ
            local current = hrp.CFrame
            local tgtPos = targetCF.Position
            targetCF = keepUprightCFrame(CFrame.new(tgtPos), tgtPos.Y, hrp)
        end

        if useTween then
            local info = TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local tween = TweenService:Create(hrp, info, {CFrame = targetCF})
            tween:Play()
            tween.Completed:Wait()
        else
            hrp.CFrame = targetCF
        end

        -- optional: anti reset upright (tiny reapply next frame)
        if env_AntiReset then
            task.defer(function()
                pcall(function()
                    hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + (hrp.CFrame.LookVector * Vector3.new(1,0,1)).Unit)
                end)
            end)
        end

        safeWait(delayPerTP)
    end
    return true
end

local function startSummit()
    if SummitLoopConn then SummitLoopConn:Disconnect() end
    SummitLoopConn = RunService.Heartbeat:Connect(function() end) -- keep handle
    task.spawn(function()
        local totalRuns = 0
        if summitMode == "Infinite" then
            while AutoSummitEnabled do
                local ok = summitOnce()
                if not ok or not AutoSummitEnabled then break end
                totalRuns += 1
                Rayfield:Notify({Title="Auto Summit", Content=("Completed run #%d"):format(totalRuns), Duration=2})
            end
        else
            for r = 1, summitRuns do
                if not AutoSummitEnabled then break end
                local ok = summitOnce()
                if not ok then break end
                totalRuns = r
                Rayfield:Notify({Title="Auto Summit", Content=("Completed run #%d/%d"):format(r, summitRuns), Duration=2})
            end
        end
        AutoSummitEnabled = false
        if SummitLoopConn then SummitLoopConn:Disconnect(); SummitLoopConn = nil end
        setNoClip(false)
        Rayfield:Notify({Title="Auto Summit", Content="Stopped.", Duration=3})
    end)
end

local function stopSummit()
    AutoSummitEnabled = false
    if SummitLoopConn then SummitLoopConn:Disconnect(); SummitLoopConn = nil end
    setNoClip(false)
end

TabGeneral:CreateToggle({
    Name = "Auto Summit (Mount Nganu)",
    CurrentValue = false,
    Flag = "Nux_SummitToggle",
    Callback = function(v)
        AutoSummitEnabled = v
        if v then
            startSummit()
            Rayfield:Notify({Title="Auto Summit", Content="Running…", Duration=3})
        else
            stopSummit()
        end
    end
})

TabGeneral:CreateButton({
    Name = "Stop & Reset Summit",
    Callback = function()
        stopSummit()
        Rayfield:Notify({Title="Auto Summit", Content="Force stopped & reset.", Duration=3})
    end
})

-- reapply safety on respawn
LP.CharacterAdded:Connect(function()
    if AutoSummitEnabled and env_NoClip then setNoClip(true) end
end)

----------------------------------------------------------------------
-- TAB: MISC (Camera Zoom) — icon LUCIDE: brackets
----------------------------------------------------------------------
local TabMisc   = Window:CreateTab("Misc", "brackets")
local SecCam    = TabMisc:CreateSection("Camera Zoom")
TabMisc:CreateDivider()

--== State & helpers (Camera Zoom)
local DEFAULT_MIN = LP.CameraMinZoomDistance or 0.5
local DEFAULT_MAX = LP.CameraMaxZoomDistance or 128
local desiredMin  = DEFAULT_MIN
local desiredMax  = DEFAULT_MAX
local enforceZoom = true
local hbZoom

local function applyZoom(minZ, maxZ)
    if typeof(minZ) ~= "number" or typeof(maxZ) ~= "number" then return end
    minZ = math.clamp(minZ, 0, maxZ)
    pcall(function()
        LP.CameraMinZoomDistance = minZ
        LP.CameraMaxZoomDistance = maxZ
    end)
end

local function startZoomEnforcer()
    if hbZoom then hbZoom:Disconnect() end
    if not enforceZoom then return end
    hbZoom = RunService.Heartbeat:Connect(function()
        if math.abs((LP.CameraMaxZoomDistance or 0) - desiredMax) > 1e-3
        or math.abs((LP.CameraMinZoomDistance or 0) - desiredMin) > 1e-3 then
            applyZoom(desiredMin, desiredMax)
        end
    end)
end

TabMisc:CreateToggle({
    Name = "Enforce (Anti-Reset)",
    CurrentValue = true,
    Flag = "Nux_EnforceZoom",
    Callback = function(v)
        enforceZoom = v
        if v then
            startZoomEnforcer()
            Rayfield:Notify({Title="Enforce ON", Content="Game tidak bisa mereset zoom.", Duration=3})
        else
            if hbZoom then hbZoom:Disconnect() end
            Rayfield:Notify({Title="Enforce OFF", Content="Zoom bisa diubah oleh game.", Duration=3})
        end
    end
})

local MinSlider = TabMisc:CreateSlider({
    Name = "Min Zoom Distance",
    Range = {0, 50},
    Increment = 0.5,
    CurrentValue = DEFAULT_MIN,
    Flag = "Nux_MinZoom",
    Callback = function(val)
        desiredMin = tonumber(val) or 0
        if desiredMin > desiredMax then desiredMin = desiredMax end
        applyZoom(desiredMin, desiredMax)
    end
})

local MaxSlider = TabMisc:CreateSlider({
    Name = "Max Zoom Distance",
    Range = {10, 10000},
    Increment = 10,
    CurrentValue = DEFAULT_MAX,
    Flag = "Nux_MaxZoom",
    Callback = function(val)
        desiredMax = tonumber(val) or DEFAULT_MAX
        if desiredMax < desiredMin then desiredMin = desiredMax end
        applyZoom(desiredMin, desiredMax)
    end
})

TabMisc:CreateSection("Presets")
TabMisc:CreateButton({
    Name = "Preset: Default (128)",
    Callback = function()
        desiredMax = 128
        pcall(function() MaxSlider:Set(128) end)
        applyZoom(desiredMin, desiredMax)
        Rayfield:Notify({Title="Preset", Content="Max Zoom = 128", Duration=3})
    end
})
TabMisc:CreateButton({
    Name = "Preset: 400",
    Callback = function()
        desiredMax = 400
        pcall(function() MaxSlider:Set(400) end)
        applyZoom(desiredMin, desiredMax)
        Rayfield:Notify({Title="Preset", Content="Max Zoom = 400", Duration=3})
    end
})
TabMisc:CreateButton({
    Name = "Preset: Super Far (10000)",
    Callback = function()
        desiredMax = 10000
        pcall(function() MaxSlider:Set(10000) end)
        applyZoom(desiredMin, desiredMax)
        Rayfield:Notify({Title="Preset", Content="Max Zoom = 10000", Duration=3})
    end
})

TabMisc:CreateSection("Reset")
TabMisc:CreateButton({
    Name = "Reset to Current Defaults",
    Callback = function()
        DEFAULT_MIN = LP.CameraMinZoomDistance or 0.5
        DEFAULT_MAX = LP.CameraMaxZoomDistance or 128
        desiredMin   = DEFAULT_MIN
        desiredMax   = DEFAULT_MAX
        pcall(function()
            MinSlider:Set(desiredMin)
            MaxSlider:Set(desiredMax)
        end)
        applyZoom(desiredMin, desiredMax)
        Rayfield:Notify({Title="Reset", Content=("Min=%s, Max=%s"):format(desiredMin, desiredMax), Duration=3})
    end
})

-- Reapply on spawn
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    applyZoom(desiredMin, desiredMax)
end)

-- Initial apply + info
applyZoom(desiredMin, desiredMax)
startZoomEnforcer()
pcall(function()
    StarterGui:SetCore("ChatMakeSystemMessage", {Text = "[NuxiosHub] Press K to toggle UI"; Color = Color3.new(1,1,1)})
end)
