-- Client-local native circle. reticuleaoe's default radius is 4 world units
-- (native reticuleaoe.lua: a 1.05 ping grows radius by .2).
-- One local entity, never a network FX or a saved world object.
local C=require("agri/constants")
local M={}
function M.Clear(marks)
    for _,inst in ipairs(marks or {}) do if inst:IsValid() then inst:Remove() end end
end
function M.Show(marks,x,z,radius)
    marks=marks or {}
    local inst=marks[1]
    if inst and inst:IsValid() and marks.x==x and marks.z==z and marks.radius==radius then return marks end
    if not inst or not inst:IsValid() then
        inst=SpawnPrefab("reticuleaoe");marks[1]=inst
        if not inst then return marks end
        inst.persists=false
        -- A ground reticule without a light override becomes hard to see in
        -- ordinary dusk/night lighting, even while its hover text is lit.
        inst.AnimState:SetLightOverride(1)
        inst.AnimState:SetMultColour(.2,.85,1,1)
        inst.AnimState:SetAddColour(.1,.3,.4,0)
        inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
        inst.AnimState:SetSortOrder(8)
    end
    inst.Transform:SetPosition(x,0,z)
    local scale=radius/4
    inst.Transform:SetScale(scale,scale,scale)
    marks.x,marks.z,marks.radius=x,z,radius
    return marks
end
-- Match server Register's eligible oldest group, using replicated
-- fixed origins, not moving robots. Existing coverage can join at r1+r2.
function M.FindCenter(x,z)
    local best
    for _,inst in ipairs(TheSim:FindEntities(x,0,z,C.RADII[#C.RADII]+C.DEFAULT_RADIUS,{"agriworkcenter"})) do
        local radius=inst._agri_radius:value()
        local cx,_,cz=inst.Transform:GetWorldPosition()
        if (x-cx)^2+(z-cz)^2<=(radius+C.DEFAULT_RADIUS)^2 then
            if not best or inst._agri_order:value()<best._agri_order:value() then best=inst end
        end
    end
    return best
end
function M.SetupPlacer(inst)
    local function clear()
        M.Clear(inst._agri_range);inst._agri_range=nil
    end
    inst.components.placer.onupdatetransform=function()
        if inst.components.placer.mouse_blocked then clear();return end
        local x,_,z=inst.Transform:GetWorldPosition()
        local center=M.FindCenter(x,z)
        local radius=C.DEFAULT_RADIUS
        if center then x,_,z=center.Transform:GetWorldPosition();radius=center._agri_radius:value() end
        inst._agri_range=M.Show(inst._agri_range,x,z,radius)
    end
    inst:ListenForEvent("onremove",clear)
end
return M
