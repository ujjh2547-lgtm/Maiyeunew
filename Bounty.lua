-- ================================================================
--  Bounty.lua — MAIN SCRIPT VIP
--  Menu kéo được, Kill tracking đúng, Fix 267/773 mạnh hơn
-- ================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TpSvc      = game:GetService("TeleportService")
local GuiSvc     = game:GetService("GuiService")
local VIM        = game:GetService("VirtualInputManager")
local UIS        = game:GetService("UserInputService")
local LP         = Players.LocalPlayer
local Camera     = workspace.CurrentCamera

-- ================================================================
-- [1] ĐỌC CONFIG
-- ================================================================
local CFG       = getgenv().BountyExtra or {}
local SKILL_CFG = CFG["Auto Skill"]    or {}

local ENABLE_PSILENT    = CFG["AimSilent"]       ~= false
local ENABLE_TRIGGERBOT = CFG["Triggerbot"]      == true
local ENABLE_M1         = CFG["M1 click"]        ~= false
local ENABLE_AUTOSKILL  = SKILL_CFG["Enabled"]   ~= false
local ENABLE_AUTOHOP    = CFG["Auto server hop"] ~= false
local ENABLE_GUI        = CFG["Gui"]             ~= false

local SKILL_Z     = SKILL_CFG["Z"]     ~= false
local SKILL_X     = SKILL_CFG["X"]     ~= false
local SKILL_C     = SKILL_CFG["C"]     ~= false
local SKILL_V     = SKILL_CFG["V"]     == true
local SKILL_F     = SKILL_CFG["F"]     ~= false
local SKILL_DELAY = SKILL_CFG["Delay"] or 0.3

local HIT_CHANCE = CFG["HitChance"] or 87
local MAX_DIST   = 150

local M1_WHITELIST = CFG["M1"] or {
    ["kitsune"]=true, ["t-rex"]=true, ["dragon"]=true,
    ["blade"]=true,   ["dough"]=true, ["gas"]=true,
    ["pain"]=true,    ["leopard"]=true,
}

-- ================================================================
-- [2] STATE
-- ================================================================
local TGT         = nil
local TGT_AT      = 0
local _myDeaths   = 0
local _kills      = 0
local _cpsCount   = 0
local _cpsLast    = tick()
local _cps        = 0
local _hopCount   = 0
local _lastHopTime = 0

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
-- [4] KILL + DEATH TRACKING
--     Kill = khi enemy Humanoid.Died VÀ tao là người cuối đánh
-- ================================================================
local _lastDamaged = {}  -- lưu ai tao vừa đánh

local function trackEnemy(p)
    if not p or p == LP then return end
    p.CharacterAdded:Connect(function(c)
        task.wait(0.5)
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then return end
        -- Khi enemy chết
        h.Died:Connect(function()
            -- Chỉ tính kill nếu tao vừa đánh nó gần đây (< 5s)
            if _lastDamaged[p.Name] and tick() - _lastDamaged[p.Name] < 5 then
                _kills = _kills + 1
                _lastDamaged[p.Name] = nil
                warn("💀 Kill: " .. p.Name .. " | Total: " .. _kills)
            end
        end)
    end)
end

-- Track tất cả player hiện tại
for _, p in ipairs(Players:GetPlayers()) do
    trackEnemy(p)
end
Players.PlayerAdded:Connect(trackEnemy)

-- Track death của mình
local function setupMyDeath()
    local c = LP.Character; if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid"); if not h then return end
    h.Died:Connect(function()
        _myDeaths = _myDeaths + 1
        warn("💀 Tao chết lần " .. _myDeaths)
    end)
end

LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    setupMyDeath()
end)
task.delay(1, setupMyDeath)

-- Đánh dấu khi M1/skill chạm enemy
local function markDamage(target)
    if target and target ~= LP then
        _lastDamaged[target.Name] = tick()
    end
end

-- ================================================================
-- [5] pSILENT
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
    markDamage(TGT)
    task.defer(function()
        pcall(function() Camera.CFrame = origCF end)
    end)
end

-- ================================================================
-- [6] TRIGGERBOT
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
        local result = workspace:Raycast(
            unitRay.Origin, unitRay.Direction * MAX_DIST, params
        )
        if not result then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and isValid(p) and p.Character then
                if result.Instance:IsDescendantOf(p.Character) then
                    _tbLast = now
                    markDamage(p)
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
-- [7] M1 HUMANIZED
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

    -- CPS tracking
    _cpsCount = _cpsCount + 1
    local elapsed = now - _cpsLast
    if elapsed >= 1 then
        _cps = math.floor(_cpsCount/elapsed)
        _cpsCount = 0; _cpsLast = now
    end

    if _m1Burst >= math.random(6,8) then
        _m1Burst = 0
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
-- [9] AUTO HOP — fix 267/268/773 mạnh nhất
--     773 + nút "Rời Khỏi" → detect và hop ngay
--     267 → hop sau 8s (không retry liên tục)
--     268 → hop sau 5s
--     Hop quá 3 lần → nghỉ 60s tránh ban
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

