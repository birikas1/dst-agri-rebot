local Adapter=require("agri/source_adapter")
local Solver=require("agri/crop_solver")
local Season=require("agri/season_predictor")
local Moisture=require("agri/moisture_sim")
local Tending=require("agri/tending_sim")
local Fertilizer=require("agri/fertilizer_solver")
local Nutrients=require("agri/nutrient_sim")
local Layout=require("agri/layout_planner")
local U=require("agri/util")
local C=require("agri/constants")
local T=require("agri/task_types")
local Simple=require("agri/simple_planner")
local function positionkey(p) return string.format("%.2f:%.2f",p.x,p.z) end
local function shallow(t) local o={};for k,v in pairs(t or {}) do o[k]=v end;return o end
local function reasons(search)
    local out={};for _,code in ipairs(U.Keys(search.reason_counts)) do out[#out+1]={code=code,count=search.reason_counts[code]} end
    if not search.complete then out[#out+1]={code="SEARCH_PENDING",nodes=search.nodes} end
    return out
end
local function task(tasks,id,kind,p,extra)
    local t={id=id,kind=kind,point=p,priority=3,deps={},state="pending",count=1,data={}}
    for k,v in pairs(extra or {}) do t[k]=v end
    tasks[#tasks+1]=t;return t
end
-- Simple management waters the measured soil of a plot with living crops,
-- whether or not the old stage forecast is known or still recoverable. A task
-- is one native use; the next plan reads the soil again. Soil above the level
-- that would last two plan intervals counts as moist and is not watered.
local function simple_water(tasks,summary,snapshot,cell,base_drain,drink)
    local tile=cell.moisture or {}
    local function note(code) summary.water_reasons[#summary.water_reasons+1]={code=code,cell=cell.key} end
    if type(tile.moisture)~="number" then note("WATER_MOISTURE_UNKNOWN");return end
    local first=(tile.weather or {})[1]
    local loss=(base_drain or 0)+drink-(first and first.rain or 0)
    if loss<0 then return end -- Current rain is already wetting this plot.
    local water=snapshot.resources.water or {}
    local per_use=water.soil_per_use or water.per_use or 0
    local threshold=loss*C.PLAN_INTERVAL*2
    if per_use>0 then threshold=math.min(threshold,per_use*.5) end
    if tile.moisture>threshold then return end
    local carried,uses=0,0
    for _,can in ipairs(water.cans or {}) do if can.carried~=false then carried=carried+1;uses=uses+(can.uses or 0) end end
    if #(water.cans or {})==0 then note("WATER_NO_CAN");return end
    if carried==0 then note("WATER_CAN_NOT_CARRIED");return end
    -- An empty can still gets the job: the executor turns it into REFILL, or
    -- into the visible no_water_source stop when no source is in range.
    if uses<=0 then note(water.has_source and "WATER_REFILLING" or "WATER_NO_SOURCE") end
    local id=(snapshot.water_tasks or {})[cell.key] or "water:"..cell.key..":"..tostring(math.floor(snapshot.now/C.PLAN_INTERVAL))
    task(tasks,id,"WATER",{x=cell.x,z=cell.z},{priority=3,data={cell=cell.key,simple=true,water_below=threshold,measured=tile.moisture,per_use=per_use}})
    summary.water_uses=summary.water_uses+1
end
local AgriPlanner=Class(function(self,inst)
    self.inst=inst;self.search=nil;self.preview_searches={};self.hole_cycles={}
end)
function AgriPlanner:Capture(group)
    local snapshot=Adapter.Capture(group,self.inst)
    group.hole_cycles=group.hole_cycles or self.hole_cycles or {};self.hole_cycles=group.hole_cycles
    local present={}
    for _,cell in ipairs(snapshot.cells) do for _,plant in ipairs(cell.plants) do present[positionkey(plant.point)]=plant.entity and plant.entity.GUID or plant.id end end
    for key,record in pairs(group.hole_cycles) do
        local guid=present[key]
        if record.plant_guid and record.plant_guid~=guid then record.generation=(record.generation or 0)+1 end
        record.plant_guid=guid;record.had_crop=record.had_crop or guid~=nil
    end
    for key,guid in pairs(present) do if not group.hole_cycles[key] then group.hole_cycles[key]={generation=0,plant_guid=guid,had_crop=true} end end
    snapshot.hole_cycles=group.hole_cycles;snapshot.group_id=group.id;snapshot.epoch=group.planner_epoch or 0;snapshot.settings=group.settings
    return snapshot
end
function AgriPlanner:Signature(snapshot,settings,presets)
    local out={tostring(snapshot.revision),tostring(snapshot.world.season),settings.mode,tostring(settings.density),tostring(settings.allow_random),settings.planting or "auto",settings.crop or ""}
    for _,key in ipairs(U.Keys((snapshot.resources or {}).seeds)) do out[#out+1]=key.."="..snapshot.resources.seeds[key] end
    for _,key in ipairs(U.Keys((snapshot.resources or {}).fertilizers)) do local f=snapshot.resources.fertilizers[key];out[#out+1]=key.."="..tostring(f.count)..":"..table.concat(f.nutrients or {},",") end
    local water=snapshot.resources.water or {};out[#out+1]="water="..tostring(water.uses)..":"..tostring(water.has_source)
    for _,key in ipairs(U.Keys(snapshot.resources.tools)) do local tool=snapshot.resources.tools[key];out[#out+1]=key.."="..tostring(tool.uses)..":"..tostring(tool.replenishable) end
    for _,cell in ipairs(snapshot.cells) do
        out[#out+1]=cell.key..":"..tostring(cell.is_farm)..":"..table.concat(cell.nutrients or {},",")
        for _,p in ipairs(cell.plants) do out[#out+1]=p.id..":"..tostring(p.stage) end
        for _,soil in ipairs(cell.soils or {}) do out[#out+1]="soil:"..tostring(soil.id) end
    end
    for _,entry in ipairs(snapshot.killjoys or {}) do out[#out+1]="killjoy:"..tostring(entry.id) end
    for _,entry in ipairs(snapshot.lights or {}) do out[#out+1]="light:"..tostring(entry.id)..":"..tostring(entry.radius) end
    for _,entry in ipairs(snapshot.debris or {}) do out[#out+1]="debris:"..tostring(entry.id)..":"..tostring(entry.work) end
    for _,entry in ipairs(snapshot.obstacles or {}) do out[#out+1]="obstacle:"..tostring(entry.id)..":"..positionkey(entry.point) end
    for _,entry in ipairs(snapshot.pickups or {}) do out[#out+1]="pickup:"..tostring(entry.id)..":"..positionkey(entry.point) end
    local preset=(presets or {})[snapshot.world.season] or {}
    out[#out+1]=tostring(preset.mode)..":"..tostring(preset.crop)
    for _,key in ipairs(U.Keys(preset.ratio)) do out[#out+1]=key..":"..tostring(preset.ratio[key]) end
    return table.concat(out,"|")
end
function AgriPlanner:Maintenance(snapshot,skip_preparation)
    local tasks,summary={}, {water_uses=0,tending=0,harvests=0,fertilizer=0,viability_failures={},water_reasons={}}
    local plants={}
    -- Only an explicit simple=false keeps the forecast-gated watering below.
    local simple=not (snapshot.settings and snapshot.settings.simple==false)
    for _,cell in ipairs(snapshot.cells) do
        local crops={};local tile=shallow(cell.moisture);local base_drain=tile.drain or 0;local drink,horizon,nightdrink,living=0,0,0,0
        tile.water_per_use=snapshot.resources.water and (snapshot.resources.water.soil_per_use or snapshot.resources.water.per_use)
        for _,p in ipairs(cell.plants) do
            plants[#plants+1]=p
            if p.mature then
                task(tasks,"harvest:"..p.id,"HARVEST",p.point,{target=p.entity,priority=3,deadline=p.remaining and snapshot.now+p.remaining,data={crop=p.crop,cell=cell.key,hole_key=positionkey(p.point)}})
                summary.harvests=summary.harvests+1
            else
                local c=shallow(p);c.growth=Season.Predict(p.def,snapshot.world,p)
                if not c.growth.feasible then
                    summary.viability_failures[#summary.viability_failures+1]={cluster=cell.key,crop=p.id,reason=c.growth.reason,kind="prediction_unknown"}
                elseif snapshot.settings and snapshot.settings.mode=="oversized" and not c.growth.oversized_eligible then
                    summary.viability_failures[#summary.viability_failures+1]={cluster=cell.key,crop=p.id,reason="SEASON_STRESS",kind="oversized_eligibility"}
                end
                if c.growth.feasible then c.remaining=c.growth.stages[1] and c.growth.stages[1].latest end
                if c.growth.feasible then crops[#crops+1]=c end
                living=living+1
                local rate=math.abs((p.def.moisture or {}).drink_rate or p.moisture and p.moisture.rate or 0);drink=drink+rate;if p.night_light then nightdrink=nightdrink+rate end;horizon=math.max(horizon,c.remaining or 0)
            end
        end
        if simple and living>0 then simple_water(tasks,summary,snapshot,cell,base_drain,drink) end
        if #crops>0 then
            local water={}
            if not simple then
                tile.drain=base_drain+drink;tile.weather=Season.EnvironmentTimeline(snapshot.world,horizon,base_drain,drink,tile.weather,nightdrink)
                water=Moisture.Predict(tile,crops)
            end
            if water.feasible and water.water>0 and (water.due or 0)<=C.PLAN_INTERVAL*2 then
                -- One native use, followed by a fresh soil read. Additional uses
                -- are not sent blindly when rain or another robot already helped.
                task(tasks,"water:"..cell.key..":"..tostring(math.floor(snapshot.now/C.PLAN_INTERVAL)),"WATER",{x=cell.x,z=cell.z},
                    {priority=3,not_before=snapshot.now+math.max(0,(water.due or 0)-C.PLAN_INTERVAL*2),data={cell=cell.key,required_water=water.now_water,
                        target_moisture=(tile.moisture or 0)+math.min(water.now_water,tile.water_per_use or 0),projection=water}})
                summary.water_uses=summary.water_uses+1
            end
            local imminent={};local deadline=math.huge
            for _,p in ipairs(crops) do
                local near=shallow(p);near.growth={stages={}}
                for _,stage in ipairs(p.growth.stages) do if stage.earliest<=C.PLAN_INTERVAL*2 then
                    near.growth.stages[#near.growth.stages+1]=stage;deadline=math.min(deadline,stage.earliest)
                end end
                if #near.growth.stages>0 then imminent[#imminent+1]=near end
            end
            if #imminent>0 then
                local projection=Nutrients.Simulate(imminent,cell.nutrients,snapshot.tuning.nutrient_capacity)
                local deficit=projection.deficit;local target_nutrients={}
                for i=1,3 do
                    target_nutrients[i]=math.min(snapshot.tuning.nutrient_capacity or math.huge,(cell.nutrients[i] or 0)+deficit[i])
                    deficit[i]=math.max(0,target_nutrients[i]-(cell.nutrients[i] or 0))
                end
                local choice=Fertilizer.Solve(deficit,snapshot.resources.fertilizers)
                if choice.feasible then for name,count in pairs(choice.items) do
                    for n=1,count do task(tasks,"fertilize:"..cell.key..":"..tostring(math.floor(snapshot.now/C.PLAN_INTERVAL))..":"..name..":"..n,"FERTILIZE",{x=cell.x,z=cell.z},
                        {prefab=name,priority=3,deadline=snapshot.now+deadline,data={cell=cell.key,verify_nutrients=target_nutrients,emergency=true,projection=projection}}) end
                    summary.fertilizer=summary.fertilizer+count
                end end
            end
        end
    end
    local tending=Tending.Predict(plants,snapshot.resources.music,snapshot.tuning.music_range,snapshot.legal_music)
    for index,action in ipairs(tending.actions) do
        local suffix=table.concat(action.plants,",")
        local stage="";for _,p in ipairs(plants) do if U.Contains(action.plants,p.id) then stage=stage..":"..tostring(p.stage) end end
        task(tasks,"tend:"..suffix..stage,action.kind,action.point,{target=action.target,priority=3,data={plants=action.plants,radius=action.radius}})
        summary.tending=summary.tending+1
    end
    for _,entity in ipairs(snapshot.oversized or {}) do
        task(tasks,"hammer:"..tostring(entity.GUID),"HAMMER",{x=entity.x,z=entity.z},{target=entity.entity,priority=3,data={oversized=true}})
    end
    for _,entry in ipairs(snapshot.pickups or {}) do task(tasks,"pickup:"..entry.id,"PICKUP",entry.point,
        {target=entry.entity,prefab=entry.prefab,priority=entry.priority or 3,data={blocker=entry.blocker==true}}) end
    for _,entry in ipairs(snapshot.debris or {}) do task(tasks,"clear:"..entry.id,"CLEAR",entry.point,{target=entry.entity,priority=3,data={cell=entry.cell,safe=true,tool_action="DIG"}}) end
    -- Preparing empty, already cultivated plots does not spend seeds or bypass
    -- the complete-round planting check. It also makes a missing input visible
    -- without leaving an otherwise usable hoe idle.
    local hoe=snapshot.resources.tools and snapshot.resources.tools.hoe
    if not skip_preparation and hoe and ((hoe.uses or 0)>0 or hoe.replenishable) then
        for _,cluster in ipairs(Layout.Clusters(snapshot.cells)) do
            local empty=true;for _,cell in ipairs(cluster.cells) do if not cell.is_farm or #(cell.plants or {})>0 then empty=false end end
            if empty then
                local density=snapshot.settings and snapshot.settings.density or "dynamic"
                if density=="dynamic" then density=9 end
                local holes=Layout.Holes(cluster,density,snapshot.tuning.min_spacing,snapshot.legal_hole)
                for _,hole in ipairs(holes or {}) do if not hole.soil then
                    local key=positionkey(hole.point);local record=(snapshot.hole_cycles or {})[key] or {}
                    local id=(snapshot.group_id or "farm")..":epoch:"..tostring(snapshot.epoch or 0)..":"..key..":"..tostring(record.generation or 0)..":till"
                    local deps={};for _,entry in ipairs(snapshot.debris or {}) do if entry.cell==hole.cell then deps[#deps+1]="clear:"..entry.id end end
                    task(tasks,id,"TILL",hole.point,{deps=deps,data={cell=hole.cell,preparation=true,realign=hole.realign==true}})
                end end
            end
        end
    end
    return tasks,summary
end
function AgriPlanner:Tasks(snapshot,candidates,initial)
    local tasks=initial or {};local group=snapshot.group_id or "farm";local now=snapshot.projection_base or snapshot.now or 0
    for _,candidate in ipairs(candidates) do
        local prefix=group..":epoch:"..tostring(snapshot.epoch or 0)..":"..candidate.id
        local startdeps={}
        -- Per-action Prepare inserts a batched FETCH only when actual local
        -- stock requires a warehouse trip. The round is already fully checked.
        -- Automatic plowing is disabled here too: no PLOW task is created for
        -- uncultivated blueprint cells (the solver also rejects them without
        -- a plow tool). Plantings there wait on manual cultivation.
        local plows={}
        local planting_tasks={}
        for _,crop in ipairs(candidate.assignment) do
            if not crop.existing then
                local key=positionkey(crop.point);local record=(snapshot.hole_cycles or {})[key] or {generation=0}
                local generation=(record.generation or 0)+(crop.harvest and 1 or 0)
                local base=group..":epoch:"..tostring(snapshot.epoch or 0)..":"..key..":"..generation
                local deps=U.Copy(startdeps)
                if plows[crop.cell] then deps[#deps+1]=plows[crop.cell] end
                for _,id in ipairs((snapshot.plow_dependencies or {})[crop.cell] or {}) do deps[#deps+1]=id end
                for _,entry in ipairs(snapshot.debris or {}) do if entry.cell==crop.cell then deps[#deps+1]="clear:"..entry.id end end
                if crop.harvest then deps[#deps+1]="harvest:"..crop.harvest.id end
                if not crop.soil then local till=task(planting_tasks,base..":till","TILL",crop.point,{deps=deps,data={cell=crop.cell,realign=crop.realign==true}});deps={till.id} end
                task(planting_tasks,base..":plant","PLANT",crop.point,{target=crop.soil,prefab=crop.def.seed,deps=deps,data={crop=crop.crop,cell=crop.cell,hole_key=key,round=candidate.id,generation=generation,full_preflight=true,season=snapshot.world.season}})
            end
        end
        -- Reserve deadline-bearing fertilizer positions before the planting
        -- backlog is appended. This is the initial FIFO order, not a rescan
        -- priority bump; not_before still prevents unnecessary early spending.
        for _,action in ipairs(candidate.fertilizer_actions) do
            local deps=U.Copy(startdeps);if plows[action.cell] then deps[#deps+1]=plows[action.cell] end
            for _,name in ipairs(U.Keys(action.choice.items)) do for n=1,action.choice.items[name] do
                local id=prefix..":fert:"..action.cell..":"..action.window..":"..name..":"..n
                task(tasks,id,"FERTILIZE",action.point,{prefab=name,deps=U.Copy(deps),priority=3,
                    not_before=now+math.max(0,action.before-C.PLAN_INTERVAL*2),deadline=now+action.before,
                    data={cell=action.cell,verify_nutrients=action.required,checkpoint=action.window,full_preflight=true}})
                deps={id}
            end end
        end
        for _,pending in ipairs(planting_tasks) do tasks[#tasks+1]=pending end
    end
    return tasks
end
function AgriPlanner:Result(snapshot,search)
    local tasks,maintenance=self:Maintenance(snapshot)
    local chosen=search.dispatch_best or (search.complete and search.best or {})
    local plan={status=#chosen>0 and "ready" or search.complete and search.status or "waiting",clusters={},tasks=tasks,reasons=reasons(search),
        recommendations={},viability_failures=maintenance.viability_failures,summary={nodes=search.nodes,search_pending=not search.complete,feasible_count=search.feasible_count,
            recommendation_count=#search.recommendations,maintenance=maintenance,source_build=C.SOURCE_BUILD,complete_round=#chosen>0,
            optimality=(search.dispatch_best and search.dispatch_search_complete or not search.dispatch_best and search.complete) and "complete" or "best_known",snapshot_at=search.snapshot.now,
            layout_failures=search.layout_failures},generated_at=snapshot.now}
    if #chosen>0 then
        snapshot.projection_base=(search.dispatch_snapshot or search.snapshot).now
        self:Tasks(snapshot,chosen,tasks)
        for _,candidate in ipairs(chosen) do plan.clusters[#plan.clusters+1]=Solver.Summary(candidate) end
    end
    for _,code in ipairs(snapshot.reasons or {}) do plan.reasons[#plan.reasons+1]={code=code} end
    plan.recommendations=Solver.Page(search,0,8)
    return plan
end
function AgriPlanner:Build(snapshot,settings,presets)
    local search=Solver.NewSearch(snapshot,settings,presets);Solver.Resume(search,6000)
    return self:Result(snapshot,search)
end
local function live(t) return t.state~="complete" and t.state~="cancelled" and t.state~="failed" end
-- Simple branch: density + per-crop counts decide everything. The original
-- search planner below is kept for reference but is no longer called.
function AgriPlanner:PlanSimple(group,snapshot)
    snapshot.center=group.center
    local settings=group.settings
    local plan_key={}
    for _,crop in ipairs(U.Keys(settings.plan or {})) do plan_key[#plan_key+1]=crop.."="..tostring(settings.plan[crop]) end
    local config=table.concat({"simple",tostring(settings.radius),tostring(settings.density),table.concat(plan_key,",")},"|")
    -- Hole preparation is named by a layout generation: the planner epoch at
    -- the last radius/density change, persisted as "#L<n>" in planner_config.
    -- Plan-only changes keep it, so queued tills and removals keep their ids;
    -- any layout change (also back to an earlier one) takes the new epoch, so
    -- completed tills of an older layout are never reused.
    local layout_key=tostring(settings.radius).."|"..tostring(settings.density)
    local saved,saved_layout=group.planner_config,nil
    if saved then
        local base,generation=saved:match("^(.*)#L(%d+)$")
        saved=base or saved;saved_layout=generation and tonumber(generation)
    end
    local scheduler=group.scheduler;local cancellations={};local changed=false
    if saved and saved~=config then
        changed=true
        group.planner_epoch=(group.planner_epoch or 0)+1;snapshot.epoch=group.planner_epoch
        for id,t in pairs(scheduler and scheduler.tasks or {}) do
            if live(t) and (t.kind=="PLANT" or t.kind=="PLOW" or t.kind=="FETCH")
                and not (t.continuation and t.continuation.phase=="plowing") then cancellations[#cancellations+1]=id end
        end
    end
    -- Saves from before the suffix named tills by the planner epoch itself.
    local layout=group.planner_epoch or 0
    if saved_layout and saved and saved:match("^simple|([^|]*|[^|]*)|")==layout_key then layout=saved_layout end
    group.planner_config=config.."#L"..tostring(layout)
    -- Automatic plowing is disabled: no plowable-ground scan and no new PLOW.
    -- Only a native plow already deployed by an older version still counts
    -- as farmland on its way.
    local active=0
    for id,t in pairs(scheduler and scheduler.tasks or {}) do
        if t.kind=="PLOW" and live(t) and t.state~="blocked" and t.continuation and t.continuation.phase=="plowing"
            and not U.Contains(cancellations,id) then active=active+1 end
    end
    local result=Simple.Build(snapshot,settings,{group_id=group.id,epoch=group.planner_epoch or 0,layout_epoch=tostring(layout),hole_cycles=snapshot.hole_cycles,
        active_plows=active})
    -- Tills the new plan no longer names (other layout, fewer plots, child
    -- restores of cancelled plantings) are cancelled; the rest continue.
    if changed then
        local keep={};for _,t in ipairs(result.tasks) do keep[t.id]=true end
        for id,t in pairs(scheduler and scheduler.tasks or {}) do
            if t.kind=="TILL" and live(t) and not keep[id] then cancellations[#cancellations+1]=id end
        end
    end
    -- A plan shrink cancelled these tills under the same layout generation;
    -- when the plan grows back, the same ids are pending again instead of
    -- staying cancelled forever (SetPlan never re-adds an existing id).
    if settings.planting~="pause" then
        for _,t in ipairs(result.tasks) do
            local old=t.kind=="TILL" and scheduler and scheduler.tasks and scheduler.tasks[t.id]
            if old and old.state=="cancelled" and old.reason=="plan_invalidated" then
                old.state,old.reason,old.retries,old.continuation="pending",nil,0,nil
            end
        end
    end
    -- One live water job per plot. A queued, running or refill-suspended job
    -- keeps its id across rescans, so no second native use is stacked on it;
    -- a blocked one is retired so the next fresh soil read can retry.
    local water_tasks,retired={},{}
    for _,id in ipairs(scheduler and scheduler.order or {}) do
        local t=scheduler.tasks[id]
        if t and t.kind=="WATER" and not t.parent_id and live(t) and t.data and t.data.cell then
            if t.state=="blocked" or water_tasks[t.data.cell] and t.state~="claimed" and t.state~="running" then retired[#retired+1]=id
            elseif not water_tasks[t.data.cell] then water_tasks[t.data.cell]=id end
        end
    end
    snapshot.water_tasks=water_tasks
    local tasks,maintenance=self:Maintenance(snapshot,true)
    local emitted={};for _,t in ipairs(tasks) do emitted[t.id]=true end
    for _,id in ipairs(retired) do if not emitted[id] then
        cancellations[#cancellations+1]=id
        for child,t in pairs(scheduler.tasks) do if t.parent_id==id and live(t) then cancellations[#cancellations+1]=child end end
    end end
    for _,t in ipairs(result.tasks) do tasks[#tasks+1]=t end
    -- Watering problems come first: the status line shows the first reasons.
    local reasons,seen={},{}
    for _,r in ipairs(maintenance.water_reasons or {}) do if not seen[r.code] then seen[r.code]=true;reasons[#reasons+1]=r end end
    if type(self.inst)=="table" and self.inst.components then
        for _,code in ipairs({"WATER_MOISTURE_UNKNOWN","WATER_NO_CAN","WATER_CAN_NOT_CARRIED","WATER_NO_SOURCE"}) do
            if seen[code] then U.OnceTalk(self.inst,"water:"..code,T.Message(code)) else U.ClearTalk(self.inst,"water:"..code) end
        end
    end
    -- Collected plows that cannot reach the warehouse stay in the robot.
    for _,robot in ipairs(group.members or {}) do
        local resource=type(robot)=="table" and robot.components and robot.components.agriresource
        local blocked=resource and resource.RecycleBlocked and resource:RecycleBlocked(group)
        if blocked and not seen[blocked] then seen[blocked]=true;reasons[#reasons+1]={code=blocked} end
    end
    for _,r in ipairs(result.reasons) do reasons[#reasons+1]=r end
    for _,code in ipairs(snapshot.reasons or {}) do reasons[#reasons+1]={code=code} end
    result.reasons=reasons
    return {status=#result.tasks>0 and "ready" or "waiting",tasks=tasks,clusters={},reasons=result.reasons,cancel_ids=cancellations,
        recommendations={},viability_failures=maintenance.viability_failures,generated_at=snapshot.now,
        summary={simple=result.summary,maintenance=maintenance,source_build=C.SOURCE_BUILD}}
end
function AgriPlanner:Plan(group)
    local snapshot=self:Capture(group)
    self.last_snapshot=snapshot
    if group.settings.simple~=false then return self:PlanSimple(group,snapshot) end
    self.last_snapshot=snapshot
    local config={snapshot.world.season,group.settings.mode,tostring(group.settings.radius),tostring(group.settings.density),tostring(group.settings.allow_random),group.settings.planting or "auto",group.settings.crop or ""}
    local selected=(group.presets or {})[snapshot.world.season] or {}
    config[#config+1]=selected.mode or "auto";config[#config+1]=selected.crop or ""
    for _,key in ipairs(U.Keys(selected.ratio)) do config[#config+1]=key.."="..tostring(selected.ratio[key]) end
    if group.blueprint and group.blueprint.confirmed then
        local coordinates={};for _,cell in ipairs(group.blueprint.cells or {}) do coordinates[#coordinates+1]=positionkey(cell) end;table.sort(coordinates)
        for _,key in ipairs(coordinates) do config[#config+1]="blueprint:"..key end
    end
    config=table.concat(config,"|")
    local cancellations={}
    local scheduler=group.scheduler
    if group.planner_config and group.planner_config~=config then
        group.planner_epoch=(group.planner_epoch or 0)+1;snapshot.epoch=group.planner_epoch
        self.search=nil;self.committed=nil;self.refresh=nil
        for id,t in pairs(scheduler and scheduler.tasks or {}) do
            if t.state~="complete" and t.state~="cancelled" and t.state~="failed" and
                (t.kind=="PLANT" or t.kind=="TILL" or t.kind=="PLOW" or t.kind=="FERTILIZE" or t.kind=="FETCH") then cancellations[#cancellations+1]=id end
        end
    end
    group.planner_config=config
    if group.settings.continuous~=false then group.single_round_started=false end
    group.last_continuous=group.settings.continuous~=false
    -- Completing the chosen round is a commitment. Seed consumption and newly
    -- created soil entities must not reshuffle the remaining crop assignment.
    local committed=false
    if #cancellations==0 then
        for _,t in pairs(scheduler and scheduler.tasks or {}) do
            if t.kind=="PLANT" and t.data and t.data.full_preflight and t.state~="complete" and t.state~="cancelled" and t.state~="failed" then committed=true;break end
        end
    end
    if committed then
        if self.search then Solver.Resume(self.search,6000) end
        local tasks,maintenance=self:Maintenance(snapshot)
        return {status="ready",tasks=tasks,clusters=self.committed and self.committed.clusters or {},reasons={},
            viability_failures=maintenance.viability_failures,
            recommendations=self.search and Solver.Page(self.search,0,8) or {},generated_at=snapshot.now,
            summary={committed_round=true,maintenance=maintenance,source_build=C.SOURCE_BUILD,complete_round=true,search_pending=self.search and not self.search.complete or false}}
    end
    if group.settings.continuous==false then
        local existing=false;for _,cell in ipairs(snapshot.cells) do if #cell.plants>0 then existing=true;break end end
        if group.single_round_started or existing then
            group.single_round_started=true
            local tasks,maintenance=self:Maintenance(snapshot)
            return {status="waiting",tasks=tasks,clusters={},reasons={{code="SINGLE_ROUND_MONITORING"}},cancel_ids=cancellations,
                recommendations=self.search and Solver.Page(self.search,0,8) or {},viability_failures=maintenance.viability_failures,
                summary={continuous=false,maintenance=maintenance,complete_round=false,search_pending=false},generated_at=snapshot.now}
        end
    end
    local signature=self:Signature(snapshot,group.settings,group.presets)
    local retry_observation=self.search and self.search.complete and self.search.status~="ready" and snapshot.now-(self.search.snapshot.now or 0)>=C.PLAN_INTERVAL
    if not self.search or self.signature~=signature or retry_observation then self.search=Solver.NewSearch(snapshot,group.settings,group.presets);self.signature=signature;self.refresh=nil end
    Solver.Resume(self.search,6000)
    local available=Solver.CurrentBest(self.search);local actionable=false
    for _,candidate in ipairs(available) do if candidate.seed_count>0 then actionable=true;break end end
    if (actionable or self.search.complete and self.search.status=="ready") and not self.search.refreshed then
        if not self.refresh then
            local refresh={snapshot=snapshot,chosen=self.search.complete and self.search.best or available}
            refresh.thread=coroutine.create(function()
                refresh.best,refresh.reason=Solver.Refresh(snapshot,group.settings,refresh.chosen,function()coroutine.yield()end)
                refresh.complete=true
            end)
            self.refresh=refresh
        end
        for _=1,6000 do
            local ok,err=coroutine.resume(self.refresh.thread)
            if not ok then self.refresh.reason="PLANNER_ERROR";self.refresh.error=tostring(err);self.refresh.complete=true end
            if self.refresh.complete then break end
        end
        if not self.refresh.complete then
            local tasks,maintenance=self:Maintenance(snapshot)
            return {status="waiting",tasks=tasks,clusters={},reasons={{code="PREFLIGHT_REVALIDATING"}},cancel_ids=cancellations,
                recommendations=Solver.Page(self.search,0,8),summary={search_pending=true,maintenance=maintenance,complete_round=false}}
        elseif not self.refresh.best then
            local failure=self.refresh.reason;self.search=nil;self.refresh=nil
            local tasks,maintenance=self:Maintenance(snapshot)
            return {status="waiting",tasks=tasks,clusters={},reasons={{code=failure or "PREFLIGHT_CHANGED"}},cancel_ids=cancellations,
                recommendations={},summary={search_pending=false,maintenance=maintenance,complete_round=false}}
        else
            self.search.dispatch_best=self.refresh.best;self.search.dispatch_snapshot=self.refresh.snapshot;self.search.dispatch_search_complete=self.search.complete;self.search.refreshed=true;self.refresh=nil
        end
    end
    local plan=self:Result(snapshot,self.search);plan.cancel_ids=cancellations
    if plan.status=="ready" then self.committed=plan;if group.settings.continuous==false then group.single_round_started=true end end
    return plan
end
function AgriPlanner:GetRecommendations(group,page,page_size)
    local snapshot=self:Capture(group)
    local settings=U.Copy(group.settings);settings.planting="auto";settings.crop=nil
    local signature=self:Signature(snapshot,settings,{})
    -- The signature tracks discrete farm/resource changes. Seasonal time,
    -- daylight and soil moisture also move without changing it, so a completed
    -- forecast cannot stay valid indefinitely. Keep in-progress searches alive
    -- so large layouts can still finish across multiple planner ticks.
    local expired=self.recommendation_search and self.recommendation_search.complete
        and snapshot.now-(self.recommendation_search.snapshot.now or 0)>=C.PLAN_INTERVAL
    if not self.recommendation_search or self.recommendation_signature~=signature or expired then
        self.recommendation_search=Solver.NewSearch(snapshot,settings,{})
        self.recommendation_signature=signature
    end
    Solver.Resume(self.recommendation_search,6000)
    page=math.max(1,math.floor(page or 1));page_size=math.max(1,math.min(8,math.floor(page_size or 8)))
    local out=Solver.Page(self.recommendation_search,(page-1)*page_size,page_size);out.page=page;out.page_size=page_size;out.search_pending=not out.complete
    out.reasons=reasons(self.recommendation_search)
    if out.total==0 then
        local refs={};local names=U.Keys(snapshot.defs)
        local function net(def)
            local c=def.nutrient_consumption or {};local total,count=0,0
            for i=1,3 do total=total+(c[i] or 0);if (def.nutrient_restoration or {})[i] then count=count+1 end end
            local v={};for i=1,3 do v[i]=((def.nutrient_restoration or {})[i] and count>0 and math.floor(total/count) or 0)-(c[i] or 0) end
            return v
        end
        for ai,a in ipairs(names) do for bi=ai+1,#names do
            local b=names[bi];local ad,bd=snapshot.defs[a],snapshot.defs[b]
            if not ad.is_randomseed and not bd.is_randomseed and (ad.good_seasons or {})[snapshot.world.season] and (bd.good_seasons or {})[snapshot.world.season] then
                local av,bv=net(ad),net(bd)
                local maximum=snapshot.tuning.max_plants or 9
                for na=math.max(1,ad.family_min_count or 1),maximum do for nb=math.max(1,bd.family_min_count or 1),maximum-na do
                    local zero=true;for i=1,3 do if av[i]*na+bv[i]*nb~=0 then zero=false end end
                    if zero then
                        local missing={};for _,v in ipairs({{ad.seed,na},{bd.seed,nb}}) do local n=math.max(0,v[2]-((snapshot.resources.seeds or {})[v[1]] or 0));if n>0 then missing[v[1]]=n end end
                        local ag,bg=Season.Predict(ad,snapshot.world),Season.Predict(bd,snapshot.world)
                        refs[#refs+1]={id="reference/"..a..":"..na.."/"..b..":"..nb,counts={[a]=na,[b]=nb},reference=true,available=false,
                            missing_seeds=missing,nutrients={net={0,0,0}},estimated_maturity=math.max(ag.maximum or 0,bg.maximum or 0),
                            warnings={"REFERENCE_REQUIRES_PREFLIGHT"},season=snapshot.world.season}
                    end
                end end
            end
        end end
        if #refs>0 then
            out.items={};for i=(page-1)*page_size+1,math.min(#refs,page*page_size) do out.items[#out.items+1]=refs[i] end
            out.total=#refs;out.reference=true;out.note="原版营养平衡参考；缺少的材料和实际布局仍须预检，选择后不会凭空产生资源。"
        end
    end
    return out
end
function AgriPlanner:Preview(group,season,preset,detail_page)
    local snapshot=self:Capture(group)
    if not snapshot.world.season_lengths[season] then return {status="blocked",reasons={{code="CALENDAR_UNAVAILABLE"}}} end
    snapshot.world.season=season;snapshot.world.season_remaining=snapshot.world.season_lengths[season]
    for _,cell in ipairs(snapshot.cells) do cell.plants={};cell.soils={} end
    snapshot.neighbors={}
    local presets=U.Copy(group.presets or {});if preset then presets[season]=preset end
    local key=season..":"..self:Signature(snapshot,group.settings,presets)
    local search=self.preview_searches[key]
    if not search then search=Solver.NewSearch(snapshot,group.settings,presets);self.preview_searches[key]=search end
    Solver.Resume(search,6000)
    detail_page=math.max(1,math.floor(tonumber(detail_page) or 1))
    local result={status=search.complete and search.status or "waiting",preview=true,season=season,
        assumptions={"CURRENT_STOCK_AND_SOIL","FUTURE_SEASON_START","NO_UNVERIFIED_FUTURE_RAIN_CREDIT"},reasons=reasons(search),
        recommendations=Solver.Page(search,0,8),clusters={},details={},detail_page=detail_page,detail_page_size=2,detail_total=0,
        summary={nodes=search.nodes,search_pending=not search.complete,complete_round=search.complete and search.status=="ready"}}
    local first=(detail_page-1)*2+1;local last=first+1
    for _,candidate in ipairs(search.best) do
        local included=false
        for _,cell in ipairs(U.Keys(candidate.nutrients)) do
            result.detail_total=result.detail_total+1
            if result.detail_total>=first and result.detail_total<=last then
                result.details[#result.details+1]={cluster=candidate.cluster,cell=cell,nutrient_projection=candidate.nutrients[cell],watering_projection=candidate.watering[cell]}
                included=true
            end
        end
        if included then result.clusters[#result.clusters+1]=Solver.Summary(candidate) end
    end
    result.detail_pages=math.max(1,math.ceil(result.detail_total/2))
    return result
end
function AgriPlanner:OnSave() return {hole_cycles=U.Copy(self.hole_cycles)} end
function AgriPlanner:OnLoad(data) self.hole_cycles=data and data.hole_cycles or {} end
function AgriPlanner:OnTaskComplete(completed,group)
    if completed.kind~="HARVEST" then return end
    local key=completed.data and completed.data.hole_key or completed.point and positionkey(completed.point)
    if not key then return end
    group.hole_cycles=group.hole_cycles or self.hole_cycles or {}
    local record=group.hole_cycles[key] or {generation=0}
    if record.last_harvest~=completed.id then record.generation=(record.generation or 0)+1;record.plant_guid=nil;record.last_harvest=completed.id;record.had_crop=true end
    group.hole_cycles[key]=record;self.hole_cycles=group.hole_cycles
end
AgriPlanner.OnHarvest=AgriPlanner.OnTaskComplete
return AgriPlanner
