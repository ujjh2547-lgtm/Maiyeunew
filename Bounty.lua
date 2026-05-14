-- ================================================================
--  Bounty.lua — MAIN SCRIPT (upload lên GitHub raw)
--  Không chứa config của Bountynew.lua
--  Đọc config từ getgenv() do script config (Dạng 2) set sẵn
-- ================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TpSvc      = game:GetService("TeleportService")
local GuiSvc     = game:GetService("GuiService")
local LP         = Players.LocalPlayer

-- ================================================================
-- [1] ĐỌC CONFIG TỪ GETGENV (do script config set)
-- ================================================================
local CFG = getgenv().BountyExtra or {}

local ENABLE_AIMBOT    = CFG["Aimbot"]      ~= false
local ENABLE_M1        = CFG["M1 click"]    ~= false
local ENABLE_FASTATTK  = CFG["Fast Attack"] ~= false
local ENABLE_AUTOSKILL = (CFG["Auto Skill"] or {})["Enabled"] ~= false
local ENABLE_AUTOHOP   = CFG["Auto server hop"] ~= false
local ENABLE_GUI       = CFG["Gui"]         ~= false

local SKILL_Z = (CFG["Auto Skill"] or {})["Z"] ~= false
local SKILL_X = (CFG["Auto Skill"] or {})["X"] ~= false
local SKILL_C = (CFG["Auto Skill"] or {})["C"] ~= false
local SKILL_V = (CFG["Auto Skill"] or {})["V"] == true   -- default false
local SKILL_F = (CFG["Auto Skill"] or {})["F"] ~= false

local M1_WHITELIST = CFG["M1"] or {
    ["kitsune"]=true, ["t-rex"]=true,  ["dragon"]=true,
    ["blade"]=true,   ["dough"]=true,  ["gas"]=true,
    ["pain"]=true,    ["leopard"]=true,
}

-- ================================================================
-- [2] M1 WHITELIST CHECK
-- ================================================================
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

-- ================================================================
-- [3] M1 TOKEN BUCKET
-- ================================================================
local _tokens   = 3.0
local _lastFill = tick()
local MAX_TOK   = 3.0
local FILL_RATE = 2.5
local _m1Last   = 0
local M1_MIN_CD = 0.25

local function getToken()
    local now = tick()
    local dt  = now - _lastFill
    _lastFill = now
    _tokens   = math.min(MAX_TOK, _tokens + dt * FILL_RATE)
    if _tokens < 1 then return false end
    _tokens = _tokens - 1
    return true
end

local function doM1(sx, sy)
    if not ENABLE_M1 then return end
    local now = tick()
    if now - _m1Last < M1_MIN_CD + math.random()*0.05 then return end
    if not getToken() then return end
    _m1Last = now
    local ox   = math.random(-4, 4)
    local oy   = math.random(-4, 4)
    local hold = 0.018 + math.random() * 0.016
    task.spawn(function()
        pcall(function()
            mousemoveabs(sx + ox, sy + oy)
            mouse1press()
            task.wait(hold)
            mouse1release()
        end)
    end)
end

-- ================================================================
-- [4] AUTO HOP (773 / 267)
-- ================================================================
local _hopLock = false
local _lastHop = 0
local HOP_MIN  = 20

local function charReady()
    local c = LP.Character
    if not c or not c.Parent then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    if not c:FindFirstChild("HumanoidRootPart") then return false end
    return true
end

local function getNewServer()
    local ok, result = pcall(function()
        local HS  = game:GetService("HttpService")
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
        local raw = game:HttpGet(url)
        local data = HS:JSONDecode(raw)
        if not data or not data.data then return nil end
        local best, bestScore = nil, math.huge
        for _, sv in ipairs(data.data) do
            if sv.id ~= game.JobId
            and sv.playing >= 2
            and sv.playing <= 10
            and sv.maxPlayers >= sv.playing then
                local score = (sv.ping or 999) + (sv.playing * 10)
                if score < bestScore then bestScore=score; best=sv.id end
            end
        end
        return best
    end)
    return ok and result or nil
end

local function hopServer(delaySec)
    if not ENABLE_AUTOHOP then return end
    if _hopLock then return end
    if tick() - _lastHop < HOP_MIN then return end
    _hopLock = true
    task.spawn(function()
        task.wait(delaySec or 8)
        local w = 0
        while not charReady() and w < 15 do task.wait(0.5); w=w+0.5 end
        task.wait(1.5)
        _lastHop = tick()
        local newSv = getNewServer()
        if newSv then
            local ok = pcall(function() TpSvc:TeleportToPlaceInstance(game.PlaceId, newSv, LP) end)
            if not ok then task.wait(3); pcall(function() TpSvc:Teleport(game.PlaceId, LP) end) end
        else
            pcall(function() TpSvc:Teleport(game.PlaceId, LP) end)
        end
        task.wait(20); _hopLock = false
    end)
end

TpSvc.TeleportInitFailed:Connect(function(plr)
    if plr ~= LP then return end
    hopServer(8 + math.random()*4)
end)

