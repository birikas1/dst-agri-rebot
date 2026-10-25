local C = require("agri/constants")
local U = require("agri/util")
local T = require("agri/task_types")
local Adapter = require("agri/source_adapter")
require("bufferedaction") -- Native module installs global BufferedAction and returns no class.
local function now() return GetTime() end
local function position(entity)
    local x, _, z = entity.Transform:GetWorldPosition()
    return { x=x,z=z }
end
local function vector(p) return Vector3(p.x,0,p.z) end
local function valid(entity) return U.Valid(entity) end
local function component(entity, name) return valid(entity) and entity.components and entity.components[name] end
local function safe_pickup(entity)
    local item = component(entity,"inventoryitem")
    return item and item.owner == nil and item.canbepickedup ~= false and not entity:HasTag("INLIMBO")
        and not entity:HasTag("irreplaceable") and not entity:HasTag("heavy") and not entity:HasTag("oversized_veggie")
end
local function safe_clear(entity)
    local work = component(entity,"workable")
    return work and work:GetWorkAction() == ACTIONS.DIG and (entity:HasTag("weed") or entity:HasTag("farm_debris"))
end

local AgriExecutor = Class(function(self, inst)
    self.inst = inst
    self.current,self.action,self.pending,self.result = nil,nil,nil,nil
    self.action_epoch,self.last_music = 0,-math.huge
    self._task = inst:DoPeriodicTask(C.EXECUTOR_INTERVAL,function() self:Tick() end)
end)
function AgriExecutor:GetGroup()
    local registry = TheWorld.components.agrifarmgroup
    return registry and registry:GetGroup(self.inst)
end
function AgriExecutor:GetAction()
    local group=self:GetGroup()
    if not group or not group.settings or not group.scheduler or group.settings.running~=true or group.scheduler:IsFrozen() then return nil end
    local pending = self.pending
    self.pending = nil
    return pending
end
function AgriExecutor:HasPendingAction() return self.pending ~= nil or self.action ~= nil end
function AgriExecutor:StopMotion()
    local locomotor=self.inst.components.locomotor
    if locomotor then
        if locomotor.Clear then locomotor:Clear() end
        locomotor:Stop()
    end
    if self.inst.ClearBufferedAction then self.inst:ClearBufferedAction() end
    if self.inst.sg and self.inst.sg.currentstate and self.inst.sg.currentstate.name ~= "idle" then self.inst.sg:GoToState("idle") end
end
function AgriExecutor:Interrupt(reason, preserve_claim)
    -- Success callbacks run inside the native action, before our next periodic
    -- tick. Record that committed work before pausing, or a resumed fertilizer /
    -- watering job could consume its resource twice.
    if self.result and self.current then
        local group = self:GetGroup()
        if group then self:ActionResult(group) end
    end
    self.action_epoch = self.action_epoch+1
    self.pending,self.action,self.result = nil,nil,nil
    self:StopMotion()
    local task = self.current
    if task then
        task.continuation = task.continuation or {}
        -- A deployed native plow is still doing work after the item has left inventory.
        if task.continuation.phase~="plowing" then task.continuation.phase="validate" end
        task.continuation.reason=reason
        if self.inst.components.agriresource then self.inst.components.agriresource:Finish(task,false) end
    end
    self.current,self.action_started,self.move_target = nil,nil,nil
    self._heat_item,self._heat_last=nil,nil
    if not preserve_claim then
        local group = self:GetGroup()
        if group and group.scheduler then group.scheduler:Release(self.inst) end
    end
end
function AgriExecutor:Finish(success,reason,immediate,cancelled)
    local task,group = self.current,self:GetGroup()
    if not task then return end
    self.action_epoch = self.action_epoch+1
    self.pending,self.action,self.result = nil,nil,nil
    self:StopMotion()
    local stored = self.inst.components.agriresource:Finish(task,success)
    self.current,self.action_started = nil,nil
    self._heat_item,self._heat_last=nil,nil
    if group and group.scheduler then
        if success then
            group.scheduler:Complete(task.id,self.inst,cancelled)
            local planner = group.primary and group.primary.components.agriplanner
            if planner and planner.OnTaskComplete then planner:OnTaskComplete(task,group) end
            TheWorld.components.agrifarmgroup:MarkDirty(group,task.kind == "HARVEST" and "harvest" or "task_complete")
        else group.scheduler:Fail(task.id,self.inst,reason,immediate) end
    end
    if not stored then U.OnceTalk(self.inst,"working_inventory_full",T.Message("working_inventory_full")) end
