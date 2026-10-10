-- wasteland_players :: server/main.lua
-- Module "players": accounts, sessions and characters with persistence.

local Characters = WLP.Characters
local Sessions = WLP.Sessions
local Interface = WLP.Interface

local commandRegistered = false
local netEventsRegistered = false

-- Periodic work: position samples, character saves, retries of failed
-- final saves, expiry of accepted-but-never-joined connections.
local function saveLoop(token)
    local sinceSave, sinceSample = 0, 0
    local TICK = 1000
    while WLP.token == token do
        Citizen.Wait(TICK)
        if WLP.token ~= token then return end
        sinceSave = sinceSave + TICK
        sinceSample = sinceSample + TICK
        if sinceSample >= WLP.cfg.positionSampleSeconds * 1000 then
            sinceSample = 0
            for _, char in pairs(WLP.loaded) do Characters.samplePosition(char) end
        end
        if sinceSave >= WLP.cfg.saveIntervalSeconds * 1000 then
            sinceSave = 0
            local now = GetGameTimer()
            for license, p in pairs(WLP.pending) do
                if p.expiresAt < now then WLP.pending[license] = nil end
            end
            if WDB.isUp() then
                local ids = {}
                for id in pairs(WLP.loaded) do ids[#ids + 1] = id end
                table.sort(ids)
                local failed = 0
                for _, id in ipairs(ids) do
                    local char = WLP.loaded[id]
                    if char and not Characters.save(char, 'periodic') then failed = failed + 1 end
                    if WLP.token ~= token then return end
                end
                if failed > 0 then
                    WLP.M.log:error('periodic save: %d of %d character(s) could not be saved', failed, #ids)
                end
                Characters.retryUnsaved()
            else
                local n = 0
                for _ in pairs(WLP.loaded) do n = n + 1 end
                if n > 0 then
                    WLP.M.log:warn('periodic save skipped for %d character(s): database unavailable', n)
                end
            end
        end
    end
end

AddEventHandler('wasteland:database:health', function(up)
    if not WLP.active() then return end
    local token = WLP.token
    if up then
        Citizen.CreateThread(function()
            if WLP.token ~= token then return end
            Characters.retryUnsaved()
            Characters.reportUnsaved()
            -- Save everyone now: their changes could not be written while it was down.
            for _, char in pairs(WLP.loaded) do Characters.save(char, 'database restored') end
        end)
    else
        WLP.M.setHealth('degraded', 'database unavailable: characters cannot be saved, created or loaded')
    end
end)

local M = Wasteland.DefineModule({
    name = 'players',
    version = '0.1.0',
    description = 'Accounts, sessions and characters with persistence',
    core = '^1.1.0',
    dependencies = { database = '^0.1.0' },
    async = true,
    config = {
        file = 'players.lua',
        optional = true,
        schema = {
            type = 'table',
            fields = {
                identifier = { type = 'enum', values = { 'license', 'license2' }, default = 'license',
                    description = 'Identifier that defines an account.' },
                maxCharacters = { type = 'integer', default = 3, min = 1, max = 10,
                    description = 'Character slots per account.' },
                duplicateSession = { type = 'enum', values = { 'kick_old', 'reject_new' }, default = 'kick_old',
                    description = 'What happens when an account connects while already connected.' },
                sessionReleaseTimeoutSeconds = { type = 'integer', default = 20, min = 1, max = 120,
                    description = 'How long a connection waits for the previous session of the same account to finish saving.' },
                saveIntervalSeconds = { type = 'integer', default = 60, min = 10, max = 3600,
                    description = 'Seconds between periodic character saves.' },
                savePosition = { type = 'boolean', default = true,
                    description = 'Remember where each character was.' },
                positionSampleSeconds = { type = 'integer', default = 10, min = 1, max = 600,
                    description = 'How often the position is sampled in memory (written with the next save).' },
                restoreDelayMs = { type = 'integer', default = 1000, min = 0, max = 10000,
                    description = 'After this resource restarts, wait this long before reloading characters.' },
                maxCharacterDataBytes = { type = 'integer', default = 65536, min = 1024, max = 1048576,
                    description = 'Maximum size of one module data value (JSON bytes).' },
                allowCharacterDeletion = { type = 'boolean', default = true,
                    description = 'Let players delete their own characters.' },
                commandName = { type = 'string', default = 'character', pattern = '^[a-z][a-z0-9_]*$', maxLength = 32,
                    description = 'Chat command for character management.' },
                names = {
                    type = 'table',
                    fields = {
                        minLength = { type = 'integer', default = 2, min = 1, max = 32 },
                        maxLength = { type = 'integer', default = 20, min = 1, max = 32 },
                        pattern = { type = 'string', default = "^[%a][%a' %-]*$", minLength = 1,
                            description = 'Lua pattern every name must match.' },
                    },
                },
                defaultSpawn = { type = 'vector3', default = { x = 1734.0, y = 3297.0, z = 41.2 },
                    description = 'Where new characters start.' },
                defaultHeading = { type = 'number', default = 195.0, min = 0, max = 360 },
            },
        },
    },

    onInit = function(M, ctx)
        if M.config.names.minLength > M.config.names.maxLength then
            return false, 'players.lua: names.minLength must not be greater than names.maxLength'
        end
        WLP.M = M
        WLP.cfg = M.config
        local token = {}
        WLP.token = token
        if not commandRegistered then
            -- FiveM commands cannot be unregistered; register once per resource start.
            Interface.registerCommand(M.config.commandName)
            commandRegistered = true
        end
        if not netEventsRegistered then
            Interface.registerNetEvents(M)
            netEventsRegistered = true
        end
        Citizen.CreateThread(function()
            local result, err = WDB.migrate('players', WLP.MIGRATIONS)
            if WLP.token ~= token then return end
            if not result then
                M.fail('database migrations failed: ' .. tostring(err))
                return
            end
            M.ready()
            Citizen.CreateThread(function() saveLoop(token) end)
            Sessions.restore(token)
        end)
        return true
    end,

    onShutdown = function(M, reason)
        WLP.token = nil
        -- We cannot wait here: issue final saves and let them complete in the
        -- database resource. Keep the state bags, so a restart can restore.
        local issued, failed = 0, 0
        for _, char in pairs(WLP.loaded) do
            if Characters.saveWithoutWaiting(char) then issued = issued + 1 else failed = failed + 1 end
        end
        for _, char in pairs(WLP.unsaved) do
            if Characters.saveWithoutWaiting(char) then issued = issued + 1 else failed = failed + 1 end
        end
        if issued > 0 then M.log:info('issued final saves for %d character(s) (%s)', issued, tostring(reason)) end
        if failed > 0 then
            M.log:error('could not issue final saves for %d character(s) (%s): the database is not reachable; changes since their last save are lost',
                failed, tostring(reason))
        end
        WLP.sessions, WLP.byLicense, WLP.pending, WLP.loaded, WLP.unsaved = {}, {}, {}, {}, {}
    end,
})
