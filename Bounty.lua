-- ================================================================
--  Bounty.lua — MAIN SCRIPT VIP
--  Aim: pSilent + Triggerbot + Anti-Detect
--  Menu: Deaths, Kills, Players, CPS, FPS, Ping, Uptime
--  Fix: giảm tối đa 267/268/773
-- ================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TpSvc      = game:GetService("TeleportService")
local GuiSvc     = game:GetService("GuiService")
local VIM        = game:GetService("VirtualInputManager")
local Stats      = game:GetService("Stats")
local LP         = Players.LocalPlayer
local Camera     = workspace.CurrentCamera

-- ================================================================
-- [1] ĐỌC CONFIG
-- ================================================================
local CFG       = getgenv().BountyExtra or {}
local SKILL_CFG = CFG["Auto Skill"]    or {}

local ENABLE_PSILENT     = CFG["AimSilent"]       ~= false
local ENABLE_TRIGGERBOT  = CFG["Triggerbot"]      == true
local ENABLE_M1          = CFG["M1 click"]        ~= false
local ENABLE_AUTOSKILL   = SKILL_CFG["Enabled"]   ~= false
local ENABLE_AUTOHOP     = CFG["Auto server hop"] ~= false
local ENABLE_GUI         = CFG["Gui"]             ~= false

local SKILL_Z     = SKILL_CFG["Z"]     ~= false
local SKILL_X     = SKILL_CFG["X"]     ~= false
local SKILL_C     = SKILL_CFG["C"]     ~= false
local SKILL_V     = SKILL_CFG["V"]     == true
local SKILL_F     = SKILL_CFG["F"]     ~= false
local SKILL_DELAY = SKILL_CFG["Delay"] or 0.3

-- pSilent config
local HIT_CHANCE  = CFG["HitChance"] or 87  -- 80-92%
local MAX_DIST    = 150

local M1_WHITELIST = CFG["M1"] or {
    ["kitsune"]=true, ["t-rex"]=true, ["dragon"]=true,
    ["blade"]=true,   ["dough"]=true, ["gas"]=true,
    ["pain"]=true,    ["leopard"]=true,
}

-- ================================================================
-- [2] STATE
-- ================================================================
local TGT      = nil
local TGT_AT   = 0
local _myDeaths   = 0
local _theirDeaths = 0
local _cpsCount   = 0
local _cpsLast    = tick()
local _cps        = 0

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
-- [4] TRACK DEATHS
-- ================================================================
local function setupDeathTrack()
    local c = LP.Character; if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid"); if not h then return end
    h.Died:Connect(function()
        _myDeaths = _myDeaths + 1
    end)
    -- Track enemy deaths
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local eh = p.Character:FindFirstChildOfClass("Humanoid")
            if eh then
                eh.Died:Connect(function()
                    _theirDeaths = _theirDeaths + 1
                end)
            end
        end
    end
end

LP.CharacterAdded:Connect(function(c)
    task.wait(0.5)
    setupDeathTrack()
end)

Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(c)
        task.wait(0.5)
        local eh = c:FindFirstChildOfClass("Humanoid")
        if eh then
            eh.Died:Connect(function()
                _theirDeaths = _theirDeaths + 1
            end)
        end
    end)
end)

task.delay(1, setupDeathTrack)

-- ================================================================
-- [5] pSILENT — snap 1 frame
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
-- [6] TRIGGERBOT — tự click khi crosshair chạm target
--     Ít bị detect hơn raw spam vì chỉ click khi aim đúng
-- ================================================================
local _tbLast = 0

local function checkTriggerbot()
    if not ENABLE_TRIGGERBOT then return end
    local now = tick()
    if now - _tbLast < 0.08 + math.random()*0.04 then return end
    pcall(function()
        local mc = LP.Character; if not mc then return end
        local mh = mc:FindFirstChildOfClass("Humanoid")
        if not mh or mh.Health <= 0 then return end
        local unitRay = Camera:ScreenPointToRay(
            Camera.ViewportSize.X/2,
            Camera.ViewportSize.Y/2
        )
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {mc}
        params.FilterType = Enum.RaycastFilterType.Exclude
        local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * MAX_DIST, params)
        if not result then return end
        -- Kiểm tra có phải character của enemy không
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and isValid(p) and p.Character then
                if result.Instance:IsDescendantOf(p.Character) then
                    _tbLast = now
                    -- Click humanized
                    pcall(function()
                        mouse1press()
                        task.wait(0.018 + math.random()*0.01)
                        mouse1release()
                    end)
                    return
                end
            end
        end
    end)
end