end
function AgriExecutor:FindNear(point,predicate,radius,tags)
    if not point then return nil end
    local best,distance
    for _, entity in ipairs(TheSim:FindEntities(point.x,0,point.z,radius or 0.8,tags,{"INLIMBO","FX","NOCLICK"})) do
        if entity ~= self.inst and predicate(entity) then
            local d = U.DistanceSq(position(entity),point)
            if not distance or d < distance or d == distance and entity.GUID < best.GUID then best,distance=entity,d end
        end
    end
    return best
end
function AgriExecutor:Resolve(task)
    if task.kind=="PLANT" then
        if valid(task.target) and task.target:HasTag("soil") and not task.target:HasTag("NOBLOCK") then return task.target end
        -- Soil is a replaceable hole, unlike a specific crop or giant harvest
        -- target. A collapsed, nonpersistent animation is never a usable soil.
        task.target=self:FindNear(task.point,function(e) return e:HasTag("soil") and not e:HasTag("NOBLOCK") end,0.45,{"soil"})
        task.entity_bound=nil
        return task.target
    end
    if valid(task.target) then return task.target end
    if task.entity_bound then return nil end -- An obsolete GUID must not be retargeted to a new crop at the same hole.
    local k,p = task.kind,task.point
    if k == "PLANT" then task.target=self:FindNear(p,function(e) return e:HasTag("soil") end,0.45,{"soil"})
    elseif k == "HARVEST" or k == "TEND" then
        task.target=self:FindNear(p,function(e) return e:HasTag("farm_plant") and not e:HasTag("weed") end,0.65,{"farm_plant"})
    elseif k == "HAMMER" then task.target=self:FindNear(p,function(e) return e:HasTag("oversized_veggie") end,1.6,{"oversized_veggie"})
    elseif k == "CLEAR" then task.target=self:FindNear(p,safe_clear,0.7)
    elseif k == "PICKUP" then task.target=self:FindNear(p,function(e) return safe_pickup(e) and (not task.prefab or e.prefab==task.prefab) end,1.6)
    end
    return task.target
end
function AgriExecutor:Blocker(task)
    if task.kind ~= "TILL" and task.kind ~= "PLOW" then return nil end
    local radius = task.kind == "PLOW" and 2.8 or GetFarmTillSpacing()
    return self:FindNear(task.point,function(e) return safe_pickup(e) or safe_clear(e) end,radius)
end
function AgriExecutor:TrackPlow(task)
    local plow=valid(task.target) and task.target.prefab=="farm_plow" and task.target
    if not plow then
        -- Do not inherit item/plant NOCLICK filters when recognizing this exact
        -- native machine. The deployment callback has already positioned it.
        for _,entity in ipairs(TheSim:FindEntities(task.point.x,0,task.point.z,2.1)) do
            if entity.prefab=="farm_plow" and valid(entity) then plow=entity;break end
        end
    end
    if not plow then return false end
    task.target=plow
    -- Native StartUp waits for animover before starting its drilling timer. Keep
    -- only this claimed native machine awake so off-screen animation can finish.
    plow.entity:SetCanSleep(false)
    task.continuation=task.continuation or {}
    task.continuation.phase="plowing"
    local remaining=plow.components.timer and plow.components.timer:GetTimeLeft("drilling")
    task.continuation.wait_until=math.max(task.continuation.wait_until or 0,
        now()+(remaining or TUNING.FARM_PLOW_DRILLING_DURATION)+C.TASK_TIMEOUT)
    return true
