-- ================================================================
--  Bounty.lua — MAIN SCRIPT
--  pSilent, M1 humanized, Auto Skill, Auto Hop, Low Health Fly
-- ================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TpSvc      = game:GetService("TeleportService")
local GuiSvc     = game:GetService("GuiService")
local VIM        = game:GetService("VirtualInputManager")
local LP         = Players.LocalPlayer
local Camera     = workspace.CurrentCamera

-- ================================================================
-- [1] ĐỌC CONFIG
-- ================================================================
local CFG       = getgenv().BountyExtra or {}
local SKILL_CFG = CFG["Auto Skill"]    or {}

local ENABLE_PSILENT   = CFG["AimSilent"]       ~= false
local ENABLE_M1        = CFG["M1 click"]        ~= false
local ENABLE_AUTOSKILL = SKILL_CFG["Enabled"]   ~= false
local ENABLE_AUTOHOP   = CFG["Auto server hop"] ~= false
local ENABLE_GUI       = CFG["Gui"]             ~= false

local SKILL_Z     = SKILL_CFG["Z"]     ~= false
local SKILL_X     = SKILL_CFG["X"]     ~= false
local SKILL_C     = SKILL_CFG["C"]     ~= false
local SKILL_V     = SKILL_CFG["V"]     == true
local SKILL_F     = SKILL_CFG["F"]     ~= false
local SKILL_DELAY = SKILL_CFG["Delay"] or 0.3

local DISABLE_HF  = CFG["disableHealthFly"] == true
local LHF_ENABLED = (not DISABLE_HF) and (CFG["lowHealthFly"] == true)
local LOW_HP      = CFG["lowHealth"]  or 5600
local SAFE_HP     = CFG["safeHealth"] or 6600

local HIT_CHANCE = 87
local MAX_DIST   = 150

local M1_WHITELIST = CFG["M1"] or {
    ["kitsune"]=true, ["t-rex"]=true, ["dragon"]=true,
    ["blade"]=true,   ["dough"]=true, ["gas"]=true,
    ["pain"]=true,    ["leopard"]=true,
}

-- ================================================================
-- [2] STATE
-- ================================================================
local _flying = false
local TGT     = nil
local TGT_AT  = 0

-- ================================================================
-- [3] TARGET SYSTEM
-- ================================================================
local function isValid(p)
    if not p or not p:IsA("Player") then return false end
    if p == LP then return false end
    if not Players:FindFirstChild(p.Name) then return false end
    local c = p.Character
    if not c or not c:FindFirstChild("HumanoidRootPart") then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    if p.Team and LP.Team and p.Team == LP.Team then return false end
    return true
end

local function pickTarget()
    local mc = LP.Character; if not mc then return nil end
    local mr = mc:FindFirstChild("HumanoidRootPart"); if not mr then return nil end
    local best, bd = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if isValid(p) then
            local d = (p.Character.HumanoidRootPart.Position - mr.Position).Magnitude
            if d < bd then bd = d; best = p end
        end
    end
    return best
end

local function tgtDist()
    if not TGT or not TGT.Character then return math.huge end
    local mc = LP.Character; if not mc then return math.huge end
    local mr = mc:FindFirstChild("HumanoidRootPart"); if not mr then return math.huge end
    local tr = TGT.Character:FindFirstChild("HumanoidRootPart"); if not tr then return math.huge end
    return (tr.Position - mr.Position).Magnitude
end

local function getPredPos(tr)
    local vel      = tr.AssemblyLinearVelocity
    local tD       = (tr.Position - Camera.CFrame.Position).Magnitude
    local predMult = 0.88 + math.clamp(vel.Magnitude/200, 0, 0.45)
    return tr.Position
        + vel * (tD/260) * predMult
        + Vector3.new(0, 2.8, 0)
end

local function isVisible(pos)
    local mc = LP.Character; if not mc then return false end
    local mr = mc:FindFirstChild("HumanoidRootPart"); if not mr then return false end
    local origin = mr.Position + Vector3.new(0, 2, 0)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {mc}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local result = workspace:Raycast(origin, pos - origin, params)
    if not result then return true end
    local tc = TGT and TGT.Character
    return tc and result.Instance:IsDescendantOf(tc)
end

