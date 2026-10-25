local C = require("agri/constants")
local U = require("agri/util")

local function now() return GetTime() end
local function position(inst)
    local x, _, z = inst.Transform:GetWorldPosition()
    return { x = x, z = z }
end
local function ordered(a, b)
    return (a._agri_order or math.huge) < (b._agri_order or math.huge)
end
local function public(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    local kind = type(value)
    if kind == "number" then return U.Finite(value) and value or nil end
    if kind == "boolean" or kind == "string" then return value end
    if kind ~= "table" or depth > 8 or seen[value] or value.entity ~= nil then return nil end
    local out = {}
    seen[value] = true
    for k, v in pairs(value) do
        if type(k) == "string" or type(k) == "number" then out[k] = public(v, depth+1, seen) end
    end
    seen[value] = nil
    return out
end

local AgriFarmGroup = Class(function(self, inst)
    self.inst = inst
    self.groups, self.locks, self.inventory_holds = {}, {}, {}
    self.next_order, self.next_group = 1, 1
    self.metrics = { planner_recomputes = 0, group_ticks = 0 }
    self._task = inst:DoPeriodicTask(C.SCAN_INTERVAL, function() self:Tick() end)
    inst:WatchWorldState("season", function()
        for _, group in pairs(self.groups) do self:MarkDirty(group, "season") end
    end)
    inst:ListenForEvent("ms_playerleft", function(_, player)
        self:ReleasePlayer(player)
    end)
end)

function AgriFarmGroup:NewGroup(robot, id)
    id = id or ("farm_" .. tostring(self.next_group))
    self.next_group = self.next_group + 1
    local group = {
        id = id, members = {}, primary = nil, center = position(robot),
        settings = U.Settings(), presets = {}, blueprint = { cells = {}, visible = true, confirmed = false },
        dirty = true, revision = 1, created = now(), last_plan = -C.PLAN_INTERVAL,
    }
    self.groups[id] = group
    return group
end

function AgriFarmGroup:SelectPrimary(group)
    local old = group.primary
    for i = #group.members, 1, -1 do
        if not U.Valid(group.members[i]) then table.remove(group.members,i) end
    end
    table.sort(group.members, ordered)
    group.primary = group.members[1]
    if group.primary then
        local scheduler = group.primary.components.agrischeduler
        if scheduler and group.scheduler ~= scheduler then
            if group.scheduler and scheduler.Takeover then
                scheduler:Takeover(group.scheduler)
            elseif group.scheduler and group.scheduler.Save and scheduler.Restore then
                scheduler:Restore(group.scheduler:Save())
            elseif group.saved_scheduler and scheduler.Restore then
                scheduler:Restore(group.saved_scheduler)
                group.saved_scheduler = nil
            end
            group.scheduler = scheduler
        end
        -- Bind before the first executor tick. Loaded paused farms must never
        -- run a claimed seed action while waiting for the periodic world tick.
        if group.scheduler then group.scheduler.group=group end
        group.placement_order = group.primary._agri_order
        for _, member in ipairs(group.members) do
            member._agri_group_id = group.id
            member._agri_primary = member == group.primary
            if member._agri_groupnet then member._agri_groupnet:set(group.id) end
        end
    end
    if old ~= group.primary then self:MarkDirty(group, "primary_changed") end
end

function AgriFarmGroup:Register(robot, saved)
    if not U.Valid(robot) then return nil end
    saved = saved or {}
    local existing = self:GetGroup(robot)
    if existing then
        for _, member in ipairs(existing.members) do if member == robot then return existing end end
    end
    robot._agri_order = saved.placement_order or robot._agri_order or self.next_order
    self.next_order = math.max(self.next_order, robot._agri_order + 1)
    robot._agri_personal_settings = U.Settings(saved.personal_settings or robot._agri_personal_settings)
    local saved_id = saved.group_id or robot._agri_group_id
    local group = saved_id and self.groups[saved_id] or nil
    if not group then
        local candidate, p = nil, position(robot)
        for _, other in pairs(self.groups) do
            local radius = other.settings.radius + robot._agri_personal_settings.radius
            if #other.members > 0 and U.DistanceSq(p, other.center) <= radius * radius then
                if not candidate or (other.placement_order or math.huge) < (candidate.placement_order or math.huge) then candidate = other end
            end
        end
        group = candidate or self:NewGroup(robot, saved_id)
    end
    group.members[#group.members+1] = robot
    robot._agri_group_id = group.id
    self:SelectPrimary(group)
    self:MarkDirty(group, "member_joined")
    return group
end

function AgriFarmGroup:GetGroup(robot)
    return robot and self.groups[robot._agri_group_id] or nil
end

function AgriFarmGroup:Unregister(robot)
    local group = self:GetGroup(robot)
    self.locks[robot.GUID] = nil
    for key,hold in pairs(self.inventory_holds) do if hold.robot==robot then self.inventory_holds[key]=nil end end
    if not group then return end
    if group.scheduler and group.scheduler.Release then group.scheduler:Release(robot) end
    for i = #group.members, 1, -1 do
        if group.members[i] == robot then table.remove(group.members,i) end
    end
    robot._agri_group_id = nil
    self:SelectPrimary(group)
    self:RefreshEditing(group)
    if #group.members == 0 then self.groups[group.id] = nil end
end

function AgriFarmGroup:MarkDirty(group, reason)
    if not group then return end
    group.dirty = true
    group.dirty_reason = reason
    if reason == "resources" and group.scheduler and group.scheduler.Unblock then group.scheduler:Unblock(reason) end
end

function AgriFarmGroup:SetWarehouse(group, warehouse)
    if warehouse ~= nil and (not U.Valid(warehouse) or not warehouse:HasTag("agriwarehouse")) then return false end
    group.warehouse = warehouse
    group.revision = group.revision + 1
    self:MarkDirty(group, "warehouse")
    return true
end

function AgriFarmGroup:CanEdit(player, robot)
    return U.Valid(player) and U.Valid(robot) and player.userid ~= nil
        and not player:HasTag("playerghost")
        and self:GetGroup(robot) ~= nil
        and U.DistanceSq(position(player),position(robot)) <= C.INTERACT_DISTANCE * C.INTERACT_DISTANCE
end

function AgriFarmGroup:AcquireLock(player, robot)
    if not self:CanEdit(player,robot) then return false, "距离太远或机器人已移除" end
    local lock = self.locks[robot.GUID]
    if lock and lock.expires > now() and lock.userid ~= player.userid then return false, "另一位玩家正在管理" end
    self.locks[robot.GUID] = { userid = player.userid, player = player, robot = robot, expires = now()+C.LOCK_TIMEOUT }
    self:RefreshEditing(self:GetGroup(robot))
    return true
end

function AgriFarmGroup:RefreshEditing(group)
    if not group then return end
    local editing=false
    for _,lock in pairs(self.locks) do
        if lock.expires>now() and self:CanEdit(lock.player,lock.robot) and self:GetGroup(lock.robot)==group then editing=true;break end
    end
    if not editing then
        for key,hold in pairs(self.inventory_holds) do
            local container=U.Valid(hold.robot) and hold.robot.components.container
            local opened=container and container.openlist and container.openlist[hold.player]
            if not self:CanEdit(hold.player,hold.robot) or not (hold.pending or opened) then self.inventory_holds[key]=nil
            elseif self:GetGroup(hold.robot)==group then editing=true end
        end
    end
    local changed=group.editing~=editing
    group.editing=editing
    if editing and changed then
        for _,robot in ipairs(group.members) do
            if group.scheduler and group.scheduler.Pause then group.scheduler:Pause(robot,"player_edit") end
            local executor=robot.components.agriexecutor
            if executor and executor.Interrupt then executor:Interrupt("player_edit",true) end
            if robot._agri_statusnet then robot._agri_statusnet:set("PLAYER_EDIT") end
        end
    elseif changed then self:MarkDirty(group,"edit_complete") end
end

function AgriFarmGroup:SetInventoryHold(player,robot,enabled,pending)
    local key=tostring(robot.GUID)..":"..tostring(player.userid)
    if enabled then self.inventory_holds[key]={player=player,robot=robot,pending=pending==true}
    else self.inventory_holds[key]=nil end
    self:RefreshEditing(self:GetGroup(robot))
end

function AgriFarmGroup:HasLock(player, robot)
    local lock = robot and self.locks[robot.GUID]
    return self:CanEdit(player,robot) and lock ~= nil and lock.userid == player.userid and lock.expires > now()
end

function AgriFarmGroup:ReleaseLock(player, robot)
    local lock = robot and self.locks[robot.GUID]
    if lock and (player == nil or lock.userid == player.userid) then
        self.locks[robot.GUID] = nil
        self:RefreshEditing(self:GetGroup(robot))
    end
end

function AgriFarmGroup:ReleasePlayer(player)
    for id, lock in pairs(self.locks) do
        if lock.player == player or (type(player)=="string" and lock.userid==player) then self.locks[id] = nil end
    end
    for key,hold in pairs(self.inventory_holds) do if hold.player==player or type(player)=="string" and hold.player.userid==player then self.inventory_holds[key]=nil end end
    for _,group in pairs(self.groups) do self:RefreshEditing(group) end
end

function AgriFarmGroup:UpdateSettings(group, data)
    local settings = U.Copy(group.settings)
    for key, value in pairs(data or {}) do settings[key] = value end
    group.settings = U.Settings(settings)
    group.revision = group.revision + 1
    self:MarkDirty(group, "settings")
end

function AgriFarmGroup:Snapshot(group, player)
    local primary = group.primary
    local resource = primary and primary.components.agriresource
    local plan = group.plan or {}
    local memberinfo = {}
    for _, robot in ipairs(group.members) do
        local current=group.scheduler and group.scheduler.Current and group.scheduler:Current(robot)
        local module=robot.components.container and robot.components.container:GetItemInSlot(C.MODULE_SLOT)
        memberinfo[#memberinfo+1] = { guid=robot.GUID, order=robot._agri_order, primary=robot==primary, point=position(robot),
            module=U.Valid(module) and module.prefab or "none",
            current=current and {kind=current.kind,state=current.state,reason=current.reason} or nil }
    end
    local resources=resource and resource:Snapshot(group) or {}
    if resources.water and U.Valid(resources.water.source) then
        resources.water.source={prefab=resources.water.source.prefab,point=position(resources.water.source)}
    end
    resources.robots=public(memberinfo)
    local warehouse=U.Valid(group.warehouse) and group.warehouse or nil
    if warehouse and warehouse.components.agriwarehouse then resources.warehouse=warehouse.components.agriwarehouse:GetStatus() end
    local stats={plots=0,holes=0,growing=0,mature=0,issues=0}
    local captured=primary and primary.components.agriplanner and primary.components.agriplanner.last_snapshot
    for _,cell in ipairs(captured and captured.cells or {}) do
        if cell.is_farm then stats.plots=stats.plots+1 end;stats.holes=stats.holes+#(cell.soils or {})
        for _,plant in ipairs(cell.plants or {}) do
            if plant.mature then stats.mature=stats.mature+1 else stats.growing=stats.growing+1 end
        end
    end
    stats.issues=#(group.blueprint.warnings or {})
    local scheduler = group.scheduler
    return {
        version=C.VERSION, group_id=group.id, revision=group.revision, settings=public(group.settings),editing=group.editing==true,
        center=public(group.center), members=memberinfo, blueprint=public(group.blueprint), presets=public(group.presets),
        warehouse=U.Valid(group.warehouse) and {guid=group.warehouse.GUID,point=position(group.warehouse)} or nil,
        season=self.inst.state and self.inst.state.season,
        cycles=self.inst.state and self.inst.state.cycles,
        plan=public({status=plan.status,reasons=plan.reasons,summary=plan.summary,clusters=plan.clusters,recommendations=plan.recommendations}),
        resources=public(resources),farm_stats=stats,
        tasks=scheduler and scheduler.Snapshot and public(scheduler:Snapshot()) or {},
        metrics=public(self.metrics),
    }
end

function AgriFarmGroup:Tick()
    self.metrics.group_ticks = self.metrics.group_ticks+1
    for id, lock in pairs(self.locks) do
        if lock.expires <= now() or not self:CanEdit(lock.player,lock.robot) then self.locks[id] = nil end
    end
    for _, group in pairs(self.groups) do
        self:SelectPrimary(group)
        self:RefreshEditing(group)
        local primary = group.primary
        if primary then
            if not U.Valid(group.warehouse) then
                group.warehouse = nil
                local p = group.center
                local warehouses = TheSim:FindEntities(p.x,0,p.z,group.settings.radius+8,{"agriwarehouse"},{"INLIMBO"})
                table.sort(warehouses,function(a,b)
                    local da,db=U.DistanceSq(position(a),p),U.DistanceSq(position(b),p)
                    return da==db and a.GUID<b.GUID or da<db
                end)
                if warehouses[1] then self:SetWarehouse(group,warehouses[1]) end
            end
            if group.scheduler and group.scheduler.Tick then group.scheduler:Tick(group) end
            local planner = primary.components.agriplanner
            local due = now()-(group.last_plan or 0) >= C.PLAN_INTERVAL
            if planner and group.settings.running and (group.dirty or due) then
                -- SetPlan must merge stable task ids; claimed or interrupted jobs retain FIFO order.
                local ok, result = pcall(function() return planner:Plan(group) end)
                group.last_plan, group.dirty = now(), false
                self.metrics.planner_recomputes = self.metrics.planner_recomputes+1
                if ok and type(result)=="table" then
                    group.planner_error = nil
                    group.plan = result
                    if group.scheduler and group.scheduler.SetPlan then group.scheduler:SetPlan(result,group) end
                    U.ClearTalk(primary,"planner_error")
                else
                    group.planner_error = true
                    if group.scheduler then
                        for _, robot in ipairs(group.members) do group.scheduler:Pause(robot,"planner_error") end
                    end
                    group.plan = {status="blocked",reasons={"规划器异常；请查看服务器日志"}}
                    U.OnceTalk(primary,"planner_error","规划遇到问题，已安全暂停。")
                    print("[AgriRobot] planner error: " .. tostring(result))
                end
            end
        end
    end
end

function AgriFarmGroup:OnSave()
    local data = {schema_version=C.SCHEMA_VERSION,next_order=self.next_order,next_group=self.next_group,groups={}}
    local refs, used = {}, {}
    local function ref(inst)
        if U.Valid(inst) and not used[inst.GUID] then used[inst.GUID]=true; refs[#refs+1]=inst.GUID end
        return U.Valid(inst) and inst.GUID or nil
    end
    for _, id in ipairs(U.Keys(self.groups)) do
        local group = self.groups[id]
        local saved = {
            id=id,center=U.Copy(group.center),settings=U.Copy(group.settings),presets=public(group.presets),
            blueprint=public(group.blueprint),revision=group.revision,warehouse=ref(group.warehouse),members={},
            hole_cycles=public(group.hole_cycles),
            planner_epoch=group.planner_epoch,planner_config=group.planner_config,
            single_round_started=group.single_round_started,last_continuous=group.last_continuous,
            plan=public(group.plan and {status=group.plan.status,summary=group.plan.summary,reasons=group.plan.reasons}),
        }
        for _, robot in ipairs(group.members) do
            saved.members[#saved.members+1]={guid=ref(robot),order=robot._agri_order}
        end
        -- Tasks and claims are reconstructed from real soil/crops after reload.
        data.groups[#data.groups+1]=saved
    end
    return data, refs
end

function AgriFarmGroup:OnLoad(data)
    if type(data)~="table" then return end
    self.next_order = tonumber(data.next_order) or 1
    self.next_group = tonumber(data.next_group) or 1
    self._load_groups = data.groups or {}
    for _, saved in ipairs(self._load_groups) do
        if type(saved.id)=="string" then
            self.groups[saved.id]={id=saved.id,members={},center=saved.center or {x=0,z=0},
                settings=U.Settings(saved.settings),presets=saved.presets or {},
                blueprint=saved.blueprint or {cells={},visible=true,confirmed=false},
                revision=saved.revision or 1,dirty=true,last_plan=-C.PLAN_INTERVAL,plan=saved.plan,hole_cycles=saved.hole_cycles or {},
                planner_epoch=saved.planner_epoch,planner_config=saved.planner_config,
                single_round_started=saved.single_round_started,last_continuous=saved.last_continuous}
        end
    end
end

function AgriFarmGroup:LoadPostPass(newents)
    for _, saved in ipairs(self._load_groups or {}) do
        local group=self.groups[saved.id]
        if group then
            local warehouse=saved.warehouse and newents[saved.warehouse]
            group.warehouse=warehouse and warehouse.entity or nil
            for _, item in ipairs(saved.members or {}) do
                local entry=item.guid and newents[item.guid]
                local robot=entry and entry.entity
                if U.Valid(robot) then
                    robot._agri_group_id=group.id
                    robot._agri_order=item.order or self.next_order
                    self:Register(robot,{group_id=group.id,placement_order=robot._agri_order})
                end
            end
            self:SelectPrimary(group)
        end
    end
    self._load_groups=nil
end

return AgriFarmGroup
