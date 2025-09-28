-- npc-police/client.lua

local QBCore = exports['qb-core']:GetCoreObject()

-- ===== GARANTIR CONFIG =====
-- Se por algum motivo o config não foi carregado, crie um fallback mínimo pra não quebrar.
if not Config then
    print("^1[npc-police] ATENÇÃO: Config global não encontrada. Use shared_script 'config.lua' no fxmanifest antes do client.lua!^0")
    Config = {
        PoliceAmbient = { enableFoot=true, enableVehicle=true, maxFoot=4, maxVehicle=3, spawnMinDist=160.0, spawnMaxDist=300.0, footWanderRadius=20.0, vehicleCruiseSpeed=17.0, repathSeconds=20 },
        PoliceEscalation = { [1]={extraVehicles=0}, [2]={extraVehicles=1}, [3]={extraVehicles=2}, [4]={extraVehicles=3}, [5]={extraVehicles=4} },
        Response = { maxRespondDistance=400.0, engageDistance=200.0, loseDistance=550.0, neverSpawnNear=120.0, vehicleStandOff=35.0 },
        SafeDespawn = { minDistance=160.0, onlyWhenNotVisible=true },
        PoliceVehicleModels = { `police`, `police2` },
        PolicePedModelsFoot  = { "s_m_y_cop_01" },
        PolicePedModelsCar   = { "s_m_y_cop_01" },
        Debug = true
    }
end

local function DBG(msg)
    if Config.Debug then
        print(("^3[npc-police]^0 %s"):format(msg))
    end
end

-- ===== ESTADO =====
local Pool = {
    foot = {},       -- { ped, state='patrol'|'respond'|'return', home=vector3, removed=false }
    cars = {},       -- { veh, driver, pass, state='patrol'|'respond'|'return', home=vector3, removed=false }
    incident = nil,  -- { target=ped, level=int, startedAt=ms }
}

-- ===== UTILS =====
local function VecDist(a, b) return #(a - b) end

local function LoadModel(hashOrName)
    local mdl = type(hashOrName) == 'number' and hashOrName or GetHashKey(hashOrName)
    if not IsModelInCdimage(mdl) then DBG(("Modelo não existe: %s"):format(tostring(hashOrName))); return nil end
    RequestModel(mdl)
    local t = GetGameTimer()
    while not HasModelLoaded(mdl) and GetGameTimer() - t < 5000 do Wait(10) end
    if not HasModelLoaded(mdl) then DBG(("Falha ao carregar modelo: %s"):format(tostring(hashOrName))); return nil end
    return mdl
end

local function SafeDeleteEntity(ent)
    if not DoesEntityExist(ent) then return end
    SetEntityAsMissionEntity(ent, true, true)
    DeleteEntity(ent)
end

local function GroundZ(x, y, zHint)
    local ok, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, (zHint or 80.0) + 0.0, false)
    return ok and gz or (zHint or 80.0)
end

-- nunca spawnar perto do player
local function FindSpawnFarFromPlayer(minDist, maxDist, tries)
    tries = tries or 20
    local p = PlayerPedId()
    local pcoords = GetEntityCoords(p)
    for _=1, tries do
        local ang = math.random() * math.pi * 2
        local dist = minDist + math.random() * (maxDist - minDist)
        local pos = pcoords + vector3(math.cos(ang) * dist, math.sin(ang) * dist, 0.0)
        local z = GroundZ(pos.x, pos.y, pcoords.z + 30.0)
        local spawn = vector3(pos.x, pos.y, z)
        if VecDist(spawn, pcoords) >= minDist then
            return spawn
        end
    end
    return nil
end

