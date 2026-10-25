local assets = { Asset("ANIM", "anim/dragon_scales.zip") }
local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)
    inst.AnimState:SetBank("dragon_scales")
    inst.AnimState:SetBuild("dragon_scales")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetMultColour(0.9, 0.66, 0.35, 1)
    inst:AddTag("agrirobot_upgrade")
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst:AddComponent("inspectable")
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("dragon_scales")
    return inst
end
return Prefab("scale_thermostat_module", fn, assets)
