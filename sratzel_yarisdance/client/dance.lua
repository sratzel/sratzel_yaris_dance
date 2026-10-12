-- each dancing yaris gets a local proxy, the real one just goes invisible.
-- every frame: copy matrix, scale it, write to proxy

local MODEL = joaat(Config.Model)
local PERIOD = 60.0 / BeatMap.bpm
local FADE_BEATS = (Config.FadeMs / 1000.0) / PERIOD
local CURVE = Config.Curve
local CYCLE = Config.BeatsPerCycle
local WIDTH_EXP = -Config.WidthShare
local LENGTH_EXP = -(1.0 - Config.WidthShare)

---@type table<number, { veh: number, proxy: number, src: table, amp: number, leaving: boolean, jitter: number, lastCopy: number, moving: boolean, wheels: number }>
local dancers = {}
local proxies = {}       -- so scan skips our own proxies
local modelHeld = false
local minZ = 0.0

local function isRest(beat)
    if beat > BeatMap.lastBeat then return true end
    for _, r in ipairs(BeatMap.rests) do
        if beat >= r[1] and beat <= r[2] then return true end
    end
    return false
end

-- smoothstep between keyframes
local function curve(phase)
    for i = 2, #CURVE do
        local b = CURVE[i]
        if phase <= b[1] then
            local a = CURVE[i - 1]
            local u = (phase - a[1]) / (b[1] - a[1])
            u = u * u * (3.0 - 2.0 * u)
            return a[2] + (b[2] - a[2]) * u
        end
    end
    return CURVE[#CURVE][2]
end

-- returns scale, active. looks ahead FadeMs so fades finish before the beat
local function shape(t, jitter)
    local x = (t - BeatMap.firstBeat) / PERIOD + Config.PhaseOffset + jitter
    if x < 0 then
        -- intro idle, ends at s = 1
        if Config.IntroIdle then return 1.0 + 0.03 * math.sin(x * math.pi), true end
        return 1.0, true
    end

    local xc = x / CYCLE
    local cycle = math.floor(xc)
    local s = curve(xc - cycle)
    if (cycle * CYCLE) % BeatMap.beatsPerBar == 0 then
        s = 1.0 + (s - 1.0) * Config.BarAccent
    end
    return s, not isRest(math.floor(x + FADE_BEATS))
end

local function copyLook(veh, proxy)
    local p, s = GetVehicleColours(veh)
    SetVehicleColours(proxy, p, s)
    local pearl, wheel = GetVehicleExtraColours(veh)
    SetVehicleExtraColours(proxy, pearl, wheel)
    if GetIsVehiclePrimaryColourCustom(veh) then
        SetVehicleCustomPrimaryColour(proxy, GetVehicleCustomPrimaryColour(veh))
    end
    if GetIsVehicleSecondaryColourCustom(veh) then
        SetVehicleCustomSecondaryColour(proxy, GetVehicleCustomSecondaryColour(veh))
    end

    SetVehicleModKit(proxy, 0)
    SetVehicleWheelType(proxy, GetVehicleWheelType(veh))
    for i = 0, 48 do
        local mod = GetVehicleMod(veh, i)
        if GetVehicleMod(proxy, i) ~= mod then
            SetVehicleMod(proxy, i, mod, GetVehicleModVariation(veh, i))
        end
    end
    for i = 17, 22 do
        ToggleVehicleMod(proxy, i, IsToggleModOn(veh, i))
    end

    SetVehicleLivery(proxy, GetVehicleLivery(veh))
    for i = 0, 20 do
        if DoesExtraExist(veh, i) then
            SetVehicleExtra(proxy, i, not IsVehicleExtraTurnedOn(veh, i))
        end
    end

    SetVehicleNumberPlateText(proxy, GetVehicleNumberPlateText(veh))
    SetVehicleNumberPlateTextIndex(proxy, GetVehicleNumberPlateTextIndex(veh))
    SetVehicleWindowTint(proxy, GetVehicleWindowTint(veh))
    SetVehicleDirtLevel(proxy, GetVehicleDirtLevel(veh))

    local _, lightsOn, highBeams = GetVehicleLightsState(veh)
    local on = lightsOn == 1 or lightsOn == true or highBeams == 1 or highBeams == true
    SetVehicleLights(proxy, on and 2 or 1)
end

local function createProxy(veh)
    local pos = GetEntityCoords(veh)
    local proxy = CreateVehicle(MODEL, pos.x, pos.y, pos.z, GetEntityHeading(veh), false, false)
    if proxy == 0 then return nil end

    -- frozen or physics overwrites the matrix
    SetEntityAsMissionEntity(proxy, true, true)
    SetEntityCollision(proxy, false, false)
    FreezeEntityPosition(proxy, true)
    SetEntityInvincible(proxy, true)
    SetVehicleEngineOn(proxy, false, true, true)
    SetVehicleRadioEnabled(proxy, false)
    SetVehicleDoorsLocked(proxy, 2)
    copyLook(veh, proxy)
    proxies[proxy] = true
    return proxy
end

-- occupants: seated peds can't be scaled, so same trick as the car (local clone, real ped hidden)

local function dot(u, v)
    return u.x * v.x + u.y * v.y + u.z * v.z
end

local function toLocal(v, a0, b0, u0)
    return vector3(dot(v, a0), dot(v, b0), dot(v, u0))
end

local function fromLocal(l, a, b, u)
    return a * l.x + b * l.y + u * l.z
end

local function setMatrix(entity, a, b, u, p)
    SetEntityCoordsNoOffset(entity, p.x, p.y, p.z, false, false, false)   -- or it gets culled
    SetEntityMatrix(entity, a.x, a.y, a.z, b.x, b.y, b.z, u.x, u.y, u.z, p.x, p.y, p.z)
end

local PEDS = Config.ScaleOccupants or not Config.ShowOccupants
local CLONES = Config.ShowOccupants and Config.ScaleOccupants
local SEAT = Config.OccupantMode == 'seat'

-- handles get reused, dont touch someone elses entity
local function isClone(o)
    return o.clone ~= nil and DoesEntityExist(o.clone) and GetEntityModel(o.clone) == o.model
        and not NetworkGetEntityIsNetworked(o.clone)
end

local function deleteClone(o)
    if isClone(o) then
        SetEntityAsMissionEntity(o.clone, true, true)
        DeletePed(o.clone)
    end
    o.clone = nil
end

local function createClone(ped, seat, proxy)
    local anim = Config.OccupantAnims[seat] or Config.OccupantAnims[0]
    if not SEAT and not HasAnimDictLoaded(anim[1]) then
        RequestAnimDict(anim[1])   -- next scan
        return nil
    end
    local clone = ClonePed(ped, false, false, true)
    if clone == 0 then return nil end

    SetEntityAsMissionEntity(clone, true, true)
    SetEntityInvincible(clone, true)
    SetBlockingOfNonTemporaryEvents(clone, true)
    SetPedCanRagdoll(clone, false)
    if SEAT then
        SetPedIntoVehicle(clone, proxy, seat)
    else
        SetEntityCollision(clone, false, false)
        FreezeEntityPosition(clone, true)
        TaskPlayAnim(clone, anim[1], anim[2], 8.0, 8.0, -1, 1, 0.0, false, false, false)
    end
    return clone
end

local function syncOccupants(d)
    local seen = {}
    for seat = -1, GetVehicleMaxNumberOfPassengers(d.veh) - 1 do
        local ped = GetPedInVehicleSeat(d.veh, seat)
        if ped ~= 0 then
            seen[ped] = true
            local o = d.occ[ped]
            if not o or o.seat ~= seat then
                if o then deleteClone(o) end
                o = { seat = seat, model = GetEntityModel(ped) }
                d.occ[ped] = o
            end
            if CLONES and not isClone(o) then o.clone = createClone(ped, seat, d.proxy) end
            if CLONES and SEAT and isClone(o) and GetPedInVehicleSeat(d.proxy, seat) ~= o.clone then
                SetPedIntoVehicle(o.clone, d.proxy, seat)   -- fell out
            end
            -- seat offset, only measured when standing still (ped matrix lags while driving)
            if CLONES and not SEAT and IsPedSittingInVehicle(ped, d.veh) and (not o.L or GetEntitySpeed(d.veh) < 0.3) then
                local a0, b0, u0, pos0 = GetEntityMatrix(d.veh)
                local pa, pb, pu, pp = GetEntityMatrix(ped)
                o.L = { toLocal(pa, a0, b0, u0), toLocal(pb, a0, b0, u0), toLocal(pu, a0, b0, u0), toLocal(pp - pos0, a0, b0, u0) }
            end
        end
    end
    for ped, o in pairs(d.occ) do
        if not seen[ped] then
            deleteClone(o)
            d.occ[ped] = nil
        end
    end
end

local function updateOccupants(d, a, b, u, p)
    local me = PlayerPedId()
    for ped, o in pairs(d.occ) do
        if DoesEntityExist(ped) and IsPedSittingInVehicle(ped, d.veh) then
            if not Config.ShowOccupants then
                SetEntityLocallyInvisible(ped)
            elseif isClone(o) then
                local L = o.L
                if (not SEAT and not L) or (ped == me and GetFollowVehicleCamViewMode() == 4) then
                    -- no offset yet or first person, keep the real ped
                    SetEntityLocallyInvisible(o.clone)
                else
                    if not SEAT then
                        setMatrix(o.clone, fromLocal(L[1], a, b, u), fromLocal(L[2], a, b, u), fromLocal(L[3], a, b, u), p + fromLocal(L[4], a, b, u))
                    end
                    SetEntityLocallyInvisible(ped)
                end
            end
        elseif isClone(o) then
            SetEntityLocallyInvisible(o.clone)
        end
    end
end

-- alpha keeps skidmarks etc, invisible doesnt
local AUTO = Config.HideOriginal == 'auto'
local ALPHA = AUTO or Config.HideOriginal == 'alpha'

local function isDamaged(veh)
    return GetVehicleBodyHealth(veh) < 999.0 or not AreAllVehicleWindowsIntact(veh)
end

local function hideOriginal(veh)
    if ALPHA then SetEntityAlpha(veh, 0, false) end
end

-- handles get reused, so check model (and not networked for proxies)
local function isProxy(d)
    return DoesEntityExist(d.proxy) and GetEntityModel(d.proxy) == MODEL and not NetworkGetEntityIsNetworked(d.proxy)
end

local function isOriginal(d)
    return DoesEntityExist(d.veh) and GetEntityModel(d.veh) == MODEL
end

local function deleteProxy(d)
    proxies[d.proxy] = nil
    for _, o in pairs(d.occ) do deleteClone(o) end   -- before the car or they fall out
    if isProxy(d) then
        SetEntityAsMissionEntity(d.proxy, true, true)
        DeleteVehicle(d.proxy)
    end
    if ALPHA and isOriginal(d) then ResetEntityAlpha(d.veh) end
end

-- docs are unclear which matrix vector is forward, so check once
local forwardFirst

local function detectAxes(veh)
    local a = GetEntityMatrix(veh)
    local f = GetEntityForwardVector(veh)
    forwardFirst = a.x * f.x + a.y * f.y + a.z * f.z > 0.5
end

local function ensureModel()
    if not modelHeld then
        RequestModel(MODEL)
        modelHeld = true
    end
    if not HasModelLoaded(MODEL) then return false end
    local min = GetModelDimensions(MODEL)
    minZ = min.z
    return true
end

local function releaseModel()
    if modelHeld then
        SetModelAsNoLongerNeeded(MODEL)
        modelHeld = false
    end
end

local function scan()
    local heard = {}
    for _, src in pairs(YarisDance.sources) do
        if src.heard and src.coords then heard[#heard + 1] = src end
    end

    -- nearest source per car, nearest cars first
    local wanted = {}
    if #heard > 0 then
        local playerPos = GetEntityCoords(PlayerPedId())
        local list = {}
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if not proxies[veh] and GetEntityModel(veh) == MODEL then
                local pos = GetEntityCoords(veh)
                local best, bestDist
                for _, src in ipairs(heard) do
                    local dist = #(pos - src.coords)
                    if dist <= src.data.range and (not bestDist or dist < bestDist) then
                        best, bestDist = src, dist
                    end
                end
                if best then list[#list + 1] = { veh = veh, src = best, dist = #(pos - playerPos) } end
            end
        end
        table.sort(list, function(a, b) return a.dist < b.dist end)
        for i = 1, math.min(#list, Config.MaxDancers) do
            wanted[list[i].veh] = list[i].src
        end
    end

    local now = GetGameTimer()

    for veh, d in pairs(dancers) do
        if not isOriginal(d) or not isProxy(d) then
            deleteProxy(d)
            dancers[veh] = nil
        elseif wanted[veh] then
            d.src, d.leaving = wanted[veh], false
            d.moving = GetEntitySpeed(veh) > 0.1 or not IsVehicleSeatFree(veh, -1)
            hideOriginal(veh)   -- in case another script reset the alpha
            d.damaged = AUTO and isDamaged(veh)
            if PEDS then syncOccupants(d) end
            if now - d.lastCopy > 2000 then
                copyLook(veh, d.proxy)
                d.lastCopy = now
            end
        else
            d.leaving = true   -- fade out, frame loop deletes it
        end
    end

    if next(wanted) and ensureModel() then
        for veh, src in pairs(wanted) do
            if not dancers[veh] then
                local proxy = createProxy(veh)
                if proxy then
                    if forwardFirst == nil then detectAxes(veh) end
                    hideOriginal(veh)
                    dancers[veh] = {
                        veh = veh,
                        proxy = proxy,
                        src = src,
                        amp = 0.0,
                        leaving = false,
                        moving = true,
                        wheels = GetVehicleNumberOfWheels(veh),
                        occ = {},   -- ped -> { seat, model, clone }
                        jitter = Config.PerCarJitter > 0 and (math.random() * 2.0 - 1.0) * Config.PerCarJitter or 0.0,
                        lastCopy = now,
                    }
                end
            end
        end
    end

    if not next(wanted) and not next(dancers) then releaseModel() end
end

CreateThread(function()
    while true do
        scan()
        Wait(Config.ScanInterval)
    end
end)

local function frame(d, now, dt)
    local veh, proxy = d.veh, d.proxy
    if not isOriginal(d) or not isProxy(d) then return false end

    local t = YarisDance.danceTime(d.src.data, now)
    local s, active = 1.0, false
    if t then s, active = shape(t, d.jitter) end

    local step = dt / Config.FadeMs
    if active and not d.leaving then
        d.amp = math.min(1.0, d.amp + step)
    else
        d.amp = math.max(0.0, d.amp - step)
        if d.leaving and d.amp == 0.0 then return false end
    end
    s = 1.0 + (s - 1.0) * d.amp
    d.s, d.t = s, t

    local a, b, up, pos = GetEntityMatrix(veh)
    if d.moving and Config.MotionPrediction > 0 then
        -- matrix is read before physics, so proxy would lag one frame behind
        pos = pos + GetEntityVelocity(veh) * (GetFrameTime() * Config.MotionPrediction)
    end
    local sLen, sWid = s ^ LENGTH_EXP, s ^ WIDTH_EXP
    if forwardFirst then
        a, b = a * sLen, b * sWid
    else
        a, b = a * sWid, b * sLen
    end
    local p = pos + up * (minZ * (1.0 - s))
    up = up * s

    -- SetEntityMatrix alone doesnt move it for culling, so set coords first
    SetEntityCoordsNoOffset(proxy, p.x, p.y, p.z, false, false, false)
    SetEntityMatrix(proxy, a.x, a.y, a.z, b.x, b.y, b.z, up.x, up.y, up.z, p.x, p.y, p.z)

    if PEDS and next(d.occ) then
        updateOccupants(d, a, b, up, p)
    end

    if d.moving and Config.CopyWheels then
        for i = 0, d.wheels - 1 do
            SetVehicleWheelYRotation(proxy, i, GetVehicleWheelYRotation(veh, i))
        end
        SetVehicleSteeringAngle(proxy, GetVehicleSteeringAngle(veh))
    end

    if not ALPHA or d.damaged then SetEntityLocallyInvisible(veh) end
    return true
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        if next(dancers) then
            local now = GetGameTimer()
            local dt = math.min(now - last, 100)
            last = now
            for veh, d in pairs(dancers) do
                if not frame(d, now, dt) then
                    deleteProxy(d)
                    dancers[veh] = nil
                end
            end
            Wait(0)
        else
            Wait(500)
            last = GetGameTimer()
        end
    end
end)

RegisterCommand('yarisdebug', function()
    print(('[sratzel_yarisdance] Achsen: %s | Modell geladen: %s | minZ %.2f'):format(
        forwardFirst == nil and 'noch nicht geprueft' or (forwardFirst and 'forward zuerst' or 'right zuerst'),
        tostring(HasModelLoaded(MODEL)), minZ))
    local count = 0
    for id, src in pairs(YarisDance.sources) do
        count += 1
        local t = YarisDance.danceTime(src.data)
        print(('  Quelle %s: hoerbar %s, Abstand %.1f m, Songzeit %s'):format(
            id, tostring(src.heard), src.dist or -1, t and ('%.2f s'):format(t) or 'kein Server-Offset'))
    end
    if count == 0 then print('  keine Quellen') end
    count = 0
    for veh, d in pairs(dancers) do
        count += 1
        local exists = DoesEntityExist(d.proxy)
        print(('  Taenzer %d: Proxy %d existiert %s, sichtbar %s, Abstand zum Original %.2f m, s %.2f, amp %.2f'):format(
            veh, d.proxy, tostring(exists), tostring(exists and IsEntityVisible(d.proxy)),
            exists and #(GetEntityCoords(d.proxy) - GetEntityCoords(veh)) or -1, d.s or 1.0, d.amp))
        for ped, o in pairs(d.occ) do
            print(('    Insasse %d (Sitz %d): Klon %s'):format(ped, o.seat, isClone(o) and tostring(o.clone) or 'keiner'))
        end
    end
    if count == 0 then print('  keine Taenzer') end
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, d in pairs(dancers) do deleteProxy(d) end
    releaseModel()
end)
