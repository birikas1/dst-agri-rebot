local C = require("agri/constants")
local U = require("agri/util")
local Fields = require("agri/field_zones")

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
    -- World zone registry: plans outlive groups, robots and scans.
    self.zones = { records = {}, next_id = 1 }
    self.zone_locks, self.zone_budget = {}, {}
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
        id = id, members = {}, primary = nil, center = U.Copy(robot._agri_build_origin or position(robot)),
        settings = U.Settings(), presets = {}, blueprint = { cells = {}, visible = true, confirmed = false },
        dirty = true, revision = 1, created = now(), last_plan = -C.PLAN_INTERVAL,
    }
    self:EnableZones(group)
    self.groups[id] = group
    return group
end
-- Every real group (new or loaded) manages connected farm zones.
function AgriFarmGroup:EnableZones(group)
    group.zones_enabled = true
    group.zone_store, group.zone_registry = self.zones, self
    group.zone_holds = group.zone_holds or {}
end

function AgriFarmGroup:RefreshWorkCenter(group)
    if not group then return end
    if not group.primary then
        if U.Valid(group.workcenter) then group.workcenter:Remove() end
        group.workcenter=nil
        return
    end
    if not U.Valid(group.workcenter) then group.workcenter=SpawnPrefab("agriworkcenter") end
    local marker=group.workcenter
    if marker then
        marker.Transform:SetPosition(group.center.x,0,group.center.z)
        marker._agri_radius:set(group.settings.radius)
        marker._agri_order:set(group.placement_order or 0)
        marker._agri_group:set(group.id)
    end
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
    self:RefreshWorkCenter(group)
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
    robot._agri_build_origin=U.Copy(saved.origin or robot._agri_build_origin or position(robot))
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
    local userid=type(player)=="string" and player or type(player)=="table" and player.userid or nil
    for zid,lock in pairs(self.zone_locks) do
        if lock.player==player or userid~=nil and lock.userid==userid then self.zone_locks[zid]=nil end
    end
    if userid then self.zone_budget[userid]=nil end
    for _,group in pairs(self.groups) do self:RefreshEditing(group);self:ApplyZoneHolds(group) end
end

-- Zones ----------------------------------------------------------------------
-- A record seen recently by another live group stays with that group, so two
-- overlapping groups never plan the same zone twice.
function AgriFarmGroup:ZoneForeign(record,group,time)
    local owner=record and record.group_id
    if not owner or owner==group.id then return false end
    local other=self.groups[owner]
    if not other or #other.members==0 then return false end
    return record.last_seen~=nil and (time or now())-record.last_seen<C.PLAN_INTERVAL*3
end
local function lockalive(lock) return lock~=nil and lock.expires>now() end
function AgriFarmGroup:ZoneHolds(group)
    -- All records this group owns (bounded by Fields.MAX_RECORDS), so tasks
    -- restored from a save are held before the first plan after loading.
    local holds={}
    for zid,record in pairs(self.zones.records) do
        if record.group_id==group.id and not record.gone then
            if lockalive(self.zone_locks[zid]) then holds[zid]="zone_editing"
            elseif record.paused then holds[zid]="zone_paused" end
        end
    end
    return holds
end
-- Holds pause only the held zone's work; robots on other zones continue.
function AgriFarmGroup:ApplyZoneHolds(group)
    if not group or not group.zones_enabled then return end
    group.zone_holds=self:ZoneHolds(group)
    local scheduler=group.scheduler
    if not (scheduler and scheduler.ZoneHeld) then return end
    for _,robot in ipairs(group.members) do
        local current=scheduler.Current and scheduler:Current(robot)
        local held=current and scheduler:ZoneHeld(current)
        if held then scheduler:Pause(robot,held) end
    end
    if scheduler.RefreshReady then scheduler:RefreshReady() end