GuiSvc.ErrorMessageChanged:Connect(function()
    local m = GuiSvc:GetErrorMessage() or ""
    if string.find(m,"267") or string.find(m,"Security") then
        hopServer(15 + math.random()*10)
    elseif string.find(m,"773") or string.find(m,"reconnect") or string.find(m,"disconnect") then
        hopServer(8 + math.random()*4)
    end
end)

LP.CharacterRemoving:Connect(function()
    task.spawn(function()
        task.wait(12)
        if not charReady() then hopServer(3 + math.random()*3) end
    end)
end)

-- ================================================================
-- [5] GUI FPS/PING (bật/tắt qua config)
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
        l.Size=sz; l.Position=pos
        l.BackgroundTransparency=1
        l.Text=txt; l.TextSize=fs
        l.TextXAlignment=Enum.TextXAlignment.Center
        l.Font=bold and Enum.Font.GothamBold or Enum.Font.GothamSemibold
        return l
    end

    local TL = lb(UDim2.new(1,0,0,24),UDim2.new(0,0,0,0),"FPS • PING",15,true)
    local IL = lb(UDim2.new(1,0,0,22),UDim2.new(0,0,0,26),"FPS:60|Ping:0ms",13,false)
    local UL = lb(UDim2.new(1,0,0,18),UDim2.new(0,0,0,48),"Uptime:00:00:00",12,false)
    TL.TextColor3 = Color3.fromRGB(255,215,0)
    IL.TextColor3 = Color3.fromRGB(255,255,255)
    UL.TextColor3 = Color3.fromRGB(200,200,200)

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
            UL.Text=("Uptime:%02d:%02d:%02d"):format(math.floor(e/3600),math.floor(e%3600/60),math.floor(e%60))
        end
    end)
    task.delay(0.6,function() F.Visible=true end)
end

-- ================================================================
-- [6] SAFEZONE / DIALOGUE BYPASS
-- ================================================================
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local pg = LP.PlayerGui
            local d = pg:FindFirstChild("DialogueGui")
            if d then d.Enabled=false end
            local q = pg:FindFirstChild("QuestGui")
            if q then q.Enabled=false end
            local c = LP.Character
            if c then
                c:SetAttribute("InSafeZone",false)
                local ff = c:FindFirstChildOfClass("ForceField")
                if ff then ff:Destroy() end
            end
        end)
    end
end)

-- ================================================================
-- [7] TARGET SYSTEM
-- ================================================================
local TGT    = nil
local TGT_AT = 0

local function isValid(p)
    if not p or not p:IsA("Player") then return false end
    if p == LP then return false end
    if not Players:FindFirstChild(p.Name) then return false end
    local c = p.Character; if not c then return false end
    if not c:FindFirstChild("HumanoidRootPart") then return false end
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
            if d < bd then bd=d; best=p end
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

-- ================================================================
-- [8] AIMBOT
-- ================================================================
if ENABLE_AIMBOT then
    local _lastAim = 0
    RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - _lastAim < 0.125 then return end
        _lastAim = now
        pcall(function()
            local mc = LP.Character; if not mc then return end
            local mh = mc:FindFirstChildOfClass("Humanoid")
            if not mh or mh.Health <= 0 then return end
            local dist = tgtDist()
            if not TGT or not isValid(TGT) or (now - TGT_AT > 6) or (dist > 80) then
                TGT = pickTarget(); TGT_AT = now
            end
            if not TGT then return end
            local tc = TGT.Character; if not tc then return end
            local tr = tc:FindFirstChild("HumanoidRootPart"); if not tr then return end
            local cam = workspace.CurrentCamera; if not cam then return end
            local vel      = tr.AssemblyLinearVelocity
            local speed    = vel.Magnitude
            local predMult = 0.88 + math.clamp(speed/200, 0, 0.4)
            local tDist    = (tr.Position - cam.CFrame.Position).Magnitude
            local pred     = tr.Position + vel*(tDist/260)*predMult + Vector3.new(0,2.2,0)
            local dir = (pred - cam.CFrame.Position).Unit
            cam.CFrame = CFrame.new(cam.CFrame.Position, cam.CFrame.Position + dir)
        end)
    end)
end

-- ================================================================
-- [9] M1 LOOP
-- ================================================================
if ENABLE_M1 then
    task.spawn(function()
        while task.wait(0.05) do
            if not TGT or not isValid(TGT) then continue end
            pcall(function()
                local mc = LP.Character; if not mc then return end
                local mh = mc:FindFirstChildOfClass("Humanoid")
                if not mh or mh.Health <= 0 then return end
                if not canM1(mc) then return end
                if tgtDist() > 25 then return end
                local tc = TGT.Character; if not tc then return end
                local tr = tc:FindFirstChild("HumanoidRootPart"); if not tr then return end
                local cam = workspace.CurrentCamera; if not cam then return end
                local sp, onScreen = cam:WorldToViewportPoint(tr.Position)
                if not onScreen or sp.Z <= 0 then return end
                local vp = cam.ViewportSize
                local cx = math.clamp(sp.X + math.random(-3,3), 1, vp.X-1)
                local cy = math.clamp(sp.Y + math.random(-3,3), 1, vp.Y-1)
                doM1(cx, cy)
            end)
        end
    end)
end

print("✅ Bounty.lua loaded")
