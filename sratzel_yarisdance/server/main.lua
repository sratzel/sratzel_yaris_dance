-- active sources live in GlobalState.yarisDance, clients only read it
-- vehicle = yaris plays it (/dealer), boombox = other script via AddSource

local T = Config.Texts
local MODEL = joaat(Config.Model)
local DURATION_MS = math.floor(BeatMap.duration * 1000)

---@type table<string, table>
local sources = {}
local vehicleEntities = {}   -- id -> entity, for despawn check
local lastToggle = {}        -- src -> GetGameTimer()

local function publish()
    GlobalState.yarisDance = sources
end

local function debug(msg, ...)
    if Config.Debug then print(('^5[sratzel_yarisdance]^7 ' .. msg):format(...)) end
end

local function notify(src, text, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = T.title, description = text, type = kind or 'inform' })
end

local function removeSource(id)
    if not sources[id] then return end
    sources[id] = nil
    vehicleEntities[id] = nil
    publish()
    debug('Quelle %s entfernt', id)
end

-- time sync
RegisterNetEvent('sratzel_yarisdance:ping', function(clientTime)
    TriggerClientEvent('sratzel_yarisdance:pong', source, clientTime, GetGameTimer())
end)

RegisterNetEvent('sratzel_yarisdance:toggle', function(netId)
    local src = source
    if not Config.VehicleSource.enabled or type(netId) ~= 'number' then return end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if GetEntityModel(veh) ~= MODEL then return notify(src, T.notYaris, 'error') end
    if GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return notify(src, T.notDriver, 'error') end

    local now = GetGameTimer()
    if lastToggle[src] and now - lastToggle[src] < Config.VehicleSource.cooldown then
        return notify(src, T.cooldown, 'error')
    end
    lastToggle[src] = now

    local id = ('veh:%d'):format(netId)
    if sources[id] then
        removeSource(id)
        return notify(src, T.stopped)
    end

    sources[id] = {
        type = 'vehicle',
        netId = netId,
        range = Config.VehicleSource.range,
        soundName = ('yarisdance_veh_%d'):format(netId),
        startedAt = now,
    }
    vehicleEntities[id] = veh
    publish()
    notify(src, T.started, 'success')
    debug('%s startet den Song in Fahrzeug %d', GetPlayerName(src), netId)
end)

AddEventHandler('playerDropped', function()
    lastToggle[source] = nil
end)

-- cleanup ended songs / gone vehicles
CreateThread(function()
    while true do
        Wait(2000)
        local now = GetGameTimer()
        for id, data in pairs(sources) do
            if data.type == 'vehicle' then
                if now - data.startedAt > DURATION_MS or not DoesEntityExist(vehicleEntities[id]) then
                    removeSource(id)
                end
            elseif not data.loop and now - data.startedAt > DURATION_MS then
                removeSource(id)
            end
        end
    end
end)

-- exports for boombox scripts
---@param id string e.g. 'boombox:12'
---@param data { coords: vector3, range: number, soundName: string, startedAt: number?, loop: boolean? }
exports('AddSource', function(id, data)
    if type(id) ~= 'string' or type(data) ~= 'table' then return false end
    if type(data.coords) ~= 'vector3' or type(data.soundName) ~= 'string' then return false end

    sources[id] = {
        type = 'boombox',
        coords = data.coords,
        range = tonumber(data.range) or 25.0,
        soundName = data.soundName,
        startedAt = tonumber(data.startedAt) or GetGameTimer(),
        loop = data.loop == true,
    }
    publish()
    return true
end)

exports('RemoveSource', function(id)
    removeSource(id)
end)

exports('IsDanceTrack', function(urlOrFile)
    if type(urlOrFile) ~= 'string' then return false end
    local s = urlOrFile:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end):lower()
    for _, match in ipairs(Config.TrackMatch) do
        if s:find(match:lower(), 1, true) then return true end
    end
    return false
end)

publish()

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    GlobalState.yarisDance = {}
end)
