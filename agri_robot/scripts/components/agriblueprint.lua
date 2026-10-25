local C = require("agri/constants")
local U = require("agri/util")

-- This component only edits a value blueprint. It never changes the map.
local AgriBlueprint = Class(function(self, inst)
    self.inst = inst
end)

function AgriBlueprint:Center(x, z)
    if not U.Finite(x) or not U.Finite(z) then return nil end
    if TheWorld and TheWorld.Map then
        local cx, _, cz = TheWorld.Map:GetTileCenterPoint(x, 0, z)
        if cx ~= nil and cz ~= nil then return { x = cx, z = cz } end
    end
    return { x = math.floor(x / 4) * 4 + 2, z = math.floor(z / 4) * 4 + 2 }
end

function AgriBlueprint:Validate(group, proposed)
    if type(proposed) ~= "table" or #proposed > C.MAX_BLUEPRINT_CELLS then
        return nil, "蓝图过大或格式错误"
    end
    local out, seen, warnings = {}, {}, {}
    for _, value in ipairs(proposed) do
        if type(value) ~= "table" then return nil, "蓝图坐标错误" end
        local cell = self:Center(value.x, value.z)
        if not cell then return nil, "蓝图坐标错误" end
        if U.DistanceSq(cell, group.center) > group.settings.radius * group.settings.radius then
            warnings[#warnings + 1] = { x = cell.x, z = cell.z, reason = "超出主农场工作范围" }
        else
            local key = U.CellKey(cell.x, cell.z)
            local safe, reason = self:IsSafe(cell)
            if not safe then
                warnings[#warnings+1]={x=cell.x,z=cell.z,reason=reason}
            elseif not seen[key] then
                seen[key] = true
                cell.key = key
                out[#out + 1] = cell
            end
        end
    end
    table.sort(out, function(a, b) return a.x == b.x and a.z < b.z or a.x < b.x end)
    return out, warnings
end

function AgriBlueprint:IsSafe(cell)
    if not TheWorld or not TheWorld.Map then return true end
    local map=TheWorld.Map
    if map.CanPlantAtPoint and not map:CanPlantAtPoint(cell.x,0,cell.z) then
        return false,"地形不可耕作"
    end
    if TheSim then
        local entities=TheSim:FindEntities(cell.x,0,cell.z,3,nil,{"INLIMBO","FX","NOCLICK","NOBLOCK","DECOR","locomotor"})
        for _,entity in ipairs(entities) do
            if entity:HasTag("structure") or entity:HasTag("wall") or entity:HasTag("agriwarehouse") then
                local x,_,z=entity.Transform:GetWorldPosition()
                local center=self:Center(x,z)
                if center and U.CellKey(center.x,center.z)==U.CellKey(cell.x,cell.z) then
                    return false,"建筑占用，保留原建筑"
                end
            end
        end
    end
    return true
end

function AgriBlueprint:Apply(group, cells)
    local result, warnings = self:Validate(group, cells)
    if not result then return false, warnings end
    group.blueprint.cells = result
    group.blueprint.confirmed = true
    group.blueprint.warnings = warnings
    group.revision = (group.revision or 0) + 1
    group.dirty = true
    return true, warnings
end

function AgriBlueprint:Fill(group)
    local center, radius = self:Center(group.center.x, group.center.z), group.settings.radius
    local cells = {}
    for dx = -math.ceil(radius / 4), math.ceil(radius / 4) do
        for dz = -math.ceil(radius / 4), math.ceil(radius / 4) do
            local point = { x = center.x + dx * 4, z = center.z + dz * 4 }
            if U.DistanceSq(point, group.center) <= radius * radius then cells[#cells + 1] = point end
        end
    end
    return self:Validate(group, cells)
end

function AgriBlueprint:Rectangle(group, first, last, base, remove)
    local a, b = self:Center(first.x, first.z), self:Center(last.x, last.z)
    if not a or not b then return nil, "矩形坐标错误" end
    if math.abs(a.x-b.x) > group.settings.radius * 2 + 8 or math.abs(a.z-b.z) > group.settings.radius * 2 + 8 then return nil, "矩形超出工作范围" end
    local cells = {}
    for _, point in ipairs(base or {}) do cells[U.CellKey(point.x,point.z)] = point end
    for x = math.min(a.x,b.x), math.max(a.x,b.x), 4 do
        for z = math.min(a.z,b.z), math.max(a.z,b.z), 4 do
            local key = U.CellKey(x,z)
            if remove then cells[key] = nil else cells[key] = { x=x, z=z } end
        end
    end
    local list = {}
    for _, key in ipairs(U.Keys(cells)) do list[#list+1] = cells[key] end
    return self:Validate(group,list)
end

return AgriBlueprint
