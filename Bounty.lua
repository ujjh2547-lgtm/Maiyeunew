-- ================================================================
--  Bounty.lua — MAIN SCRIPT VIP
--  Fix: 267/773 mọi dạng, Kill tracking chắc chắn,
--       Config M1 từng trái, Chống hồi sinh mất bounty
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

-- ================================================================
-- [2] CONFIG M1 TỪNG TRÁI
--     delay  = thời gian giữa các M1 (giây) — nhỏ = nhanh hơn
--     burst  = số M1 liên tiếp trước khi nghỉ
--     rest   = thời gian nghỉ sau burst (giây)
--     active = có dùng M1 không
-- ================================================================
local FRUIT_CONFIG = {
    -- Trái farm ngon, M1 mạnh
    ["kitsune"]  = { delay=0.05, burst=8,  rest=0.3, active=true  },
    ["t-rex"]    = { delay=0.06, burst=7,  rest=0.35,active=true  },
    ["dragon"]   = { delay=0.07, burst=6,  rest=0.4, active=true  },
    ["leopard"]  = { delay=0.06, burst=7,  rest=0.35,active=true  },
    ["dough"]    = { delay=0.07, burst=6,  rest=0.4, active=true  },

    -- Trái M1 trung bình
    ["blade"]    = { delay=0.08, burst=6,  rest=0.4, active=true  },
    ["pain"]     = { delay=0.08, burst=5,  rest=0.45,active=true  },
    ["gas"]      = { delay=0.09, burst=5,  rest=0.45,active=true  },

    -- Default cho trái không có config
    ["default"]  = { delay=0.08, burst=6,  rest=0.4, active=true  },
}

local function getFruitConfig(char)
    local t = char and char:FindFirstChildOfClass("Tool")
    if not t then return nil end
    local s = string.lower((t.ToolTip or "").." "..(t.Name or ""))
    for fruit, cfg in pairs(FRUIT_CONFIG) do
        if fruit ~= "default" and string.find(s, fruit, 1, true) then
            return cfg, fruit
        end
    end
    -- Kiểm tra có phải trái nào đó không
    for fruit in pairs(FRUIT_CONFIG) do
        if fruit ~= "default" then
            if string.find(s, fruit, 1, true) then
                return FRUIT_CONFIG[fruit], fruit
            end
        end
    end
    return nil, nil
end

-- ================================================================
-- [3] STATE
-- ================================================================
local TGT          = nil
local TGT_AT       = 0
local _myDeaths    = 0
local _kills       = 0
local _cpsCount    = 0
local _cpsLast     = tick()
local _cps         = 0
local _hopCount    = 0
local _lastHop     = 0
local _hopLock     = false
local _lastErrMsg  = ""
local _lastDamaged = {}
local _m1Last      = 0
local _m1Burst     = 0
local _m1BurstCD   = 0

-- ================================================================
-- [4] TARGET SYSTEM
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
-- [5] KILL TRACKING — chắc chắn không miss
--     Dùng cả Humanoid.Died + HealthChanged để chắc
-- ================================================================
local function setupKillTrack(p)
    if not p or p == LP then return end
    local function onCharAdded(c)
        task.wait(0.3)
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then return end

        -- Cách 1: Humanoid.Died
        h.Died:Connect(function()
            if _lastDamaged[p.Name]
            and tick() - _lastDamaged[p.Name] < 8 then
                _kills = _kills + 1
                _lastDamaged[p.Name] = nil
                warn("☠️ KILL! "..p.Name.." | Total: ".._kills)
            end
        end)

        -- Cách 2: HealthChanged backup (đề phòng Died không fire)
        local _prevHP = h.Health
        h.HealthChanged:Connect(function(hp)
            if hp <= 0 and _prevHP > 0 then
                if _lastDamaged[p.Name]
                and tick() - _lastDamaged[p.Name] < 8 then
                    _kills = _kills + 1
                    _lastDamaged[p.Name] = nil
                    warn("☠️ KILL(HP)! "..p.Name.." | Total: ".._kills)
                end
            end
            _prevHP = hp
        end)
    end

    p.CharacterAdded:Connect(onCharAdded)
    if p.Character then onCharAdded(p.Character) end