-- ================================================================
-- [7] M1 HUMANIZED — CPS 12-18, burst control, anti-detect
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
    -- CPS 12-18 → delay 55-83ms + jitter
    local delay = 0.055 + math.random()*0.028
    if now - _m1Last < delay then return end
    _m1Last  = now
    _m1Burst = _m1Burst + 1

    -- CPS tracking
    _cpsCount = _cpsCount + 1
    local elapsed = now - _cpsLast
    if elapsed >= 1 then
        _cps      = math.floor(_cpsCount / elapsed)
        _cpsCount = 0
        _cpsLast  = now
    end

    -- Burst: 6-8 click rồi nghỉ 400-800ms
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
-- [8] PRESS KEY
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
-- [9] AUTO HOP — fix 267/268/773
--     267: hop nhanh (bị kick bởi server)
--     268: hop sau 5s (bị teleport về spawn)
--     773: hop ngay (mất kết nối server)
--     Anti-detect: random delay, không retry liên tục
-- ================================================================
local _hopLock  = false
local _lastHop  = 0
local _hopCount = 0  -- đếm số lần hop liên tiếp, nghỉ nếu quá nhiều

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

local function hopServer(delay, reason)
    if not ENABLE_AUTOHOP then return end
    if _hopLock then return end
    -- Nếu hop quá 3 lần liên tiếp → nghỉ 60s tránh ban
    if _hopCount >= 3 then
        warn("⚠️ Hop quá nhiều lần — nghỉ 60s")
        task.wait(60)
        _hopCount = 0
    end
    if tick() - _lastHop < 20 then return end
    _hopLock = true
    _hopCount = _hopCount + 1
    warn("🔄 Hop ["..( reason or "auto").."] sau "..(delay or 3).."s")
    task.spawn(function()
        task.wait(delay or 3)
        local w = 0
        local function charReady()
            local c = LP.Character
            if not c or not c.Parent then return false end
            local h = c:FindFirstChildOfClass("Humanoid")
            if not h or h.Health <= 0 then return false end
            return c:FindFirstChild("HumanoidRootPart") ~= nil
        end
        while not charReady() and w < 15 do task.wait(0.5); w=w+0.5 end
        task.wait(0.5 + math.random()*0.5)  -- random delay tránh detect
        _lastHop = tick()
        local sv = getNewServer()
        if sv then
            warn("✅ Server mới OK")
            local ok = pcall(function()
                TpSvc:TeleportToPlaceInstance(game.PlaceId, sv, LP)
            end)
            if not ok then
                task.wait(2 + math.random()*2)
                pcall(function() TpSvc:Teleport(game.PlaceId, LP) end)
            end
        else
            warn("⚠️ Teleport thường")
            pcall(function() TpSvc:Teleport(game.PlaceId, LP) end)
        end
        task.wait(15)
        _hopLock  = false
    end)
end

-- Reset hop count sau 5 phút không bị lỗi
task.spawn(function()
    while task.wait(300) do
        _hopCount = 0
    end
end)

TpSvc.TeleportInitFailed:Connect(function(plr)
    if plr ~= LP then return end
    _hopLock = false; _lastHop = 0
    hopServer(2, "773-TpFailed")
end)

LP.CharacterRemoving:Connect(function()
    task.spawn(function()
        task.wait(10)
        local c = LP.Character
        if not c or not c:FindFirstChild("HumanoidRootPart") then
            _hopLock = false
            hopServer(2, "NoSpawn")
        end
    end)
end)

-- ================================================================
-- [10] HEARTBEAT — target + poll lỗi 267/268/773
-- ================================================================
local _lastErrCheck = 0
local _lastTgtCheck = 0

RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Poll lỗi 0.5s
    if now - _lastErrCheck >= 0.5 then
        _lastErrCheck = now
        pcall(function()
            local m = GuiSvc:GetErrorMessage() or ""
            if m == "" then return end
            -- 773: mất kết nối → hop ngay
            if string.find(m,"773") or string.find(m,"disconnect")
            or string.find(m,"reconnect") then
                _hopLock = false; hopServer(2, "773")
            -- 267: bị kick → hop sau 8s
            elseif string.find(m,"267") or string.find(m,"Security")
            or string.find(m,"kicked") then
                _hopLock = false; hopServer(8, "267")
            -- 268: bị teleport về spawn → hop sau 5s
            elseif string.find(m,"268") then
                _hopLock = false; hopServer(5, "268")
            end
        end)
    end

    -- Triggerbot
    checkTriggerbot()

    -- Refresh target 0.5s
    if now - _lastTgtCheck >= 0.5 then
        _lastTgtCheck = now
        if not TGT or not isValid(TGT) or tgtDist() > MAX_DIST then
            TGT = pickTarget(); TGT_AT = now
        end
    end
end)