end
-- Server-side access check for one zone: a living, connected player near
-- the zone's ground, and a live group that currently manages the zone.
function AgriFarmGroup:ZoneAccess(player,zid)
    if not U.Valid(player) or type(player.userid)~="string" or player.userid=="" or player:HasTag("playerghost") then
        return nil,nil,"玩家状态无效"
    end
    if type(zid)~="string" or #zid>16 then return nil,nil,"田块无效" end
    local record=self.zones.records[zid]
    if not record or record.gone then return nil,nil,"田块不存在" end
    local group=record.group_id and self.groups[record.group_id]
    local view=group and group.zone_view and group.zone_view[zid]
    if not group or #group.members==0 or not view then return nil,nil,"田块不在机器人的工作范围内" end
    local p,near=position(player),false
    for _,point in ipairs(view.points or {}) do
        if U.DistanceSq(p,point)<=C.ZONE_EDIT_DISTANCE*C.ZONE_EDIT_DISTANCE then near=true;break end
    end
    if not near then return nil,nil,"距离田块太远" end
    return record,group
end
function AgriFarmGroup:AcquireZoneLock(player,zid)
    local record,group,why=self:ZoneAccess(player,zid)
    if not record then return false,why end
    local lock=self.zone_locks[zid]
    if lockalive(lock) and lock.userid~=player.userid then return false,"另一位玩家正在编辑这个田块" end
    -- One expanded editor per player: opening a zone closes the previous one.
    for other,held in pairs(self.zone_locks) do
        if other~=zid and held.userid==player.userid then
            self.zone_locks[other]=nil
            local r=self.zones.records[other];self:ApplyZoneHolds(r and self.groups[r.group_id or ""])
        end
    end
    local fresh=not (lockalive(lock) and lock.userid==player.userid)
    self.zone_locks[zid]={userid=player.userid,player=player,expires=now()+C.ZONE_LOCK_TIMEOUT,group_id=group.id}
    if fresh then self:ApplyZoneHolds(group) end
    return true
end
function AgriFarmGroup:HasZoneLock(player,zid)
    local lock=type(zid)=="string" and self.zone_locks[zid]
    if not lockalive(lock) or not U.Valid(player) or lock.userid~=player.userid then return false end
    return self:ZoneAccess(player,zid)~=nil
end
function AgriFarmGroup:ReleaseZoneLock(player,zid)
    local lock=type(zid)=="string" and self.zone_locks[zid]
    if lock and (player==nil or U.Valid(player) and lock.userid==player.userid) then
        self.zone_locks[zid]=nil
        local record=self.zones.records[zid]
        self:ApplyZoneHolds(record and self.groups[record.group_id or ""])
        return true
    end
    return false
end
local function crop_ok()
    local crops={}
    for key,def in pairs(require("agri/source_adapter").GetCropDefs()) do if not def.is_randomseed then crops[key]=true end end
    return crops
