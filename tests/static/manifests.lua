-- Static checks over the real resource folders (no code is executed except
-- manifests, which are parsed in a sandbox).

local RESOURCE_NAMES = {
    'wasteland_config', 'wasteland_core', 'wasteland_template', 'wasteland_database', 'wasteland_players',
    'wasteland_ui', 'wasteland_appearance', 'wasteland_inventory', 'wasteland_survival',
    'wasteland_world', 'wasteland_admin', 'wasteland_weapons', 'wasteland_images', 'wasteland_zombies', 'wasteland_target', 'wasteland_loot', 'wasteland_camps', 'wasteland_crafting', 'wasteland_quests', 'wasteland_vehicles', 'wasteland_loadscreen', 'wasteland_emotes', 'wasteland_tailor', 'wasteland_supplydrops',
}
local FORBIDDEN = { 'qb-core', 'QBCore', 'qbx_core', 'es_extended', 'ESX', 'ox_lib', 'ox_inventory', 'ox_target' }

local function read(path)
    local f = io.open(path, 'rb'); if not f then return nil end
    local s = f:read('a'); f:close(); return s
end

local IS_WINDOWS = package.config:sub(1, 1) == '\\'

local function listLuaFiles(dir)
    local cmd
    if IS_WINDOWS then
        cmd = 'dir /s /b "' .. dir:gsub('/', '\\') .. '\\*.lua" 2>nul'
    else
        cmd = 'find "' .. dir .. '" -name "*.lua" -type f 2>/dev/null'
    end
    local ok, p = pcall(io.popen, cmd)
    if not ok or not p then return nil end
    -- Results are rebuilt as `dir .. <path below dir>` so they compare
    -- equal to the paths built from the manifest (Windows returns absolute,
    -- backslash-separated paths).
    local tail = (dir:gsub('\\', '/'):gsub('^%./', ''))
    local out = {}
    for line in p:lines() do
        line = (line:gsub('\\', '/'))
        local idx = line:find(tail, 1, true)
        out[#out + 1] = idx and (dir .. line:sub(idx + #tail)) or line
    end
    p:close()
    if #out == 0 then return nil end
    return out
end

for _, name in ipairs(RESOURCE_NAMES) do
    local dir = RESOURCES .. '/' .. name
    describe('resource ' .. name, function()
        local meta, err = Mock.parseManifest(dir .. '/fxmanifest.lua')
        it('fxmanifest parses', function() expect(meta ~= nil).toBe(true) end)
        if not meta then print('       ' .. tostring(err)); return end

        it('declares fx_version cerulean, game gta5, lua54 and a semver version', function()
            expect(meta.fx_version[1]).toBe('cerulean')
            expect(meta.game[1]).toBe('gta5')
            local scripts = meta.shared_script or meta.server_script or meta.client_script
            if scripts then expect((meta.lua54 or {})[1]).toBe('yes') end -- asset-only resources run no Lua
            expect(meta.version[1]:match('^%d+%.%d+%.%d+$') ~= nil).toBe(true)
        end)

        local referenced = {}
        local entries = {}
        for _, key in ipairs({ 'shared_script', 'server_script', 'client_script', 'file' }) do
            for _, e in ipairs(meta[key] or {}) do entries[#entries + 1] = e end
        end
        it('every referenced file exists and every Lua script compiles', function()
            for _, e in ipairs(entries) do
                local other, rel = e:match('^@([^/]+)/(.+)$')
                local path = other and (RESOURCES .. '/' .. other .. '/' .. rel) or (dir .. '/' .. e)
                if e:find('*', 1, true) then
                    -- wildcard (e.g. html/images/*.webp): at least one match
                    local dirPart, pattern = path:match('^(.*)/([^/]*)$')
                    local luaPattern = '^' .. pattern:gsub('%.', '%%.'):gsub('%*', '.*') .. '$'
                    local cmd = IS_WINDOWS and ('dir /b "' .. dirPart:gsub('/', '\\') .. '" 2>nul') or ('ls "' .. dirPart .. '" 2>/dev/null')
                    local p, found = io.popen(cmd), false
                    for line in p:lines() do if line:match(luaPattern) then found = true; break end end
                    p:close()
                    if not found then error('no files match manifest entry: ' .. e) end
                    goto continue
                end
                local src = read(path)
                if not src then error('missing file referenced by manifest: ' .. e) end
                if not other then referenced[path] = true end
                if path:match('%.lua$') then
                    local chunk, cerr = load(src, '@' .. path, 't', {})
                    if not chunk then error(cerr) end
                end
                ::continue::
            end
        end)

        it('does not reference other gameplay frameworks', function()
            for _, e in ipairs(entries) do
                local other, rel = e:match('^@([^/]+)/(.+)$')
                local path = other and (RESOURCES .. '/' .. other .. '/' .. rel) or (dir .. '/' .. e)
                local src = read(path) or ''
                for _, bad in ipairs(FORBIDDEN) do
                    if src:find(bad, 1, true) then error(path .. ' references ' .. bad) end
                end
            end
            for _, d in ipairs(meta.dependency or {}) do
                if not d:match('^wasteland_') then error('non-framework dependency: ' .. d) end
            end
        end)

        local all = listLuaFiles(dir)
        if all then
            it('every Lua file is loaded by the manifest (no dead files) or is a config file', function()
                for _, path in ipairs(all) do
                    local isManifest = path:match('fxmanifest%.lua$')
                    local isConfig = name == 'wasteland_config' and path:match('/config/[^/]+%.lua$')
                    if not isManifest and not isConfig and not referenced[path] then
                        error('Lua file not referenced by fxmanifest.lua: ' .. path)
                    end
                    if isConfig then
                        local chunk, cerr = load(read(path), '@' .. path, 't', {})
                        if not chunk then error(cerr) end
                    end
                end
            end)
        end
    end)
end