end
function AgriExecutor:Validate(task)
    local k,p = task.kind,task.point
    local target = self:Resolve(task)
    if k == "PLOW" then
        if not p then return "blocked","invalid_terrain" end
        if TheWorld.Map:GetTileAtPoint(p.x,0,p.z)==WORLD_TILES.FARMING_SOIL then return "done" end
        if self:TrackPlow(task) then return "plowing" end
        -- Automatic plowing is disabled. Only an already deployed native plow
        -- (tracked above) is followed; an unstarted job never deploys an item.
        return "blocked","plow_disabled"
    elseif k == "TILL" then
        if not p then return "blocked","invalid_terrain" end
        if task.data and task.data.unsoil then
            if not self:RemovalSoil(task) then return "done" end
            return self:PlowActive(p) and "wait" or "execute"
        end
        if self:FindNear(p,function(e) return e:HasTag("farm_plant") and not e:HasTag("weed") end,0.45) then return "done" end
        if not (task.data and task.data.realign) and self:FindNear(p,function(e) return e:HasTag("soil") end,0.45) then return "done" end
        if not TheWorld.Map:CanTillSoilAtPoint(p.x,0,p.z,false) then
            local blocker = self:Blocker(task)
            if blocker then return "blocker",blocker end
            return "blocked",TheWorld.Map:GetTileAtPoint(p.x,0,p.z)==WORLD_TILES.FARMING_SOIL and "blocked_structure" or "invalid_terrain"
        end
    elseif k == "PLANT" then
        if not valid(target) then
            local plant=self:FindNear(p,function(e) return e:HasTag("farm_plant") and not e:HasTag("weed") end,0.5)
            if plant then return "done" end
            if p and TheWorld.Map:CanTillSoilAtPoint(p.x,0,p.z,false) then return "need_till" end
            return "blocked","missing_soil"
        end
        if not target:HasTag("soil") then return "blocked","safety_stop" end
    elseif k == "HARVEST" then
        if not valid(target) then return "done" end
        local pickable=component(target,"pickable")
        if not pickable or not pickable:CanBePicked() then return "wait" end
        if target:HasTag("weed") then return "blocked","safety_stop" end
    elseif k == "HAMMER" then
        if not valid(target) then return "done" end
        local work=component(target,"workable")
        if not target:HasTag("oversized_veggie") or not work or work:GetWorkAction()~=ACTIONS.HAMMER then return "blocked","safety_stop" end
    elseif k == "PICKUP" then
        if not valid(target) then return "done" end
        if not safe_pickup(target) then return "done" end
    elseif k == "CLEAR" then
        if not valid(target) then return "done" end
        if not safe_clear(target) then return "blocked","safety_stop" end
        task.data.tool_action="DIG"
    elseif k == "TEND" then
        if not valid(target) then return "done" end
        local tend=component(target,"farmplanttendable")
        if not tend or not tend.tendable then return "done" end
    elseif k == "FERTILIZE" or k == "WATER" then
        if not p or TheWorld.Map:GetTileAtPoint(p.x,0,p.z)~=WORLD_TILES.FARMING_SOIL then return "blocked","invalid_terrain" end
        if k == "FERTILIZE" and task.data.verify_nutrients then
            local tx,tz=TheWorld.Map:GetTileCoordsAtPoint(p.x,0,p.z)
            local n={TheWorld.components.farming_manager:GetTileNutrients(tx,tz)}
            local enough=true
            for i=1,3 do if n[i] < (task.data.verify_nutrients[i] or 0) then enough=false end end
            if enough then return "done" end
        elseif k == "WATER" and task.data.water_below then
            -- Simple watering re-reads the soil right before each native use:
            -- rain or another robot may already have wetted it.
            local moisture=Adapter.SoilMoistureAt(TheWorld,p.x,p.z)
            if moisture==nil then return "blocked","moisture_unknown" end
            if moisture>task.data.water_below then return "done" end
        elseif k == "WATER" and task.data.target_moisture then
            local group=self:GetGroup()
            if not group._agri_water_snapshot or now()-(group._agri_water_snapshot_time or -100) > 1 then
                local ok,data=pcall(function() return DecodeAndUnzipSaveData(TheWorld.components.farming_manager:OnSave()) end)
                group._agri_water_snapshot=ok and data and data.moisturegrid or nil
                group._agri_water_snapshot_time=now()
            end
            local tx,tz=TheWorld.Map:GetTileCoordsAtPoint(p.x,0,p.z)
            local w=TheWorld.Map:GetSize()
            local moisture=group._agri_water_snapshot and group._agri_water_snapshot[tz*w+tx]
            if moisture and moisture>=task.data.target_moisture then return "done" end
        end
    end
    return "execute"
