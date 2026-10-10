local files = {}
local env = loadCoreFiles({
    'shared/util.lua', 'shared/semver.lua', 'shared/schema.lua', 'shared/logger.lua', 'server/config_loader.lua',
}, {
    LoadResourceFile = function(res, path) return files[res .. '/' .. path] end,
    GetResourceState = function(res) return res == 'wasteland_config' and 'started' or 'missing' end,
})
local Config = env.WL.Config
local schema = { type = 'table', fields = { n = { type = 'integer', default = 1, min = 0 } } }

describe('config loader', function()
    it('loads and validates a config file', function()
        files['wasteland_config/config/a.lua'] = 'return { n = 4 }'
        local r = Config.loadValidated('a.lua', schema)
        expect(r.ok).toBe(true); expect(r.config.n).toBe(4)
    end)
    it('reports syntax errors with file and line', function()
        files['wasteland_config/config/b.lua'] = 'return {\n n = = 4 }'
        local r = Config.loadValidated('b.lua', schema)
        expect(r.ok).toBe(false)
        expect(r.errors[1]).toContain('wasteland_config/config/b.lua')
        expect(r.errors[1]).toContain('syntax error')
        expect(r.errors[1]).toContain(':2:')
    end)
    it('reports runtime errors and non-table results', function()
        files['wasteland_config/config/c.lua'] = 'return nil + 1'
        expect(Config.loadValidated('c.lua', schema).errors[1]).toContain('error while evaluating')
        files['wasteland_config/config/d.lua'] = 'return 5'
        expect(Config.loadValidated('d.lua', schema).errors[1]).toContain('must `return { ... }`')
    end)
    it('reports validation errors with file and setting', function()
        files['wasteland_config/config/e.lua'] = 'return { n = -1 }'
        local r = Config.loadValidated('e.lua', schema)
        expect(r.errors[1]).toBe("wasteland_config/config/e.lua: setting 'n': expected an integer >= 0, got -1")
    end)
    it('missing file: error when required, defaults + warning when optional', function()
        expect(Config.loadValidated('none.lua', schema).errors[1]).toContain('file not found')
        local r = Config.loadValidated('none.lua', schema, { optional = true })
        expect(r.ok).toBe(true); expect(r.config.n).toBe(1)
        expect(r.warnings[1]).toContain('using built-in defaults')
    end)
    it('sandboxes config files (no os/io/natives)', function()
        files['wasteland_config/config/f.lua'] = 'return { n = os.time() }'
        expect(Config.loadValidated('f.lua', schema).errors[1]).toContain("attempt to index a nil value (global 'os')")
        files['wasteland_config/config/g.lua'] = 'return { n = math.floor(2.0) }'
        expect(Config.loadValidated('g.lua', schema).ok).toBe(true)
    end)
    it('rejects path traversal in file names', function()
        local r = Config.loadValidated('../secret.lua', schema)
        expect(r.errors[1]).toContain('invalid config file name')
    end)
    it('reports a missing configuration resource clearly', function()
        local r = Config.loadValidated('a.lua', schema, { resource = 'nope' })
        expect(r.errors[1]).toContain('configuration resource "nope" is not installed')
    end)
    it('core config schemas are self-consistent', function()
        for name, s in pairs(Config.CORE_SCHEMAS) do
            local ok, errs = env.WL.Schema.check(s)
            if not ok then error(name .. ': ' .. table.concat(errs, '; ')) end
        end
    end)
end)
