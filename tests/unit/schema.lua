local env = loadCoreFiles({ 'shared/util.lua', 'shared/schema.lua' })
local Schema = env.WL.Schema

local schema = {
    type = 'table',
    fields = {
        name = { type = 'string', default = 'X', minLength = 1 },
        level = { type = 'enum', values = { 'a', 'b' }, default = 'a' },
        count = { type = 'integer', min = 1, max = 10, default = 5 },
        ratio = { type = 'number', min = 0, max = 1 },
        flag = { type = 'boolean', default = false },
        must = { type = 'string', required = true },
        nested = { type = 'table', fields = { inner = { type = 'integer', default = 3 } } },
        list = { type = 'array', items = { type = 'string' }, default = {} },
        map = { type = 'map', values = { type = 'boolean' }, default = {} },
        pos = { type = 'vector3' },
        id = { type = 'string', pattern = '^[a-z]+$' },
    },
}

describe('schema validation', function()
    it('applies defaults, including nested table defaults', function()
        local v, errs = Schema.validate(schema, { must = 'ok' })
        expect(#errs).toBe(0)
        expect(v.name).toBe('X'); expect(v.count).toBe(5); expect(v.flag).toBe(false)
        expect(v.nested.inner).toBe(3)
    end)
    it('reports missing required settings with the path', function()
        local _, errs = Schema.validate(schema, {})
        expect(#errs).toBe(1)
        expect(errs[1].path).toBe('must')
        expect(errs[1].message).toContain('missing required setting')
    end)
    it('reports type, range, enum, pattern and length errors with expected values', function()
        local _, errs = Schema.validate(schema, {
            must = 'ok', name = '', level = 'c', count = 11, ratio = 'x', flag = 'yes', id = 'ABC',
        })
        local byPath = {}
        for _, e in ipairs(errs) do byPath[e.path] = e.message end
        expect(byPath.name).toContain('at least 1 character')
        expect(byPath.level).toContain('one of "a", "b"')
        expect(byPath.count).toContain('between 1 and 10')
        expect(byPath.ratio).toContain('expected a number')
        expect(byPath.flag).toContain('true or false')
        expect(byPath.id).toContain('does not match')
    end)
    it('rejects non-integer for integer fields', function()
        local _, errs = Schema.validate(schema, { must = 'x', count = 2.5 })
        expect(errs[1].path).toBe('count')
    end)
    it('validates arrays and maps element by element', function()
        local _, errs = Schema.validate(schema, { must = 'x', list = { 'a', 2 }, map = { a = true, b = 'no' } })
        local paths = {}
        for _, e in ipairs(errs) do paths[#paths + 1] = e.path end
        expect(paths).toContain('list[2]')
        expect(paths).toContain('map.b')
    end)
    it('rejects non-sequential tables as arrays', function()
        local _, errs = Schema.validate(schema, { must = 'x', list = { a = 1 } })
        expect(errs[1].message).toContain('expected a list')
    end)
    it('accepts vector3-shaped tables and rejects others', function()
        local _, ok = Schema.validate(schema, { must = 'x', pos = { x = 1, y = 2, z = 3 } })
        expect(#ok).toBe(0)
        local _, bad = Schema.validate(schema, { must = 'x', pos = { 1, 2, 3 } })
        expect(bad[1].path).toBe('pos')
    end)
    it('warns about unknown keys (typos) without failing', function()
        local v, errs, warns = Schema.validate(schema, { must = 'x', nmae = 'typo' })
        expect(#errs).toBe(0)
        expect(warns[1].path).toBe('nmae')
        expect(v.nmae).toBe(nil)
    end)
    it('does not share default tables between results', function()
        local a = Schema.validate(schema, { must = 'x' })
        a.list[1] = 'mutated'
        local b = Schema.validate(schema, { must = 'x' })
        expect(#b.list).toBe(0)
    end)
    it('formats issues as "<file>: setting \'path\': message"', function()
        local _, errs = Schema.validate(schema, { must = 'x', count = 99 })
        local lines = Schema.formatIssues(errs, 'cfg/x.lua')
        expect(lines[1]).toContain("cfg/x.lua: setting 'count': expected an integer between 1 and 10, got 99")
    end)
end)

describe('schema self-check', function()
    it('accepts a well-formed schema', function()
        expect((Schema.check(schema))).toBe(true)
    end)
    it('rejects unknown types, empty enums and invalid defaults', function()
        local ok, errs = Schema.check({ type = 'table', fields = {
            a = { type = 'strnig' },
            b = { type = 'enum', values = {} },
            c = { type = 'integer', min = 1, default = 0 },
        } })
        expect(ok).toBe(false)
        expect(#errs).toBe(3)
        expect(table.concat(errs, '\n')).toContain('default value is invalid')
    end)
end)

describe('nullable tables', function()
    local s = { type = 'table', fields = { section = { type = 'table', nullable = true, fields = {
        file = { type = 'string', required = true } } } } }
    it('stay nil when absent (children not checked)', function()
        local v, errs = Schema.validate(s, {})
        expect(#errs).toBe(0); expect(v.section).toBe(nil)
    end)
    it('validate children when present', function()
        local _, errs = Schema.validate(s, { section = {} })
        expect(errs[1].path).toBe('section.file')
    end)
end)
