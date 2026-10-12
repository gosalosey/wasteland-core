-- wasteland_groups :: shared/rules.lua (pure, unit-tested)

WLG = WLG or {}
local Rules = {}
WLG.Rules = Rules

--- A clean group name, or nil, reason. Letters, digits, spaces and - _ ' . !
function Rules.cleanName(name, minLen, maxLen)
    if type(name) ~= 'string' then return nil, 'Give the group a name.' end
    name = name:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
    if #name < minLen or #name > maxLen then
        return nil, string.format('The name must be %d to %d characters.', minLen, maxLen)
    end
    if not name:match("^[%w _%-'%.!]+$") then return nil, 'Use letters, numbers, spaces and - _ \' . ! only.' end
    return name
end

--- Is this name taken (case does not matter)? groups: { [id] = { name } }
function Rules.nameTaken(groups, name, exceptId)
    local lower = name:lower()
    for id, g in pairs(groups) do
        if id ~= exceptId and g.name:lower() == lower then return true end
    end
    return false
end

return Rules
