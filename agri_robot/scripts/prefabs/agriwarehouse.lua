local assets = { Asset("ANIM", "anim/treasure_chest.zip") }
local prefabs = { "collapse_big" }

local function hammered(inst, worker)
    if not worker or not worker:HasTag("player") then inst.components.workable:SetWorkLeft(4); return end
    inst.components.container:Close()
    inst.components.container:DropEverything()
    inst.components.lootdropper:DropLoot()
    local fx = SpawnPrefab("collapse_big")
    if fx then fx.Transform:SetPosition(inst.Transform:GetWorldPosition()) end
    inst:Remove()
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()
    MakeObstaclePhysics(inst, 0.55)
    inst.AnimState:SetBank("chest")
    inst.AnimState:SetBuild("treasure_chest")
    inst.AnimState:PlayAnimation("closed")
    inst.AnimState:SetMultColour(0.76, 0.91, 0.68, 1)
    inst:AddTag("structure")
    inst:AddTag("chest")
    inst:AddTag("agriwarehouse")
    inst:AddTag("_container")
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst:AddComponent("inspectable")
    inst:AddComponent("container")
    inst.components.container:WidgetSetup("agriwarehouse")
    inst.components.container.onopenfn = function(entity)
        entity.AnimState:PlayAnimation("open")
    end
    inst.components.container.onclosefn = function(entity)
        entity.AnimState:PlayAnimation("close")
        entity.AnimState:PushAnimation("closed", false)
    end
    inst:AddComponent("agriwarehouse")
    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetLoot({ "boards", "boards", "boards", "boards" })
    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(4)
    inst.components.workable:SetOnWorkCallback(function(entity, worker)
        if not worker or not worker:HasTag("player") then entity.components.workable:SetWorkLeft(4) end
    end)
    inst.components.workable:SetOnFinishCallback(hammered)
    inst:ListenForEvent("onbuilt", function(entity)
        entity.AnimState:PlayAnimation("place")
        entity.AnimState:PushAnimation("closed", false)
    end)
    return inst
end

return Prefab("agriwarehouse", fn, assets, prefabs),
    MakePlacer("agriwarehouse_placer", "chest", "treasure_chest", "closed")
