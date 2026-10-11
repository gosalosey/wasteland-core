-- Pure inventory logic: item definitions and grid placement.

local function load()
    local env = setmetatable({}, { __index = _G })
    for _, f in ipairs({ 'shared/items.lua', 'shared/grid.lua' }) do
        assert(loadfile(RESOURCES .. '/wasteland_inventory/' .. f, 't', env))()
    end
    local schemaEnv = loadCoreFiles({ 'shared/util.lua', 'shared/schema.lua' })
    return env.WLI, schemaEnv.WL.Schema
end

local WLI, Schema = load()
local Grid = WLI.Grid

local function def(name, raw)
    local d, err = WLI.validateItem(Schema, name, raw)
    assert(d, err)
    return d
end

local DEFS = {
    can = def('can', { label = 'Can', width = 1, height = 1, stack = 5, weight = 0.4 }),
    bottle = def('bottle', { label = 'Bottle', width = 1, height = 2, weight = 1 }),
    plank = def('plank', { label = 'Plank', width = 3, height = 1, weight = 2 }),
    crate = def('crate', { label = 'Crate', width = 2, height = 2, weight = 5, stack = 1 }),
}

local function inv(w, h, items)
    local t = { width = w, height = h, maxWeight = 100, items = {} }
    for _, s in ipairs(items or {}) do t.items[s.uid] = s end
    return t
end

describe('item definitions', function()
    it('applies defaults and names the item', function()
        local d = def('thing', { label = 'Thing' })
        expect(d.name).toBe('thing')
        expect(d.width).toBe(1)
        expect(d.stack).toBe(50)
        expect(d.category).toBe('misc')
    end)
    it('items that cannot stack default to 1 and refuse a bigger stack', function()
        expect(def('gun', { label = 'Gun', durability = 100 }).stack).toBe(1)
        expect(def('bag', { label = 'Bag', equip = 'back', container = { width = 2, height = 2, maxWeight = 5 } }).stack).toBe(1)
        expect(def('hat', { label = 'Hat', equip = 'head' }).stack).toBe(1)
        local _, err = WLI.validateItem(Schema, 'shirt', { label = 'Shirt', equip = 'torso', stack = 50 })
        expect(err).toContain('cannot stack')
    end)
    it('rejects bad names, sizes and impossible combinations', function()
        local _, e1 = WLI.validateItem(Schema, 'Bad Name', { label = 'x' })
        expect(e1).toContain('must match')
        local _, e2 = WLI.validateItem(Schema, 'big', { label = 'x', width = 11 })
        expect(e2).toContain('width')
        local _, e3 = WLI.validateItem(Schema, 'bag', { label = 'x', container = { width = 4, height = 4, maxWeight = 10 } })
        expect(e3).toContain('must be worn on the back')
        local _, e4 = WLI.validateItem(Schema, 'knife', { label = 'x', stack = 5, durability = 100 })
        expect(e4).toContain('cannot stack')
        local _, e5 = WLI.validateItem(Schema, 'nolabel', {})
        expect(e5).toContain('label')
    end)
end)

describe('grid placement', function()
    it('accepts positions inside the grid and refuses outside ones', function()
        local i = inv(4, 3)
        expect(Grid.fits(i, DEFS, DEFS.plank, 1, 0, false)).toBe(true)
        expect(select(2, Grid.fits(i, DEFS, DEFS.plank, 2, 0, false))).toBe('outside')
        expect(select(2, Grid.fits(i, DEFS, DEFS.plank, -1, 0, false))).toBe('outside')
        expect(select(2, Grid.fits(i, DEFS, DEFS.plank, 0, 0.5, false))).toBe('outside')
    end)
    it('rotation swaps width and height', function()
        local i = inv(2, 3)
        expect(Grid.fits(i, DEFS, DEFS.plank, 0, 0, false)).toBe(false)
        expect(Grid.fits(i, DEFS, DEFS.plank, 1, 0, true)).toBe(true)
    end)
    it('detects overlap and names the blocking stack, ignoring the moved stack itself', function()
        local i = inv(4, 4, { { uid = 'c', name = 'crate', count = 1, x = 1, y = 1 } })
        local ok, why, blocker = Grid.fits(i, DEFS, DEFS.bottle, 2, 0, false)
        expect(ok).toBe(false); expect(why).toBe('overlap'); expect(blocker).toBe('c')
        expect(Grid.fits(i, DEFS, DEFS.bottle, 0, 0, false)).toBe(true)
        expect(Grid.fits(i, DEFS, DEFS.crate, 2, 2, false, 'c')).toBe(true)
    end)
    it('finds the first free spot, rotating when only that fits', function()
        local i = inv(3, 3, { { uid = 'a', name = 'crate', count = 1, x = 0, y = 0 } })
        local x, y, r = Grid.findSpot(i, DEFS, DEFS.bottle)
        expect(x).toBe(2); expect(y).toBe(0); expect(r).toBe(false)
        local px, py, pr = Grid.findSpot(i, DEFS, DEFS.plank)
        expect(px).toBe(0); expect(py).toBe(2); expect(pr).toBe(false)
        local full = inv(2, 2, { { uid = 'a', name = 'crate', count = 1, x = 0, y = 0 } })
        expect(Grid.findSpot(full, DEFS, DEFS.can)).toBe(nil)
        local tall = inv(1, 3)
        local tx, ty, tr = Grid.findSpot(tall, DEFS, DEFS.plank)
        expect(tx).toBe(0); expect(ty).toBe(0); expect(tr).toBe(true)
    end)
end)

describe('weights and stacks', function()
    it('sums weight per unit times count', function()
        local i = inv(4, 4, {
            { uid = 'a', name = 'can', count = 5, x = 0, y = 0 },
            { uid = 'b', name = 'crate', count = 1, x = 1, y = 0 },
        })
        expect(math.abs(Grid.weight(i, DEFS) - 7.0) < 1e-9).toBe(true)
        expect(math.abs(Grid.weight(i, DEFS, 'b') - 2.0) < 1e-9).toBe(true)
    end)
    it('merges only stackable items of the same name and metadata', function()
        local a = { uid = 'a', name = 'can', count = 1, metadata = {} }
        expect(Grid.canMerge(a, { uid = 'b', name = 'can', count = 1, metadata = {} }, DEFS)).toBe(true)
        expect(Grid.canMerge(a, { uid = 'b', name = 'can', count = 1, metadata = { spoiled = true } }, DEFS)).toBe(false)
        expect(Grid.canMerge(a, a, DEFS)).toBe(false)
        expect(Grid.canMerge({ uid = 'x', name = 'crate', count = 1 }, { uid = 'y', name = 'crate', count = 1 }, DEFS)).toBe(false)
    end)
end)
