-- Single Lua server thread makes the checked assignment atomic; no client owns claims.
local Claims = {}
Claims.__index = Claims
function Claims.New() return setmetatable({ entries = {} }, Claims) end
function Claims:Acquire(id, owner, now, duration)
    local old = self.entries[id]
    if old and old.owner ~= owner and old.expires > now then return false end
    self.entries[id] = { owner = owner, expires = now + duration }
    return true
end
function Claims:Renew(id, owner, now, duration)
    local old = self.entries[id]
    if not old or old.owner ~= owner then return false end
    old.expires = now + duration
    return true
end
function Claims:Release(id, owner)
    local old = self.entries[id]
    if old and (owner == nil or old.owner == owner) then self.entries[id] = nil; return true end
    return false
end
function Claims:Get(id) return self.entries[id] end
function Claims:ReleaseOwner(owner)
    local result = {}
    for id, entry in pairs(self.entries) do
        if entry.owner == owner then result[#result + 1] = id; self.entries[id] = nil end
    end
    return result
end
return Claims
