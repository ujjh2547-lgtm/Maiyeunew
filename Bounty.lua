-- ================================================================
--  Bounty.lua — MAIN SCRIPT
--  Đọc config từ getgenv().BountyExtra và getgenv().config
-- ================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TpSvc      = game:GetService("TeleportService")
local GuiSvc     = game:GetService("GuiService")
local VIM        = game:GetService("VirtualInputManager")
local LP         = Players.LocalPlayer

-- ================================================================
-- [1] ĐỌC CONFIG
-- ================================================================
local CFG       = getgenv().BountyExtra or {}
local GCFG      = getgenv().config      or {}
local SKILL_CFG = CFG["Auto Skill"]     or {}

local ENABLE_AIMBOT    = CFG["Aimbot"]          ~= false
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

-- Low Health Fly đọc từ getgenv().config (cùng chỗ với Bountynew)
local LHF_ENABLED = true
local LOW_HP      = GCFG["lowHealth"]  or 5600
local SAFE_HP     = GCFG["safeHealth"] or 6600

local M1_WHITELIST = CFG["M1"] or {
    ["kitsune"]=true, ["t-rex"]=true, ["dragon"]=true,
    ["blade"]=true,   ["dough"]=true, ["gas"]=true,
    ["pain"]=true,    ["leopard"]=true,
}

-- ================================================================
-- [2] HELPER
-- ================================================================
local _flying = false

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

local function charReady()
    local c = LP.Character
    if not c or not c.Parent then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    return c:FindFirstChild("HumanoidRootPart") ~= nil
end

-- ================================================================
-- [3] M1 CLICK
-- ================================================================
local _m1Last = 0

local function doM1(sx, sy)
    local now = tick()
    if now - _m1Last < 0.22 + math.random()*0.05 then return end
    _m1Last = now
    task.spawn(function()
        pcall(function()
            mousemoveabs(sx + math.random(-3,3), sy + math.random(-3,3))
            mouse1press()
            task.wait(0.02)
            mouse1release()
        end)
    end)
end

-- ================================================================
-- [4] PRESS KEY
-- ================================================================
local function pressKey(keyCode)
    pcall(function()
        VIM:SendKeyEvent(true,  keyCode, false, nil)
        task.wait(0.05)
        VIM:SendKeyEvent(false, keyCode, false, nil)
    end)
end

-- ================================================================
-- [5] AUTO HOP
-- ================================================================
local _hopLock = false
local _lastHop = 0

local function getNewServer()
    local ok, sv = pcall(function()
        local HS   = game:GetService("HttpService")
        local url  = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
        local data = HS:JSONDecode(game:HttpGet(url))
        if not data or not data.data then return nil end
        local best, bestScore = nil, math.huge
        for _, s in ipairs(data.data) do
            if s.id ~= game.JobId
            and s.playing >= 2 and s.playing <= 10
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
    warn("🔄 Hop server sau " .. (delay or 5) .. "s")
    task.spawn(function()
        task.wait(delay or 5)
        local w = 0
        while not charReady() and w < 15 do task.wait(0.5); w = w + 0.5 end
        task.wait(1)
        _lastHop = tick()
        local sv = getNewServer()
        if sv then
            warn("✅ Tìm được server mới")
            pcall(function() TpSvc:TeleportToPlaceInstance(game.PlaceId, sv, LP) end)
        else
            warn("⚠️ Dùng Teleport thường")
            pcall(function() TpSvc:Teleport(game.PlaceId, LP) end)
        end
        task.wait(15)
        _hopLock = false
    end)
end

TpSvc.TeleportInitFailed:Connect(function(plr)
    if plr ~= LP then return end
    hopServer(5)
end)

LP.CharacterRemoving:Connect(function()
    task.spawn(function()
        task.wait(12)
        if not charReady() then hopServer(3) end
    end)
end)

-- ================================================================
-- [6] HEARTBEAT — aimlock + check lỗi (1 listener duy nhất)
-- ================================================================
local _lastErrCheck = 0
local _lastAim      = 0
local TGT           = nil
local TGT_AT        = 0

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

RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Check lỗi 773/267 mỗi 1.5s
    if now - _lastErrCheck >= 1.5 then
        _lastErrCheck = now
        pcall(function()
            local m = GuiSvc:GetErrorMessage() or ""
            if string.find(m, "773") or string.find(m, "disconnect")
            or string.find(m, "reconnect") then
                hopServer(5)
            elseif string.find(m, "267") or string.find(m, "Security") then
                hopServer(15)
            end
        end)
    end

    -- Aimlock 20fps, dừng khi đang flying
    if ENABLE_AIMBOT and not _flying and now - _lastAim >= 0.05 then
        _lastAim = now
        pcall(function()
            local mc = LP.Character; if not mc then return end
            local mh = mc:FindFirstChildOfClass("Humanoid")
            if not mh or mh.Health <= 0 then return end
            local dist = tgtDist()
            if not TGT or not isValid(TGT) or now - TGT_AT > 4 or dist > 100 then
                TGT = pickTarget(); TGT_AT = now
            end
            if not TGT then return end
            local tc = TGT.Character; if not tc then return end
            local tr = tc:FindFirstChild("HumanoidRootPart"); if not tr then return end
            local cam = workspace.CurrentCamera; if not cam then return end
            local vel  = tr.AssemblyLinearVelocity
            local tD   = (tr.Position - cam.CFrame.Position).Magnitude
            local pred = tr.Position
                + vel * (tD/260) * (0.88 + math.clamp(vel.Magnitude/200, 0, 0.45))
                + Vector3.new(0, 2.5, 0)
            cam.CFrame = CFrame.new(
                cam.CFrame.Position,
                cam.CFrame.Position + (pred - cam.CFrame.Position).Unit
            )
        end)
    end
end)

