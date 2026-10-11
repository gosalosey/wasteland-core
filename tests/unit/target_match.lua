-- Target matching (wasteland_target/shared/match.lua).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_target/shared/match.lua', 't', env))()
local Match = env.WLT.Match

local function hash(s) return #s end -- stand-in for GetHashKey
local noop = function() end

local function regs()
    local r = {}
    r[1] = { id = 1, kind = 'model', models = Match.models({ 'dumpster', 77 }, hash), options = Match.options({
        { label = 'Search', onSelect = noop }, { label = 'Climb', distance = 1.0, onSelect = noop } }) }
    r[2] = { id = 2, kind = 'global', global = 'vehicle', options = Match.options({ label = 'Check fuel', event = 'x' }) }
    r[3] = { id = 3, kind = 'zone', zone = { shape = 'sphere', coords = { x = 0, y = 0, z = 0 }, radius = 1 },
        options = Match.options({ { label = 'Search bag', serverEvent = 'y' } }) }
    r[4] = { id = 4, kind = 'net', netId = 55, options = Match.options({ { label = 'Talk', onSelect = noop, name = 'talk' } }) }
    return r
end

describe('target options', function()
    it('need a label and something to do', function()
        local _, e1 = Match.options({ { onSelect = noop } })
        expect(e1).toContain('needs a label')
        local _, e2 = Match.options({ { label = 'Nothing' } })
        expect(e2).toContain('needs onSelect, event or serverEvent')
        expect(#Match.options({ label = 'Single', event = 'e' })).toBe(1)
        expect(Match.models('dumpster', hash)[8]).toBe(true)
    end)
end)

describe('target matching', function()
    local r = regs()
    it('models, by distance per option', function()
        local list = Match.collect(r, { entity = 9, model = 8, type = 'object', coords = { x = 9, y = 9, z = 0 }, distance = 2 })
        expect(#list).toBe(1); expect(list[1].option.label).toBe('Search')
        list = Match.collect(r, { entity = 9, model = 77, type = 'object', coords = { x = 9, y = 9, z = 0 }, distance = 0.8 })
        expect(#list).toBe(2)
        list = Match.collect(r, { entity = 9, model = 8, type = 'object', coords = { x = 9, y = 9, z = 0 }, distance = 4 })
        expect(#list).toBe(0)
    end)
    it('globals, network ids and zones; several at once in registration order', function()
        local list = Match.collect(r, { entity = 3, model = 1, type = 'vehicle', netId = 55, coords = { x = 0.5, y = 0, z = 0 }, distance = 1 })
        local labels = {}
        for _, c in ipairs(list) do labels[#labels + 1] = c.option.label end
        expect(table.concat(labels, ',')).toBe('Check fuel,Search bag,Talk')
        expect(#Match.collect(r, { coords = { x = 3, y = 0, z = 0 }, distance = 1 })).toBe(0)
    end)
    it('canInteract can hide options; errors in it hide them too', function()
        local list = Match.collect(r, { entity = 9, model = 77, type = 'object', coords = { x = 9, y = 9, z = 0 }, distance = 0.5 },
            function(_, o) if o.label == 'Climb' then error('boom') end return true end)
        expect(#list).toBe(1); expect(list[1].option.label).toBe('Search')
    end)
    it('box zones respect heading', function()
        local box = { shape = 'box', coords = { x = 0, y = 0, z = 0 }, size = { x = 4, y = 1, z = 2 }, heading = 0 }
        expect(Match.inZone(box, { x = 1.9, y = 0, z = 0 })).toBe(true)
        expect(Match.inZone(box, { x = 0, y = 1.9, z = 0 })).toBe(false)
        box.heading = 90
        expect(Match.inZone(box, { x = 0, y = 1.9, z = 0 })).toBe(true)
        expect(Match.inZone(box, { x = 1.9, y = 0, z = 0 })).toBe(false)
    end)
end)

describe('model hashes', function()
    it('a hash matches whether the game reads it signed or unsigned', function()
        local m = Match.models({ -1234567890 }, function() return 0 end)
        expect(m[-1234567890]).toBe(true)
        expect(m[-1234567890 + 4294967296]).toBe(true)
        local u = Match.models({ 3060399406 }, function() return 0 end)
        expect(u[3060399406 - 4294967296]).toBe(true)
    end)
end)
