local U = require("agri/util")
local M = {}
function M.Scan(group)
    local out = {}
    if not group or not TheWorld or not TheSim then return out end
    local p = group.center
    local radius = group.settings.radius
    local entities = TheSim:FindEntities(p.x, 0, p.z, radius, { "epic" }, { "INLIMBO", "FX", "NOCLICK" })
    for _, ent in ipairs(entities) do
        local health = ent.components and ent.components.health
        -- SRC-024: bosses are epic + hostile; lordfruitfly carries both tags.
        if U.Valid(ent) and not (health and health:IsDead())
            and (ent:HasTag("hostile") or ent:HasTag("lordfruitfly")) then
            local key = ent:HasTag("lordfruitfly") and "lordfruitfly" or "boss"
            out[key .. ":" .. tostring(ent.GUID)] = { kind = key, guid = ent.GUID, prefab = ent.prefab }
        end
    end
    local rain = TheWorld.components.frograin
    local s = TheWorld.state
    if rain and s.isspring and s.israining and s.precipitationrate > TUNING.FROG_RAIN_PRECIPITATION
        and s.moistureceil > TUNING.FROG_RAIN_MOISTURE then
        local ok, data = pcall(rain.OnSave, rain)
        if ok and data and (data.frogcap or 0) > 0 then out.frograin = { kind = "frograin" } end
    end
    return out
end
function M.Label(threat)
    return threat.kind == "lordfruitfly" and "果蝇王" or threat.kind == "frograin" and "青蛙雨" or "Boss 进入农场"
end
function M.Announce(text)
    if TheNet and TheNet.Announce then TheNet:Announce("[农业机器人] " .. text) end
end
return M
