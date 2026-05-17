-- ================================================================
--  Bounty.lua — MAIN SCRIPT VIP
--  KHÔNG có TeleportService hop — để Bountynew lo hoàn toàn
--  Chỉ detect 773 "Mất kết nối" thật → tự rejoin
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
local ENABLE_GUI        = CFG["Gui"]             ~= false

local SKILL_Z     = SKILL_CFG["Z"]     ~= false
local SKILL_X     = SKILL_CFG["X"]     ~= false
local SKILL_C     = SKILL_CFG["C"]     ~= false
local SKILL_V     = SKILL_CFG["V"]     == true
local SKILL_F     = SKILL_CFG["F"]     ~= false
local SKILL_DELAY = SKILL_CFG["Delay"] or 0.35

local HIT_CHANCE = CFG["HitChance"] or 87
local MAX_DIST   = 150

-- ================================================================
-- [2] FRUIT CONFIG
-- ================================================================
local FRUIT_CONFIG = {
    ["kitsune"]  = { delay=0.05, burst=8,  rest=0.30, active=true },
    ["t-rex"]    = { delay=0.06, burst=7,  rest=0.35, active=true },
    ["dragon"]   = { delay=0.07, burst=6,  rest=0.40, active=true },
    ["leopard"]  = { delay=0.06, burst=7,  rest=0.35, active=true },
    ["dough"]    = { delay=0.07, burst=6,  rest=0.40, active=true },
    ["blade"]    = { delay=0.08, burst=6,  rest=0.40, active=true },
    ["pain"]     = { delay=0.08, burst=5,  rest=0.45, active=true },
    ["gas"]      = { delay=0.09, burst=5,  rest=0.45, active=true },
    ["default"]  = { delay=0.08, burst=6,  rest=0.40, active=true },
}

local function getFruitCFG(char)
    local t = char and char:FindFirstChildOfClass("Tool")
    if not t then return nil end
    local s = string.lower((t.ToolTip or "").." "..(t.Name or ""))
    for fruit, cfg in pairs(FRUIT_CONFIG) do
        if fruit ~= "default" and string.find(s, fruit, 1, true) then
            return cfg
        end
    end
    return nil
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
local _lastDamaged = {}
local _m1Last      = 0
local _m1Burst     = 0
local _m1BurstCD   = 0
local _lastSkillCD = 0

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
-- [5] DETECT 773 "MẤT KẾT NỐI" THẬT → TỰ REJOIN
--     Popup: "Mất kết nối" + nút "Rời Khỏi"
--     → Teleport rejoin ngay trước khi bị kick hoàn toàn
-- ================================================================
local _rejoinLock    = false
local _lastRejoin    = 0
local _lastErrMsg    = ""
local _lastErrCheck  = 0
local _lastPopCheck  = 0

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
                local score = (s.ping or 999) + s.playing*10
                if score < bestScore then bestScore=score; best=s.id end
            end
        end
        return best
    end)
    return ok and sv or nil
end

local function rejoinServer(reason)
    if _rejoinLock then return end
    if tick() - _lastRejoin < 15 then return end
    _rejoinLock = true
    _lastRejoin = tick()
    warn("🔄 Rejoin ["..tostring(reason).."]")
    task.spawn(function()
        -- Thử teleport sang server mới ngay
        local sv = getNewServer()
        if sv then
            warn("✅ Rejoin server: "..sv:sub(1,8).."...")
            pcall(function()
                TpSvc:TeleportToPlaceInstance(game.PlaceId, sv, LP)
            end)
        else
            warn("⚠️ Rejoin thường")
            pcall(function()
                TpSvc:Teleport(game.PlaceId, LP)
            end)
        end
        task.wait(20)
        _rejoinLock = false
    end)
end

