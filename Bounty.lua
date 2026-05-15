-- ================================================================
--  Bounty.lua — MAIN SCRIPT VIP
--  TeleportInitFailed: chỉ tắt popup, không hop nếu vẫn trong game
--  267: thêm cooldown giữa skill, giảm spam
--  NPC: detect "Bỏ qua" đúng
--  Kill: dùng cả Died + HealthChanged
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
local SKILL_DELAY = SKILL_CFG["Delay"] or 0.35

local HIT_CHANCE = CFG["HitChance"] or 87
local MAX_DIST   = 150

-- ================================================================
-- [2] FRUIT CONFIG — M1 delay theo từng trái
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
local TGT           = nil
local TGT_AT        = 0
local _myDeaths     = 0
local _kills        = 0
local _cpsCount     = 0
local _cpsLast      = tick()
local _cps          = 0
local _hopCount     = 0
local _lastHop      = 0
local _hopLock      = false
local _lastErrMsg   = ""
local _lastDamaged  = {}
local _m1Last       = 0
local _m1Burst      = 0
local _m1BurstCD    = 0
local _lastSkillCD  = 0
local _inGame       = true  -- flag: còn trong game không

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
-- [5] KILL + DEATH TRACKING
-- ================================================================
local function setupKillTrack(p)
    if not p or p == LP then return end
    local function onChar(c)
        task.wait(0.3)
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then return end
        local _prevHP = h.Health
        h.Died:Connect(function()
            if _lastDamaged[p.Name] and tick()-_lastDamaged[p.Name] < 8 then
                _kills = _kills + 1
                _lastDamaged[p.Name] = nil
                warn("☠️ Kill! "..p.Name.." | Total: ".._kills)
            end
        end)
        h.HealthChanged:Connect(function(hp)
            if hp <= 0 and _prevHP > 0 then
                if _lastDamaged[p.Name] and tick()-_lastDamaged[p.Name] < 8 then
                    _kills = _kills + 1
                    _lastDamaged[p.Name] = nil
                    warn("☠️ Kill(HP)! "..p.Name.." | Total: ".._kills)
                end
            end
            _prevHP = hp
        end)
    end
    p.CharacterAdded:Connect(onChar)
    if p.Character then onChar(p.Character) end
end

for _, p in ipairs(Players:GetPlayers()) do setupKillTrack(p) end
Players.PlayerAdded:Connect(setupKillTrack)

local function setupMyDeath()
    local c = LP.Character; if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid"); if not h then return end
    h.Died:Connect(function()
        _myDeaths = _myDeaths + 1
        warn("💀 Chết lần ".._myDeaths)
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
-- [6] pSILENT
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
    local origCF = Camera.CFrame
    local dir    = (pred - Camera.CFrame.Position).Unit
    Camera.CFrame = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + dir)
    doAction()
    task.defer(function()
        pcall(function() Camera.CFrame = origCF end)
    end)
end

-- ================================================================
-- [7] TRIGGERBOT
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
-- [8] M1 HUMANIZED
-- ================================================================
local function doM1(sx, sy)
    local now = tick()
    if now < _m1BurstCD then return end
    local mc = LP.Character
    local fc = (mc and getFruitCFG(mc)) or FRUIT_CONFIG["default"]
    if not fc or not fc.active then return end
    if now - _m1Last < fc.delay then return end
    _m1Last  = now; _m1Burst = _m1Burst + 1
    _cpsCount = _cpsCount + 1
    local el = now - _cpsLast
    if el >= 1 then _cps=math.floor(_cpsCount/el); _cpsCount=0; _cpsLast=now end
    if _m1Burst >= math.random(fc.burst-1, fc.burst+1) then
        _m1Burst=0; _m1BurstCD=now+fc.rest+math.random()*0.2
    end
    markDamage()
    psilentSnap(function()
        pcall(function()
            mousemoveabs(sx+math.random(-4,4), sy+math.random(-4,4))
            mouse1press()
            task.wait(0.018+math.random()*0.012)
            mouse1release()
        end)
    end)
end

-- ================================================================
-- [9] PRESS KEY — skill không bị block, có cooldown chống 267
-- ================================================================
local function pressKey(keyCode)
    markDamage()
    task.spawn(function()
        pcall(function()
            local origCF = nil
            if ENABLE_PSILENT and TGT and isValid(TGT) then
                local tc = TGT.Character
                local tr = tc and tc:FindFirstChild("HumanoidRootPart")
                if tr then
                    local pred = getPredPos(tr)
                    if isVisible(pred) then
                        origCF = Camera.CFrame
                        Camera.CFrame = CFrame.new(
                            Camera.CFrame.Position,
                            Camera.CFrame.Position + (pred-Camera.CFrame.Position).Unit
                        )
                    end
                end
            end
            VIM:SendKeyEvent(true,  keyCode, false, nil)
            task.wait(0.05)
            VIM:SendKeyEvent(false, keyCode, false, nil)
            if origCF then
                task.defer(function()
                    pcall(function() Camera.CFrame = origCF end)
                end)
            end
        end)
    end)
