-- npc-police/server.lua
local QBCore = exports['qb-core']:GetCoreObject()

-- cache: identifier -> { level=int, timer=handle|nil }
local Wanted = {}

local function getIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1,7) == 'license' then return id end
    end
    return GetPlayerIdentifiers(src)[1] or ('src:'..tostring(src))
end

local function clamp(x, a, b) if x < a then return a end if x > b then return b end return x end

local function clearTimer(ident)
    local entry = Wanted[ident]
    if entry and entry.timer then
        ClearTimeout(entry.timer) -- no-op, just in case (we'll use SetTimeout below)
        entry.timer = nil
    end
end

local function setDecay(ident, seconds)
    clearTimer(ident)
    if not seconds or seconds <= 0 then return end
    if not Wanted[ident] then return end

    Wanted[ident].timer = SetTimeout(seconds * 1000, function()
        if not Wanted[ident] then return end
        Wanted[ident].level = 0
        Wanted[ident].timer = nil
        local src = Wanted[ident].src
        if src and GetPlayerPed(src) ~= 0 then
            TriggerClientEvent('QBCore:Notify', src, 'Voce perdeu o nivel de procurado.', 'primary')
        end
    end)
end

-- API simples: calcula amount pela “gravidade” do crime
local CrimeScale = {
    car_theft  = 1,   -- lockpick / hotwire
    carjack    = 2,   -- carjacking à mão armada
    shooting   = 2,
    homicide   = 3,
}

-- ==== EVENTOS ====

-- Controle fino: addWanted(amount[, crime][, decaySeconds])
RegisterNetEvent('police:server:addWanted', function(amount, crime, decaySeconds, targetSrc)
    local caller = source
    local src = caller
    local override = targetSrc and tonumber(targetSrc) or nil

    if caller == 0 and override then
        src = override
    elseif caller ~= 0 and override and override ~= caller then
        print(('[npc-police] blocked addWanted from %s to target %s'):format(tostring(caller), tostring(targetSrc)))
        return
    end

    if not src or src <= 0 or GetPlayerPed(src) == 0 then
        return
    end

    local ident = getIdentifier(src)
    Wanted[ident] = Wanted[ident] or { level = 0, src = src }

    local inc = tonumber(amount) or 1
    Wanted[ident].level = clamp((Wanted[ident].level or 0) + inc, 0, 5)
    Wanted[ident].src = src

    if decaySeconds and tonumber(decaySeconds) then
        setDecay(ident, tonumber(decaySeconds))
    end

    local level = Wanted[ident].level
    print(('[npc-police] +wanted -> %s level=%d crime=%s'):format(ident, level, tostring(crime or 'na')))

    TriggerClientEvent('police:client:spawnResponse', src, level)
end)

RegisterNetEvent('police:server:reportCrime', function(crimeId, decaySeconds, targetSrc)
    local caller = source
    local target = caller

    if caller == 0 and targetSrc then
        target = tonumber(targetSrc)
    end

    local amount = CrimeScale[crimeId] or 1
    TriggerEvent('police:server:addWanted', amount, crimeId, decaySeconds or 180, target)
end)

-- ==== CALLBACKS / COMANDOS ADMIN ====

QBCore.Functions.CreateCallback('police:server:getWanted', function(source, cb)
    local ident = getIdentifier(source)
    cb(Wanted[ident] and Wanted[ident].level or 0)
end)

QBCore.Commands.Add('addwanted', 'Adicionar procurado a um player', {
    {name='id', help='ID do player'},
    {name='amount', help='1..5'},
    {name='crime', help='(opcional)'}
}, true, function(src, args)
    local tgt = tonumber(args[1]); if not tgt then return end
    if GetPlayerPed(tgt) == 0 then
        TriggerClientEvent('QBCore:Notify', src, 'Player nao encontrado.', 'error')
        return
    end

    local amt = tonumber(args[2]) or 1
    local crime = args[3] or 'admin'

    TriggerEvent('police:server:addWanted', amt, crime, 180, tgt)

    local ident = getIdentifier(tgt)
    local level = Wanted[ident] and Wanted[ident].level or clamp(amt, 0, 5)

    TriggerClientEvent('QBCore:Notify', src, ('Wanted do ID %d: %d'):format(tgt, level), 'primary')
    TriggerClientEvent('QBCore:Notify', tgt, ('Seu nivel de procurado agora e %d'):format(level), 'error')
end, 'admin')

QBCore.Commands.Add('getwanted', 'Ver seu nível de procurado (ou de outro player)', {
    {name='id', help='(opcional)'}
}, false, function(src, args)
    local tgt = tonumber(args[1]) or src
    local ident = getIdentifier(tgt)
    local lvl = Wanted[ident] and Wanted[ident].level or 0
    TriggerClientEvent('QBCore:Notify', src, ('Wanted do ID %d: %d'):format(tgt, lvl), 'primary')
end, 'admin')

QBCore.Commands.Add('resetwanted', 'Zerar nível de procurado (seu ou de outro player)', {
    {name='id', help='(opcional)'}
}, false, function(src, args)
    local tgt = tonumber(args[1]) or src
    local ident = getIdentifier(tgt)
    if Wanted[ident] then Wanted[ident].level = 0; clearTimer(ident) end
    TriggerClientEvent('QBCore:Notify', tgt, 'Seu nível de procurado foi zerado.', 'success')
end, 'admin')