-- ================================================================
-- [4] pSILENT — snap camera 1 frame khi M1/skill
-- ================================================================
local function psilentSnap(doAction)
    if not ENABLE_PSILENT or not TGT then
        doAction(); return
    end
    if math.random(1,100) > HIT_CHANCE then
        doAction(); return
    end
    local tc = TGT.Character; if not tc then doAction(); return end
    local tr = tc:FindFirstChild("HumanoidRootPart"); if not tr then doAction(); return end
    local pred = getPredPos(tr)
    if not isVisible(pred) then doAction(); return end
    local origCF  = Camera.CFrame
    local dir     = (pred - Camera.CFrame.Position).Unit
    Camera.CFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + dir)
    doAction()
    task.defer(function()
        pcall(function() Camera.CFrame = origCF end)
    end)
end

-- ================================================================
-- [5] M1 HUMANIZED
-- ================================================================
local _m1Last    = 0
local _m1Burst   = 0
local _m1BurstCD = 0

local function canM1(char)
    if not ENABLE_M1 then return false end
    local t = char and char:FindFirstChildOfClass("Tool")
    if not t then return false end
    local s = string.lower((t.ToolTip or "").." "..(t.Name or ""))
    for k in pairs(M1_WHITELIST) do
        if string.find(s, k, 1, true) then return true end
    end
    return false
end

local function doM1(sx, sy)
    local now = tick()
    if now < _m1BurstCD then return end
    local delay = 0.055 + math.random()*0.028
    if now - _m1Last < delay then return end
    _m1Last  = now
    _m1Burst = _m1Burst + 1
    if _m1Burst >= math.random(6,8) then
        _m1Burst   = 0
        _m1BurstCD = now + 0.4 + math.random()*0.4
    end
    psilentSnap(function()
        pcall(function()
            mousemoveabs(sx + math.random(-4,4), sy + math.random(-4,4))
            mouse1press()
            task.wait(0.018 + math.random()*0.012)
            mouse1release()
        end)
    end)
end

-- ================================================================
-- [6] PRESS KEY
-- ================================================================
local function pressKey(keyCode)
    psilentSnap(function()
        pcall(function()
            VIM:SendKeyEvent(true,  keyCode, false, nil)
            task.wait(0.05)
            VIM:SendKeyEvent(false, keyCode, false, nil)
        end)
    end)
end

-- ================================================================
-- [7] AUTO HOP
-- ================================================================
local _hopLock = false
local _lastHop = 0

local function charReady()
    local c = LP.Character
    if not c or not c.Parent then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    return c:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getNewServer()
    local ok, sv = pcall(function()
        local HS   = game:GetService("HttpService")
        local url  = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
        local data = HS:JSONDecode(game:HttpGet(url))
        if not data or not data.data then return nil end
        local best, bestScore = nil, math.huge
        for _, s in ipairs(data.data) do
            if s.id ~= game.JobId
            and s.playing >= 2 and s.playing <= 11
            and s.maxPlayers >= s.playing then
                local score = (s.ping or 999) + s.playing * 10
                if score < bestScore then bestScore = score; best = s.id end
            end
        end
        return best
    end)
    return ok and sv or nil
end

local function hopServer(delay)
    if not ENABLE_AUTOHOP then return end
    if _hopLock then return end
    if tick() - _lastHop < 20 then return end
    _hopLock = true
    warn("🔄 Hop server sau "..(delay or 3).."s")
    task.spawn(function()
        task.wait(delay or 3)
        local w = 0
        while not charReady() and w < 15 do task.wait(0.5); w=w+0.5 end
        task.wait(0.5)
        _lastHop = tick()
        local sv = getNewServer()
        if sv then
            warn("✅ Server mới OK")
            local ok = pcall(function()
                TpSvc:TeleportToPlaceInstance(game.PlaceId, sv, LP)
            end)
            if not ok then
                task.wait(2)
                pcall(function() TpSvc:Teleport(game.PlaceId, LP) end)
            end
        else
            warn("⚠️ Teleport thường")
            pcall(function() TpSvc:Teleport(game.PlaceId, LP) end)
        end
        task.wait(15)
        _hopLock = false
    end)
end

TpSvc.TeleportInitFailed:Connect(function(plr)
    if plr ~= LP then return end
    _hopLock = false; _lastHop = 0
    hopServer(2)
end)

