local M = {}
M.PRIORITY = { EMERGENCY = 0, VIABILITY = 1, BLOCKER = 2, NORMAL = 3 }
M.KINDS = {}
for _, name in ipairs({ "PLOW", "TILL", "PLANT", "FERTILIZE", "WATER", "TEND", "MUSIC_TEND",
    "HARVEST", "HAMMER", "PICKUP", "REFILL", "HEAT", "UNLOAD", "FETCH", "CLEAR" }) do M.KINDS[name] = true end
M.TERMINAL = { complete = true, cancelled = true, failed = true }
-- PLOW stays a known kind so an already deployed native plow is still
-- tracked to completion, but it has no native action: nothing is deployed.
M.ACTIONS = { TILL = "TILL", PLANT = "PLANTSOIL", FERTILIZE = "DEPLOY_TILEARRIVE",
    WATER = "POUR_WATER_GROUNDTILE", TEND = "INTERACT_WITH", HARVEST = "PICK", HAMMER = "HAMMER", PICKUP = "PICKUP", REFILL = "FILL" }
M.RESOURCE_REASONS = { need_fetch = true, output_full = true, working_inventory_full = true,
    out_of_water = true, no_empty_can = true, missing_seed = true, missing_fertilizer = true,
    missing_tool = true, needs_heat = true, no_water_source = true, no_furnace = true,
    warehouse_full = true, resources_unavailable = true, no_warehouse = true }
M.REASONS = {
    output_full = "产物空间不足，等待仓库或背包腾出空间。", working_inventory_full = "临时库存未能归还，已暂停等待空间。",
    out_of_water = "水壶缺水，正在准备集中补水。", no_water_source = "范围内没有可用水源。",
    no_furnace = "没有找到可用的龙鳞炉，热能工具已暂停使用。", no_warehouse = "没有可用仓库，请绑定农业仓库。",
    warehouse_full = "仓库对应分类已满，请腾出空间。", missing_seed = "本轮种子不足。", missing_fertilizer = "本轮肥料不足。",
    missing_tool = "缺少可用工具。", path_timeout = "无法到达目标，已停止重试。", blocked_structure = "孔位被建筑或未知实体阻挡，请手动处理。",
    invalid_terrain = "目标地形不允许耕作。", resources_unavailable = "仓库中没有足够的所需物资。",
    needs_heat = "热能工具需要维护。", heat_timeout = "炉边升温未达可用温度，请检查炉子和环境。",
    action_rejected = "原版动作持续拒绝，已保留任务等待处理。", safety_stop = "发现不可安全处理的目标。",
    moisture_unknown = "读不到这块农田的土壤湿度，本次没有浇水。",
    WATER_MOISTURE_UNKNOWN = "读不到农田土壤湿度，无法判断是否需要浇水。", WATER_NO_CAN = "作物缺水，但没有找到水壶。",
    WATER_CAN_NOT_CARRIED = "作物缺水：水壶在仓库里，请放进机器人的水壶格。", WATER_NO_SOURCE = "作物缺水，水壶已空，范围内没有可用水源。",
    plow_disabled = "自动耕地已关闭，这个旧的耕地任务不会执行；请手动开垦农田。",
    recycle_no_warehouse = "捡到的耕地机暂留在机器人里：请绑定农业仓库。",
    recycle_warehouse_full = "仓库作物/回收区已满，捡到的耕地机暂留在机器人里。",
    legacy_plow_stuck = "旧工具格里的耕地机没地方放：请腾出工作库存或仓库作物/回收区。",
    NEED_FARMLAND = "农田不够：请手动用耕地机开垦，机器人不会自动耕地。",
}
function M.Normalize(task)
    task.kind = string.upper(task.kind or "")
    if not M.KINDS[task.kind] or type(task.id) ~= "string" then return nil end
    task.priority = math.max(1, math.min(3, tonumber(task.priority) or 3))
    task.deps, task.data = task.deps or {}, task.data or {}
    task.state = task.state or "pending"
    task.retries = task.retries or 0
    return task
end
function M.IsDone(task) return task ~= nil and (task.state == "complete" or task.state == "cancelled" and task.cancel_satisfies == true) end
function M.Message(reason) return M.REASONS[reason] or ("任务已暂停：" .. tostring(reason or "未知原因")) end
return M
