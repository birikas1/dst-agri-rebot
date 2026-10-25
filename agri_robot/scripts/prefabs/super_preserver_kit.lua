local assets = { Asset("ANIM", "anim/bearger_fur.zip") }
local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)
    inst.AnimState:SetBank("bearger_fur")
    inst.AnimState:SetBuild("bearger_fur")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetMultColour(0.65, 0.92, 1, 1)
    inst:AddTag("agriwarehouse_upgrade")
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst:AddComponent("inspectable")
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem:ChangeImageName("bearger_fur")
    return inst
end
return Prefab("super_preserver_kit", fn, assets)
