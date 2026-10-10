-- Wasteland Core :: server/security.lua
-- Counts net-event violations reported by the SDK guard in module resources
-- (`wasteland:core:netViolation`) and optionally kicks repeat offenders.
-- The event is server-local: it is never registered as a net event, so
-- clients cannot raise it.

WL = WL or {}
WL.Security = WL.Security or {}
local Security = WL.Security
local log = WL.Logger.new('security')

Security.violations = Security.violations or {} -- [source] = { times... }

local function settings()
    local cfg = WL.Lifecycle.coreConfig
    return cfg and cfg.framework.security or { kickAfterViolations = 0, violationWindowSeconds = 60 }
end

--- Record a violation. Returns the number of violations by this player
--- inside the configured window.
function Security.record(src, module, eventName, kind, detail)
    src = tonumber(src)
    if not src or src <= 0 then return 0 end
    local s = settings()
    local now = GetGameTimer()
    local windowMs = s.violationWindowSeconds * 1000
    local list = Security.violations[src] or {}
    local kept = {}
    for _, t in ipairs(list) do
        if now - t < windowMs then kept[#kept + 1] = t end
    end
    kept[#kept + 1] = now
    Security.violations[src] = kept
    if s.kickAfterViolations > 0 and #kept >= s.kickAfterViolations then
        log:warn('kicking player %d: %d rejected requests within %ds (last: %s %s: %s)',
            src, #kept, s.violationWindowSeconds, tostring(module), tostring(eventName), tostring(detail))
        Security.violations[src] = nil
        DropPlayer(tostring(src), 'Kicked: too many invalid requests to the server.')
    end
    return #kept
end

AddEventHandler('wasteland:core:netViolation', function(src, module, eventName, kind, detail)
    Security.record(src, module, eventName, kind, detail)
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then Security.violations[src] = nil end
end)

return Security