local function hopServer(delay, reason)
    if not ENABLE_AUTOHOP then return end
    if _hopLock then return end

    -- Hop quá 3 lần liên tiếp → nghỉ 60s
    if _hopCount >= 3 then
        warn("⚠️ Hop quá nhiều — nghỉ 60s")
        task.wait(60)
        _hopCount = 0
    end

    if tick() - _lastHop < 20 then return end
    _hopLock  = true
    _hopCount = _hopCount + 1
    warn("🔄 Hop ["..tostring(reason or "auto").."] sau "..tostring(delay or 3).."s")

    task.spawn(function()
        task.wait(delay or 3)
        local w = 0
        while not charReady() and w < 15 do task.wait(0.5); w=w+0.5 end
        task.wait(0.5 + math.random()*0.5)
        _lastHop = tick()

        local sv = getNewServer()
        if sv then
            warn("✅ Tìm được server mới")
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
        _hopLock = false
    end)
end

-- Reset hop count sau 5 phút
task.spawn(function()
    while task.wait(300) do _hopCount = 0 end
end)

-- TeleportInitFailed — hop ngay
TpSvc.TeleportInitFailed:Connect(function(plr)
    if plr ~= LP then return end
    _hopLock = false; _lastHop = 0
    hopServer(2, "TpFailed")
end)

