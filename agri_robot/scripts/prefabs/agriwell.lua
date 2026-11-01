local assets={
    Asset("ANIM","anim/agriwell.zip"),
    Asset("ATLAS","images/inventoryimages/agriwell.xml"),
    Asset("IMAGE","images/inventoryimages/agriwell.tex"),
}
local function notify(inst)
    local registry=TheWorld and TheWorld.components.agrifarmgroup
    if not registry then return end
    local x,_,z=inst.Transform:GetWorldPosition()
    for _,group in pairs(registry.groups) do
        local center=group.center
        if center and (center.x-x)^2+(center.z-z)^2<=group.settings.radius^2 then
            registry:MarkDirty(group,"resources")
        end
    end
end
local function hammered(inst,worker)
    if not worker or not worker:HasTag("player") then inst.components.workable:SetWorkLeft(6);return end
    inst.components.lootdropper:DropLoot()
    local fx=SpawnPrefab("collapse_big")
    if fx then fx.Transform:SetPosition(inst.Transform:GetWorldPosition())end
    inst:Remove()
end
local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()
    MakeObstaclePhysics(inst,.85)
    inst.DynamicShadow:SetSize(2.4,1.2)
    inst.AnimState:SetBank("agriwell")
    inst.AnimState:SetBuild("agriwell")
    inst.AnimState:PlayAnimation("idle",true)
    inst:AddTag("structure")
    inst:AddTag("agriwell")
    inst:AddTag("watersource")
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst:AddComponent("inspectable")
    -- Native FILL/Fillable handles the real watering can's uses. The well is
    -- a permanent fresh source; no synthetic water or direct tool-use edits.
    inst:AddComponent("watersource")
    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetLoot({"cutstone","cutstone","cutstone","boards","boards","rope"})
    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(6)
    inst.components.workable:SetOnWorkCallback(function(entity,worker)
        if not worker or not worker:HasTag("player")then entity.components.workable:SetWorkLeft(6)end
    end)
    inst.components.workable:SetOnFinishCallback(hammered)
    inst:ListenForEvent("onbuilt",notify)
    inst:ListenForEvent("onremove",notify)
    inst:DoTaskInTime(0,notify)
    return inst
end
return Prefab("agriwell",fn,assets,{"collapse_big"}),
    MakePlacer("agriwell_placer","agriwell","agriwell","idle")