end

for _, p in ipairs(Players:GetPlayers()) do setupKillTrack(p) end
Players.PlayerAdded:Connect(setupKillTrack)

-- Death tracking
local function setupMyDeath()
    local c = LP.Character; if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid"); if not h then return end
    h.Died:Connect(function()
        _myDeaths = _myDeaths + 1
        warn("💀 Tao chết lần ".._myDeaths)
    end)
end
LP.CharacterAdded:Connect(function() task.wait(0.3); setupMyDeath() end)
task.delay(1, setupMyDeath)

local function markDamage()
    if TGT and isValid(TGT) then
        _lastDamaged[TGT.Name] = tick()
    end
end

-- ================================================================
-- [6] CHỐNG HỒI SINH MẤT BOUNTY
--     Khi character chết → chặn màn hình respawn
--     Tự chọn "Respawn" thay vì để game tự hồi sinh
--     (tránh bounty bị reset do timeout respawn)
-- ================================================================
local _lastRespawnBlock = 0

local function blockRespawnScreen()
    local now = tick()
    if now - _lastRespawnBlock < 1 then return end
    _lastRespawnBlock = now
    pcall(function()
        local pg = LP.PlayerGui
        -- Tìm màn hình respawn của Roblox
        for _, gui in ipairs(pg:GetChildren()) do
            if gui:IsA("ScreenGui") then
                local name = string.lower(gui.Name)
                if string.find(name,"respawn")
                or string.find(name,"death")
                or string.find(name,"died") then
                    -- Tìm nút respawn và bấm ngay
                    for _, obj in ipairs(gui:GetDescendants()) do
                        if obj:IsA("TextButton") then
                            local t = string.lower(obj.Text or "")
                            if string.find(t,"respawn")
                            or string.find(t,"hoi sinh")
                            or string.find(t,"hồi sinh")
                            or string.find(t,"play again")
                            or string.find(t,"continue") then
                                pcall(function() obj:Activate() end)
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ================================================================
-- [7] pSILENT
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
-- [8] TRIGGERBOT
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
            Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {mc}
        params.FilterType = Enum.RaycastFilterType.Exclude
        local result = workspace:Raycast(
            unitRay.Origin, unitRay.Direction*MAX_DIST, params)
        if not result then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and isValid(p) and p.Character then
                if result.Instance:IsDescendantOf(p.Character) then
                    _tbLast = now
                    _lastDamaged[p.Name] = tick()
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
-- [9] M1 — delay theo từng trái, burst control
-- ================================================================
local function doM1(sx, sy)
    local now = tick()
    if now < _m1BurstCD then return end

    -- Lấy config trái hiện tại
    local mc = LP.Character
    local fruitCFG = nil
    if mc then
        local cfg, _ = getFruitConfig(mc)
        fruitCFG = cfg
    end
    local fc = fruitCFG or FRUIT_CONFIG["default"]
    if not fc.active then return end

    if now - _m1Last < fc.delay then return end
    _m1Last  = now
    _m1Burst = _m1Burst + 1

    -- CPS
    _cpsCount = _cpsCount + 1
    local elapsed = now - _cpsLast
    if elapsed >= 1 then
        _cps = math.floor(_cpsCount/elapsed)
        _cpsCount = 0; _cpsLast = now
    end

    -- Burst control theo trái
    if _m1Burst >= math.random(fc.burst - 1, fc.burst + 1) then
        _m1Burst   = 0
        _m1BurstCD = now + fc.rest + math.random()*0.2
    end

    markDamage()
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
-- [10] PRESS KEY
-- ================================================================
local function pressKey(keyCode)
    markDamage()
    psilentSnap(function()
        pcall(function()
            VIM:SendKeyEvent(true,  keyCode, false, nil)
            task.wait(0.05)
            VIM:SendKeyEvent(false, keyCode, false, nil)
        end)
    end)
end

-- ================================================================
-- [11] AUTO HOP — fix MỌI dạng 773/267
--      Detect: số mã, text tiếng Việt, nút Rời Khỏi/OK/Kết nối lại
--      773 → hop sau 1s (nhanh nhất có thể)
--      267 → hop sau 8s
--      268 → hop sau 5s
-- ================================================================
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
    if _hopCount >= 3 then
        warn("⚠️ Hop quá nhiều — nghỉ 60s")
        task.wait(60); _hopCount = 0
    end
    if tick() - _lastHop < 15 then return end
    _hopLock  = true
    _hopCount = _hopCount + 1
    warn("🔄 Hop ["..tostring(reason).."] sau "..tostring(delay).."s")
    task.spawn(function()
        task.wait(delay)
        local w = 0
        while not charReady() and w < 10 do task.wait(0.5); w=w+0.5 end
        task.wait(0.3 + math.random()*0.3)
        _lastHop = tick()
        local sv = getNewServer()
        if sv then
            warn("✅ Server mới: "..sv)
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
        task.wait(12)
        _hopLock = false
    end)
end

task.spawn(function() while task.wait(300) do _hopCount = 0 end end)

TpSvc.TeleportInitFailed:Connect(function(plr)
    if plr ~= LP then return end
    warn("TeleportInitFailed")
    _hopLock = false; _lastHop = 0
    hopServer(1, "TpFailed")
end)

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
-- [12] HEARTBEAT — detect 267/773 MỌI DẠNG
-- ================================================================
local _lastErrCheck = 0
local _lastTgtCheck = 0
local _lastPopupCheck = 0

-- Tất cả pattern có thể của 773/267
local PATTERNS_773 = {
    "773", "disconnect", "reconnect", "lost connection",
    "connection lost", "mất kết nối", "mat ket noi",
    "roi khoi", "rời khỏi", "leave", "server closed",
    "không thể kết nối", "khong the ket noi",
    "kết nối lại không thành công", "ket noi lai",
    "không nhận được phản hồi", "phan hoi",
}

local PATTERNS_267 = {
    "267", "kicked", "security", "violation",
    "bị đuổi", "bi duoi", "vi phạm", "vi pham",
    "cheat", "exploit",
}

local PATTERNS_268 = {
    "268", "teleported", "moved to",
}

local function matchPatterns(m, patterns)
    local ml = string.lower(m)
    for _, p in ipairs(patterns) do
        if string.find(ml, p, 1, true) then return true end
    end
    return false
end

RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Poll GuiService error mỗi 0.3s
    if now - _lastErrCheck >= 0.3 then
        _lastErrCheck = now
        pcall(function()
            local m = GuiSvc:GetErrorMessage() or ""
            if m ~= "" and m ~= _lastErrMsg then
                _lastErrMsg = m
                warn("🚨 Error: "..m)
                if matchPatterns(m, PATTERNS_773) then
                    _hopLock = false; hopServer(1, "773")
                elseif matchPatterns(m, PATTERNS_267) then
                    _hopLock = false; hopServer(8, "267")
                elseif matchPatterns(m, PATTERNS_268) then
                    _hopLock = false; hopServer(5, "268")
                end
            end
        end)
    end

    -- Scan popup trong PlayerGui mỗi 0.5s
    -- Detect nút "Rời Khỏi", "OK", "Kết nối lại"
    if now - _lastPopupCheck >= 0.5 then
        _lastPopupCheck = now
        pcall(function()
            local pg = LP.PlayerGui
            for _, gui in ipairs(pg:GetDescendants()) do
                if gui:IsA("TextLabel") or gui:IsA("TextBox") then
                    local t = gui.Text or ""
                    if t ~= "" then
                        if matchPatterns(t, PATTERNS_773) then
                            warn("🚨 Popup 773: "..t:sub(1,50))
                            _hopLock = false; hopServer(1, "773-popup")
                        elseif matchPatterns(t, PATTERNS_267) then
                            warn("🚨 Popup 267: "..t:sub(1,50))
                            _hopLock = false; hopServer(8, "267-popup")
                        end
                    end
                end
            end
        end)
    end

    -- Respawn screen check
    blockRespawnScreen()

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
-- [13] GUI VIP — KÉO ĐƯỢC
-- ================================================================
if ENABLE_GUI then
    local G = Instance.new("ScreenGui")
    G.Name = "BountyGUI"; G.ResetOnSpawn = false
    G.DisplayOrder = 999
    G.Parent = LP:WaitForChild("PlayerGui")

    local F = Instance.new("Frame", G)
    F.Size = UDim2.new(0, 215, 0, 175)
    F.Position = UDim2.new(0, 10, 0.4, 0)
    F.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
    F.BackgroundTransparency = 0.1
    F.BorderSizePixel = 0; F.Active = true; F.Visible = false
    Instance.new("UICorner", F).CornerRadius = UDim.new(0, 14)
    local St = Instance.new("UIStroke", F); St.Thickness = 1.5

    local TB = Instance.new("Frame", F)
    TB.Size = UDim2.new(1,0,0,28); TB.Position = UDim2.new(0,0,0,0)
    TB.BackgroundColor3 = Color3.fromRGB(20,20,20)
    TB.BackgroundTransparency = 0.3
    TB.BorderSizePixel = 0; TB.Active = true
    Instance.new("UICorner", TB).CornerRadius = UDim.new(0,14)

    local TL = Instance.new("TextLabel", TB)
    TL.Size = UDim2.new(1,-10,1,0); TL.Position = UDim2.new(0,10,0,0)
    TL.BackgroundTransparency = 1; TL.Text = "⚡ BOUNTY VIP"
    TL.TextSize = 13; TL.Font = Enum.Font.GothamBold
    TL.TextColor3 = Color3.fromRGB(255,215,0)
    TL.TextXAlignment = Enum.TextXAlignment.Left

    local Div = Instance.new("Frame", F)
    Div.Size = UDim2.new(1,-16,0,1); Div.Position = UDim2.new(0,8,0,29)
    Div.BackgroundColor3 = Color3.fromRGB(60,60,60); Div.BorderSizePixel = 0

    local function lb(pos, txt, color)
        local l = Instance.new("TextLabel", F)
        l.Size = UDim2.new(1,-16,0,19); l.Position = pos
        l.BackgroundTransparency = 1; l.Text = txt; l.TextSize = 12
        l.Font = Enum.Font.Gotham
        l.TextColor3 = color or Color3.fromRGB(220,220,220)
        l.TextXAlignment = Enum.TextXAlignment.Left
        return l
    end

    local L1 = lb(UDim2.new(0,8,0,33),  "📶 FPS: --  Ping: --ms", Color3.fromRGB(120,255,120))
    local L2 = lb(UDim2.new(0,8,0,54),  "🖱️ CPS: 0",              Color3.fromRGB(130,200,255))
    local L3 = lb(UDim2.new(0,8,0,75),  "👥 Players: 0",           Color3.fromRGB(255,200,120))
    local L4 = lb(UDim2.new(0,8,0,96),  "💀 Tao chết: 0",          Color3.fromRGB(255,100,100))
    local L5 = lb(UDim2.new(0,8,0,117), "☠️ Kill: 0",              Color3.fromRGB(100,255,150))
    local L6 = lb(UDim2.new(0,8,0,138), "🎯 Target: None",          Color3.fromRGB(255,255,150))
    local L7 = lb(UDim2.new(0,8,0,158), "⏱ 00:00:00",              Color3.fromRGB(180,180,180))

    -- Drag
    local _drag=false; local _ds; local _fs
    TB.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch
        or i.UserInputType==Enum.UserInputType.MouseButton1 then
            _drag=true; _ds=i.Position; _fs=F.Position
        end
    end)
    TB.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch
        or i.UserInputType==Enum.UserInputType.MouseButton1 then
            _drag=false
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if not _drag then return end
        if i.UserInputType~=Enum.UserInputType.MouseMovement
        and i.UserInputType~=Enum.UserInputType.Touch then return end
        local d=i.Position-_ds
        F.Position=UDim2.new(_fs.X.Scale,_fs.X.Offset+d.X,_fs.Y.Scale,_fs.Y.Offset+d.Y)
    end)

    local fps=60; local t0=os.clock()
    RunService.RenderStepped:Connect(function(dt)
        if dt>0 then fps=math.floor(1/dt) end
        local c=Color3.fromHSV((os.clock()%4)/4,.9,1)
        TL.TextColor3=c; St.Color=c
    end)

    task.spawn(function()
        while task.wait(0.5) do
            local ping  = math.floor(LP:GetNetworkPing()*1000)
            local pCount = #Players:GetPlayers()
            local e     = os.clock()-t0
            local tName = (TGT and isValid(TGT)) and TGT.Name or "None"
            if ping<80 then L1.TextColor3=Color3.fromRGB(120,255,120)
            elseif ping<150 then L1.TextColor3=Color3.fromRGB(255,220,80)
            else L1.TextColor3=Color3.fromRGB(255,80,80) end
            L1.Text=("📶 FPS:%d  Ping:%dms"):format(fps,ping)
            L2.Text=("🖱️ CPS:%d"):format(_cps)
            L3.Text=("👥 Players:%d"):format(pCount)
            L4.Text=("💀 Chết:%d"):format(_myDeaths)
            L5.Text=("☠️ Kill:%d"):format(_kills)
            L6.Text=("🎯 %s"):format(tName)
            L7.Text=("⏱ %02d:%02d:%02d"):format(
                math.floor(e/3600),math.floor(e%3600/60),math.floor(e%60))
        end
    end)
    task.delay(0.8,function() F.Visible=true end)
