local M={}
function M.Clear(markers)
    for _,marker in ipairs(markers or {}) do if marker:IsValid() then marker:Remove() end end
end
function M.Show(snapshot,draft,duration)
    local markers={}
    if not ThePlayer or not snapshot then return markers end
    local function mark(x,z,colour,scale)
        local inst=SpawnPrefab("tile_outline")
        if inst then
            inst.Transform:SetPosition(x,0,z)
            inst.Transform:SetScale(scale or 1,1,scale or 1)
            inst.AnimState:SetMultColour(colour[1],colour[2],colour[3],0.65)
            inst:DoTaskInTime(duration or 8,inst.Remove)
            markers[#markers+1]=inst
        end
    end
    local center=snapshot.center
    local radius=snapshot.settings.radius
    for n=0,31 do
        local angle=n*2*math.pi/32
        mark(center.x+math.cos(angle)*radius,center.z+math.sin(angle)*radius,{0.45,0.65,1},0.2)
    end
    for _,cell in ipairs(draft or snapshot.blueprint.cells or {}) do mark(cell.x,cell.z,{0.35,1,0.5}) end
    for _,cell in ipairs(snapshot.blueprint.warnings or {}) do mark(cell.x,cell.z,{1,0.3,0.25}) end
    return markers
end
return M
