local M = {}
function M.Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[M.Copy(key, seen)] = M.Copy(item, seen) end
    return result
end
function M.Valid(inst)
    return type(inst) == "table" and type(inst.IsValid) == "function" and inst:IsValid()
end
function M.Count(values)
    local n = 0
    for _ in pairs(values or {}) do n = n + 1 end
    return n
end
function M.Keys(values)
    local result = {}
    for k in pairs(values or {}) do result[#result + 1] = k end
    table.sort(result, function(a,b) return tostring(a) < tostring(b) end)
    return result
end
function M.DistanceSq(a, b)
    local dx, dz = (a.x or 0) - (b.x or 0), (a.z or 0) - (b.z or 0)
    return dx * dx + dz * dz
end
function M.CellKey(x, z)
    -- Native tile origins are world-dependent; normalize arbitrary crop/hole
    -- positions through the map instead of treating a tile centre as its edge.
    if TheWorld and TheWorld.Map and TheWorld.Map.GetTileCenterPoint then
        local cx, _, cz = TheWorld.Map:GetTileCenterPoint(x, 0, z)
        if cx ~= nil and cz ~= nil then x,z=cx,cz end
    end
    return tostring(math.floor(x / 4)) .. ":" .. tostring(math.floor(z / 4))
end
function M.Finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end
function M.Contains(list, value)
    for _, entry in ipairs(list or {}) do if entry == value then return true end end
    return false
end
function M.OnceTalk(robot, reason, text)
    robot._agri_messages = robot._agri_messages or {}
    if not robot._agri_messages[reason] then
        robot._agri_messages[reason] = true
        if robot.components.talker then robot.components.talker:Say(text or tostring(reason)) end
    end
end
function M.ClearTalk(robot, reason)
    if robot._agri_messages then robot._agri_messages[reason] = nil end
end
function M.Settings(data)
    local C = require("agri/constants")
    local out = M.Copy(C.DEFAULT_SETTINGS)
    data = type(data) == "table" and data or {}
    for k, v in pairs(out) do
        if type(data[k]) == type(v) then out[k] = data[k] end
    end
    if not M.Contains(C.RADII, out.radius) then out.radius = C.DEFAULT_RADIUS end
    if out.mode ~= "stable" and out.mode ~= "oversized" then out.mode = "stable" end
    if type(data.density) == "number" then out.density = tostring(data.density) end
    if not M.Contains(C.DENSITIES, tostring(out.density)) then out.density = C.DEFAULT_DENSITY end
    out.density = tostring(out.density)
    out.plan = {}
    if type(data.plan) == "table" then
        local total = 0
        for crop, count in pairs(data.plan) do
            count = tonumber(count)
            if type(crop) == "string" and #crop < 80 and count and count >= 1 and count % 1 == 0 and total + count <= C.PLAN_MAX_TOTAL then
                out.plan[crop] = math.min(C.PLAN_MAX_PER_CROP, count); total = total + out.plan[crop]
            end
        end
    end
    if not M.Contains({ "auto", "crop", "pause" }, out.planting) then out.planting = "auto" end
    if type(data.crop) == "string" and #data.crop < 80 then out.crop = data.crop end
    return out
end
return M