-- Character không spawn 10s → hop
LP.CharacterRemoving:Connect(function()
    task.spawn(function()
        task.wait(10)
        if not charReady() then
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
local _lastErrMsg   = ""

RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Poll lỗi mỗi 0.3s — nhanh hơn để detect 773 kịp
    if now - _lastErrCheck >= 0.3 then
        _lastErrCheck = now
        pcall(function()
            local m = GuiSvc:GetErrorMessage() or ""
            -- Chỉ xử lý khi message thay đổi hoặc mới
            if m ~= "" and m ~= _lastErrMsg then
                _lastErrMsg = m
                warn("ErrorMsg: " .. m)
                local ml = string.lower(m)
                if string.find(ml,"773")
                or string.find(ml,"disconnect")
                or string.find(ml,"reconnect")
                or string.find(ml,"roi khoi")
                or string.find(ml,"rời khỏi")
                or string.find(ml,"leave") then
                    -- 773: hop ngay, reset lock
                    _hopLock = false
                    hopServer(1, "773")
                elseif string.find(ml,"267")
                or string.find(ml,"security")
                or string.find(ml,"kicked") then
                    -- 267: hop sau 8s
                    _hopLock = false
                    hopServer(8, "267")
                elseif string.find(ml,"268") then
                    -- 268: hop sau 5s
                    _hopLock = false
                    hopServer(5, "268")
                end
            end
        end)
    end

    -- Triggerbot
    checkTriggerbot()

    -- Refresh target
    if now - _lastTgtCheck >= 0.5 then
        _lastTgtCheck = now
        if not TGT or not isValid(TGT) or tgtDist() > MAX_DIST then
            TGT = pickTarget(); TGT_AT = now
        end
    end
end)

-- ================================================================
-- [11] GUI VIP — KÉO ĐƯỢC
-- ================================================================
if ENABLE_GUI then
    local G = Instance.new("ScreenGui")
    G.Name = "BountyGUI"
    G.ResetOnSpawn = false
    G.DisplayOrder = 999
    G.Parent = LP:WaitForChild("PlayerGui")

    -- Main Frame
    local F = Instance.new("Frame", G)
    F.Size = UDim2.new(0, 215, 0, 195)
    F.Position = UDim2.new(0, 10, 0.4, 0)
    F.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
    F.BackgroundTransparency = 0.1
    F.BorderSizePixel = 0
    F.Active = true
    F.Visible = false
    Instance.new("UICorner", F).CornerRadius = UDim.new(0, 14)
    local St = Instance.new("UIStroke", F)
    St.Thickness = 1.5
    St.Color = Color3.fromRGB(255, 215, 0)

    -- Title bar (kéo ở đây)
    local TitleBar = Instance.new("Frame", F)
    TitleBar.Size = UDim2.new(1, 0, 0, 28)
    TitleBar.Position = UDim2.new(0, 0, 0, 0)
    TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    TitleBar.BackgroundTransparency = 0.3
    TitleBar.BorderSizePixel = 0
    TitleBar.Active = true
    Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 14)

    local TitleLbl = Instance.new("TextLabel", TitleBar)
    TitleLbl.Size = UDim2.new(1, -10, 1, 0)
    TitleLbl.Position = UDim2.new(0, 10, 0, 0)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.Text = "⚡ BOUNTY VIP"
    TitleLbl.TextSize = 13
    TitleLbl.Font = Enum.Font.GothamBold
    TitleLbl.TextColor3 = Color3.fromRGB(255, 215, 0)
    TitleLbl.TextXAlignment = Enum.TextXAlignment.Left

    -- Divider
    local Div = Instance.new("Frame", F)
    Div.Size = UDim2.new(1, -16, 0, 1)
    Div.Position = UDim2.new(0, 8, 0, 29)
    Div.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    Div.BorderSizePixel = 0

    -- Labels
    local function lb(pos, txt, color)
        local l = Instance.new("TextLabel", F)
        l.Size = UDim2.new(1, -16, 0, 19)
        l.Position = pos
        l.BackgroundTransparency = 1
        l.Text = txt
        l.TextSize = 12
        l.Font = Enum.Font.Gotham
        l.TextColor3 = color or Color3.fromRGB(220, 220, 220)
        l.TextXAlignment = Enum.TextXAlignment.Left
        return l
    end

    local L1 = lb(UDim2.new(0,8,0,33),  "📶 FPS: --  Ping: --ms",     Color3.fromRGB(120,255,120))
    local L2 = lb(UDim2.new(0,8,0,54),  "🖱️ CPS: 0",                  Color3.fromRGB(130,200,255))
    local L3 = lb(UDim2.new(0,8,0,75),  "👥 Players: 0",               Color3.fromRGB(255,200,120))
    local L4 = lb(UDim2.new(0,8,0,96),  "💀 Tao chết: 0",              Color3.fromRGB(255,100,100))
    local L5 = lb(UDim2.new(0,8,0,117), "☠️ Kill: 0",                  Color3.fromRGB(100,255,150))
    local L6 = lb(UDim2.new(0,8,0,138), "🎯 Target: None",              Color3.fromRGB(255,255,150))
    local L7 = lb(UDim2.new(0,8,0,159), "⏱ Uptime: 00:00:00",          Color3.fromRGB(180,180,180))
    local L8 = lb(UDim2.new(0,8,0,178), "🔄 Hop: 0 lần",               Color3.fromRGB(200,150,255))

    -- ================================================================
    -- DRAG — kéo menu
    -- ================================================================
    local _dragging = false
    local _dragStart = nil
    local _frameStart = nil

    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            _dragging   = true
            _dragStart  = input.Position
            _frameStart = F.Position
        end
    end)

    TitleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            _dragging = false
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not _dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - _dragStart
        F.Position = UDim2.new(
            _frameStart.X.Scale,
            _frameStart.X.Offset + delta.X,
            _frameStart.Y.Scale,
            _frameStart.Y.Offset + delta.Y
        )
    end)

    -- ================================================================
    -- UPDATE LOOP
    -- ================================================================
    local fps = 60
    local t0  = os.clock()

    RunService.RenderStepped:Connect(function(dt)
        if dt > 0 then fps = math.floor(1/dt) end
        local c = Color3.fromHSV((os.clock()%4)/4, .9, 1)
        TitleLbl.TextColor3 = c
        St.Color = c
    end)

    task.spawn(function()
        while task.wait(0.5) do
            local ping  = math.floor(LP:GetNetworkPing()*1000)
            local pCount = #Players:GetPlayers()
            local e     = os.clock() - t0
            local tName = (TGT and isValid(TGT)) and TGT.Name or "None"

            -- FPS màu theo giá trị
            local fpsColor
            if fps >= 50 then fpsColor = Color3.fromRGB(120,255,120)
            elseif fps >= 30 then fpsColor = Color3.fromRGB(255,220,80)
            else fpsColor = Color3.fromRGB(255,80,80) end
            L1.TextColor3 = fpsColor

            -- Ping màu theo ngưỡng
            if ping < 80 then L1.TextColor3 = Color3.fromRGB(120,255,120)
            elseif ping < 150 then L1.TextColor3 = Color3.fromRGB(255,220,80)
            else L1.TextColor3 = Color3.fromRGB(255,80,80) end

            L1.Text = ("📶 FPS: %d  Ping: %dms"):format(fps, ping)
            L2.Text = ("🖱️ CPS: %d"):format(_cps)
            L3.Text = ("👥 Players: %d"):format(pCount)
            L4.Text = ("💀 Tao chết: %d"):format(_myDeaths)
            L5.Text = ("☠️ Kill: %d"):format(_kills)
            L6.Text = ("🎯 Target: %s"):format(tName)
            L7.Text = ("⏱ Uptime: %02d:%02d:%02d"):format(
                math.floor(e/3600), math.floor(e%3600/60), math.floor(e%60))
            L8.Text = ("🔄 Hop: %d lần"):format(_hopCount)
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