end

-- ================================================================
-- [10] TẮT POPUP — dùng chung cho mọi loại popup
-- ================================================================
local function closePopup()
    pcall(function()
        local pg = LP.PlayerGui
        for _, obj in ipairs(pg:GetDescendants()) do
            if obj:IsA("TextButton") and obj.Visible then
                local t = string.lower(string.gsub(obj.Text or "", "%s+", ""))
                if t == "ok" or t == "okay" or t == "đóng" or t == "dong"
                or t == "roikhoi" or t == "rờikhỏi" or t == "close" then
                    pcall(function() obj:Activate() end)
                end
            end
        end
    end)
end

-- ================================================================
-- [11] AUTO HOP — chống loop, chỉ hop 1 lần mỗi 30s
-- ================================================================
local _hopLock   = false
local _lastHop   = 0
local _hopCount  = 0
local _popupDismissed = {} -- track popup đã dismiss rồi

local function charReady()
    local c = LP.Character
    if not c or not c.Parent then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    return c:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getNewServer()
    local ok, sv = pcall(function()
        local HS  = game:GetService("HttpService")
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
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
    -- Chặn hop nếu vẫn trong game
    if charReady() then
        warn("⚠️ Vẫn trong game — bỏ qua hop ["..reason.."]")
        return
    end
    if _hopLock then
        warn("⚠️ hopLock đang bật — bỏ qua ["..reason.."]")
        return
    end
    local now = tick()
    if now - _lastHop < 30 then
        warn("⚠️ Hop cooldown còn "..(30-(now-_lastHop)).."s")
        return
    end
    -- Giới hạn cứng: tối đa 3 hop mỗi 5 phút
    if _hopCount >= 3 then
        warn("⚠️ Đã hop 3 lần — chờ 5 phút")
        task.spawn(function()
            task.wait(300); _hopCount = 0
            warn("✅ Reset hop counter")
        end)
        return
    end
    _hopLock  = true
    _lastHop  = now
    _hopCount = _hopCount + 1
    warn("🔄 Hop ["..reason.."] lần ".._hopCount.." — sau "..delay.."s")
    task.spawn(function()
        task.wait(delay)
        -- Kiểm tra lại lần cuối trước khi hop
        if charReady() then
            warn("✅ Đã vào game lại — huỷ hop")
            _hopLock = false
            return
        end
        local sv = getNewServer()
        local ok = false
        if sv then
            ok = pcall(function()
                TpSvc:TeleportToPlaceInstance(game.PlaceId, sv, LP)
            end)
        end
        if not ok then
            task.wait(2)
            pcall(function() TpSvc:Teleport(game.PlaceId, LP) end)
        end
        -- Unlock sau 30s dù thành công hay không
        task.wait(30)
        _hopLock = false
    end)
end

-- TeleportInitFailed: CHỈ dismiss popup, KHÔNG hop
TpSvc.TeleportInitFailed:Connect(function(plr, errMsg, errCode)
    if plr ~= LP then return end
    warn("TeleportInitFailed code="..tostring(errCode).." — chỉ dismiss popup")
    task.spawn(function()
        task.wait(0.3)
        closePopup()
    end)
end)

LP.CharacterRemoving:Connect(function()
    task.spawn(function()
        task.wait(15) -- chờ respawn
        if not charReady() then
            hopServer(2, "NoSpawn")
        end
    end)
end)

-- ================================================================
-- [12] HEARTBEAT — chỉ dismiss popup 773, KHÔNG hop khi còn game
-- ================================================================
local _lastErrCheck   = 0
local _lastTgtCheck   = 0
local _lastPopupCheck = 0
local _lastErrMsg     = ""

local PATTERNS_773 = {
    "773", "disconnect", "reconnect", "lost connection",
    "mất kết nối", "mat ket noi", "rời khỏi", "roi khoi",
    "server closed", "dịch chuyển thất bại", "dich chuyen that bai",
    "địa điểm bị hạn chế", "dia diem bi han che",
    "bị hạn chế", "bi han che", "mã lỗi: 773", "ma loi: 773",
    "restricted", "place restricted",
}
local PATTERNS_267 = {
    "267", "kicked", "security", "violation",
    "bị đuổi", "bi duoi", "vi phạm", "vi pham",
}
local PATTERNS_268 = { "268", "teleported", "moved to" }

local function matchP(m, pats)
    local ml = string.lower(m)
    for _, p in ipairs(pats) do
        if string.find(ml, p, 1, true) then return true end
    end
    return false
end

RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Poll GuiService error
    if now - _lastErrCheck >= 0.5 then
        _lastErrCheck = now
        pcall(function()
            local m = GuiSvc:GetErrorMessage() or ""
            if m ~= "" and m ~= _lastErrMsg then
                _lastErrMsg = m
                warn("🚨 ErrorMsg: "..m)
                if matchP(m, PATTERNS_773) then
                    -- Luôn dismiss popup trước
                    closePopup()
                    -- Chỉ hop nếu thật sự bị kick
                    if not charReady() then
                        task.wait(1)
                        if not charReady() then
                            hopServer(2, "773-err")
                        end
                    end
                elseif matchP(m, PATTERNS_267) then
                    hopServer(10, "267-err")
                elseif matchP(m, PATTERNS_268) then
                    hopServer(5, "268-err")
                end
            end
        end)
    end

    -- Scan popup PlayerGui
if now - _lastPopupCheck >= 0.8 then
    _lastPopupCheck = now
    pcall(function()
        local pg = LP.PlayerGui
        for _, gui in ipairs(pg:GetDescendants()) do
            if (gui:IsA("TextLabel") or gui:IsA("TextBox")) and gui.Visible then
                local t = gui.Text or ""
                if t ~= "" and matchP(t, PATTERNS_773) then
                    -- Kiểm tra button để phân biệt 2 dạng
                    local hasRoiKhoi = false
                    local hasOk      = false
                    local root = gui.Parent
                    while root and not root:IsA("ScreenGui") do
                        root = root.Parent
                    end
                    if root then
                        for _, btn in ipairs(root:GetDescendants()) do
                            if btn:IsA("TextButton") and btn.Visible then
                                local bt = string.lower(btn.Text or "")
                                -- "Rời Khỏi" / "roi khoi" / "leave" → bị kick thật
                                if string.find(bt,"r%u%u%u kh%u%u%u")
                                or string.find(bt,"roi khoi")
                                or string.find(bt,"rời khỏi")
                                or string.find(bt,"leave")
                                or bt == "rời khỏi" then
                                    hasRoiKhoi = true
                                end
                                -- "Ok" / "okay" → vẫn trong game
                                if bt == "ok" or bt == "okay" then
                                    hasOk = true
                                end
                            end
                        end
                    end

                    if hasRoiKhoi then
                        -- Dạng 2: Mất kết nối thật → hop
                        warn("🔴 773 dạng MẤT KẾT NỐI — bắt đầu hop")
                        _hopLock = false
                        hopServer(2, "773-disconnect")
                    elseif hasOk then
                        -- Dạng 1: Dịch chuyển thất bại → chỉ dismiss
                        closePopup()
                        warn("🟡 773 dạng DỊCH CHUYỂN — chỉ dismiss")
                    end
                end
            end
        end
    end)
end

    checkTriggerbot()

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
    G.Name="BountyGUI"; G.ResetOnSpawn=false
    G.DisplayOrder=999
    G.Parent=LP:WaitForChild("PlayerGui")

    local F = Instance.new("Frame", G)
    F.Size=UDim2.new(0,215,0,175)
    F.Position=UDim2.new(0,10,0.4,0)
    F.BackgroundColor3=Color3.fromRGB(8,8,8)
    F.BackgroundTransparency=0.1
    F.BorderSizePixel=0; F.Active=true; F.Visible=false
    Instance.new("UICorner",F).CornerRadius=UDim.new(0,14)
    local St=Instance.new("UIStroke",F); St.Thickness=1.5

    local TB=Instance.new("Frame",F)
    TB.Size=UDim2.new(1,0,0,28); TB.Position=UDim2.new(0,0,0,0)
    TB.BackgroundColor3=Color3.fromRGB(20,20,20)
    TB.BackgroundTransparency=0.3
    TB.BorderSizePixel=0; TB.Active=true
    Instance.new("UICorner",TB).CornerRadius=UDim.new(0,14)

    local TL=Instance.new("TextLabel",TB)
    TL.Size=UDim2.new(1,-10,1,0); TL.Position=UDim2.new(0,10,0,0)
    TL.BackgroundTransparency=1; TL.Text="⚡ BOUNTY VIP"
    TL.TextSize=13; TL.Font=Enum.Font.GothamBold
    TL.TextColor3=Color3.fromRGB(255,215,0)
    TL.TextXAlignment=Enum.TextXAlignment.Left

    local Div=Instance.new("Frame",F)
    Div.Size=UDim2.new(1,-16,0,1); Div.Position=UDim2.new(0,8,0,29)
    Div.BackgroundColor3=Color3.fromRGB(60,60,60); Div.BorderSizePixel=0

    local function lb(pos,txt,color)
        local l=Instance.new("TextLabel",F)
        l.Size=UDim2.new(1,-16,0,19); l.Position=pos
        l.BackgroundTransparency=1; l.Text=txt; l.TextSize=12
        l.Font=Enum.Font.Gotham
        l.TextColor3=color or Color3.fromRGB(220,220,220)
        l.TextXAlignment=Enum.TextXAlignment.Left
        return l
    end

    local L1=lb(UDim2.new(0,8,0,33), "📶 FPS:--  Ping:--ms",  Color3.fromRGB(120,255,120))
    local L2=lb(UDim2.new(0,8,0,54), "🖱️ CPS:0",              Color3.fromRGB(130,200,255))
    local L3=lb(UDim2.new(0,8,0,75), "👥 Players:0",           Color3.fromRGB(255,200,120))
    local L4=lb(UDim2.new(0,8,0,96), "💀 Chết:0",              Color3.fromRGB(255,100,100))
    local L5=lb(UDim2.new(0,8,0,117),"☠️ Kill:0",              Color3.fromRGB(100,255,150))
    local L6=lb(UDim2.new(0,8,0,138),"🎯 None",                Color3.fromRGB(255,255,150))
    local L7=lb(UDim2.new(0,8,0,158),"⏱ 00:00:00",             Color3.fromRGB(180,180,180))

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
            local ping=math.floor(LP:GetNetworkPing()*1000)
            local e=os.clock()-t0
            local tName=(TGT and isValid(TGT)) and TGT.Name or "None"
            if ping<80 then L1.TextColor3=Color3.fromRGB(120,255,120)
            elseif ping<150 then L1.TextColor3=Color3.fromRGB(255,220,80)
            else L1.TextColor3=Color3.fromRGB(255,80,80) end
            L1.Text=("📶 FPS:%d  Ping:%dms"):format(fps,ping)
            L2.Text=("🖱️ CPS:%d"):format(_cps)
            L3.Text=("👥 Players:%d"):format(#Players:GetPlayers())
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
-- [14] NPC / QUEST BYPASS — detect "Bỏ qua" đúng
-- ================================================================
task.spawn(function()
    while task.wait(0.2) do
        pcall(function()
            local pg=LP.PlayerGui
            for _, gui in ipairs(pg:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    local name=string.lower(gui.Name)
                    if string.find(name,"dialogue") or string.find(name,"quest")
                    or string.find(name,"npc") or string.find(name,"shop")
                    or string.find(name,"interact") or string.find(name,"talk")
                    or string.find(name,"mission") then
                        local closed=false
                        for _, obj in ipairs(gui:GetDescendants()) do
                            if obj:IsA("TextButton") and obj.Visible then
                                local t=obj.Text or ""
                                local tl=string.lower(t)
                                -- Detect chính xác "Bỏ qua"
                                if t=="Bỏ qua" or t=="bỏ qua" or t=="Bo qua"
                                or string.find(tl,"bo qua") or string.find(tl,"bỏ qua")
                                or string.find(tl,"skip") or string.find(tl,"close")
                                or string.find(tl,"cancel") or tl=="x"
                                or string.find(tl,"thoat") or string.find(tl,"thoát")
                                or string.find(tl,"next") or string.find(tl,"tiep")
                                or string.find(tl,"tiếp") then
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
-- [15] SPAM SKILL — cooldown chống 267
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
                local now=tick()
                if now-_lastSkillCD < 0.12 then return end
                if SKILL_Z then pressKey(Enum.KeyCode.Z); _lastSkillCD=tick(); task.wait(0.12+math.random()*0.05) end
                if SKILL_X then pressKey(Enum.KeyCode.X); _lastSkillCD=tick(); task.wait(0.12+math.random()*0.05) end
                if SKILL_C then pressKey(Enum.KeyCode.C); _lastSkillCD=tick(); task.wait(0.12+math.random()*0.05) end
                if SKILL_F then pressKey(Enum.KeyCode.F); _lastSkillCD=tick(); task.wait(0.12+math.random()*0.05) end
                if SKILL_V then pressKey(Enum.KeyCode.V); _lastSkillCD=tick(); task.wait(0.12+math.random()*0.05) end
            end)
        end
    end)
end

-- ================================================================
-- [16] SPAM M1
-- ================================================================
if ENABLE_M1 then
    task.spawn(function()
        while task.wait(0.04) do
            if not TGT or not isValid(TGT) then continue end
            pcall(function()
                local mc=LP.Character; if not mc then return end
                local mh=mc:FindFirstChildOfClass("Humanoid")
                if not mh or mh.Health<=0 then return end
                local fc=getFruitCFG(mc)
                if not fc or not fc.active then return end
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
