local C = require("agri/constants")
local U = require("agri/util")
local T = require("agri/task_types")
local Claims = require("agri/task_claims")
local Emergency = require("agri/emergency_detector")
local function now() return GetTime() end
local function ownerid(robot) return robot and robot.GUID end
local function plain(value, seen)
    if type(value) ~= "table" then return type(value) ~= "function" and value or nil end
    if value.entity or value.IsValid then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do
        if type(k) == "number" or type(k) == "string" then out[k] = plain(v, seen) end
    end
    seen[value] = nil
    return out
end
local function copytask(task)
    local out = plain(task) or {}
    out.target = task.target
    out.invobject = nil
    return out
end
-- Automatic plowing is disabled. A PLOW that never started is blocked with a
-- visible reason; one with a continuation may own a deployed native plow and
-- is left to the executor, which tracks it or blocks it the same way.
local function disableplow(task)
    if task.kind == "PLOW" and not T.TERMINAL[task.state] and task.continuation == nil then
        task.state, task.reason = "blocked", "plow_disabled"
        task.owner_guid, task.pause_reason = nil, nil
    end
    return task
end

local AgriScheduler = Class(function(self, inst)
    self.inst = inst
    self.tasks, self.order, self.claims, self.active = {}, {}, Claims.New(), {}
    self.next_sequence, self.next_child = 1, 1
    self.active_p0_threats, self.announced = {}, {}
    self.metrics = { claimed = 0, completed = 0, blocked = 0, retries = 0, preemptions = 0 }
    self.group = nil
end)

