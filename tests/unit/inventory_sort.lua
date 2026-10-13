-- Inventory auto-sort (wasteland_inventory/shared/grid.lua Grid.sortPlan).

local env = setmetatable({}, { __index = _G })
assert(loadfile(RESOURCES .. '/wasteland_inventory/shared/grid.lua', 't', env))()
local Grid = env.WLI.Grid

local defs = {
    bandage = { label = 'Bandage', category = 'medical', width = 1, height = 1, stack = 50 },
    pistol = { label = 'Pistol', category = 'weapon', width = 2, height = 2, stack = 1 },
    beans = { label = 'Beans', category = 'food', width = 1, height = 1, stack = 50 },
    rifle = { label = 'Rifle', category = 'weapon', width = 5, height = 1, stack = 1 },
}

describe('inventory sort', function()
    it('merges part stacks of the same item and packs from the top left by category', function()
        local inv = { width = 6, height = 4, items = {
            a = { uid = 'a', name = 'bandage', count = 30, x = 5, y = 3 },
            b = { uid = 'b', name = 'bandage', count = 30, x = 0, y = 3 },
            c = { uid = 'c', name = 'pistol', count = 1, x = 3, y = 1 },
            d = { uid = 'd', name = 'beans', count = 2, x = 1, y = 0 },
            e = { uid = 'e', name = 'rifle', count = 1, x = 0, y = 1 },
        } }
        local plan = Grid.sortPlan(inv, defs)
        -- 60 bandages: a full stack of 50 (kept uid a) and 10 (b)
        expect(plan.place.a.count).toBe(50); expect(plan.place.b.count).toBe(10)
        expect(#plan.remove).toBe(0)
        -- weapons first, the bigger rifle before the pistol
        expect(plan.place.e.x).toBe(0); expect(plan.place.e.y).toBe(0)
        expect(plan.place.c.x).toBe(0); expect(plan.place.c.y).toBe(1)
    end)

    it('stacks that merge into one leave the rest to be removed (and say where they went)', function()
        local inv = { width = 4, height = 2, items = {
            a = { uid = 'a', name = 'beans', count = 3, x = 3, y = 1 },
            b = { uid = 'b', name = 'beans', count = 4, x = 0, y = 0 },
        } }
        local plan = Grid.sortPlan(inv, defs)
        expect(plan.place.a.count).toBe(7)
        expect(plan.remove[1]).toBe('b'); expect(plan.into.b).toBe('a')
        expect(plan.place.a.x).toBe(0); expect(plan.place.a.y).toBe(0)
    end)

    it('different metadata does not merge', function()
        local inv = { width = 4, height = 2, items = {
            a = { uid = 'a', name = 'beans', count = 3, x = 3, y = 1, metadata = { spoiled = true } },
            b = { uid = 'b', name = 'beans', count = 4, x = 0, y = 0 },
        } }
        local plan = Grid.sortPlan(inv, defs)
        expect(#plan.remove).toBe(0)
    end)
end)