-- Pattern CHỈ cho 773 "Mất kết nối" thật
-- KHÔNG bao gồm "Dịch Chuyển" vì đó là TeleportInitFailed
local PATTERNS_773_REAL = {
    "mat ket noi",
    "mất kết nối",
    "ket noi lai khong thanh cong",
    "kết nối lại không thành công",
    "lost connection",
    "disconnect",
}

local function is773Real(m)
    local ml = string.lower(m)
    for _, p in ipairs(PATTERNS_773_REAL) do
        if string.find(ml, p, 1, true) then return true end
    end
    return false
end

-- ================================================================
-- [6] KILL + DEATH TRACKING
-- ================================================================
local function setupKillTrack(p)
    if not p or p == LP then return end
    local function onChar(c)
        task.wait(0.3)
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then return end
        local _prevHP = h.Health
        h.Died:Connect(function()
            if _lastDamaged[p.Name] and tick()-_lastDamaged[p.Name]<8 then
                _kills=_kills+1; _lastDamaged[p.Name]=nil
                warn("☠️ Kill! "..p.Name.." | ".._kills)
            end
        end)
        h.HealthChanged:Connect(function(hp)
            if hp<=0 and _prevHP>0 then
                if _lastDamaged[p.Name] and tick()-_lastDamaged[p.Name]<8 then
                    _kills=_kills+1; _lastDamaged[p.Name]=nil
                    warn("☠️ Kill(HP)! "..p.Name.." | ".._kills)
                end
            end
            _prevHP=hp
        end)
    end
    p.CharacterAdded:Connect(onChar)
    if p.Character then onChar(p.Character) end
end

for _, p in ipairs(Players:GetPlayers()) do setupKillTrack(p) end
Players.PlayerAdded:Connect(setupKillTrack)

local function setupMyDeath()
    local c=LP.Character; if not c then return end
    local h=c:FindFirstChildOfClass("Humanoid"); if not h then return end
    h.Died:Connect(function()
        _myDeaths=_myDeaths+1
        warn("💀 Chết lần ".._myDeaths)
    end)
end
LP.CharacterAdded:Connect(function() task.wait(0.3); setupMyDeath() end)
task.delay(1, setupMyDeath)

local function markDamage()
    if TGT and isValid(TGT) then _lastDamaged[TGT.Name]=tick() end
end

-- ================================================================
-- [7] pSILENT
-- ================================================================
local function psilentSnap(doAction)
    if not ENABLE_PSILENT or not TGT then doAction(); return end
    if math.random(1,100)>HIT_CHANCE then doAction(); return end
    local tc=TGT.Character; if not tc then doAction(); return end
    local tr=tc:FindFirstChild("HumanoidRootPart"); if not tr then doAction(); return end
    local pred=getPredPos(tr)
    if not isVisible(pred) then doAction(); return end
    local origCF=Camera.CFrame
    local dir=(pred-Camera.CFrame.Position).Unit
    Camera.CFrame=CFrame.new(Camera.CFrame.Position,Camera.CFrame.Position+dir)
    doAction()
    task.defer(function() pcall(function() Camera.CFrame=origCF end) end)
end

-- ================================================================
-- [8] TRIGGERBOT
-- ================================================================
local _tbLast=0
local function checkTriggerbot()
    if not ENABLE_TRIGGERBOT then return end
    local now=tick()
    if now-_tbLast<0.08+math.random()*0.04 then return end
    pcall(function()
        local mc=LP.Character; if not mc then return end
        local mh=mc:FindFirstChildOfClass("Humanoid")
        if not mh or mh.Health<=0 then return end
        local unitRay=Camera:ScreenPointToRay(
            Camera.ViewportSize.X/2,Camera.ViewportSize.Y/2)
        local params=RaycastParams.new()
        params.FilterDescendantsInstances={mc}
        params.FilterType=Enum.RaycastFilterType.Exclude
        local result=workspace:Raycast(unitRay.Origin,unitRay.Direction*MAX_DIST,params)
        if not result then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p~=LP and isValid(p) and p.Character then
                if result.Instance:IsDescendantOf(p.Character) then
                    _tbLast=now; _lastDamaged[p.Name]=tick()
                    pcall(function()
                        mouse1press()
                        task.wait(0.018+math.random()*0.01)
                        mouse1release()
                    end)
                    return
                end
            end
        end
    end)