-- ================================================================
-- [7] GUI FPS / PING / UPTIME
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
    Instance.new("UICorner", F).CornerRadius = UDim.new(0,12)
    local St = Instance.new("UIStroke", F); St.Thickness = 2
    local function lb(sz,pos,txt,fs,bold)
        local l = Instance.new("TextLabel",F)
        l.Size=sz; l.Position=pos; l.BackgroundTransparency=1
        l.Text=txt; l.TextSize=fs
        l.TextXAlignment=Enum.TextXAlignment.Center
        l.Font=bold and Enum.Font.GothamBold or Enum.Font.GothamSemibold
        return l
    end
    local TL=lb(UDim2.new(1,0,0,24),UDim2.new(0,0,0,0),"FPS • PING",15,true)
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
-- [8] SAFEZONE BYPASS
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
                if ff then ff:Destroy() end
            end
        end)
    end
end)

-- ================================================================
-- [9] LOW HEALTH FLY
--     Đọc lowHealth/safeHealth từ getgenv().config
--     cùng nguồn với Bountynew.lua
-- ================================================================
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local c  = LP.Character; if not c then return end
            local h  = c:FindFirstChildOfClass("Humanoid"); if not h then return end
            local hr = c:FindFirstChild("HumanoidRootPart"); if not hr then return end

            if h.Health <= LOW_HP and not _flying then
                _flying = true
                warn("⚠️ Máu thấp "..math.floor(h.Health).." — bay lên trời đợi hồi máu")
                hr.CFrame = CFrame.new(hr.Position + Vector3.new(0, 800, 0))
            elseif h.Health >= SAFE_HP and _flying then
                _flying = false
                warn("✅ Máu hồi đủ "..math.floor(h.Health).." — tiếp tục săn")
            end
        end)
    end
end)

-- ================================================================
-- [10] SPAM SKILL
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
-- [11] SPAM M1
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
                local cam=workspace.CurrentCamera; if not cam then return end
                local sp,onScreen=cam:WorldToViewportPoint(tr.Position)
                if not onScreen or sp.Z<=0 then return end
                local vp=cam.ViewportSize
                doM1(
                    math.clamp(sp.X+math.random(-3,3),1,vp.X-1),
                    math.clamp(sp.Y+math.random(-3,3),1,vp.Y-1)
                )
            end)
        end
    end)
end

print("✅ Bounty.lua loaded — Aimlock + Skill + M1 + AutoHop + LowHealthFly OK")
