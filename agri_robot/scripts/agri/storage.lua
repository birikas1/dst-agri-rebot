-- Agricultural classification and finite, real-item transfers. Native API facts:
-- SOURCE_VERIFICATION.md (build 756039); this module never creates resources.
local C = require("agri/constants")
local M = {}
local crop_seeds, crops, oversized = {}, {}, {}
local ok, native = pcall(require, "prefabs/farm_plant_defs")
if ok and native and native.PLANT_DEFS then
    for _, def in pairs(native.PLANT_DEFS) do
        if type(def) == "table" and not def.is_randomseed then
            if def.seed then crop_seeds[def.seed] = def end
            if def.product then crops[def.product] = def end
            if def.product_oversized then oversized[def.product_oversized] = def end
        end
    end
end

function M.Valid(item)
    return item ~= nil and item.IsValid ~= nil and item:IsValid()
end

function M.Count(item)
    if not M.Valid(item) then return 0 end
    local stack = item.components and item.components.stackable
    return stack and stack:StackSize() or 1
end

function M.IsSeed(item)
    if not item then return false end
    if item.prefab == "seeds" or crop_seeds[item.prefab] then return true end
    -- farmplantable is the native farm-soil system; planted vegetation uses
    -- deployable/plantable and is deliberately not treated as a farm seed.
    if item.components and item.components.farmplantable ~= nil then return true end
    if TheWorld and TheWorld.ismastersim then return false end
    return item.HasTag ~= nil and item:HasTag("deployedfarmplant")
end

function M.IsFertilizer(item)
    return item ~= nil and ((item.components and item.components.fertilizer ~= nil)
        or (item.HasTag and item:HasTag("fertilizer"))) or false
end

function M.IsCrop(item)
    return item ~= nil and not M.IsSeed(item) and crops[item.prefab] ~= nil
end

function M.IsWateringCan(item)
    if item == nil or item.HasTag == nil or not item:HasTag("wateringcan") then return false end
    if TheWorld and TheWorld.ismastersim then
        return item.components ~= nil and item.components.finiteuses ~= nil
            and item.components.fillable ~= nil and item.components.wateryprotection ~= nil
    end
    return true
end

-- A collected plow is returned to the warehouse, never used by the robot.
function M.IsRecyclable(item)
    return item ~= nil and item.prefab == "farm_plow_item"
end

function M.Category(item)
    if M.IsSeed(item) then return "seed" end
    if M.IsFertilizer(item) then return "fertilizer" end
    if M.IsCrop(item) then return "crop" end
    if M.IsRecyclable(item) then return "recycle" end
    return nil
end

function M.CropDefinition(prefab)
    return crops[prefab] or crop_seeds[prefab] or oversized[prefab]
end

function M.WarehouseRange(category)
    local seeds, ferts = C.WAREHOUSE_SEED_SLOTS, C.WAREHOUSE_FERTILIZER_SLOTS
    if category == "seed" then return 1, seeds end
    if category == "fertilizer" then return seeds + 1, seeds + ferts end
    -- Recycled items share the output area with crops (25..48).
    if category == "crop" or category == "recycle" then return seeds + ferts + 1, seeds + ferts + C.WAREHOUSE_CROP_SLOTS end
    if category == "module" then return C.WAREHOUSE_MODULE_SLOT, C.WAREHOUSE_MODULE_SLOT end
    return nil, nil
end

function M.WarehouseTest(container, item, slot)
    if not item then return false end
    if slot == nil and (item.prefab == "bluegem" or item.prefab == "super_preserver_kit") then return true end
    if slot == C.WAREHOUSE_MODULE_SLOT then
        return item.prefab == "bluegem" or item.prefab == "super_preserver_kit"
    end
    local lo, hi = M.WarehouseRange(M.Category(item))
    if not lo then return false end
    return slot == nil or slot >= lo and slot <= hi
end

function M.RobotTest(container, item, slot)
    if not item then return false end
    local inst = container.inst
    local reserved = inst and inst._agri_reserved_slots
    if slot and reserved and reserved[slot] and not inst._agri_internal_transfer
        and reserved[slot] ~= item then return false end
    if slot == C.MODULE_SLOT then return item.prefab == "scale_thermostat_module" end
    -- Hidden legacy slot: only an old save's plow (during load) or a rollback
    -- of that same plow may sit here; players and organizing never use it.
    if slot == C.LEGACY_PLOW_SLOT then
        return M.IsRecyclable(item) and inst ~= nil
            and (inst._agri_legacy_load == true or inst._agri_internal_transfer == true)
    end
    if slot and slot >= C.TOOL_FIRST and slot <= C.TOOL_LAST then return M.ToolSlot(item)==slot end
    if slot and slot > C.WORK_SLOTS then
        return slot <= C.WORK_SLOTS + C.WATER_SLOTS and M.IsWateringCan(item)
    end
    if slot == nil then return true end
    return slot >= 1 and slot <= C.WORK_SLOTS and not M.IsWateringCan(item)
        and item.prefab ~= "scale_thermostat_module"