end

-- ================================================================
-- [14] NPC / QUEST BYPASS
-- ================================================================
task.spawn(function()
    while task.wait(0.3) do
        pcall(function()
            local pg=LP.PlayerGui
            for _, gui in ipairs(pg:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    local name=string.lower(gui.Name)
                    if string.find(name,"dialogue") or string.find(name,"quest")
                    or string.find(name,"npc") or string.find(name,"shop")
                    or string.find(name,"interact") or string.find(name,"talk") then
                        local closed=false
                        for _, obj in ipairs(gui:GetDescendants()) do
                            if obj:IsA("TextButton") and obj.Visible then
                                local t=string.lower(obj.Text or "")
                                if string.find(t,"close") or string.find(t,"skip")
                                or string.find(t,"cancel") or t=="x"
                                or string.find(t,"thoat") or string.find(t,"thoát")
                                or string.find(t,"bo qua") or string.find(t,"bỏ qua")
                                or string.find(t,"next") or string.find(t,"tiep") then
                                    pcall(function() obj:Activate() end)
                                    closed=true
                                end
                            end
                        end
                        if not closed then gui.Enabled=false end
                    end
                end
            end
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
-- [15] SPAM SKILL
-- ================================================================
if ENABLE_AUTOSKILL then
    task.spawn(function()
        while task.wait(SKILL_DELAY) do
            if not TGT or not isValid(TGT) then continue end
            pcall(function()
                local mc=LP.Character; if not mc then return end
                local mh=mc:FindFirstChildOfClass("Humanoid")
                if not mh or mh.Health<=0 then return end
                if tgtDist()>80 then return end
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
-- [16] SPAM M1 — dùng config từng trái
-- ================================================================
if ENABLE_M1 then
    task.spawn(function()
        while task.wait(0.04) do
            if not TGT or not isValid(TGT) then continue end
            pcall(function()
                local mc=LP.Character; if not mc then return end
                local mh=mc:FindFirstChildOfClass("Humanoid")
                if not mh or mh.Health<=0 then return end
                -- Check trái có trong whitelist không
                local fc, fname = getFruitConfig(mc)
                if not fc then return end  -- không có trái trong whitelist
                if not fc.active then return end
                if tgtDist()>25 then return end
                local tc=TGT.Character; if not tc then return end
                local tr=tc:FindFirstChild("HumanoidRootPart"); if not tr then return end
                local pred=ENABLE_PSILENT and getPredPos(tr) or tr.Position
                local sp,onScreen=Camera:WorldToViewportPoint(pred)
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
