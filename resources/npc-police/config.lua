-- npc-police/config.lua
-- ATENÇÃO: este arquivo deve ser carregado como shared_script no fxmanifest
-- (ver instruções ao final)

Config = Config or {}

-- ===== POLICING BEHAVIOR TUNING =====
Config.PoliceAmbient = {
    enableFoot = true,               -- spawns de policiais a pé (apenas fora de ocorrências)
    enableVehicle = true,            -- spawns de viaturas (2 policiais cada)

    -- limites do pool “ambient”
    maxFoot = 8,                     -- máximo de policiais a pé ativos
    maxVehicle = 6,                  -- máximo de viaturas ativas (cada uma com 2 policiais)

    -- distâncias de spawn (sempre longe do player)
    spawnMinDist = 180.0,            -- nunca spawnar mais perto que isso do player
    spawnMaxDist = 320.0,

    -- patrulha
    footWanderRadius = 25.0,         -- “bolha” onde o policial a pé circula
    vehicleCruiseSpeed = 17.0,       -- m/s (~ 60 km/h)
    repathSeconds = 20,              -- tempo entre novos destinos de patrulha (a pé e viatura)

    throttling = false               -- (opcional) ligar se quiser poupar CPU/GPU sob carga
}

-- escalonamento durante o procurado:
-- NUNCA cria novos policiais a pé durante ocorrência; APENAS viaturas extras (sempre longe).
Config.PoliceEscalation = {
    [1] = { extraVehicles = 0 },
    [2] = { extraVehicles = 1 },
    [3] = { extraVehicles = 2 },
    [4] = { extraVehicles = 3 },
    [5] = { extraVehicles = 4 },
}

-- alcance/resposta
Config.Response = {
    maxRespondDistance = 450.0,      -- apenas unidades já existentes dentro desse raio respondem
    engageDistance     = 220.0,      -- até onde perseguem ativamente
    loseDistance       = 600.0,      -- perdeu o rastro -> encerram e voltam à rotina

    neverSpawnNear     = 140.0,      -- qualquer viatura de reforço deve respeitar isso
    vehicleStandOff    = 35.0        -- viatura não “cola” no player
}

-- regras de despawn seguro (nunca sumir “na cara” do player)
Config.SafeDespawn = {
    minDistance = 180.0,             -- só despawnar se >= isso do player
    onlyWhenNotVisible = true        -- e fora do FOV/streaming do player
}

-- modelos
Config.PoliceVehicleModels = { `police`, `police2`, `police3` }
Config.PolicePedModelsFoot  = { "s_m_y_cop_01", "s_f_y_cop_01" }
Config.PolicePedModelsCar   = { "s_m_y_cop_01", "s_f_y_cop_01" }

-- debug (opcional)
Config.Debug = true

-- IMPORTANTE:
-- 1) Deixe o dispatch padrão da engine OFF (você já fez).
-- 2) Remova de QUALQUER script de “smallresources”/core:
--    - BlacklistedScenarios: 'WORLD_VEHICLE_POLICE_NEXT_TO_CAR', 'WORLD_VEHICLE_POLICE_CAR', 'WORLD_VEHICLE_POLICE_BIKE'
--    - BlacklistedPeds: modelos de polícia (s_m_y_cop_01, s_f_y_cop_01 etc)
-- Senão, o jogo vai deletar nossos NPCs/viaturas assim que nascerem.