-- ===== AMBIENT A PÉ (apenas fora de ocorrência) =====
local function SpawnFootCop()
    if not Config.PoliceAmbient.enableFoot then return end
    if #Pool.foot >= Config.PoliceAmbient.maxFoot then return end
    if Pool.incident then return end -- nunca criar a pé durante ocorrência

    local model = Config.PolicePedModelsFoot[math.random(#Config.PolicePedModelsFoot)]
    local mdl = LoadModel(model); if not mdl then return end
    local pos = FindSpawnFarFromPlayer(Config.PoliceAmbient.spawnMinDist, Config.PoliceAmbient.spawnMaxDist)
    if not pos then DBG("SpawnFootCop: pos nil"); return end

    local ped = CreatePed(6, mdl, pos.x, pos.y, pos.z, math.random(0,360), true, true)
    if not DoesEntityExist(ped) then DBG("SpawnFootCop: ped não criado"); return end

    SetPedRelationshipGroupHash(ped, GetHashKey("COP"))
    SetPedArmour(ped, 50)
    SetEntityHealth(ped, 200)
    SetPedSeeingRange(ped, 60.0)
    SetPedHearingRange(ped, 60.0)
    SetPedCombatAttributes(ped, 46, true)      -- use cover
    SetPedCombatRange(ped, 2)                  -- médio

    TaskWanderInArea(ped, pos.x, pos.y, pos.z, Config.PoliceAmbient.footWanderRadius, 5.0, 5.0)
    table.insert(Pool.foot, { ped = ped, state = 'patrol', home = pos, removed = false })
    DBG(("SpawnFootCop OK (total=%d)"):format(#Pool.foot))
end

-- ===== AMBIENT VIATURA (2 policiais por carro) =====
local function SpawnPatrolCar()
    if not Config.PoliceAmbient.enableVehicle then return end
    if #Pool.cars >= Config.PoliceAmbient.maxVehicle then return end

    local vmodel = Config.PoliceVehicleModels[math.random(#Config.PoliceVehicleModels)]
    local vmdl = LoadModel(vmodel); if not vmdl then return end

    local pos = FindSpawnFarFromPlayer(Config.PoliceAmbient.spawnMinDist, Config.PoliceAmbient.spawnMaxDist)
    if not pos then DBG("SpawnPatrolCar: pos nil"); return end

    local veh = CreateVehicle(vmdl, pos.x, pos.y, pos.z, math.random(0,360), true, true)
    if not DoesEntityExist(veh) then DBG("SpawnPatrolCar: veh não criado"); return end

    SetVehicleSiren(veh, false)
    SetVehicleEngineOn(veh, true, true, false)

    local pmodelA = Config.PolicePedModelsCar[math.random(#Config.PolicePedModelsCar)]
    local pmodelB = Config.PolicePedModelsCar[math.random(#Config.PolicePedModelsCar)]
    local mdlA = LoadModel(pmodelA); local mdlB = LoadModel(pmodelB)
    if not (mdlA and mdlB) then SafeDeleteEntity(veh); DBG("SpawnPatrolCar: falha ped models"); return end

    local driver = CreatePedInsideVehicle(veh, 6, mdlA, -1, true, true)
    local pass   = CreatePedInsideVehicle(veh, 6, mdlB,  0, true, true)
    if not (DoesEntityExist(driver) and DoesEntityExist(pass)) then
        DBG("SpawnPatrolCar: peds não criados")
        SafeDeleteEntity(driver); SafeDeleteEntity(pass); SafeDeleteEntity(veh)
        return
    end

    SetPedRelationshipGroupHash(driver, GetHashKey("COP"))
    SetPedRelationshipGroupHash(pass,   GetHashKey("COP"))

    TaskVehicleDriveWander(driver, veh, Config.PoliceAmbient.vehicleCruiseSpeed, 786603)
    table.insert(Pool.cars, { veh = veh, driver = driver, pass = pass, state = 'patrol', home = pos, removed = false })
    DBG(("SpawnPatrolCar OK (total=%d)"):format(#Pool.cars))
end

-- ===== LOOPS DE MANUTENÇÃO =====
CreateThread(function()
    while true do
        if not Pool.incident then
            if #Pool.foot < Config.PoliceAmbient.maxFoot then SpawnFootCop() end
        end
        if #Pool.cars < Config.PoliceAmbient.maxVehicle then SpawnPatrolCar() end
        Wait(2000)
    end
end)

CreateThread(function()
    while true do
        local repath = (Config.PoliceAmbient.repathSeconds or 20) * 1000
        if not Pool.incident then
            for _, u in ipairs(Pool.foot) do
                if DoesEntityExist(u.ped) and u.state == 'patrol' then
                    TaskWanderInArea(u.ped, u.home.x, u.home.y, u.home.z, Config.PoliceAmbient.footWanderRadius, 5.0, 5.0)
                end
            end
            for _, u in ipairs(Pool.cars) do
                if DoesEntityExist(u.driver) and DoesEntityExist(u.veh) and u.state == 'patrol' then
                    TaskVehicleDriveWander(u.driver, u.veh, Config.PoliceAmbient.vehicleCruiseSpeed, 786603)
                end
            end
        end
        Wait(repath)
    end
end)

-- ===== RESPOSTA À OCORRÊNCIA =====
local function DriveVehicleTo(u, dest)
    if not (DoesEntityExist(u.driver) and DoesEntityExist(u.veh)) then return end
    TaskVehicleDriveToCoord(u.driver, u.veh, dest.x, dest.y, dest.z,
        Config.PoliceAmbient.vehicleCruiseSpeed, 0, GetEntityModel(u.veh), 786603, 5.0, true)
end

local function UnitsRespond(level)
    local player = PlayerPedId()
    local ppos = GetEntityCoords(player)
    Pool.incident = { target = player, level = level, startedAt = GetGameTimer() }
    DBG(("UnitsRespond: level=%d"):format(level))

    -- 1) Unidades EXISTENTES e PRÓXIMAS respondem
    for _, u in ipairs(Pool.foot) do
        if DoesEntityExist(u.ped) then
            local d = VecDist(GetEntityCoords(u.ped), ppos)
            if d <= Config.Response.maxRespondDistance then
                ClearPedTasks(u.ped)
                TaskGoToEntity(u.ped, player, -1, 15.0, 4.0, 0, 0)
                TaskCombatPed(u.ped, player, 0, 16)
                u.state = 'respond'
            end
        end
    end
    for _, u in ipairs(Pool.cars) do
        if DoesEntityExist(u.driver) and DoesEntityExist(u.veh) then
            local d = VecDist(GetEntityCoords(u.veh), ppos)
            if d <= Config.Response.maxRespondDistance then
                ClearPedTasks(u.driver)
                DriveVehicleTo(u, ppos)
                u.state = 'respond'
            end
        end
    end

    -- 2) Escalonamento: viaturas extras (nunca a pé), longe do player
    local extra = (Config.PoliceEscalation[level] and Config.PoliceEscalation[level].extraVehicles) or 0
    DBG(("UnitsRespond: extraVehicles=%d"):format(extra))
    for i = 1, extra do
        local spawnPos = FindSpawnFarFromPlayer(Config.Response.neverSpawnNear, Config.PoliceAmbient.spawnMaxDist)
        if spawnPos then
            local before = #Pool.cars
            SpawnPatrolCar()
            local u = Pool.cars[#Pool.cars]
            if u and u.state == 'patrol' then
                DriveVehicleTo(u, ppos)
                u.state = 'respond'
            end
        end
    end
end

RegisterNetEvent('police:client:spawnResponse', function(wantedLevel)
    if wantedLevel and wantedLevel > 0 then
        UnitsRespond(wantedLevel)
        QBCore.Functions.Notify(("Polícia em deslocamento. Nível: %d"):format(wantedLevel), "error", 3000)
    end
end)

-- ===== ENCERRAMENTO / FUGA =====
local function ReturnOrDespawnUnit(u)
    local player = PlayerPedId()
    local ppos = GetEntityCoords(player)
    local farEnough = VecDist((u.home or ppos), ppos) >= Config.SafeDespawn.minDistance

    local function visible(ent)
        return Config.SafeDespawn.onlyWhenNotVisible and IsEntityOnScreen(ent)
    end

    -- se visível, não despawnar: voltar rotina
    if (u.ped and DoesEntityExist(u.ped) and visible(u.ped))
    or (u.veh and DoesEntityExist(u.veh) and visible(u.veh)) then
        if u.ped and DoesEntityExist(u.ped) then
            TaskWanderInArea(u.ped, u.home.x, u.home.y, u.home.z, Config.PoliceAmbient.footWanderRadius, 5.0, 5.0)
            u.state = 'patrol'
        elseif u.driver and DoesEntityExist(u.driver) and DoesEntityExist(u.veh) then
            TaskVehicleDriveWander(u.driver, u.veh, Config.PoliceAmbient.vehicleCruiseSpeed, 786603)
            u.state = 'patrol'
        end
        return
    end

    -- se longe e fora da vista, despawn seguro
    if farEnough then
        if u.ped and DoesEntityExist(u.ped) then SafeDeleteEntity(u.ped) end
        if u.driver and DoesEntityExist(u.driver) then SafeDeleteEntity(u.driver) end
        if u.pass and DoesEntityExist(u.pass) then SafeDeleteEntity(u.pass) end
        if u.veh and DoesEntityExist(u.veh) then SafeDeleteEntity(u.veh) end
        u.removed = true
    else
        -- muito perto: mandar “voltar pra base”
        if u.ped and DoesEntityExist(u.ped) then
            TaskWanderInArea(u.ped, u.home.x, u.home.y, u.home.z, Config.PoliceAmbient.footWanderRadius, 5.0, 5.0)
            u.state = 'patrol'
        elseif u.driver and DoesEntityExist(u.driver) and DoesEntityExist(u.veh) then
            TaskVehicleDriveToCoord(u.driver, u.veh, u.home.x, u.home.y, u.home.z,
                Config.PoliceAmbient.vehicleCruiseSpeed, 0, GetEntityModel(u.veh), 786603, 5.0, true)
            u.state = 'return'
        end
    end
end

CreateThread(function()
    while true do
        if Pool.incident then
            local player = PlayerPedId()
            local ppos = GetEntityCoords(player)

            local active = 0
            for _, u in ipairs(Pool.foot) do
                if u.state == 'respond' and DoesEntityExist(u.ped) then
                    if VecDist(GetEntityCoords(u.ped), ppos) <= Config.Response.loseDistance then
                        active = active + 1
                    end
                end
            end
            for _, u in ipairs(Pool.cars) do
                if u.state == 'respond' and DoesEntityExist(u.veh) then
                    if VecDist(GetEntityCoords(u.veh), ppos) <= Config.Response.loseDistance then
                        active = active + 1
                    end
                end
            end

            if active == 0 then
                for _, u in ipairs(Pool.foot) do
                    if u.state ~= 'patrol' then ReturnOrDespawnUnit(u) end
                end
                for _, u in ipairs(Pool.cars) do
                    if u.state ~= 'patrol' then ReturnOrDespawnUnit(u) end
                end
                Pool.incident = nil
                QBCore.Functions.Notify("As viaturas encerraram a ocorrência.", "primary", 2500)
            end
        end

        -- limpeza
        for i = #Pool.foot, 1, -1 do
            if Pool.foot[i].removed then table.remove(Pool.foot, i) end
        end
        for i = #Pool.cars, 1, -1 do
            if Pool.cars[i].removed then table.remove(Pool.cars, i) end
        end

        Wait(2000)
    end
end)

-- debug cmd
RegisterCommand('npcpolice_debug', function()
    print(('[NPC-Police] foot=%d cars=%d incident=%s'):format(#Pool.foot, #Pool.cars, Pool.incident and 'yes' or 'no'))
end, false)
