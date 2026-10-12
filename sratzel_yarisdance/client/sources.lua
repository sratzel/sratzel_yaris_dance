YarisDance = {}

local xsound = exports.xsound
local T = Config.Texts
local VS = Config.VehicleSource
local DURATION = BeatMap.duration

---@type table<string, { data: table, coords: vector3?, entity: number?, dist: number, heard: boolean, playing: boolean?, started: boolean?, ended: boolean? }>
local sources = {}
YarisDance.sources = sources

-- offset = server time - GetGameTimer()
local offset = nil
local samples = nil

RegisterNetEvent('sratzel_yarisdance:pong', function(clientTime, serverTime)
    if not samples then return end
    local rtt = GetGameTimer() - clientTime
    samples[#samples + 1] = { rtt = rtt, offset = serverTime + rtt / 2 - GetGameTimer() }
end)

-- take the ping with lowest rtt
local function measureOffset()
    samples = {}
    for _ = 1, 5 do
        TriggerServerEvent('sratzel_yarisdance:ping', GetGameTimer())
        Wait(200)
    end
    Wait(1000)

    local best
    for _, s in ipairs(samples) do
        if not best or s.rtt < best.rtt then best = s end
    end
    samples = nil
    if not best then return end

    if not offset or math.abs(best.offset - offset) > Config.ResyncThresholdMs then
        offset = best.offset
        if Config.Debug then print(('[sratzel_yarisdance] Server-Offset %d ms (RTT %d ms)'):format(offset, best.rtt)) end
    end
end

CreateThread(function()
    while true do
        measureOffset()
        Wait(offset and 60000 or 2000)
    end
end)

local function songTime(data, now)
    if not offset then return nil end
    local t = ((now or GetGameTimer()) + offset - data.startedAt) / 1000.0
    if data.loop then t = t % DURATION end
    return t
end

function YarisDance.danceTime(data, now)
    local t = songTime(data, now)
    return t and t + Config.AudioLatencyMs / 1000.0
end

local function stopSound(src)
    if src.playing and xsound:soundExists(src.data.soundName) then
        xsound:Destroy(src.data.soundName)
    end
    src.playing, src.started = false, false
end

local function startSound(src)
    local data = src.data
    local name = data.soundName
    xsound:PlayUrlPos(name, Config.AudioUrl, VS.volume, src.coords, false, {
        onPlayStart = function()
            -- jump to current song time (late join / load time)
            local t = songTime(data)
            if t and xsound:soundExists(name) then xsound:setTimeStamp(name, t) end
            src.started = true
        end,
    })
    src.playing = true
    if xsound:soundExists(name) then
        xsound:Distance(name, data.range)
    else
        src.ended = true   -- streamer mode etc, dont retry
    end
end

local function updateVehicleAudio(src)
    if src.ended then return end
    local name = src.data.soundName

    if src.playing then
        if not xsound:soundExists(name) then
            src.playing, src.ended = false, true   -- song over
        elseif not src.coords or src.dist > src.data.range + 10.0 then
            stopSound(src)
        else
            xsound:Position(name, src.coords)
        end
    elseif src.coords and src.dist <= src.data.range then
        local t = songTime(src.data)
        if t and t < DURATION - 1.0 then startSound(src) end
    end
end

local function resolve()
    local state = GlobalState.yarisDance or {}
    local pos = GetEntityCoords(PlayerPedId())

    for id, src in pairs(sources) do
        local data = state[id]
        if not data or data.startedAt ~= src.data.startedAt or data.soundName ~= src.data.soundName then
            stopSound(src)
            sources[id] = nil
        end
    end

    for id, data in pairs(state) do
        local src = sources[id] or {}
        src.data = data
        src.entity, src.coords = nil, nil

        if data.type == 'vehicle' then
            if NetworkDoesEntityExistWithNetworkId(data.netId) then
                local veh = NetToVeh(data.netId)
                if veh ~= 0 and DoesEntityExist(veh) then
                    src.entity, src.coords = veh, GetEntityCoords(veh)
                end
            end
        else
            src.coords = data.coords
        end

        src.dist = src.coords and #(pos - src.coords) or math.huge
        src.heard = src.dist <= data.range
        sources[id] = src

        if data.type == 'vehicle' then updateVehicleAudio(src) end
    end
end

CreateThread(function()
    while true do
        resolve()
        Wait(100)
    end
end)

-- resync audio if way off. getTimeStamp only counts full seconds, hence -1/+2
CreateThread(function()
    while true do
        Wait(1000)
        for _, src in pairs(sources) do
            local name = src.data.soundName
            local mine = src.data.type == 'vehicle'
            if src.heard and (not mine or src.started) and xsound:soundExists(name)
                and xsound:isPlaying(name) and xsound:getMaxDuration(name) > 0 then
                local t = songTime(src.data)
                local diff = t and t - xsound:getTimeStamp(name)
                if diff and (diff < -1.0 or diff > 2.0) and t < DURATION - 1.0 then
                    xsound:setTimeStamp(name, t)
                    if Config.Debug then print(('[sratzel_yarisdance] %s um %.2f s korrigiert'):format(name, diff)) end
                end
            end
        end
    end
end)

local function notify(text, kind)
    lib.notify({ title = T.title, description = text, type = kind or 'inform' })
end

if VS.enabled then
    RegisterCommand(VS.command, function()
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 or GetEntityModel(veh) ~= joaat(Config.Model) then return notify(T.notYaris, 'error') end
        if GetPedInVehicleSeat(veh, -1) ~= ped then return notify(T.notDriver, 'error') end
        TriggerServerEvent('sratzel_yarisdance:toggle', VehToNet(veh))
    end, false)
    RegisterKeyMapping(VS.command, T.keyLabel, 'keyboard', VS.toggleKey)
end

AddTextEntry(GetDisplayNameFromVehicleModel(joaat(Config.Model)), Config.DisplayName)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, src in pairs(sources) do
        if src.data.type == 'vehicle' then stopSound(src) end
    end
end)