function AgriScheduler:Add(task)
    if self.tasks[task.id] then return self.tasks[task.id] end
    task = T.Normalize(copytask(task))
    if not task then return nil end
    disableplow(task)
    if U.Valid(task.target) and task.kind~="PLANT" then task.entity_bound=true end
    task.sequence = self.next_sequence
    self.next_sequence = self.next_sequence + 1
    self.tasks[task.id], self.order[#self.order + 1] = task, task.id
    return task
end

function AgriScheduler:SetPlan(plan, group)
    self.group = group or self.group
    self.plan_status = plan.status
    local affected,viability_keys={},{}
    self.viability_failures=plain(plan.viability_failures) or {}
    for _,failure in ipairs(self.viability_failures) do
        local key=tostring(failure.cluster)..":"..tostring(failure.reason)
        viability_keys[key]=true
        if failure.cluster then affected[failure.cluster]=true end
        if not (self.viability_keys and self.viability_keys[key]) then
            for _,robot in ipairs(self.group and self.group.members or {}) do
                local active=self:Current(robot)
                if active and active.priority==3 and active.data and active.data.cell==failure.cluster then self:Pause(robot,"viability_changed") end
            end
            U.OnceTalk(self.inst,"viability:"..key,"作物成长条件发生变化，已重新评估本区计划；健康植株继续保留。")
        end
    end
    for key in pairs(self.viability_keys or {}) do if not viability_keys[key] then U.ClearTalk(self.inst,"viability:"..key) end end
    self.viability_keys=viability_keys
    local settings=self.group and self.group.settings or {}
    local intent={settings.planting or "",settings.crop or "",settings.mode or "",tostring(settings.radius),tostring(settings.density),tostring(settings.continuous)}
    for _,cell in ipairs(self.group and self.group.blueprint and self.group.blueprint.cells or {}) do intent[#intent+1]=tostring(cell.x)..":"..tostring(cell.z) end
    local key=table.concat(intent,"|")
    local changed=self.intent_key and self.intent_key~=key
    if changed then
        for _,id in ipairs(self.order) do
            local old=self.tasks[id]
            if not T.TERMINAL[old.state] and (old.kind=="PLOW" or old.kind=="TILL" or old.kind=="PLANT" or old.kind=="FETCH")
                and not (old.continuation and old.continuation.phase=="plowing") then self:Cancel(id,"intent_changed") end
        end
    end
    self.intent_key=key
    self.plan_ids={}
    for _, task in ipairs(plan.tasks or {}) do
        if task.data and affected[task.data.cell] and (task.kind=="WATER" or task.kind=="FERTILIZE" or task.kind=="TEND" or task.kind=="MUSIC_TEND") then
            task.priority=1
        end
        self.plan_ids[task.id]=true
        local old = self.tasks[task.id]
        if old and old.state=="cancelled" and changed and settings.planting~="pause" then
            old.state,old.reason,old.retries="pending",nil,0
            old.prefab,old.data,old.deps=task.prefab,plain(task.data) or {},task.deps or {}
        end
        if not old then self:Add(task)
        elseif not T.TERMINAL[old.state] then
            -- A rescan can refresh entities and estimates, never reorder or replace a continuation.
            if not self.claims:Get(old.id) then
                old.target, old.point = task.target or old.target, task.point or old.point
                if U.Valid(task.target) and old.kind~="PLANT" then old.entity_bound=true end
                old.prefab = task.prefab or old.prefab
                old.data = plain(task.data) or old.data
                old.not_before, old.deadline = task.not_before, task.deadline
                old.deps = task.deps or old.deps
            end
            old.priority = math.min(old.priority, task.priority or 3)
        end
    end
    for _, id in ipairs(plan.cancel_ids or {}) do self:Cancel(id, "plan_invalidated") end
    self:RefreshReady()
    self:CollectGarbage()
end
function AgriScheduler:TaskState(id) return self.tasks[id] and self.tasks[id].state or nil end
function AgriScheduler:CollectGarbage()
    local keep={}
    for _,task in pairs(self.tasks) do
        if not T.TERMINAL[task.state] then
            for _,id in ipairs(task.deps or {}) do keep[id]=true end
            if task.parent_id then keep[task.parent_id]=true end
        end
    end
    local order,retained={},0
    for i=#self.order,1,-1 do
        local id=self.order[i]
        local task=self.tasks[id]
        if task and (not T.TERMINAL[task.state] or keep[id] or self.plan_ids and self.plan_ids[id] or retained<128) then
            order[#order+1]=id
            if T.TERMINAL[task.state] then retained=retained+1 end
        else self.tasks[id]=nil end
    end
    self.order={}
    for i=#order,1,-1 do self.order[#self.order+1]=order[i] end
end

function AgriScheduler:Dependencies(task)
    for _, id in ipairs(task.deps or {}) do if not T.IsDone(self.tasks[id]) then return false end end
    return true
end
function AgriScheduler:RefreshReady()
    local time = now()
    for _, id in ipairs(self.order) do
        local task = self.tasks[id]
        if task and (task.state == "pending" or task.state == "ready") then
            local ready = not task.suspended_by and self:Dependencies(task) and (not task.not_before or task.not_before <= time)
                and (not task.retry_after or task.retry_after <= time)
            task.state = ready and "ready" or "pending"
        end
    end
end
function AgriScheduler:IsFrozen()
    return self.group==nil or self.group.settings==nil or self.group.settings.running~=true
        or self.group.editing==true or self.group.planner_error==true
        or next(self.active_p0_threats) ~= nil
end
function AgriScheduler:Current(robot)
    local id = self.active[ownerid(robot)]
    return id and self.tasks[id] or nil
end
function AgriScheduler:Pause(robot, reason)
    local id = ownerid(robot)
    local task = self:Current(robot)
    if task and not T.TERMINAL[task.state] then
        task.state, task.pause_reason = "paused", reason
        task.continuation = task.continuation or { phase = "validate", count_done = task.count_done or 0 }
        self.active[id] = nil
        self.metrics.preemptions = self.metrics.preemptions + 1
        local executor = robot.components and robot.components.agriexecutor
        if executor and executor.Interrupt then executor:Interrupt(reason, true) end
    end
    return task
end
function AgriScheduler:HigherPriority(task, robot)
    if self:IsFrozen() then return true end
    self:RefreshReady()
    for _, id in ipairs(self.order) do
        local candidate = self.tasks[id]
        if candidate and candidate.state == "ready" and candidate.priority < task.priority
            and (not candidate.reserved_owner or candidate.reserved_owner == ownerid(robot)) and self:CanClaim(robot,candidate) then return true end
    end
    return false
end
function AgriScheduler:CanClaim(robot, task)
    if U.Valid(task.target) and (task.kind=="PICKUP" or task.kind=="HARVEST" or task.kind=="HAMMER" or task.kind=="CLEAR" or task.kind=="TEND") then
        for id in pairs(self.claims.entries) do
            local other=self.tasks[id]
            if id~=task.id and other and other.target==task.target and not T.TERMINAL[other.state] then return false end
        end
    end
    local resource = robot.components and robot.components.agriresource
    if not resource or not resource.FindActionItem then return true end
    local kind = task.kind
    if kind=="CLEAR" then task.data=task.data or {};task.data.tool_action="DIG" end
    -- PLOW needs no item: it only follows an already deployed native plow,
    -- and the executor blocks an unstarted one with plow_disabled.
    if kind == "PLOW" then return true end
    if kind == "TILL" or kind == "HAMMER" or kind == "HEAT"
        or kind == "CLEAR" and task.data and (task.data.tool_action or task.data.action) then
        return resource:FindActionItem(task) ~= nil
    end
    if kind == "MUSIC_TEND" then
        for _, item in ipairs(resource:OwnItems()) do if item:HasTag("phonograph_record") then return true end end
        return false
    end
    if kind == "WATER" or kind == "REFILL" then
        for _, item in ipairs(resource:OwnItems()) do if item:HasTag("wateringcan") then return true end end
        return false
    end
    if kind=="PLANT" or kind=="FERTILIZE" then
        return resource:FindActionItem(task)~=nil or self.group and U.Valid(self.group.warehouse)
    end
    return true
end
function AgriScheduler:Claim(robot)
    if self:IsFrozen() then return nil end
    self:RefreshReady()
    local rid = ownerid(robot)
    local current = self:Current(robot)
    if current and (current.state == "claimed" or current.state == "running") then return current end
    local best
    for _, id in ipairs(self.order) do
        local task = self.tasks[id]
        local claim = self.claims:Get(id)
        local ownpaused = task.state == "paused" and claim and claim.owner == rid and not task.suspended_by
        if (task.state == "ready" or ownpaused) and (not task.reserved_owner or task.reserved_owner == rid)
            and (not claim or claim.owner == rid or claim.expires <= now()) and self:CanClaim(robot,task) then
            if not best or task.priority < best.priority or task.priority == best.priority
                and (ownpaused and best.state ~= "paused" or task.state == best.state and task.sequence < best.sequence) then best = task end
        end
    end
    if not best or not self.claims:Acquire(best.id, rid, now(), C.CLAIM_TIMEOUT) then return nil end
    best.owner, best.state, best.pause_reason = robot, "claimed", nil
    self.active[rid] = best.id
    self.metrics.claimed = self.metrics.claimed + 1
    return best
end
function AgriScheduler:Running(task, robot)
    local claim = self.claims:Get(task.id)
    if not claim or claim.owner ~= ownerid(robot) then return false end
    task.state = "running"
    return true
end
function AgriScheduler:Renew(robot)
    local rid = ownerid(robot)
    for id, claim in pairs(self.claims.entries) do
        if claim.owner == rid then self.claims:Renew(id, rid, now(), C.CLAIM_TIMEOUT) end
    end
end
function AgriScheduler:Complete(id, robot, cancelled)
    local task = self.tasks[id]
    if not task then return false end
    local claim = self.claims:Get(id)
    if claim and robot and claim.owner ~= ownerid(robot) then return false end
    self.claims:Release(id)
    if not cancelled and robot and task.last_reason then U.ClearTalk(robot,task.last_reason);task.last_reason=nil end
    if task.owner and self.active[ownerid(task.owner)]==id then self.active[ownerid(task.owner)] = nil end
    task.owner, task.state, task.finished = nil, cancelled and "cancelled" or "complete", now()
    task.target,task.target_guid=nil,nil
    task.reason, task.continuation = nil, nil
    self.metrics.completed = self.metrics.completed + 1
    local parent = task.parent_id and self.tasks[task.parent_id]
    if parent and parent.suspended_by == id then
        parent.suspended_by = nil
        if parent.state == "paused" then parent.pause_reason = nil end
    end
    self:RefreshReady()
    return true
end
function AgriScheduler:Cancel(id, reason)
    local task = self.tasks[id]
    if task and not T.TERMINAL[task.state] then
        if task.suspended_by then self:Cancel(task.suspended_by,reason) end
        local robot = task.owner
        if robot and self:Current(robot)==task and robot.components and robot.components.agriexecutor then robot.components.agriexecutor:Interrupt(reason, true) end
        self:Complete(id, robot, true)
        task.reason = reason
        for _,other in pairs(self.tasks) do
            if not T.TERMINAL[other.state] and U.Contains(other.deps,id) then self:Cancel(other.id,reason) end
        end
    end
end
function AgriScheduler:Fail(id, robot, reason, immediate_block)
    local task = self.tasks[id]
    if not task then return end
    local claim = self.claims:Get(id)
    if claim and claim.owner ~= ownerid(robot) then return end
    self.claims:Release(id)
    self.active[ownerid(robot)] = nil
    task.owner, task.reason = nil, reason or "action_rejected"
    task.retries = (task.retries or 0) + 1
    if immediate_block or T.RESOURCE_REASONS[task.reason] or task.retries >= C.MAX_RETRIES then
        task.state = "blocked"
        task.block_revision = self.group and self.group.revision or 0
        self.metrics.blocked = self.metrics.blocked + 1
        U.OnceTalk(robot, task.reason, T.Message(task.reason))
        local parent = task.parent_id and self.tasks[task.parent_id]
        if parent then
            parent.suspended_by, parent.state, parent.reason = nil, "blocked", task.reason
            self.claims:Release(parent.id)
            parent.owner = nil
        end
    else
        task.state, task.retry_after = "pending", now() + math.min(6, task.retries * 2)
        self.metrics.retries = self.metrics.retries + 1
    end
end
function AgriScheduler:Unblock(reason)
    for _, id in ipairs(self.order) do
        local task = self.tasks[id]
        if task.state == "blocked" and (reason ~= "resources" or T.RESOURCE_REASONS[task.reason]) then
            task.state, task.retries, task.retry_after = "pending", 0, nil
            task.last_reason=task.reason
            task.reason = nil
            if task.continuation then task.continuation.resource_rescans=nil end
        end
    end
    self:RefreshReady()
end
function AgriScheduler:PushSubtask(robot, parent, child)
    if not parent or parent.suspended_by then return nil end
    child.id = parent.id .. "/p2/" .. tostring(self.next_child)
    self.next_child = self.next_child + 1
    child.priority, child.parent_id, child.reserved_owner = 2, parent.id, ownerid(robot)
    child.deps = child.deps or {}
    self:Pause(robot, "blocker")
    local task = self:Add(child)
    if not task then return nil end
    parent.suspended_by = task.id
    if not self:CanClaim(robot,task) then
        local helper
        for _,member in ipairs(self.group and self.group.members or {}) do
            if self:CanClaim(member,task) then helper=member;break end
        end
        if helper then task.reserved_owner=helper.GUID
        else self:Fail(task.id,robot,"missing_tool",true);return task end
    end
    self:RefreshReady()
    return task
end
function AgriScheduler:SetEmergency(threats)
    threats = threats or {}
    local was = next(self.active_p0_threats) ~= nil
    local is = next(threats) ~= nil
    for id, threat in pairs(threats) do
        if not self.announced[id] then
            self.announced[id] = true
            Emergency.Announce(Emergency.Label(threat) .. "，农场已暂停；威胁全部解除后继续。")
        end
    end
    self.active_p0_threats = threats
    if is and not was then
        for _, robot in ipairs(self.group and self.group.members or {}) do self:Pause(robot, "emergency") end
    elseif was and not is then
        self.announced = {}
        Emergency.Announce("威胁已全部解除，正在验证并恢复原任务。")
    end
end
function AgriScheduler:Release(robot)
    local rid = ownerid(robot)
    for _, id in ipairs(self.claims:ReleaseOwner(rid)) do
        local task = self.tasks[id]
        if task and not T.TERMINAL[task.state] then
            task.state, task.owner, task.reserved_owner = "pending", nil, nil
            -- Release ownership, not the dependency on an unfinished P2 child.
            -- A replacement robot must finish the child before this task runs.
        end
    end
    for _,task in pairs(self.tasks) do
        if task.reserved_owner==rid then task.reserved_owner=nil end
    end
    self.active[rid] = nil
end
function AgriScheduler:Tick(group)
    self.group = group or self.group
    if not self.group then return end
    self:SetEmergency(Emergency.Scan(self.group))
    local members = {}
    for _, robot in ipairs(self.group.members) do members[robot.GUID] = robot end
    for id, claim in pairs(self.claims.entries) do
        local robot = members[claim.owner]
        if not U.Valid(robot) then
            self.claims:Release(id)
            local task = self.tasks[id]
            if task and not T.TERMINAL[task.state] then task.state, task.owner, task.reserved_owner = "pending", nil, nil end
        elseif self:IsFrozen() then self.claims:Renew(id, claim.owner, now(), C.CLAIM_TIMEOUT)
        elseif claim.expires <= now() then
            local executor = robot.components and robot.components.agriexecutor
            if executor then executor:Interrupt("lease_expired", true) end
            self:Release(robot)
        end
    end
    for _, robot in ipairs(self.group.members) do
        local current = self:Current(robot)
        if current and self:HigherPriority(current, robot) then self:Pause(robot, self:IsFrozen() and "stopped" or "priority") end
    end
    for _,id in ipairs(self.order) do
        local task=self.tasks[id]
        if task.state=="ready" then
            local capable=false
            for _,robot in ipairs(self.group.members) do if self:CanClaim(robot,task) then capable=true;break end end
            task.waiting_reason=not capable and "no_capable_robot" or nil
        elseif task.state=="blocked" and task.reason=="blocked_structure" and task.point then
            local p=task.point
            -- A blocked PLOW is never revived: automatic plowing is disabled.
            local resolved=task.kind=="TILL" and TheWorld.Map:CanTillSoilAtPoint(p.x,0,p.z,false)
            if resolved then
                task.state,task.retries,task.last_reason,task.reason="pending",0,task.reason,nil
                if task.continuation then task.continuation.blocker_rescans=nil end
            end
        elseif task.state=="blocked" and task.reason=="no_water_source" then
            local p=self.group.center
            if #TheSim:FindEntities(p.x,0,p.z,self.group.settings.radius,{"watersource"},{"INLIMBO"})>0 then
                task.state,task.retries,task.last_reason,task.reason="pending",0,task.reason,nil
                if task.continuation then task.continuation.resource_rescans=nil end
            end
        elseif task.state=="blocked" and task.reason=="no_furnace" then
            for _,robot in ipairs(self.group.members) do
                local thermal=robot.components.agrithermal
                if thermal and (thermal:HasModule() or U.Valid(thermal:FindFurnace(self.group))) then
                    task.state,task.retries,task.last_reason,task.reason="pending",0,task.reason,nil
                    if task.continuation then task.continuation.resource_rescans=nil end
                    break
                end
            end
        end
    end
    self:RefreshReady()
end
function AgriScheduler:Snapshot()
    local tasks, counts = {}, {}
    for _, id in ipairs(self.order) do
        local t = self.tasks[id]
        counts[t.state] = (counts[t.state] or 0) + 1
        if not T.TERMINAL[t.state] and #tasks < 100 then
            tasks[#tasks + 1] = { id=id,kind=t.kind,state=t.state,priority=t.priority,reason=t.reason or t.waiting_reason,
                point=plain(t.point),owner=t.owner and t.owner.GUID,retries=t.retries,not_before=t.not_before,deadline=t.deadline }
        end
    end
    return { queue=tasks,counts=counts,emergency=plain(self.active_p0_threats),viability=plain(self.viability_failures),metrics=plain(self.metrics) }
end
function AgriScheduler:Save()
    local data = { schema_version=C.SCHEMA_VERSION,tasks={},next_sequence=self.next_sequence,next_child=self.next_child,
        active_p0_threats=plain(self.active_p0_threats),announced=plain(self.announced),metrics=plain(self.metrics),intent_key=self.intent_key,saved_at=now() }
    local refs, seen = {}, {}
    local function ref(entity)
        if U.Valid(entity) and entity.persists~=false then
            if not seen[entity.GUID] then seen[entity.GUID]=true; refs[#refs+1]=entity.GUID end
            return entity.GUID
        end
    end
    for _, id in ipairs(self.order) do
        local task = self.tasks[id]
        local saved = plain(task)
        saved.owner, saved.target, saved.invobject = nil, nil, nil
        saved.owner_guid=ref(task.owner)
        -- Inventory contents are embedded save records, not standalone world
        -- references. Terminal pickups must not keep refs to those LIMBO items.
        if task.kind~="PLANT" and not T.TERMINAL[task.state] and U.Valid(task.target)
            and not (task.target.IsInLimbo and task.target:IsInLimbo()) then saved.target_guid=ref(task.target) end
        if task.kind=="PLANT" then saved.entity_bound=nil;saved.target_guid=nil end
        local parent=task.parent_id and self.tasks[task.parent_id]
        saved.reserved_owner_guid=task.reserved_owner and ref(task.owner or parent and parent.owner or Ents and Ents[task.reserved_owner]) or nil
        saved.reserved_owner=nil
        saved.not_before_remaining = task.not_before and math.max(0, task.not_before-now())
        saved.deadline_remaining = task.deadline and task.deadline-now()
        saved.not_before, saved.deadline, saved.retry_after = nil, nil, nil
        if task.state == "running" or task.state == "claimed" then saved.state="paused"; saved.pause_reason="reload" end
        data.tasks[#data.tasks+1] = saved
    end
    return data, refs
end
function AgriScheduler:Restore(data)
    if type(data) ~= "table" then return end
    self.tasks,self.order,self.claims,self.active = {},{},Claims.New(),{}
    self.next_sequence,self.next_child = data.next_sequence or 1,data.next_child or 1
    self.active_p0_threats,self.announced = data.active_p0_threats or {},data.announced or {}
    self.metrics=data.metrics or self.metrics
    self.intent_key=data.intent_key
    for _, saved in ipairs(data.tasks or {}) do
        local task = T.Normalize(plain(saved))
        if task then
            task.not_before = task.not_before_remaining and now()+task.not_before_remaining
            task.deadline = task.deadline_remaining and now()+task.deadline_remaining
            local continuation=task.continuation
            if continuation and data.saved_at then
                if continuation.wait_until then continuation.wait_until=now()+math.max(0,continuation.wait_until-data.saved_at) end
                if continuation.heat_started then continuation.heat_started=now()-(data.saved_at-continuation.heat_started) end
            end
            self.tasks[task.id],self.order[#self.order+1] = task,task.id
            if task.state == "paused" and not task.owner_guid then task.state="pending" end
            disableplow(task)
        end
    end
end
function AgriScheduler:Takeover(other)
    -- Same-world handoff preserves entity identities and exact FIFO/claims, including paused work.
    self.tasks,self.order,self.claims,self.active = other.tasks,other.order,other.claims,other.active
    self.next_sequence,self.next_child = other.next_sequence,other.next_child
    self.active_p0_threats,self.announced,self.metrics = other.active_p0_threats,other.announced,other.metrics
    self.intent_key,self.plan_ids=other.intent_key,other.plan_ids
    self.group=other.group
    other.tasks,other.order,other.claims,other.active = {},{},Claims.New(),{}
end
function AgriScheduler:OnSave() return self:Save() end
function AgriScheduler:OnLoad(data) self:Restore(data) end
function AgriScheduler:LoadPostPass(newents)
    for _, id in ipairs(self.order) do
        local task = self.tasks[id]
        local owner = task.owner_guid and newents[task.owner_guid]
        local target = task.target_guid and newents[task.target_guid]
        local reserved=task.reserved_owner_guid and newents[task.reserved_owner_guid]
        task.owner,task.target = owner and owner.entity,target and target.entity
        if U.Valid(task.owner) and not T.TERMINAL[task.state] then
            self.claims:Acquire(id,task.owner.GUID,now(),C.CLAIM_TIMEOUT)
            task.reserved_owner = task.owner.GUID
        elseif task.state == "paused" then task.state="pending";task.reserved_owner=nil end
        if reserved then -- Entity references are always re-keyed after a world load.
            task.reserved_owner=U.Valid(reserved.entity) and reserved.entity.GUID or nil
        end
        task.owner_guid,task.target_guid,task.reserved_owner_guid = nil,nil,nil
    end
end
return AgriScheduler
