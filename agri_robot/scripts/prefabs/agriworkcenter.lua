local C=require("agri/constants")
local Range=require("agri/work_range")
local assets={Asset("ANIM","anim/sign_mini.zip")}
local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    inst.entity:SetCanSleep(false)
    inst.AnimState:SetBank("sign_mini")
    inst.AnimState:SetBuild("sign_mini")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetMultColour(.55,1,.65,1)
    inst.AnimState:SetFinalOffset(1)
    inst.Transform:SetScale(1.2,1.2,1.2)
    inst:AddTag("agriworkcenter")
    inst:AddTag("NOBLOCK")
    -- World component recreates a single derived marker, never save a ghost.
    inst.persists=false
    inst._agri_radius=net_smallbyte(inst.GUID,"agriworkcenter.radius")
    inst._agri_order=net_uint(inst.GUID,"agriworkcenter.order")
    inst._agri_group=net_string(inst.GUID,"agriworkcenter.group")
    inst.displaynamefn=function()
        return "农业工作中心 · "..inst._agri_group:value().." · 半径 "..inst._agri_radius:value()
    end
    inst.entity:SetPristine()
    if not TheNet:IsDedicated() then
        local function clear()
            Range.Clear(inst._agri_range);inst._agri_range=nil
        end
        inst:AddComponent("updatelooper")
        inst.components.updatelooper:AddOnWallUpdateFn(function()
            -- Wall updates still run during local pause. Trust the actual
            -- world/highlight target instead of rejecting every HUD overlay:
            -- a transparent farm badge must not suppress the marker's circle.
            local highlight=inst.components.highlight
            local hover=ThePlayer and TheInput and
                (TheInput:GetWorldEntityUnderMouse()==inst or highlight and highlight.highlit)
            if hover then
                local x,_,z=inst.Transform:GetWorldPosition()
                inst._agri_range=Range.Show(inst._agri_range,x,z,inst._agri_radius:value())
            elseif inst._agri_range then clear() end
        end)
        inst:ListenForEvent("onremove",clear)
    end
    if not TheWorld.ismastersim then return inst end
    inst._agri_radius:set(C.DEFAULT_RADIUS)
    inst:AddComponent("inspectable")
    return inst
end
return Prefab("agriworkcenter",fn,assets,{"reticuleaoe"})