end
function AgriExecutor:PushChild(task,child)
    local group=self:GetGroup()
    if not group or not group.scheduler then return false end
    local n=task.continuation and task.continuation.blocker_rescans or 0
    if child.kind=="PICKUP" or child.kind=="CLEAR" then
        if n>=3 then self:Finish(false,"blocked_structure",true);return false end
        task.continuation=task.continuation or {}
        task.continuation.blocker_rescans=n+1
    else
        task.continuation=task.continuation or {}
        local attempts=task.continuation.resource_rescans or 0
        if attempts>=C.MAX_RETRIES then self:Finish(false,"resources_unavailable",true);return false end
        task.continuation.resource_rescans=attempts+1
    end
    return group.scheduler:PushSubtask(self.inst,task,child) ~= nil
end
function AgriExecutor:HandleResourceFailure(task,reason)
    local group=self:GetGroup()
    local depth,parent=0,task
    while parent and parent.parent_id do
        depth=depth+1
        parent=group.scheduler.tasks[parent.parent_id]
    end
    if depth>=3 then self:Finish(false,reason,true);return end
    if reason=="need_fetch" and valid(group.warehouse) then
        self:PushChild(task,{kind="FETCH",target=group.warehouse,point=position(group.warehouse),data={requirements=self.inst.components.agriresource:Demand(group,task)}})
    elseif (reason=="output_full" or reason=="working_inventory_full") and valid(group.warehouse) then
        self:PushChild(task,{kind="UNLOAD",target=group.warehouse,point=position(group.warehouse),data={}})
    elseif reason=="out_of_water" then
        self:PushChild(task,{kind="REFILL",data={}})
    elseif reason=="needs_heat" then
        self:PushChild(task,{kind="HEAT",prefab=task.data.heat_prefab,data={}})
    else self:Finish(false,reason,true) end
end
function AgriExecutor:QueueAction(action,subkind)
    local task=self.current
    self.action_epoch=self.action_epoch+1
    local epoch=self.action_epoch
    local previous_valid=action.validfn
    action.validfn=function(act)
        local group=self:GetGroup()
        return self.current==task and self.action_epoch==epoch and group and group.scheduler
            and group.settings and group.settings.running==true and not group.scheduler:IsFrozen() and (previous_valid==nil or previous_valid(act))
    end
    self.action,self.pending,self.action_started,self.action_subkind=action,action,now(),subkind
    action:AddSuccessAction(function()
        if self.current==task and self.action_epoch==epoch then
            -- Wake it in the same call stack as successful native deployment,
            -- before the startup animation can enter an off-screen sleep state.
            if task.kind=="PLOW" and subkind=="native" then self:TrackPlow(task) end
            self.result={success=true,subkind=subkind}
        end
    end)
    action:AddFailAction(function()
        if self.current==task and self.action_epoch==epoch then self.result={success=false,reason=action.reason or "action_rejected",subkind=subkind} end
    end)
    self:GetGroup().scheduler:Running(task,self.inst)
end
function AgriExecutor:WalkNear(point,distance)
    if U.DistanceSq(position(self.inst),point) <= distance*distance then return true end
    local action=BufferedAction(self.inst,nil,ACTIONS.WALKTO,nil,vector(point))
    action.arrivedist=distance
    self:QueueAction(action,"move")
    return false
