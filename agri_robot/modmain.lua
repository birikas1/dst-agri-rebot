PrefabFiles = { "agribot", "agriwarehouse", "super_preserver_kit", "scale_thermostat_module" }
local G = GLOBAL
local C = require("agri/constants")
G.STRINGS.NAMES.AGRIBOT = "农业机器人"
G.STRINGS.NAMES.AGRIWAREHOUSE = "农业仓库"
G.STRINGS.NAMES.SUPER_PRESERVER_KIT = "超级保鲜套件"
G.STRINGS.NAMES.SCALE_THERMOSTAT_MODULE = "龙鳞恒温模块"
G.STRINGS.RECIPE_DESC.AGRIBOT = "带上真实工具，一起照料田地。"
G.STRINGS.RECIPE_DESC.AGRIWAREHOUSE = "种子、肥料和收成，各有位置。"
G.STRINGS.RECIPE_DESC.SUPER_PRESERVER_KIT = "把农场的丰收保存得更久。"
G.STRINGS.RECIPE_DESC.SCALE_THERMOSTAT_MODULE = "让机器人携带的热能工具保持70°C。"
G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.AGRIBOT = "它在等工具和下一轮种子。"
G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.AGRIWAREHOUSE = "储存下一轮希望，也储存这一轮收获。"
G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.SUPER_PRESERVER_KIT = "放进农业仓库顶部的模块槽。"
G.STRINGS.CHARACTERS.GENERIC.DESCRIBE.SCALE_THERMOSTAT_MODULE = "放进农业机器人的模块槽。"

require("agri/containers").Register(env)
require("agri/recipes").Register(env)

AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then return end
    inst:AddComponent("agrifarmgroup")
    inst:AddComponent("agriblueprint")
    inst:ListenForEvent("entity_spawned",function(_,entity)
        if entity.prefab~="farm_plow_item" then return end
        local registry=inst.components.agrifarmgroup
        for _,group in pairs(registry.groups) do
            local scheduler=group.scheduler
            for _,task in pairs(scheduler and scheduler.tasks or {}) do
                local machine=task.kind=="PLOW" and task.target
                if task.continuation and task.continuation.phase=="plowing"
                    and machine and machine.prefab=="farm_plow" and machine:IsValid()
                    and machine.deploy_item_save_record~=nil then
                    require("agri/source_adapter").WakeReturnedPlowAtSpawn(entity)
                    return
                end
            end
        end
    end)
end)

require("agri/network").Register(env)
if GetModConfigData("debug_log") then print("[AgriRobot] " .. C.VERSION .. " / source ledger build " .. C.SOURCE_BUILD) end