LP.CharacterRemoving:Connect(function()
    task.spawn(function()
        task.wait(10)
        if not charReady() then
            _hopLock = false
            hopServer(2)
        end
    end)
end)

-- ================================================================
-- [8] HEARTBEAT — target refresh + poll lỗi
-- ================================================================
local _lastErrCheck = 0
local _lastTgtCheck = 0

RunService.Heartbeat:Connect(function()
    local now = tick()

    if now - _lastErrCheck >= 0.5 then
        _lastErrCheck = now
        pcall(function()
            local m = GuiSvc:GetErrorMessage() or ""
            if m == "" then return end
            if string.find(m,"773") or string.find(m,"disconnect")
            or string.find(m,"reconnect") then
                _hopLock = false; hopServer(2)
            elseif string.find(m,"267") or string.find(m,"Security") then
                _hopLock = false; hopServer(8)
            end
        end)
    end

    if now - _lastTgtCheck >= 0.5 then
        _lastTgtCheck = now
        if not TGT or not isValid(TGT) or tgtDist() > MAX_DIST then
            TGT = pickTarget(); TGT_AT = now
        end
    end
end)

-- ================================================================
-- [9] GUI
-- ================================================================
if ENABLE_GUI then
    local G = Instance.new("ScreenGui")
    G.Name = "BountyGUI"; G.ResetOnSpawn = false
    G.Parent = LP:WaitForChild("PlayerGui")
    local F = Instance.new("Frame", G)
    F.Size = UDim2.new(0,185,0,68)
    F.Position = UDim2.new(0.5,-92.5,0.05,0)
    F.BackgroundColor3 = Color3.fromRGB(15,15,15)
    F.BackgroundTransparency = 0.1
    F.BorderSizePixel = 0; F.Visible = false
    Instance.new("UICorner",F).CornerRadius = UDim.new(0,12)
    local St = Instance.new("UIStroke",F); St.Thickness = 2
    local function lb(sz,pos,txt,fs,bold)
        local l = Instance.new("TextLabel",F)
        l.Size=sz; l.Position=pos; l.BackgroundTransparency=1
        l.Text=txt; l.TextSize=fs
        l.TextXAlignment=Enum.TextXAlignment.Center
        l.Font=bold and Enum.Font.GothamBold or Enum.Font.GothamSemibold
        return l
    end
    local TL=lb(UDim2.new(1,0,0,24),UDim2.new(0,0,0,0),"pSilent ON",15,true)
    local IL=lb(UDim2.new(1,0,0,22),UDim2.new(0,0,0,26),"FPS:60|Ping:0ms",13,false)
    local UL=lb(UDim2.new(1,0,0,18),UDim2.new(0,0,0,48),"Uptime:00:00:00",12,false)
    TL.TextColor3=Color3.fromRGB(255,215,0)
    IL.TextColor3=Color3.fromRGB(255,255,255)
    UL.TextColor3=Color3.fromRGB(200,200,200)
    local fps=60; local t0=os.clock()
    RunService.RenderStepped:Connect(function(dt)
        if dt>0 then fps=math.floor(1/dt) end
        local c=Color3.fromHSV((os.clock()%4)/4,.95,1)
        TL.TextColor3=c; St.Color=c
    end)
    task.spawn(function()
        while task.wait(0.5) do
            IL.Text=("FPS:%d|Ping:%dms"):format(fps,math.floor(LP:GetNetworkPing()*1000))
            local e=os.clock()-t0
            UL.Text=("Uptime:%02d:%02d:%02d"):format(
                math.floor(e/3600),math.floor(e%3600/60),math.floor(e%60))
        end
    end)
    task.delay(0.6,function() F.Visible=true end)
end

-- ================================================================
-- [10] SAFEZONE BYPASS
-- ================================================================
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local pg=LP.PlayerGui
            local d=pg:FindFirstChild("DialogueGui"); if d then d.Enabled=false end
            local q=pg:FindFirstChild("QuestGui");    if q then q.Enabled=false end
            local c=LP.Character
            if c then
                c:SetAttribute("InSafeZone",false)
                local ff=c:FindFirstChildOfClass("ForceField")
                if ff and ff.Name ~= "BountyFF" then ff:Destroy() end
            end
        end)
    end
end)