end
function AgriExecutor:FindWaterSource(group)
    local p=group.center
    local best,distance
    for _, source in ipairs(TheSim:FindEntities(p.x,0,p.z,group.settings.radius,{"watersource"},{"INLIMBO"})) do
        if source.components.watersource and source.components.watersource.available then
            local d=self.inst:GetDistanceSqToInst(source)
            if not distance or d<distance then best,distance=source,d end
        end
    end
    return best
end
-- An off-grid natural hole (intact or broken) exactly at this point. Soils
-- still bound to a working plow are left alone. With a planned GUID only that
-- entity matches: a hole that reappears at the point is a new removal task.
function AgriExecutor:StraySoil(p,guid)
    for _,entity in ipairs(TheSim:FindEntities(p.x,0,p.z,0.15,{"soil"},{"INLIMBO"})) do
        if valid(entity) and entity.prefab=="farm_soil" and entity._plow==nil and (guid==nil or entity.GUID==guid) then return entity end
    end
end
function AgriExecutor:RemovalSoil(task)
    local soil=task.target
    if valid(soil) then return soil.prefab=="farm_soil" and soil:HasTag("soil") and soil._plow==nil and soil or nil end
    if task.entity_bound then return nil end -- That hole is gone; a new one gets its own task.
    return self:StraySoil(task.point,task.data.soil_guid)
end
-- A deployed native plow is still drilling this tile; its soils are not ours.
function AgriExecutor:PlowActive(p)
    local tx,tz=TheWorld.Map:GetTileCoordsAtPoint(p.x,0,p.z)
    for _,entity in ipairs(TheSim:FindEntities(p.x,0,p.z,3)) do
        if entity.prefab=="farm_plow" and valid(entity) then
            local ex,_,ez=entity.Transform:GetWorldPosition()
            local px,pz=TheWorld.Map:GetTileCoordsAtPoint(ex,0,ez)
            if px==tx and pz==tz then return true end
        end
    end
    return false
end
function AgriExecutor:Manual(task,group)
    local k=task.kind
    local resource=self.inst.components.agriresource
    if k=="TILL" and task.data and task.data.unsoil then
        if not self:WalkNear(task.point,1.2) then return true end
        -- Native farm_soil collapse: the same event a nearby till sends.
        local soil=self:RemovalSoil(task)
        if soil then soil:PushEvent("collapsesoil") end
        self:Finish(true)
        return true
    end
    if k=="FETCH" or k=="UNLOAD" then
        local requirements=task.data.requirements or task.data.manifest
        if k=="FETCH" then
            local enough=true
            for _,category in ipairs({"seeds","fertilizers"}) do
                for prefab,amount in pairs(requirements and requirements[category] or {}) do
                    amount=type(amount)=="table" and amount.count or amount
                    local carried=resource:CountPrefab(prefab,category=="fertilizers")
                    if task.data.manifest then
                        carried=0
                        for _,robot in ipairs(group.members) do
                            local r=robot.components.agriresource
                            if r then carried=carried+r:CountPrefab(prefab,category=="fertilizers") end
                        end
                    end
                    if carried<(amount or 0) then enough=false end
                end
            end
            if enough then self:Finish(true);return true end
        end
        if not valid(group.warehouse) then self:Finish(false,"no_warehouse",true);return true end
        if not self:WalkNear(position(group.warehouse),3.3) then return true end
        local success,reason
        if k=="FETCH" then success,reason=resource:Fetch(group,requirements)
        else success,reason=resource:Unload(group) end
        self:Finish(success,reason,not success)
        return true
    elseif k=="HEAT" then
        local thermal=self.inst.components.agrithermal
        local item
        for _, candidate in ipairs(resource:OwnItems()) do
            if thermal:IsWhitelisted(candidate) and not thermal:HeatReady(candidate)
                and (not task.prefab or task.prefab==candidate.prefab) then item=candidate;break end
        end
        if not item then self:Finish(true);return true end
        local furnace=thermal:FindFurnace(group)
        if not valid(furnace) then self:Finish(false,"no_furnace",true);return true end
        if not self:WalkNear(position(furnace),1.8) then return true end
        task.continuation=task.continuation or {}
        if self._heat_item~=item then self._heat_item,self._heat_last=item,now() end
        local elapsed=math.max(0,math.min(now()-(self._heat_last or now()),C.EXECUTOR_INTERVAL*2))
        self._heat_last=now()
        task.continuation.active_heat_seconds=(task.continuation.active_heat_seconds or 0)+elapsed
        if task.continuation.active_heat_seconds>180 then self:Finish(false,"heat_timeout",true);return true end
        -- No tool transfer to the furnace or temperature setter. Native item
        -- temperature in agrithermal is the one authority for passive response.
        return true
    elseif k=="MUSIC_TEND" then
        local hasrecord=false
        for _, item in ipairs(resource:OwnItems()) do if item:HasTag("phonograph_record") then hasrecord=true;break end end
        if not hasrecord then self:Finish(false,"missing_record",true);return true end
        if task.point and not self:WalkNear(task.point,0.75) then return true end
        if now()-self.last_music<TUNING.WX78_MUSIC_UPDATERATE then return true end
        self.last_music=now()
        local x,y,z=self.inst.Transform:GetWorldPosition()
        for _, plant in ipairs(TheSim:FindEntities(x,y,z,TUNING.WX78_MUSIC_RANGE,{"farm_plant"},{"INLIMBO"})) do
            if plant.components.farmplanttendable then plant.components.farmplanttendable:TendTo(self.inst) end
        end
        self:Finish(true)
        return true
    end
    return false