end
-- Edits need this player's live zone lock and the current zone revision.
-- action: "save" (data=settings), "pause"/"resume", "template" (back to
-- the group's default ratio template). Returns ok, reason, stale.
function AgriFarmGroup:UpdateZone(player,zid,revision,action,data)
    if not self:HasZoneLock(player,zid) then return false,"编辑锁已失效，请重新打开田块" end
    local record,group=self:ZoneAccess(player,zid)
    if not record then return false,"田块不存在" end
    if not U.Finite(revision) or revision%1~=0 or revision~=record.revision then return false,"田块方案已被更新，已刷新为最新内容",true end
    if action=="save" then
        local clean,why=Fields.Clean(data,crop_ok())
        if not clean then return false,why end
        local fits,reason=Fields.CheckCapacity(clean,#record.tiles)
        if not fits then return false,reason end
        record.settings,record.configured,record.review=clean,true,nil
    elseif action=="pause" or action=="resume" then
        record.paused=action=="pause"
    elseif action=="template" then
        local fits,reason=Fields.CheckCapacity(Fields.Template(group.settings),#record.tiles)
        if not fits then return false,"默认模板超出此田块容量："..reason end
        record.settings,record.configured,record.review=nil,false,nil
    else return false,"未知操作" end
    record.revision=record.revision+1
    -- Extend the lock on every accepted edit; holds follow the new state.
    self.zone_locks[zid].expires=now()+C.ZONE_LOCK_TIMEOUT
    self:ApplyZoneHolds(group)
    self:MarkDirty(group,"zone_settings")
    return true
end
local function zonestate(self,zid,view)
    if lockalive(self.zone_locks[zid]) then return "editing" end
    if view.paused then return "paused" end
    if view.review then return "review" end
    if view.unsafe then return "unsafe" end
    if view.empty then return "empty" end
    return "ok"
end
local function round1(n) return math.floor(n*10+.5)/10 end
-- Compact read-only badge entry (no entities, bounded size).
function AgriFarmGroup:ZoneBadge(zid,view)
    local pts={}
    local points=view.points or {}
    if #points>C.ZONE_POINTS_MAX then
        local minx,maxx,minz,maxz=math.huge,-math.huge,math.huge,-math.huge
        for _,p in ipairs(points) do minx,maxx,minz,maxz=math.min(minx,p.x),math.max(maxx,p.x),math.min(minz,p.z),math.max(maxz,p.z) end
        points={{x=minx,z=minz},{x=maxx,z=minz},{x=minx,z=maxz},{x=maxx,z=maxz}}
    end
    for _,p in ipairs(points) do pts[#pts+1]=round1(p.x);pts[#pts+1]=round1(p.z) end
    -- Plan progress over the untrimmed targets: tt = planned plants, td =
    -- plants of a planned crop, each crop capped at its target, so kept
    -- off-plan plants never show progress like 32/8.
    local crops,tt,td={},0,0
    for _,crop in ipairs(U.Keys(view.targets)) do
        local target=tonumber(view.targets[crop]) or 0
        local have=tonumber((view.have or {})[crop]) or 0
        tt=tt+target;td=td+math.max(0,math.min(have,target))
        crops[#crops+1]={c=crop,n=view.targets[crop],h=(view.have or {})[crop] or 0}
    end
    table.sort(crops,function(a,b) if a.n~=b.n then return a.n>b.n end return a.c<b.c end)
    while #crops>6 do crops[#crops]=nil end
    return {id=zid,rev=view.revision,pts=pts,n=view.tiles,d=view.density,m=view.mode,nom=view.nominal,use=view.usable,
        wh=view.withheld,pl=view.planted,tt=tt,td=td,tg=crops,miss=view.missing_total,st=zonestate(self,zid,view),cf=view.configured==true}
end
-- Read-only zone list for one player: zones of live groups near the player.
-- Never takes a lock, never pauses work, never changes settings.
function AgriFarmGroup:ZoneList(player)
    if not U.Valid(player) or player:HasTag("playerghost") then return {} end
    local p,out=position(player),{}
    for _,id in ipairs(U.Keys(self.groups)) do
        local group=self.groups[id]
        local reach=(group.settings.radius or C.DEFAULT_RADIUS)+C.ZONE_VIEW_EXTRA
        if #group.members>0 and group.zone_view and U.DistanceSq(p,group.center)<=reach*reach then
            for _,zid in ipairs(group.zone_order or {}) do
                local view=group.zone_view[zid]
                if view then
                    local best=math.huge
                    for _,q in ipairs(view.points or {}) do best=math.min(best,U.DistanceSq(p,q)) end
                    out[#out+1]={distance=best,badge=self:ZoneBadge(zid,view)}
                end
            end
        end
    end
    table.sort(out,function(a,b) if a.distance~=b.distance then return a.distance<b.distance end return Fields.IdLess(a.badge.id,b.badge.id) end)
    local list={}
    for i=1,math.min(#out,C.ZONE_LIST_MAX) do list[i]=out[i].badge end
    return list
end
-- Editor payload for a zone the player holds the lock of.
function AgriFarmGroup:ZoneDetail(zid,group)
    local record=self.zones.records[zid]
    local view=group and group.zone_view and group.zone_view[zid]
    if not record or not view then return nil end
    local detail=self:ZoneBadge(zid,view)
    detail.rev=record.revision
    -- The editor's own lock is not news to the editor: show the zone state.
    detail.st=record.paused and "paused" or record.review and "review" or view.unsafe and "unsafe" or view.empty and "empty" or "ok"
    detail.paused=record.paused==true
    detail.configured=record.configured==true
    detail.settings=public(Fields.Effective(record,Fields.Template(group.settings)))
    detail.template=public(Fields.Template(group.settings))
    detail.targets=public(view.targets);detail.have=public(view.have);detail.missing=public(view.missing)
    detail.spacing_lost=view.spacing_lost;detail.unsafe=view.unsafe;detail.offgrid=view.offgrid
    detail.over=view.over_capacity;detail.requested=view.requested
    detail.withheld_reasons=public(view.withheld_reasons)
    if record.review then
        detail.review={reason=record.review.reason,alternatives={}}
        for _,a in ipairs(record.review.alternatives or {}) do detail.review.alternatives[#detail.review.alternatives+1]={from=a.from,settings=public(a.settings)} end
    end
    local stock={}
    for seed,n in pairs(group.zone_stock or {}) do if type(n)=="number" and n>0 then stock[seed]=n end end
    detail.stock=stock
    local crops={}
    for key,def in pairs(require("agri/source_adapter").GetCropDefs()) do
        if not def.is_randomseed then crops[#crops+1]={id=key,seed=def.seed,product=def.product} end
    end
    table.sort(crops,function(a,b)return a.id<b.id end)
    crops[#crops+1]={id="randomseed",seed="seeds",random=true}
    detail.crops=crops
    detail.edit_distance=C.ZONE_EDIT_DISTANCE
    return detail
end

function AgriFarmGroup:UpdateSettings(group, data)
    local settings = U.Copy(group.settings)
    for key, value in pairs(data or {}) do settings[key] = value end
    group.settings = U.Settings(settings)
    self:RefreshWorkCenter(group)
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
    -- Zone groups: the robot panel lists the zones and edits only the
    -- default ratio template; per-zone plans live in the zone editor.
    local zones
    if group.zones_enabled then
        zones={}
        for _,zid in ipairs(group.zone_order or {}) do
            local view=group.zone_view and group.zone_view[zid]
            if view and #zones<C.ZONE_LIST_MAX then zones[#zones+1]=self:ZoneBadge(zid,view) end
        end
    end
    return {
        zones_enabled=group.zones_enabled==true,zones=zones,
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
    -- Zone edit locks expire (no heartbeat), or end with the player's access.
    for zid, lock in pairs(self.zone_locks) do
        if not lockalive(lock) or not U.Valid(lock.player) or self:ZoneAccess(lock.player,zid)==nil then self.zone_locks[zid] = nil end
    end
    for _, group in pairs(self.groups) do
        self:SelectPrimary(group)
        self:RefreshEditing(group)
        self:ApplyZoneHolds(group)
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
                    self:ApplyZoneHolds(group)
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
    local data = {schema_version=C.SCHEMA_VERSION,next_order=self.next_order,next_group=self.next_group,groups={},
        zones=Fields.SaveStore(self.zones)}
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
    -- Saves before zones have no registry: zones start empty and the old
    -- global crop plan stays in settings.plan as the default ratio template.
    self.zones = Fields.LoadStore(data.zones)
    self._load_groups = data.groups or {}
    for _, saved in ipairs(self._load_groups) do
        if type(saved.id)=="string" then
            self.groups[saved.id]={id=saved.id,members={},center=saved.center or {x=0,z=0},
                settings=U.Settings(saved.settings),presets=saved.presets or {},
                blueprint=saved.blueprint or {cells={},visible=true,confirmed=false},
                revision=saved.revision or 1,dirty=true,last_plan=-C.PLAN_INTERVAL,plan=saved.plan,hole_cycles=saved.hole_cycles or {},
                planner_epoch=saved.planner_epoch,planner_config=saved.planner_config,
                single_round_started=saved.single_round_started,last_continuous=saved.last_continuous}
            self:EnableZones(self.groups[saved.id])
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