-- ================================================================
-- [11] LOW HEALTH FLY
--      Đợi character spawn xong
--      ForceField vô hình khi bay → không mất máu
--      Giữ cao 900 studs liên tục chống gravity
--      CharacterAdded reset state
-- ================================================================
local function startLHF()
    if not LHF_ENABLED then return end
    task.spawn(function()
        -- Đợi character sẵn sàng
        while not LP.Character
        or not LP.Character:FindFirstChild("HumanoidRootPart")
        or not LP.Character:FindFirstChildOfClass("Humanoid") do
            task.wait(0.5)
        end

        local _ff = nil  -- ForceField hiện tại

        while task.wait(0.3) do
            pcall(function()
                local c  = LP.Character; if not c then return end
                local h  = c:FindFirstChildOfClass("Humanoid"); if not h then return end
                local hr = c:FindFirstChild("HumanoidRootPart"); if not hr then return end

                if h.Health <= LOW_HP and not _flying then
                    _flying = true
                    warn("⚠️ Máu thấp "..math.floor(h.Health).." — bay lên")

                    -- ForceField vô hình để không mất máu
                    _ff = Instance.new("ForceField")
                    _ff.Name    = "BountyFF"
                    _ff.Visible = false
                    _ff.Parent  = c

                    -- Bay lên tức thì
                    hr.CFrame = CFrame.new(
                        hr.Position + Vector3.new(math.random(-5,5), 900, math.random(-5,5))
                    )

                elseif _flying then
                    -- Giữ cao liên tục
                    if hr.Position.Y < 500 then
                        hr.CFrame = CFrame.new(hr.Position.X, 900, hr.Position.Z)
                    end

                    -- Máu hồi đủ → xuống
                    if h.Health >= SAFE_HP then
                        _flying = false
                        warn("✅ Máu hồi "..math.floor(h.Health).." — săn tiếp")
                        if _ff and _ff.Parent then _ff:Destroy() end
                        _ff = nil
                    end
                end
            end)
        end
    end)
end

startLHF()

-- Reset khi character respawn
LP.CharacterAdded:Connect(function()
    _flying = false
    task.wait(1)
    startLHF()
end)

-- ================================================================
-- [12] SPAM SKILL
-- ================================================================
if ENABLE_AUTOSKILL then
    task.spawn(function()
        while task.wait(SKILL_DELAY) do
            if _flying then continue end
            if not TGT or not isValid(TGT) then continue end
            pcall(function()
                local mc=LP.Character; if not mc then return end
                local mh=mc:FindFirstChildOfClass("Humanoid")
                if not mh or mh.Health<=0 then return end
                if tgtDist() > 80 then return end
                if SKILL_Z then pressKey(Enum.KeyCode.Z); task.wait(0.08) end
                if SKILL_X then pressKey(Enum.KeyCode.X); task.wait(0.08) end
                if SKILL_C then pressKey(Enum.KeyCode.C); task.wait(0.08) end
                if SKILL_F then pressKey(Enum.KeyCode.F); task.wait(0.08) end
                if SKILL_V then pressKey(Enum.KeyCode.V); task.wait(0.08) end
            end)
        end
    end)
end

-- ================================================================
-- [13] SPAM M1
-- ================================================================
if ENABLE_M1 then
    task.spawn(function()
        while task.wait(0.05) do
            if _flying then continue end
            if not TGT or not isValid(TGT) then continue end
            pcall(function()
                local mc=LP.Character; if not mc then return end
                local mh=mc:FindFirstChildOfClass("Humanoid")
                if not mh or mh.Health<=0 then return end
                if not canM1(mc) then return end
                if tgtDist() > 25 then return end
                local tc=TGT.Character; if not tc then return end
                local tr=tc:FindFirstChild("HumanoidRootPart"); if not tr then return end
                local pred = ENABLE_PSILENT and getPredPos(tr) or tr.Position
                local sp,onScreen = Camera:WorldToViewportPoint(pred)
                if not onScreen or sp.Z<=0 then return end
                local vp=Camera.ViewportSize
                doM1(
                    math.clamp(sp.X+math.random(-4,4),1,vp.X-1),
                    math.clamp(sp.Y+math.random(-4,4),1,vp.Y-1)
                )
            end)
        end
    end)
end

print("✅ Bounty.lua OK | pSilent="..tostring(ENABLE_PSILENT)
    .." | LHF="..tostring(LHF_ENABLED)
    .." | HitChance="..HIT_CHANCE.."%")