end
function AgriExecutor:Begin(task,group)
    local state,reason=self:Validate(task)
    if state=="done" then self:Finish(true);return end
    if state=="wait" then
        task.not_before=now()+C.SCAN_INTERVAL
        group.scheduler:Release(self.inst)
        self.current=nil
        return
    end
    if state=="plowing" then return end
    if state=="need_till" then
        self:PushChild(task,{kind="TILL",point=task.point,data={cell=task.data.cell,restore_hole=true}})
        return
    end
    if state=="blocked" then self:Finish(false,reason,true);return end
    if state=="blocker" then
        local entity=reason
        self:PushChild(task,{kind=safe_pickup(entity) and "PICKUP" or "CLEAR",target=entity,point=position(entity),data={tool_action=safe_clear(entity) and "DIG" or nil}})
        return
    end
    if task.kind=="PLOW" then self:Finish(false,"plow_disabled",true);return end
    if self:Manual(task,group) then return end
    if task.kind=="REFILL" then
        task.target=self:FindWaterSource(group)
        if not valid(task.target) then self:Finish(false,"no_water_source",true);return end
        task.point=position(task.target)
    end
    local ok,resource_reason,item=self.inst.components.agriresource:Prepare(task,group)
    if not ok then
        if task.kind=="REFILL" and resource_reason=="no_empty_can" then self:Finish(true);return end
        self:HandleResourceFailure(task,resource_reason)
        return
    end
    if task.kind=="FERTILIZE" and not (item and item.components.deployable) then
        self:Finish(false,"unsupported_fertilizer",true);return
    end
    local actionname=T.ACTIONS[task.kind]
    if task.kind=="CLEAR" then actionname="DIG" end
    if not actionname or not ACTIONS[actionname] then self:Finish(false,"unknown_action",true);return end
    local target=task.target
    if task.kind=="TILL" or task.kind=="FERTILIZE" or task.kind=="WATER" then target=nil end
    local point=(task.kind=="TILL" or task.kind=="FERTILIZE" or task.kind=="WATER") and vector(task.point) or nil
    local action=BufferedAction(self.inst,target,ACTIONS[actionname],item,point)
    action.validfn=function()
        local currentgroup=self:GetGroup()
        return self.current==task and currentgroup==group and not group.scheduler:IsFrozen()
            and (target==nil or valid(target))
    end
    if task.kind=="REFILL" then task._refill_before=item.components.finiteuses:GetUses() end
    self:QueueAction(action,"native")
