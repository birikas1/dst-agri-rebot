-- Craftable farm work center (looks like the vanilla mini sign).
-- Robots can only be built inside a center's radius; centers never overlap.
local C=require("agri/constants")
local Range=require("agri/work_range")
local assets={
    Asset("ANIM","anim/sign_mini.zip"),
    -- Same ground ring as the vanilla Ice Flingomatic placer / helper.
    Asset("ANIM","anim/firefighter_placement.zip"),
}
local prefabs={"collapse_small"}

local function registry()
    return TheWorld and TheWorld.components.agrifarmgroup
end

local function hammered(inst,worker)
    if not worker or not worker:HasTag("player") then
        inst.components.workable:SetWorkLeft(4)
        return
    end
    inst.components.lootdropper:DropLoot()
    local fx=SpawnPrefab("collapse_small")
    if fx then fx.Transform:SetPosition(inst.Transform:GetWorldPosition()) end
    inst:Remove()
end

local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()
    inst.entity:SetCanSleep(false)
    if inst.SetDeploySmartRadius then inst:SetDeploySmartRadius(.5) end
    MakeObstaclePhysics(inst,.2)
    inst.AnimState:SetBank("sign_mini")
    inst.AnimState:SetBuild("sign_mini")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetFinalOffset(1)
    inst.AnimState:SetRayTestOnBB(true)
    inst:AddTag("structure")
    inst:AddTag("agriworkcenter")
    inst.persists=true
    inst._agri_radius=net_smallbyte(inst.GUID,"agriworkcenter.radius")
    inst._agri_order=net_uint(inst.GUID,"agriworkcenter.order")
    inst._agri_group=net_string(inst.GUID,"agriworkcenter.group")
    inst.displaynamefn=function()
        return "农业工作中心 · 半径 "..tostring(Range.CenterRadius(inst))
    end
    -- Dedicated servers draw nothing.
    if not TheNet:IsDedicated() then Range.SetupCenterClient(inst) end
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end

    inst._agri_radius:set(C.DEFAULT_RADIUS)
    inst:AddComponent("inspectable")
    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetLoot({"boards"})
    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(4)
    inst.components.workable:SetOnWorkCallback(function(entity,worker)
        if not worker or not worker:HasTag("player") then entity.components.workable:SetWorkLeft(4) end
    end)
    inst.components.workable:SetOnFinishCallback(hammered)

    local function register(entity)
        local groups=registry()
        if groups then groups:RegisterCenter(entity,entity._agri_saved) end
        entity._agri_saved=nil
    end

    inst.OnSave=function(entity,data)
        data.agri={group_id=entity._agri_group_id,placement_order=entity._agri_order_saved,
            radius=entity._agri_radius and entity._agri_radius:value()}
    end
    inst.OnLoad=function(entity,data)
        entity._agri_saved=data and data.agri or nil
        if entity._agri_saved then
            entity._agri_group_id=entity._agri_saved.group_id
            entity._agri_order_saved=entity._agri_saved.placement_order
        end
    end
    inst.OnLoadPostPass=function(entity)
        register(entity)
    end
    inst:ListenForEvent("onbuilt",function(entity)
        register(entity)
    end)
    inst:ListenForEvent("onremove",function(entity)
        local groups=registry()
        if groups then groups:UnregisterCenter(entity) end
    end)
    inst:DoTaskInTime(0,register)
    return inst
end

-- Like firesuppressor_placer: the placer is the range ring (on ground,
-- scaled to the default work radius); the sign is a linked child.
local placer=MakePlacer("agriworkcenter_placer",Range.RING_BANK,Range.RING_BANK,"idle",
    true,nil,nil,Range.RingScale(C.DEFAULT_RADIUS),nil,nil,Range.SetupCenterPlacer)
return Prefab("agriworkcenter",fn,assets,prefabs),placer
