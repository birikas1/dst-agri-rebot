local C = require("agri/constants")
local S = require("agri/storage")
local T = require("agri/task_types")
local U = require("agri/util")
local function kind(task) return string.upper(task and task.kind or "") end
local function equipmentrequest(task)
    local k=kind(task)
    if k~="TILL" and k~="HAMMER" and k~="CLEAR" and k~="WATER" and k~="REFILL" and k~="HEAT" then return nil end
    local d=task.data or {}
    return {kind=k,prefab=task.prefab,data={can_guid=d.can_guid,item_guid=d.item_guid,
        tool_action=d.tool_action,action=type(d.action)=="table" and d.action.id or d.action}}
end
local function uses(item)
    local finite = item.components and item.components.finiteuses
    return finite and finite:GetUses() or S.Count(item)
end
local function capacity(item)
    local finite = item.components and item.components.finiteuses
    return finite and finite.total or uses(item)
end
local function validvector(v)
    return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
        and v[1] >= 0 and v[2] >= 0 and v[3] >= 0
end
local function inventoryitems(inventory)
    local out = {}
    for slot, item in pairs(inventory and inventory.itemslots or {}) do
        if S.Valid(item) then out[#out + 1] = { slot = slot, item = item } end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    if inventory and S.Valid(inventory.activeitem) then out[#out + 1] = { item = inventory.activeitem } end
    return out
end

local AgriResource = Class(function(self, inst)
    self.inst = inst
    self.borrowed = nil
    self.current = nil
    inst._agri_reserved_slots = {}
    -- Native container load gives each saved item back to its saved slot and
    -- drops it if the slot test refuses. An old save's plow sits in hidden
    -- slot 25; accept it there until the first frame, then move it out.
    inst._agri_legacy_load = true
    local function changed()
        local registry = TheWorld.components.agrifarmgroup
        if registry then registry:MarkDirty(registry:GetGroup(inst), "resources") end
        if not self.organizing then inst:DoTaskInTime(0,function()self:OrganizeTools()end) end
    end
    inst:ListenForEvent("itemget", changed)
    inst:ListenForEvent("itemlose", changed)
    inst:DoTaskInTime(0, function() inst._agri_legacy_load = nil; self:Recover() end)
end)

function AgriResource:OwnItems()
    local out, seen = {}, {}
    for _, component in ipairs({ self.inst.components.container, self.inst.components.inventory }) do
        local entries = component.slots and S.Items(component) or inventoryitems(component)
        for _, entry in ipairs(entries) do
            if not seen[entry.item] then
                seen[entry.item] = true
                out[#out + 1] = entry.item
            end
        end
    end
    return out
end

function AgriResource:Snapshot(group)
    local out = {
        seeds = {}, fertilizers = {},
        water = { uses = 0, capacity = 0, per_use = 0, has_source = false, cans = {} },
        -- The plow is no longer a robot tool; collected plows are only cargo.
        tools = { hoe = { count = 0, uses = 0 }, hammer = { count = 0, uses = 0 },
            shovel = { count = 0, uses = 0 }, axe = { count = 0, uses = 0 }, pickaxe = { count = 0, uses = 0 } },
        recycle = { carried = 0, stored = 0 },
        space = { robot_free = 0, warehouse_free = 0, output_blocked = false }, music = false,
    }
    local seen = {}
    local function addtool(name, item)
        local tool = out.tools[name]
        local thermal = item.components.fumaroletool
        if thermal then
            tool.thermal = true
            tool.temperature = item.components.inventoryitem:GetTemperature()
            local owner = item.components.inventoryitem:GetGrandOwner()
            local manager = owner and owner.components and owner.components.agrithermal
            local renewable = manager and (manager:HasModule() or manager:FindFurnace(group) ~= nil)
            tool.replenishable = tool.replenishable or renewable or false
            if thermal.broken then tool.coldcount = (tool.coldcount or 0) + 1; return end
            local heatonuse = thermal.heatonuse
            local thresholds = TUNING.FUMAROLETOOL_TEMPS
            local budget = type(heatonuse) == "number" and heatonuse < 0
                and math.max(0, math.floor((tool.temperature - thresholds[1]) / -heatonuse)) or nil
            if budget == nil then tool.heat_capacity_unverified = true end
            tool.count, tool.uses, tool.ready = tool.count + 1, tool.uses + (budget or 0), true
            return
        end
        if uses(item) <= 0 then return end
        tool.count, tool.uses, tool.ready = tool.count + 1, tool.uses + uses(item), true
    end
    local function collect(item, stored)
        if not S.Valid(item) or seen[item] then return end
        seen[item] = true
        if S.IsSeed(item) then
            out.seeds[item.prefab] = (out.seeds[item.prefab] or 0) + S.Count(item)
        elseif S.IsFertilizer(item) then
            local f = item.components.fertilizer
            local entry = out.fertilizers[item.prefab] or { count = 0, automatic = false }
            entry.count = entry.count + uses(item)
            if f and validvector(f.nutrients) and item.components.deployable then
                entry.nutrients = { f.nutrients[1], f.nutrients[2], f.nutrients[3] }
                entry.automatic = true
            end
            out.fertilizers[item.prefab] = entry
        end
        if S.IsWateringCan(item) then
            local n, max = uses(item), capacity(item)
            local wetness = item.components.wateryprotection and item.components.wateryprotection.addwetness or 0
            out.water.uses, out.water.capacity = out.water.uses + n, out.water.capacity + max
            if wetness > 0 and (out.water.per_use == 0 or wetness < out.water.per_use) then out.water.per_use = wetness end
            -- Stored cans are available via a real FETCH trip before use.
            out.water.cans[#out.water.cans + 1] = { guid = item.GUID, prefab = item.prefab, uses = n, capacity = max, addwetness = wetness, carried = not stored }
        end
        if item.components.farmtiller or item.prefab == "fumarole_farm_hoe" then addtool("hoe", item) end
        if S.IsRecyclable(item) then
            local key = stored and "stored" or "carried"
            out.recycle[key] = out.recycle[key] + S.Count(item)
            return
        end
        if item.prefab == "fumarolehammer" or item.components.tool and item.components.tool:CanDoAction(ACTIONS.HAMMER) then addtool("hammer", item) end
        for _, mapping in ipairs({ { "shovel", "DIG", "fumaroleshovel" }, { "axe", "CHOP", "fumaroleaxe" }, { "pickaxe", "MINE", "fumarolepickaxe" } }) do
            local action = ACTIONS[mapping[2]]
            if item.prefab == mapping[3] or action and item.components.tool and item.components.tool:CanDoAction(action) then addtool(mapping[1], item) end
        end
        if item:HasTag("phonograph_record") then out.music = true end
    end
    local members = group and group.members or { self.inst }
    for _, robot in ipairs(members) do
        if S.Valid(robot) and robot.components.agriresource then
            for _, item in ipairs(robot.components.agriresource:OwnItems()) do collect(item) end
            out.space.robot_free = out.space.robot_free + S.FreeSlots(robot.components.container, 1, C.WORK_SLOTS)
        end
    end
    if group and S.Valid(group.warehouse) and group.warehouse.components.container then
        local warehouse = group.warehouse.components.container
        for _, entry in ipairs(S.Items(warehouse)) do collect(entry.item, true) end
        out.space.warehouse_free = S.FreeSlots(warehouse, 1, C.WAREHOUSE_MODULE_SLOT - 1)
    end
    local x, _, z = self.inst.Transform:GetWorldPosition()
    if group and group.center then x, z = group.center.x, group.center.z end
    local sources = TheSim:FindEntities(x, 0, z, group and group.settings.radius or C.DEFAULT_RADIUS,
        { "watersource" }, { "INLIMBO" })
    local nearest=require("agri/water_sources").Pick(sources,self.inst)
    out.water.source, out.water.has_source = nearest, nearest ~= nil
    out.space.output_blocked = out.space.robot_free == 0 and out.space.warehouse_free == 0
    return out
end

function AgriResource:CanUnload(group)
    local warehouse = group and group.warehouse
    return S.Valid(warehouse) and warehouse.components.container ~= nil and self.inst:GetDistanceSqToInst(warehouse) <= 16
end

local function needcategory(task)
    local k = kind(task)
    return k == "PLANT" and "seeds" or k == "FERTILIZE" and "fertilizers" or nil
end
local function holder(scheduler, id, live)
    local claims = scheduler and scheduler.claims
    local claim = id ~= nil and claims and claims.Get and claims:Get(id)
    if claim then return claim.owner end
    return type(live.owner) == "table" and live.owner.GUID or nil
end
-- Live planting/fertilizing work, once per stable id: the current plan first,
-- then scheduler tasks an older scan created that a fresh plan omitted
-- (a transient blocker, a suspended parent, a rescan during logistics).
-- Terminal, orphaned and non-resource-blocked stale work holds nothing.
local function demandentries(group)
    local out, seen = {}, {}
    local scheduler = group and group.scheduler
    local tasks = scheduler and scheduler.tasks or {}
    local function add(id, entry, live, planned)
        if id ~= nil then
            if seen[id] then return end
            seen[id] = true
        end
        local into = needcategory(live and live.kind and live or entry)
        local prefab = live and live.prefab or entry.prefab
        local state = live and live.state or entry.state
        if not into or not prefab or T.TERMINAL[state] or state == "done" then return end
        if live and scheduler.Orphaned and scheduler:Orphaned(live) then return end
        -- Work of a zone the player paused or is editing (group.zone_holds)
        -- reserves nothing, so it cannot exhaust another zone's batch. Only
        -- these intentional holds count: priority-paused parents and P2
        -- suspended work keep their seeds.
        local holds = group and group.zone_holds
        if holds and next(holds) ~= nil then
            local zone
            if live and scheduler.ZoneOf then zone = scheduler:ZoneOf(live)
            else zone = (entry.data or {}).zone_id end
            if zone ~= nil and holds[zone] then return end
        end
        local owner = live and holder(scheduler, id, live)
        if state == "blocked" and not planned and not owner and not T.RESOURCE_REASONS[live and live.reason or entry.reason] then return end
        local count = (live and live.count or entry.count or 1) - (live and live.count_done or 0)
        if count > 0 then
            out[#out + 1] = { id = id, category = into, prefab = prefab, count = count, owner = owner, runnable = state ~= "blocked" }
        end
    end
    for _, entry in ipairs(group and group.plan and group.plan.tasks or {}) do
        add(entry.id, entry, entry.id ~= nil and tasks[entry.id] or nil, true)
    end
    local order = scheduler and scheduler.order
    if not order then
        order = {}
        for id in pairs(tasks) do if type(id) == "string" then order[#order + 1] = id end end
        table.sort(order)
    end
    for _, id in ipairs(order) do
        local live = tasks[id]
        if live and live.kind then add(id, live, live, scheduler.plan_ids and scheduler.plan_ids[id]) end
    end
    return out
end

-- Seeds and fertilizers this robot should hold for live work.
-- Without retain: a bounded FETCH batch that always starts with the requested
-- task (reported as needs.primary) and skips blocked work. With retain: what
-- UNLOAD keeps, every live job without the batch cutoff. Work claimed by
-- another robot is that robot's; unclaimed work is first covered by what the
-- other robots carry beyond their own claims (for retention only those listed
-- before this one), so the group never counts the same stock twice.
function AgriResource:Demand(group, task, retain)
    local equipment=not retain and equipmentrequest(task)
    if equipment then return {equipment_task=equipment,seeds={},fertilizers={}} end
    local own, pool = { seeds = {}, fertilizers = {} }, { seeds = {}, fertilizers = {} }
    local me = self.inst and self.inst.GUID
    local entries = demandentries(group)
    local claimed, considered = {}, 0
    local primary = task and task.prefab and needcategory(task)
    if primary then
        local count = math.max(1, (task.count or 1) - (task.count_done or 0))
        own[primary][task.prefab] = count
        primary = { category = primary, prefab = task.prefab, count = count }
        considered = 1
    end
    for _, entry in ipairs(entries) do
        if entry.owner ~= nil then
            local by = claimed[entry.owner] or { seeds = {}, fertilizers = {} }
            by[entry.category][entry.prefab] = (by[entry.category][entry.prefab] or 0) + entry.count
            claimed[entry.owner] = by
        end
        local current = task and entry.id ~= nil and entry.id == task.id
        local mine = me ~= nil and entry.owner == me
        if not current and (mine or entry.owner == nil or me == nil)
            and (retain or entry.runnable and considered < C.WORK_SLOTS * 2) then
            local into = (mine and own or pool)[entry.category]
            into[entry.prefab] = (into[entry.prefab] or 0) + entry.count
            considered = considered + 1
        end
    end
    if me ~= nil then
        for _, robot in ipairs(group and group.members or {}) do
            if robot == self.inst then
                if retain then break end
            elseif S.Valid(robot) and robot.components and robot.components.agriresource then
                local resource, by = robot.components.agriresource, claimed[robot.GUID]
                for category, prefabs in pairs(pool) do
                    for prefab, amount in pairs(prefabs) do
                        local spare = resource:CountPrefab(prefab, category == "fertilizers") - (by and by[category][prefab] or 0)
                        if spare > 0 then prefabs[prefab] = math.max(0, amount - spare) end
                    end
                end
            end
        end
    end
    local needs = { seeds = {}, fertilizers = {}, primary = primary }
    for _, category in ipairs({ "seeds", "fertilizers" }) do
        for _, source in ipairs({ own[category], pool[category] }) do
            for prefab, amount in pairs(source) do
                if amount > 0 then needs[category][prefab] = (needs[category][prefab] or 0) + amount end
            end
        end
    end
    return needs
end

function AgriResource:CountPrefab(prefab, actionuses)
    local n = 0
    for _, item in ipairs(self:OwnItems()) do
        if item.prefab == prefab then n = n + (actionuses and uses(item) or S.Count(item)) end
    end
    return n
end

-- Whether the bound warehouse holds the task's input right now (true when
-- there is no readable warehouse, so the executor reports that instead).
function AgriResource:WarehouseStocks(group, task)
    local warehouse = group and group.warehouse
    local container = S.Valid(warehouse) and warehouse.components and warehouse.components.container
    if not container then return true end
    local k = kind(task)
    for _, entry in ipairs(S.Items(container)) do
        local item = entry.item
        if item.prefab == task.prefab and (k == "PLANT" and S.IsSeed(item) or k == "FERTILIZE" and uses(item) > 0) then return true end
    end
    return false
end

function AgriResource:Fetch(group, requirements)
    if not self:CanUnload(group) then return false, "need_fetch" end
    local source, dest = group.warehouse.components.container, self.inst.components.container
    local needs = requirements or self:Demand(group)
    if needs.equipment_task then
        local request=needs.equipment_task
        if self:FindSuppliedEquipment(request) then return true end
        local item=self:FindWarehouseActionItem(group,request)
        if not item then return false,"resources_unavailable" end
        local lo,hi
        if S.IsWateringCan(item) then lo,hi=C.WORK_SLOTS+1,C.WORK_SLOTS+C.WATER_SLOTS
        else lo=S.ToolSlot(item);hi=lo end
        if not lo or not S.FindSlot(dest,item,lo,hi) then return false,"equipment_slot_full" end
        local moved,reason,stranded=S.Transfer(source,dest,item,nil,lo,hi)
        if stranded then self:KeepStranded(stranded) end
        return moved,not moved and (reason or "resources_unavailable") or nil
    end
    local complete, progress = true, false
    local function pull(category, prefab, target)
        local actionuses = category == "fertilizers"
        local start = self:CountPrefab(prefab, actionuses)
        local missing = math.max(0, (target or 0) - start)
        for _, entry in ipairs(S.Items(source)) do
            if missing > 0 and entry.item.prefab == prefab then
                local before = self:CountPrefab(prefab, actionuses)
                local n = actionuses and entry.item.components.finiteuses and 1 or missing
                local moved, reason, stranded = S.Transfer(source, dest, entry.item, n, 1, C.WORK_SLOTS)
                if stranded then self:KeepStranded(stranded) end
                missing = math.max(0, missing - self:CountPrefab(prefab, actionuses) + before)
                if not moved and reason == "destination_full" then break end
            end
        end
        if self:CountPrefab(prefab, actionuses) > start then progress = true end
        return missing
    end
    -- The requested action's own input goes first, so optional batch inputs
    -- never take the space or the stock it needs.
    local primary = needs.primary
    if primary and primary.prefab then pull(primary.category, primary.prefab, primary.count or 1) end
    for _, category in ipairs({ "seeds", "fertilizers" }) do
        local prefabs = {}
        for prefab in pairs(needs[category] or {}) do prefabs[#prefabs + 1] = prefab end
        table.sort(prefabs)
        for _, prefab in ipairs(prefabs) do
            local target = needs[category][prefab]
            target = type(target) == "table" and target.count or target
            if pull(category, prefab, target) > 0 then complete = false end
        end
    end
    -- A missing future batch input never fails the trip once the current
    -- action's real input is carried; only the current input decides.
    if primary and primary.prefab then
        local ready = self:CountPrefab(primary.prefab, primary.category == "fertilizers") > 0
        return ready, not ready and "resources_unavailable" or nil
    end
    if complete or progress then return true end
    return false, "resources_unavailable"
end

function AgriResource:Unload(group)
    if not self:CanUnload(group) then return false, "need_unload" end
    local source, dest = self.inst.components.container, group.warehouse.components.container
    -- Only seeds no live planting (in or out of the current plan) still needs.
    local demand = self:Demand(group, nil, true)
    local moved, full = 0, false
    for _, entry in ipairs(S.Items(source)) do
        local item, category = entry.item, S.Category(entry.item)
        -- Collected plows leave from work inventory and the legacy slot 25.
        if entry.slot <= C.WORK_SLOTS or category == "recycle" then
            local keep = category == "seed" and (demand.seeds[item.prefab] or 0) or 0
            local amount = (category == "crop" or category == "recycle") and S.Count(item)
                or category == "seed" and math.max(0, self:CountPrefab(item.prefab) - keep) or 0
            if amount > 0 then
                local lo, hi = S.WarehouseRange(category)
                -- A failed move may roll a legacy plow back into slot 25.
                self.inst._agri_internal_transfer = category == "recycle" or nil
                local success, _, stranded = S.Transfer(source, dest, item, amount, lo, hi)
                self.inst._agri_internal_transfer = nil
                if stranded then self:KeepStranded(stranded) end
                if success then moved = moved + 1 else full = true end
            end
        end
    end
    -- A plow stranded in the action bridge by an earlier rollback.
    local inventory = self.inst.components.inventory
    for _, entry in ipairs(inventoryitems(inventory)) do
        if entry.slot and S.IsRecyclable(entry.item) then
            local lo, hi = S.WarehouseRange("recycle")
            local success, _, stranded = S.Transfer(inventory, dest, entry.item, nil, lo, hi)
            if stranded then self:KeepStranded(stranded) end
            if success then moved = moved + 1 else full = true end
        end
    end
    self:Recover()
    return moved > 0 or not full, full and "warehouse_full" or nil
end

function AgriResource:CarriedRecyclables()
    local out = {}
    for _, entry in ipairs(S.Items(self.inst.components.container)) do
        if S.IsRecyclable(entry.item) then out[#out + 1] = entry.item end
    end
    -- Bridge slots only, as Unload moves them; an active item has no slot.
    for _, entry in ipairs(inventoryitems(self.inst.components.inventory)) do
        if entry.slot and S.IsRecyclable(entry.item) then out[#out + 1] = entry.item end
    end
    return out
end

-- Why carried plows cannot go to the warehouse right now (nil: they can),
-- plus how many are carried. The plows stay in the robot meanwhile.
function AgriResource:RecycleBlocked(group)
    local items = self:CarriedRecyclables()
    if #items == 0 then return nil, 0 end
    if group == nil then
        local registry = TheWorld.components.agrifarmgroup
        group = registry and registry:GetGroup(self.inst)
    end
    local warehouse = group and S.Valid(group.warehouse) and group.warehouse.components.container
    if not warehouse then return "recycle_no_warehouse", #items end
    local lo, hi = S.WarehouseRange("recycle")
    if not S.FindSlot(warehouse, items[1], lo, hi) then return "recycle_warehouse_full", #items end
    return nil, #items
end

function AgriResource:NeedsUnload(force)
    local crops = 0
    for _, entry in ipairs(S.Items(self.inst.components.container)) do
        if S.IsCrop(entry.item) then crops = crops + 1 end
    end
    -- A carried plow is unloaded at once, but only when the warehouse can
    -- take it; otherwise it stays in the robot with a visible reason.
    local blocked, plows = self:RecycleBlocked()
    for _, code in ipairs({ "recycle_no_warehouse", "recycle_warehouse_full" }) do
        if blocked == code then U.OnceTalk(self.inst, code, T.Message(code)) else U.ClearTalk(self.inst, code) end
    end
    if plows > 0 and blocked == nil then return true end
    return crops > 0 and (force == true or crops >= 3 or S.FreeSlots(self.inst.components.container, 1, C.WORK_SLOTS) <= 2)
end

function AgriResource:HasOutputSpace(task)
    local container = self.inst.components.container
    if #inventoryitems(self.inst.components.inventory) > 0 and not self.current then return false end
    local target = task and task.target
    local definition = target and (target.plant_def or S.CropDefinition(target.prefab))
    local outputs = task and task.data and task.data.expected_outputs or {}
    if kind(task) == "PICKUP" and target then outputs = { [target.prefab] = S.Count(target) }
    elseif definition then
        -- A missing native quantity is unknown, not one free use. Until a
        -- precise quantity is supplied, reserve a whole empty slot per output.
        if not next(outputs) then
            if definition.product then outputs[definition.product] = false end
            if definition.seed then outputs[definition.seed] = false end
        end
    end
    local needed = 0
    for prefab, amount in pairs(outputs) do
        local remaining = type(amount) == "number" and math.max(0, math.ceil(amount)) or nil
        local maxstack
        for _, entry in ipairs(S.Items(container)) do
            local stack = entry.item.components.stackable
            if entry.slot <= C.WORK_SLOTS and entry.item.prefab == prefab and stack
                and (kind(task) ~= "PICKUP" or stack:CanStackWith(target)) then
                maxstack = type(stack.maxsize) == "number" and stack.maxsize or maxstack
                if remaining and maxstack then remaining = math.max(0, remaining - math.max(0, maxstack - stack:StackSize())) end
            end
        end
        if remaining == nil then needed = needed + 1
        elseif remaining > 0 then
            if kind(task) == "PICKUP" and target.components.stackable then maxstack = target.components.stackable.maxsize end
            needed = needed + (maxstack and math.ceil(remaining / maxstack) or 1)
        end
    end
    if next(outputs) == nil then needed = 1 end
    return S.FreeSlots(container, 1, C.WORK_SLOTS) >= needed
end

function AgriResource:ReserveOutputSlots(task)
    local k = kind(task)
    if k ~= "HARVEST" and k ~= "HAMMER" and k ~= "PICKUP" and k ~= "CLEAR" then return end
    local slots = self.inst.components.container.slots
    for slot = 1, C.WORK_SLOTS do
        if slots[slot] == nil then self.inst._agri_reserved_slots[slot] = true end
    end
end

function AgriResource:HasRecord()
    for _, item in ipairs(self:OwnItems()) do if item:HasTag("phonograph_record") then return true end end
    return false
end

function AgriResource:FindActionItem(task,container)
    local k, candidate = kind(task), nil
    local desired = task.prefab
    local requested_guid = task.data and (task.data.can_guid or task.data.item_guid)
    for _, entry in ipairs(S.Items(container or self.inst.components.container)) do
        local item = entry.item
        local eligible = not requested_guid or item.GUID == requested_guid
        if eligible and k == "PLANT" and item.prefab == desired and S.IsSeed(item) then return item end
        if eligible and k == "FERTILIZE" and item.prefab == desired and item.components.fertilizer and item.components.deployable
            and validvector(item.components.fertilizer.nutrients) and uses(item) > 0 then return item end
        if eligible and (k == "WATER" or k == "REFILL") and S.IsWateringCan(item)
            and (k == "REFILL" and uses(item) < capacity(item) or k == "WATER" and uses(item) > 0) then return item end
        -- PLOW never gets an item: automatic plowing is disabled.
        if eligible and k == "TILL" and (item.components.farmtiller or item.prefab == "fumarole_farm_hoe")
            and (item.components.fumaroletool or uses(item)>0) then
            if item.components.fumaroletool then candidate = item else return item end
        end
        local actionname = k == "HAMMER" and "HAMMER" or k == "CLEAR" and task.data and (task.data.tool_action or task.data.action)
        local action = type(actionname) == "table" and actionname or actionname and ACTIONS[actionname]
        local cold_prefabs = { HAMMER = "fumarolehammer", DIG = "fumaroleshovel", CHOP = "fumaroleaxe", MINE = "fumarolepickaxe" }
        if eligible and action and (item.components.tool and item.components.tool:CanDoAction(action)
            or type(actionname) == "string" and item.prefab == cold_prefabs[actionname])
            and (item.components.fumaroletool or uses(item)>0) then
            if item.components.fumaroletool then candidate = item else return item end
        end
        if eligible and k == "HEAT" and item.components.fumaroletool
            and (not desired or item.prefab == desired) then return item end
    end
    return candidate
end

-- An empty carried can is usable equipment: the next step refills it.
function AgriResource:FindSuppliedEquipment(task,container)
    local item=self:FindActionItem(task,container)
    if not item and kind(task)=="WATER" then
        item=self:FindActionItem({kind="REFILL",data=task.data},container)
    end
    return item
end
function AgriResource:FindWarehouseActionItem(group,task)
    if not equipmentrequest(task) then return nil end
    local warehouse=group and group.warehouse
    local container=S.Valid(warehouse) and warehouse.components and warehouse.components.container
    if container then return self:FindSuppliedEquipment(task,container) end
end

function AgriResource:Borrow(item, task)
    local source, inventory = self.inst.components.container, self.inst.components.inventory
    local slot = source:GetItemSlot(item)
    if not slot then return false, "ownership_changed" end
    if not S.FindSlot(inventory, item, 1, inventory.maxslots or C.WORK_SLOTS) then return false, "working_inventory_full" end
    self.inst._agri_reserved_slots[slot] = item
    local moved, reason, stranded = S.Transfer(source, inventory, item, nil, 1, inventory.maxslots or C.WORK_SLOTS)
    if stranded then self:KeepStranded(stranded) end
    if not moved then self.inst._agri_reserved_slots[slot] = nil; return false, reason end
    self.borrowed = { item = item, slot = slot }
    self.current = task
    task.invobject = item
    return true, nil, item
end

function AgriResource:Prepare(task, group)
    if self.current == task then return true, nil, self.borrowed and self.borrowed.item end
    if self.current then self:Finish(self.current, false) end
    if not self:Recover() then return false, "working_inventory_full" end
    local k = kind(task)
    if k == "PLOW" then return false, "plow_disabled" end
    if k == "HARVEST" or k == "HAMMER" or k == "PICKUP" or k == "CLEAR" then
        if not self:HasOutputSpace(task) then return false, "output_full" end
    end
    local requires = k == "TILL" or k == "PLANT" or k == "WATER"
        or k == "FERTILIZE" or k == "HAMMER" or k == "REFILL" or k == "HEAT"
        or k == "CLEAR" and task.data and (task.data.tool_action or task.data.action)
    if k == "MUSIC_TEND" and not self:HasRecord() then return false, "missing_record" end
    if not requires then self.current = task; self:ReserveOutputSlots(task); return true end
    local item = self:FindActionItem(task)
    if not item and equipmentrequest(task) and not self:FindSuppliedEquipment(task) then
        if self:FindWarehouseActionItem(group,task) then
            if not self:CanUnload(group) then return false,"need_fetch" end
            local fetched,reason=self:Fetch(group,self:Demand(group,task))
            if not fetched then return false,reason end
            item=self:FindActionItem(task)
        end
    end
    if not item and (k == "PLANT" or k == "FERTILIZE") then
        -- No trip to a warehouse that holds none of it: the task blocks with
        -- a visible reason and a resource change revives it.
        if not self:CanUnload(group) then
            if self:WarehouseStocks(group, task) then return false, "need_fetch" end
        else
            self:Fetch(group, self:Demand(group, task))
            item = self:FindActionItem(task)
        end
    end
    if not item then
        if k == "WATER" then return false, "out_of_water" end
        if k == "REFILL" then return false, "no_empty_can" end
        return false, k == "PLANT" and "missing_seed" or k == "FERTILIZE" and "missing_fertilizer" or "missing_tool"
    end
    if k ~= "HEAT" and self.inst.components.agrithermal:NeedsHeat(item) then
        task.data = task.data or {}
        task.data.heat_prefab = item.prefab
        return false, "needs_heat"
    end
    local ok, reason, borrowed = self:Borrow(item, task)
    if ok then self:ReserveOutputSlots(task) end
    return ok, reason, borrowed
end

function AgriResource:KeepStranded(item)
    if not S.Valid(item) then return end
    -- A rollback failure must retain its real item in the finite bridge.
    local inventory = self.inst.components.inventory
    local slot = S.FindSlot(inventory, item, 1, inventory.maxslots or C.WORK_SLOTS)
    if slot then inventory:GiveItem(item, slot) end
end

function AgriResource:Finish(task, success)
    local inventory, container = self.inst.components.inventory, self.inst.components.container
    local complete = true
    self.inst._agri_internal_transfer = true
    for _, entry in ipairs(inventoryitems(inventory)) do
        local item = entry.item
        local lo, hi = 1, C.WORK_SLOTS
        if S.IsWateringCan(item) then lo, hi = C.WORK_SLOTS + 1, C.WORK_SLOTS + C.WATER_SLOTS
        elseif item.prefab == "scale_thermostat_module" then lo, hi = C.MODULE_SLOT, C.MODULE_SLOT
        elseif S.ToolSlot(item) then lo,hi=S.ToolSlot(item),S.ToolSlot(item) end
        local prefer = self.borrowed and self.borrowed.item == item and self.borrowed.slot or nil
        local slot = S.FindSlot(container, item, lo, hi, prefer)
        if not slot and S.ToolSlot(item) then lo,hi=1,C.WORK_SLOTS;slot=S.FindSlot(container,item,lo,hi,prefer) end
        if slot then
            local removed = inventory:RemoveItem(item, true)
            if not S.Insert(container, removed, lo, hi, slot) and S.Valid(removed) then
                inventory:GiveItem(removed, entry.slot)
                complete = false
            end
        else complete = false end
    end
    self.inst._agri_internal_transfer = nil
    self.inst._agri_reserved_slots = {}
    if task then task.invobject = nil end
    self.current, self.borrowed = nil, nil
    if self.inst.components.agrithermal then self.inst.components.agrithermal:Refresh() end
    return complete
end

function AgriResource:Recover()
    if self.current then return true end
    local ok=self:Finish(nil, false)
    self:OrganizeTools()
    return ok
end

function AgriResource:OrganizeTools()
    if self.organizing or self.current then return end
    local container=self.inst.components.container
    if not container or (container.numslots or 0)<C.ROBOT_SLOTS then return end
    self.organizing=true
    self.inst._agri_internal_transfer=true
    for _,entry in ipairs(S.Items(container)) do
        local target=S.ToolSlot(entry.item)
        if entry.slot<=C.WORK_SLOTS and target and container:GetItemInSlot(target)==nil then
            local ok,_,stranded=S.Transfer(container,container,entry.item,nil,target,target)
            if stranded then self:KeepStranded(stranded) end
        end
    end
    self:MigrateLegacyPlow(container)
    self.inst._agri_internal_transfer=nil
    self.organizing=false
end

-- An old save's plow in slot 25 moves to work inventory, or straight into
-- the warehouse recycle area when work inventory is full. If neither has
-- room it stays in slot 25, which the robot widget then shows.
function AgriResource:MigrateLegacyPlow(container)
    local item=container:GetItemInSlot(C.LEGACY_PLOW_SLOT)
    if not S.Valid(item) then U.ClearTalk(self.inst,"legacy_plow_stuck");return end
    local moved,_,stranded=S.Transfer(container,container,item,nil,1,C.WORK_SLOTS)
    if stranded then self:KeepStranded(stranded) end
    if not moved and container:GetItemInSlot(C.LEGACY_PLOW_SLOT)==item then
        local registry=TheWorld.components.agrifarmgroup
        local group=registry and registry:GetGroup(self.inst)
        local warehouse=group and S.Valid(group.warehouse) and group.warehouse.components.container
        if warehouse then
            local lo,hi=S.WarehouseRange("recycle")
            moved,_,stranded=S.Transfer(container,warehouse,item,nil,lo,hi)
            if stranded then self:KeepStranded(stranded) end
        end
    end
    if container:GetItemInSlot(C.LEGACY_PLOW_SLOT)==item then
        U.OnceTalk(self.inst,"legacy_plow_stuck",T.Message("legacy_plow_stuck"))
    else U.ClearTalk(self.inst,"legacy_plow_stuck") end
end

function AgriResource:OnSave()
    -- Inventory and container components persist their own actual items once.
    return { borrowed_slot = self.borrowed and self.borrowed.slot or nil }
end

function AgriResource:OnLoad(data)
    self.current, self.borrowed = nil, nil
    self.inst:DoTaskInTime(0, function() self:Recover() end)
end

return AgriResource