end
function AgriExecutor:ActionResult(group)
    local result,task=self.result,self.current
    self.result,self.action,self.pending,self.action_started=nil,nil,nil,nil
    if not task then return end
    if not result.success then self:Finish(false,result.reason);return end
    if result.subkind=="move" then return end
    local item=task.invobject
    local refillprogress=task.kind~="REFILL" or valid(item) and item.components.finiteuses:GetUses()>(task._refill_before or -1)
    self.inst.components.agriresource:Finish(task,true)
    task.count_done=(task.count_done or 0)+1
    task.continuation={phase="validate",count_done=task.count_done}
    if task.kind=="WATER" then group._agri_water_snapshot=nil end
    if task.kind=="HAMMER" or task.kind=="CLEAR" then
        if valid(task.target) and task.target.components.workable and task.target.components.workable:CanBeWorked() then return end
    elseif task.kind=="REFILL" then
        if not refillprogress then self:Finish(false,"refill_no_progress",true);return end
        task.data.can_guid=nil
        if self.inst.components.agriresource:FindActionItem(task) then return end
    elseif task.kind=="PLOW" then
        -- Native plow finishes asynchronously and returns the remaining real item on the ground.
        task.continuation.phase="plowing"
        task.continuation.wait_until=now()+TUNING.FARM_PLOW_DRILLING_DURATION+C.TASK_TIMEOUT
        self:TrackPlow(task)
        return
    end
    self:Finish(true)
end
function AgriExecutor:Tick()
    if not valid(self.inst) or not TheWorld.ismastersim then return end
    local group=self:GetGroup()
    local scheduler=group and group.scheduler
    if not scheduler then return end
    if not group.settings or group.settings.running~=true or scheduler.group~=group then
        if self.current then self:Interrupt("stopped_or_unbound",true) end
        return
    end
    scheduler:Renew(self.inst)
    if scheduler:IsFrozen() then if self.current then self:Interrupt("emergency_or_stopped",true) end;return end
    if self.current and scheduler:HigherPriority(self.current,self.inst) then scheduler:Pause(self.inst,"priority");return end
    if self.result then self:ActionResult(group) end
    if self.action then
        if now()-self.action_started>C.TASK_TIMEOUT then self:Finish(false,"path_timeout") end
        return
    end
    -- Native success fires mid-animation; do not dispatch the next job into the
    -- old state's onexit. This also keeps multi-can refill actions sequential.
    if self.inst.sg and self.inst.sg:HasStateTag("busy") then return end
    local task=self.current
    if not task then
        task=scheduler:Claim(self.inst)
        if not task then
            local resource=self.inst.components.agriresource
            if valid(group.warehouse) and resource:NeedsUnload(true) then
                local id="idle_unload:"..tostring(self.inst.GUID)
                local old=scheduler.tasks[id]
                if old and (old.state=="complete" or old.state=="cancelled") then
                    old.state,old.reason,old.retries="pending",nil,0
                elseif not old then
                    scheduler:Add({id=id,kind="UNLOAD",priority=3,reserved_owner=self.inst.GUID,data={batch=true}})
                end
                task=scheduler:Claim(self.inst)
            end
            if not task then return end
        end
        self.current=task
        if self.inst._agri_statusnet then self.inst._agri_statusnet:set(task.kind) end
    end
    if task.continuation and task.continuation.phase=="plowing" then
        local p=task.point
        if TheWorld.Map:GetTileAtPoint(p.x,0,p.z)==WORLD_TILES.FARMING_SOIL then self:Finish(true)
        elseif now()>(task.continuation.wait_until or 0) then self:Finish(false,"plow_timeout",true) end
        return
    end
    if task.kind~="UNLOAD" and task.kind~="FETCH" and task.kind~="REFILL" and task.priority==3
        and self.inst.components.agriresource:NeedsUnload() and valid(group.warehouse) then
        self:PushChild(task,{kind="UNLOAD",target=group.warehouse,point=position(group.warehouse),data={}})
        return
    end
    self:Begin(task,group)
end
function AgriExecutor:OnRemoveFromEntity()
    if self._task then self._task:Cancel() end
    self:Interrupt("removed",false)
end
function AgriExecutor:Stop(reason) self:Interrupt(reason or "stopped",false) end
return AgriExecutor
