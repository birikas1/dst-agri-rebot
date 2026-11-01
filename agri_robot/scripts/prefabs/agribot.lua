local C = require("agri/constants")
local U = require("agri/util")
local assets = { Asset("ANIM", "anim/winona_storage_robot.zip") }
local prefabs = { "collapse_small", "agriworkcenter", "reticuleaoe" }

local function registry(inst)
    return TheWorld and TheWorld.components.agrifarmgroup
end

local function register(inst)
    local groups = registry(inst)
    if groups then groups:Register(inst, inst._agri_saved) end
    inst._agri_saved = nil
end

local function hammered(inst, worker)
    if not worker or not worker:HasTag("player") then
        inst.components.workable:SetWorkLeft(4)
        return
    end
    if inst.components.agriexecutor then inst.components.agriexecutor:Interrupt("removed", false) end
    inst.components.container:Close()
    inst.components.inventory:DropEverything()
    inst.components.container:DropEverything()
    inst.components.lootdropper:DropLoot()
    local fx = SpawnPrefab("collapse_small")
    if fx then fx.Transform:SetPosition(inst.Transform:GetWorldPosition()) end
    inst:Remove()
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()
    inst.entity:SetCanSleep(false)
    MakeCharacterPhysics(inst, 50, 0.35)
    inst.DynamicShadow:SetSize(1.6, 0.9)
    inst.Transform:SetFourFaced()
    inst.AnimState:SetBank("winona_storage_robot")
    inst.AnimState:SetBuild("winona_storage_robot")
    inst.AnimState:PlayAnimation("idle_off", true)
    inst.AnimState:SetMultColour(0.77, 0.93, 0.79, 1)
    inst:AddTag("agribot")
    inst:AddTag("companion")
    inst:AddTag("notarget")
    inst:AddTag("noattack")
    inst:AddTag("NOBLOCK")
    inst:AddTag("_container")
    inst._agri_groupnet = net_string(inst.GUID, "agribot.group", "agrigroupdirty")
    inst._agri_statusnet = net_string(inst.GUID, "agribot.status", "agristatusdirty")
    inst:AddComponent("talker")
    inst.components.talker.font = BODYTEXTFONT
    inst.components.talker.fontsize = 24
    inst.components.talker.offset = Vector3(0, -220, 0)
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end

    inst:AddComponent("inspectable")
    inst:AddComponent("locomotor")
    inst.components.locomotor.walkspeed = 4
    inst.components.locomotor.runspeed = 4
    inst:AddComponent("inventory")
    inst.components.inventory.maxslots = C.WORK_SLOTS
    inst.components.inventory.ignorefull = true
    inst:AddComponent("container")
    inst.components.container:WidgetSetup("agribot")
    local open = inst.components.container.Open
    inst.components.container.Open = function(container, player, ...)
        if not U.Valid(player) or player:HasTag("playerghost")
            or inst:GetDistanceSqToInst(player) > C.INTERACT_DISTANCE * C.INTERACT_DISTANCE then return end
        if not container.openlist[player] and not container:CanOpen() then return end
        local groups=registry(inst)
        if groups then groups:SetInventoryHold(player,inst,true,true) end
        if inst.components.agriresource then inst.components.agriresource:OrganizeTools() end
        local result=open(container, player, ...)
        if groups then groups:SetInventoryHold(player,inst,container.openlist[player]~=nil,false) end
        return result
    end
    local close=inst.components.container.Close
    inst.components.container.Close=function(container,player,...)
        local result=close(container,player,...)
        local groups=registry(inst)
        if groups then
            if player then groups:SetInventoryHold(player,inst,false)
            else
                for key,hold in pairs(groups.inventory_holds) do if hold.robot==inst then groups.inventory_holds[key]=nil end end
                groups:RefreshEditing(groups:GetGroup(inst))
            end
        end
        return result
    end
    inst:AddComponent("lootdropper")
    inst.components.lootdropper:SetLoot({ "gears", "boards", "goldnugget", "goldnugget" })
    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(4)
    inst.components.workable:SetOnWorkCallback(function(entity, worker)
        if not worker or not worker:HasTag("player") then entity.components.workable:SetWorkLeft(4) end
    end)
    inst.components.workable:SetOnFinishCallback(hammered)
    inst:AddComponent("agriresource")
    inst:AddComponent("agrithermal")
    inst:AddComponent("agriplanner")
    inst:AddComponent("agrischeduler")
    inst:AddComponent("agriexecutor")
    inst:SetStateGraph("SGagribot")
    inst:SetBrain(require("brains/agribotbrain"))
    inst.OnSave = function(entity, data)
        data.agri = { placement_order = entity._agri_order, group_id = entity._agri_group_id,
            origin = U.Copy(entity._agri_build_origin),
            personal_settings = U.Copy(entity._agri_personal_settings) }
    end
    inst.OnLoad = function(entity, data)
        entity._agri_saved = data and data.agri or nil
        entity._agri_build_origin=U.Copy(entity._agri_saved and entity._agri_saved.origin)
    end
    inst.OnLoadPostPass = function(entity)
        register(entity)
    end
    inst:ListenForEvent("onbuilt",function(entity)
        local x,_,z=entity.Transform:GetWorldPosition()
        entity._agri_build_origin={x=x,z=z}
        register(entity)
    end)
    inst:ListenForEvent("onremove", function(entity)
        local groups = registry(entity)
        if groups then groups:Unregister(entity) end
    end)
    inst:DoTaskInTime(0, register)
    return inst
end

local placer=MakePlacer("agribot_placer", "winona_storage_robot", "winona_storage_robot", "idle_off",
    nil,nil,nil,nil,nil,nil,require("agri/work_range").SetupPlacer)
placer.deps={"reticuleaoe"}
return Prefab("agribot", fn, assets, prefabs),placer