end

-- ================================================================
-- [9] M1 HUMANIZED
-- ================================================================
local function doM1(sx, sy)
    local now=tick()
    if now<_m1BurstCD then return end
    local mc=LP.Character
    local fc=(mc and getFruitCFG(mc)) or FRUIT_CONFIG["default"]
    if not fc or not fc.active then return end
    if now-_m1Last<fc.delay then return end
    _m1Last=now; _m1Burst=_m1Burst+1
    _cpsCount=_cpsCount+1
    local el=now-_cpsLast
    if el>=1 then _cps=math.floor(_cpsCount/el); _cpsCount=0; _cpsLast=now end
    if _m1Burst>=math.random(fc.burst-1,fc.burst+1) then
        _m1Burst=0; _m1BurstCD=now+fc.rest+math.random()*0.2
    end
    markDamage()
    psilentSnap(function()
        pcall(function()
            mousemoveabs(sx+math.random(-4,4),sy+math.random(-4,4))
            mouse1press(); task.wait(0.018+math.random()*0.012); mouse1release()
        end)
    end)
end

-- ================================================================
-- [10] PRESS KEY
-- ================================================================
local function pressKey(keyCode)
    markDamage()
    task.spawn(function()
        pcall(function()
            local origCF=nil
            if ENABLE_PSILENT and TGT and isValid(TGT) then
                local tc=TGT.Character
                local tr=tc and tc:FindFirstChild("HumanoidRootPart")
                if tr then
                    local pred=getPredPos(tr)
                    if isVisible(pred) then
                        origCF=Camera.CFrame
                        Camera.CFrame=CFrame.new(
                            Camera.CFrame.Position,
                            Camera.CFrame.Position+(pred-Camera.CFrame.Position).Unit
                        )
                    end
                end
            end
            VIM:SendKeyEvent(true,keyCode,false,nil)
            task.wait(0.05)
            VIM:SendKeyEvent(false,keyCode,false,nil)
            if origCF then
                task.defer(function() pcall(function() Camera.CFrame=origCF end) end)
            end
        end)
    end)
end

-- ================================================================
-- [11] HEARTBEAT — detect 773 thật, scan popup
-- ================================================================
local _lastTgtCheck = 0

RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Poll GuiService 0.5s — chỉ bắt 773 thật
    if now - _lastErrCheck >= 0.5 then
        _lastErrCheck = now
        pcall(function()
            local m = GuiSvc:GetErrorMessage() or ""
            if m ~= "" and m ~= _lastErrMsg then
                _lastErrMsg = m
                if is773Real(m) then
                    warn("🚨 773 thật: "..m:sub(1,50))
                    rejoinServer("773-GuiErr")
                end
            end
        end)
    end

    -- Scan popup 0.5s — detect "Mất kết nối" + "Rời Khỏi"
    if now - _lastPopCheck >= 0.5 then
        _lastPopCheck = now
        pcall(function()
            local pg = LP.PlayerGui
            local found773 = false

            for _, obj in ipairs(pg:GetDescendants()) do
                if (obj:IsA("TextLabel") or obj:IsA("TextBox")) and obj.Visible then
                    local t = obj.Text or ""
                    if is773Real(t) then
                        found773 = true
                        warn("🚨 Popup 773 thật: "..t:sub(1,50))
                        break
                    end
                end
            end

            if found773 then
                -- Rejoin ngay trước khi bấm Rời Khỏi
                rejoinServer("773-popup")
            end
        end)
    end

    checkTriggerbot()

    if now - _lastTgtCheck >= 0.5 then
        _lastTgtCheck = now
        if not TGT or not isValid(TGT