-- ================================================================
-- [11] GUI VIP — FPS, Ping, Uptime, Deaths, Kills, Players, CPS
-- ================================================================
if ENABLE_GUI then
    local G = Instance.new("ScreenGui")
    G.Name = "BountyGUI"; G.ResetOnSpawn = false
    G.Parent = LP:WaitForChild("PlayerGui")

    -- Main frame
    local F = Instance.new("Frame", G)
    F.Size = UDim2.new(0, 210, 0, 180)
    F.Position = UDim2.new(0, 10, 0.5, -90)
    F.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    F.BackgroundTransparency = 0.15
    F.BorderSizePixel = 0
    F.Visible = false
    Instance.new("UICorner", F).CornerRadius = UDim.new(0, 14)
    local St = Instance.new("UIStroke", F)
    St.Thickness = 1.5

    local function lb(sz, pos, txt, fs, bold, color)
        local l = Instance.new("TextLabel", F)
        l.Size = sz; l.Position = pos
        l.BackgroundTransparency = 1
        l.Text = txt; l.TextSize = fs
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        l.TextColor3 = color or Color3.fromRGB(255,255,255)
        return l
    end

    local pad = UDim2.new(0,10,0,0)

    local TL  = lb(UDim2.new(1,-10,0,22), UDim2.new(0,8,0,5),  "⚡ BOUNTY VIP",      14, true,  Color3.fromRGB(255,215,0))
    local L1  = lb(UDim2.new(1,-10,0,18), UDim2.new(0,8,0,30), "FPS: 60  |  Ping: 0ms", 12, false, Color3.fromRGB(180,255,180))
    local L2  = lb(UDim2.new(1,-10,0,18), UDim2.new(0,8,0,50), "CPS: 0",              12, false, Color3.fromRGB(180,220,255))
    local L3  = lb(UDim2.new(1,-10,0,18), UDim2.new(0,8,0,70), "Players: 0",          12, false, Color3.fromRGB(255,200,150))
    local L4  = lb(UDim2.new(1,-10,0,18), UDim2.new(0,8,0,90), "💀 Tao chết: 0",      12, false, Color3.fromRGB(255,120,120))
    local L5  = lb(UDim2.new(1,-10,0,18), UDim2.new(0,8,0,110),"☠️ Kill: 0",          12, false, Color3.fromRGB(120,255,120))
    local L6  = lb(UDim2.new(1,-10,0,18), UDim2.new(0,8,0,130),"🎯 Target: None",      12, false, Color3.fromRGB(255,255,180))
    local L7  = lb(UDim2.new(1,-10,0,18), UDim2.new(0,8,0,150),"⏱ Uptime: 00:00:00",  12, false, Color3.fromRGB(200,200,200))

    -- Divider
    local div = Instance.new("Frame", F)
    div.Size = UDim2.new(1,-16,0,1)
    div.Position = UDim2.new(0,8,0,26)
    div.BackgroundColor3 = Color3.fromRGB(80,80,80)
    div.BorderSizePixel = 0

    local fps = 60; local t0 = os.clock()

    RunService.RenderStepped:Connect(function(dt)
        if dt > 0 then fps = math.floor(1/dt) end
        local c = Color3.fromHSV((os.clock()%4)/4, .9, 1)
        TL.TextColor3 = c; St.Color = c
    end)

    task.spawn(function()
        while task.wait(0.5) do
            local ping = math.floor(LP:GetNetworkPing()*1000)
            local playerCount = #Players:GetPlayers()
            local e = os.clock() - t0
            local tgtName = (TGT and isValid(TGT)) and TGT.Name or "None"

            L1.Text = ("FPS: %d  |  Ping: %dms"):format(fps, ping)
            L2.Text = ("CPS: %d"):format(_cps)
            L3.Text = ("Players: %d"):format(playerCount)
            L4.Text = ("💀 Tao chết: %d"):format(_myDeaths)
            L5.Text = ("☠️ Kill: %d"):format(_theirDeaths)
            L6.Text = ("🎯 Target: %s"):format(tgtName)
            L7.Text = ("⏱ Uptime: %02d:%02d:%02d"):format(
                math.floor(e/3600), math.floor(e%3600/60), math.floor(e%60))

            -- Màu ping theo ngưỡng
            if ping < 80 then
                L1.TextColor3 = Color3.fromRGB(120,255,120)
            elseif ping < 150 then
                L1.TextColor3 = Color3.fromRGB(255,220,80)
            else
                L1.TextColor3 = Color3.fromRGB(255,80,80)
            end
        end
    end)

    task.delay(0.8, function() F.Visible = true end)
end

-- ================================================================
-- [12] SAFEZONE BYPASS
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
-- [13] SPAM SKILL
-- ================================================================
if ENABLE_AUTOSKILL then
    task.spawn(function()
        while task.wait(SKILL_DELAY) do
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
-- [14] SPAM M1
-- ================================================================
if ENABLE_M1 then
    task.spawn(function()
        while task.wait(0.05) do
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

print("✅ Bounty VIP | pSilent="..tostring(ENABLE_PSILENT)
    .." | Triggerbot="..tostring(ENABLE_TRIGGERBOT)
    .." | HitChance="..HIT_CHANCE.."%")