end

function M.ToolSlot(item)
    if not item or M.IsRecyclable(item) then return nil end
    if item.components and item.components.farmtiller or item.prefab=="fumarole_farm_hoe" then return 26 end
    local byprefab={farm_hoe=26,shovel=27,goldenshovel=27,fumaroleshovel=27,hammer=28,fumarolehammer=28,axe=29,goldenaxe=29,fumaroleaxe=29,pickaxe=30,goldenpickaxe=30,fumarolepickaxe=30}
    if byprefab[item.prefab] then return byprefab[item.prefab] end
    local tool=item.components and item.components.tool
    if tool and ACTIONS then
        for _,pair in ipairs({{"DIG",27},{"HAMMER",28},{"CHOP",29},{"MINE",30}}) do
            if ACTIONS[pair[1]] and tool:CanDoAction(ACTIONS[pair[1]]) then return pair[2] end
        end
    end
    return nil
end

function M.Items(container)
    local out = {}
    for slot, item in pairs(container and (container.slots or container.itemslots) or {}) do
        if M.Valid(item) then out[#out + 1] = { slot = slot, item = item } end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end

function M.Slot(container, item)
    if not container or not item then return nil end
    if container.GetItemSlot then return container:GetItemSlot(item) end
    for slot, other in pairs(container.slots or container.itemslots or {}) do
        if other == item then return slot end
    end
end

function M.CanStack(a, b)
    local stack = a and a.components and a.components.stackable
    return stack ~= nil and M.Valid(b) and a.prefab == b.prefab
        and (not stack.IsFull or not stack:IsFull())
        and (not stack.CanStackWith or stack:CanStackWith(b))
end

function M.FreeSlots(container, lo, hi)
    local count = 0
    local slots = container and (container.slots or container.itemslots) or {}
    for slot = lo, hi do if slots[slot] == nil then count = count + 1 end end
    return count
end

function M.FindSlot(container, item, lo, hi, prefer)
    if not container or not M.Valid(item) then return nil end
    local slots = container.slots or container.itemslots or {}
    lo, hi = lo or 1, hi or container.numslots or container.maxslots or C.WORK_SLOTS
    local function allowed(slot)
        return not container.itemtestfn or container.itemtestfn(container, item, slot)
    end
    if prefer and prefer >= lo and prefer <= hi and allowed(prefer)
        and (slots[prefer] == nil or M.CanStack(slots[prefer], item)) then return prefer end
    for slot = lo, hi do
        if allowed(slot) and M.CanStack(slots[slot], item) then return slot end
    end
    for slot = lo, hi do if slots[slot] == nil and allowed(slot) then return slot end end
end

function M.Insert(container, item, lo, hi, prefer)
    if not M.Valid(item) then return true end
    -- GiveItem can fill an existing stack and leave a real remainder. Continue
    -- through other compatible slots before reporting a full destination.
    local attempted = {}
    while M.Valid(item) do
        local slot = M.FindSlot(container, item, lo, hi, prefer)
        if not slot or attempted[slot] then return false end
        attempted[slot] = true
        container:GiveItem(item, slot, nil, false)
        if not M.Valid(item) or M.Slot(container, item) or container.activeitem == item then return true end
        prefer = nil
    end
    return true
end

function M.Transfer(source, dest, item, count, lo, hi)
    if not M.Valid(item) or not source or not dest then return false, "invalid_item" end
    local original = M.Slot(source, item)
    if not original then return false, "ownership_changed" end
    if not M.FindSlot(dest, item, lo, hi) then return false, "destination_full" end
    local moving = item
    local stack = item.components.stackable
    if count ~= nil and (type(count) ~= "number" or count ~= count or count <= 0 or count == math.huge) then
        return false, "invalid_count"
    end
    local requested = math.max(1, math.floor(count or M.Count(item)))
    if stack and requested < stack:StackSize() then
        moving = stack:Get(requested)
    else
        moving = source:RemoveItem(item, true)
    end
    if not M.Valid(moving) then return false, "ownership_changed" end
    if M.Insert(dest, moving, lo, hi) then return true end
    -- Event handlers can invalidate a destination during a transfer. Keep the
    -- same item; never spawn a replacement or silently discard the remainder.
    local source_hi = source.numslots or source.maxslots or C.MODULE_SLOT
    if not M.Insert(source, moving, 1, source_hi, original) then
        return false, "rollback_blocked", moving
    end
    return false, "destination_full"
end

return M
