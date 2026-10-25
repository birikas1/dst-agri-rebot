local Layout=require("agri/layout_planner")
local Season=require("agri/season_predictor")
local Nutrients=require("agri/nutrient_sim")
local Fertilizer=require("agri/fertilizer_solver")
local Moisture=require("agri/moisture_sim")
local Tending=require("agri/tending_sim")
local M={}
local function copy(t,seen) if type(t)~="table" or t.GUID then return t end;seen=seen or {};if seen[t] then return seen[t] end;local r={};seen[t]=r;for k,v in pairs(t) do r[k]=copy(v,seen) end;return r end
local function keys(t) local out={};for k in pairs(t or {}) do out[#out+1]=k end;table.sort(out);return out end
local function scorebetter(a,b) if not b then return true end;for i=1,#a do if a[i]~=b[i] then return a[i]<b[i] end end;return false end
local function countmap(t) local n=0;for _,v in pairs(t or {}) do n=n+v end;return n end
local function reason(search,code) search.reason_counts[code]=(search.reason_counts[code] or 0)+1 end
local function preset(settings,presets,season)
    local p=(presets or {})[season]
    if p and p.mode and p.mode~="auto" then return p end
    return {mode=settings.planting=="pause" and "pause" or settings.planting=="crop" and "crop" or "auto",crop=settings.crop}
end
local function nutrition_for_tile(plants,cell,inventory,capacity,yieldfn)
    local base=Nutrients.Simulate(plants,cell.nutrients or {0,0,0},capacity)
    if not base.feasible then return nil,base.reason end
    local pool=copy(cell.nutrients or {0,0,0});local actions={}
    local totals=Fertilizer.Schedule(base.windows,pool,inventory,capacity,base.deficit,yieldfn)
    if not totals.feasible then return nil,totals.reason end
    local bywindow={};for _,a in ipairs(totals.actions) do bywindow[a.window]=a end
    for name,n in pairs(totals.items) do inventory[name].count=inventory[name].count-n end
    for index,w in ipairs(base.windows) do
        local deficit={};for i=1,3 do deficit[i]=math.max(0,w.consumption[i]-pool[i]) end
        local choice=bywindow[index]
        if choice then
            -- Preserve the verified schedule's order because cap clipping makes
            -- aggregation of different fertilizer applications noncommutative.
            for _,name in ipairs(choice.order) do pool=Nutrients.Apply(pool,inventory[name].nutrients,capacity) end
            actions[#actions+1]={window=index,before=w.earliest,latest=w.latest,cell=cell.key,point={x=cell.x,z=cell.z},choice=choice,required=copy(w.consumption),deficit=deficit}
        end
        w.actual_before=copy(pool)
        for i=1,3 do
            if pool[i]+0.00001<w.consumption[i] then return nil,"FERTILIZER_CAP_LOSS" end
            pool[i]=math.min(capacity or math.huge,pool[i]-w.consumption[i]+w.restoration[i])
        end
        w.actual_after=copy(pool)
    end
    base.final=pool;base.actions=actions;base.fertilizer=totals
    return base
end
local function nutrition_for_cluster(bycell,cells,inventory,capacity,yieldfn)
    local projections,windows,soils,deficit={}, {},{}, {0,0,0}
    for _,cell in ipairs(cells) do
        local base=Nutrients.Simulate(bycell[cell.key] or {},cell.nutrients or {0,0,0},capacity)
        if not base.feasible then return nil,base.reason end
        projections[cell.key]=base;soils[cell.key]=copy(cell.nutrients or {0,0,0})
        for i=1,3 do deficit[i]=deficit[i]+base.deficit[i] end
        for localindex,w in ipairs(base.windows) do
            w.cell=cell.key;w.local_window=localindex;windows[#windows+1]=w
        end
    end
    local choice=Fertilizer.Schedule(windows,soils,inventory,capacity,deficit,yieldfn)
    if not choice.feasible then return nil,choice.reason end
    local indexed={};for _,a in ipairs(choice.actions) do indexed[a.window]=a end
    for name,n in pairs(choice.items) do inventory[name].count=inventory[name].count-n end
    local cellmap={};for _,cell in ipairs(cells) do cellmap[cell.key]=cell end
    for key,base in pairs(projections) do base.actions={};base.fertilizer={count=0,cost=0,excess=0,items={},supplied={0,0,0}} end
    for index,w in ipairs(windows) do
        local key=w.cell;local base=projections[key];local pool=soils[key];local action=indexed[index]
        if action then
            for _,name in ipairs(action.order) do pool=Nutrients.Apply(pool,inventory[name].nutrients,capacity) end
            base.actions[#base.actions+1]={window=w.local_window,before=w.earliest,latest=w.latest,cell=key,
                point={x=cellmap[key].x,z=cellmap[key].z},choice=action,required=copy(w.consumption)}
            base.fertilizer.count=base.fertilizer.count+action.count
            for name,n in pairs(action.items) do base.fertilizer.items[name]=(base.fertilizer.items[name] or 0)+n end
            for i=1,3 do base.fertilizer.supplied[i]=base.fertilizer.supplied[i]+action.supplied[i] end
        end
        w.actual_before=copy(pool)
        for i=1,3 do pool[i]=math.min(capacity,pool[i]-w.consumption[i]+w.restoration[i]) end
        w.actual_after=copy(pool);soils[key]=pool
    end
    for key,base in pairs(projections) do
        base.final=soils[key]
        for i=1,3 do base.fertilizer.excess=base.fertilizer.excess+math.max(0,base.fertilizer.supplied[i]-base.deficit[i]) end
    end
    return projections,nil,choice
end
local function stock_rounds(candidate,snapshot,cluster,inventory,yieldfn)
    local nextseeds,bycell={},{}
    local duration=0
    for _,crop in ipairs(candidate.assignment) do
        nextseeds[crop.def.seed]=(nextseeds[crop.def.seed] or 0)+1
        local future={id=crop.id,def=crop.def,crop=crop.crop,point=crop.point,cell=crop.cell,growth={stages={}}};local t=0
        for _,stage in ipairs({"seed","sprout","small","med"}) do
            local range=crop.def.grow_time[stage];t=t+(range.max or range[2])
            future.growth.stages[#future.growth.stages+1]={stage=stage,earliest=t,latest=t,checkpoint=true}
        end
        duration=math.max(duration,t);bycell[crop.cell]=bycell[crop.cell] or {};bycell[crop.cell][#bycell[crop.cell]+1]=future
    end
    local bounds={};local function bound(name,value) bounds[#bounds+1]={resource=name,additional=math.max(0,math.floor(value))} end
    local seed_extra=math.huge
    for seed,n in pairs(nextseeds) do seed_extra=math.min(seed_extra,math.floor(math.max(0,((inventory.seeds or {})[seed] or 0)-(candidate.resources.seeds[seed] or 0))/n)) end
    if seed_extra==math.huge then seed_extra=0 end
    bound("seeds",seed_extra)
    local emptycells={}
    for _,cell in ipairs(cluster.cells) do local c=copy(cell);c.nutrients={0,0,0};emptycells[#emptycells+1]=c end
    local futurefert=copy(candidate.resources.fertilizers)
    -- This UI field is a guaranteed lower bound, not a second optimization
    -- search that can hold up an already feasible production round. A concrete
    -- greedy future basket is safe to repeat; failure only lowers the bound.
    local cost={items={}};local projection,why=true,nil
    for _,cell in ipairs(emptycells) do
        local pool={0,0,0};local sim=Nutrients.Simulate(bycell[cell.key],pool,snapshot.tuning.nutrient_capacity)
        if not sim.feasible then projection=false;why=sim.reason;break end
        for _,window in ipairs(sim.windows) do
            while true do
                local deficit={};local missing=0
                for i=1,3 do deficit[i]=math.max(0,window.consumption[i]-pool[i]);missing=missing+deficit[i] end
                if missing<=0 then break end
                local choice,coverage=nil,0
                for _,name in ipairs(keys(futurefert)) do local item=futurefert[name]
                    if item.count>0 and item.nutrients then
                        local amount=0;for i=1,3 do amount=amount+math.min(deficit[i],item.nutrients[i] or 0) end
                        if amount>coverage then choice,coverage=name,amount end
                    end
                end
                if not choice then projection=false;why="FUTURE_FERTILIZER_GUARD_UNAVAILABLE";break end
                if yieldfn then yieldfn() end
                local item=futurefert[choice];item.count=item.count-1;cost.items[choice]=(cost.items[choice] or 0)+1
                pool=Nutrients.Apply(pool,item.nutrients,snapshot.tuning.nutrient_capacity)
            end
            if not projection then break end
            for i=1,3 do pool[i]=math.min(snapshot.tuning.nutrient_capacity,pool[i]-window.consumption[i]+window.restoration[i]) end
        end
        if not projection then break end
    end
    if not projection then bound("future_fertilizer",0)
    else for name,n in pairs(cost.items) do if n>0 then bound("fertilizer:"..name,(candidate.resources.fertilizers[name].count or 0)/n) end end end
    local futurewater=0
    for _,cell in ipairs(cluster.cells) do
        local crops=bycell[cell.key] or {};local drain=snapshot.tuning.max_dry_rate or (cell.moisture or {}).drain or 0
        for _,p in ipairs(crops) do drain=drain+math.abs((p.def.moisture or {}).drink_rate or 0) end
        for _,stage in ipairs({"seed","sprout","small","med"}) do
            local targets={}
            for _,p in ipairs(crops) do local range=p.def.grow_time[stage];targets[#targets+1]={id=p.id,def=p.def,remaining=range.max or range[2],moisture={elapsed=0,hydrated=0}} end
            local water=Moisture.Predict({moisture=0,drain=drain,capacity=(cell.moisture or {}).capacity,water_per_use=(inventory.water or {}).soil_per_use or (inventory.water or {}).per_use},targets)
            if not water.feasible then bound("future_water",0) end
            futurewater=futurewater+water.uses
        end
    end
    if futurewater>0 and not (inventory.water or {}).has_source then bound("water",math.max(0,((inventory.water or {}).uses or 0)-candidate.water_uses)/futurewater) end
    for _,name in ipairs({"hoe","hammer"}) do
        local tool=(inventory.tools or {})[name];local needed=name=="hoe" and #candidate.assignment or candidate.resources.tool_uses.hammer
        if needed>0 and not (tool and tool.replenishable) then bound("tool:"..name,math.max(0,(tool and tool.uses or 0)-(candidate.resources.tool_uses[name] or 0))/needed) end
    end
    -- A stock guarantee does not invent future season/weather support. Limit
    -- subsequent rounds to the current season; Preview examines later seasons.
    local day=snapshot.world.day
    local awake=snapshot.world.daylight and snapshot.world.daylight[snapshot.world.season]
    if day and awake and awake>0 then duration=(math.ceil(duration/awake)+1)*day
    elseif day and not awake then bound("future_daylight_unknown",0) end
    if snapshot.world.season_remaining~=math.huge and duration>0 then bound("current_season",math.max(0,snapshot.world.season_remaining-candidate.estimated_maturity)/duration) end
    local extra=seed_extra;for _,entry in ipairs(bounds) do extra=math.min(extra,entry.additional) end
    local limiting={};for _,entry in ipairs(bounds) do if entry.additional==extra then limiting[#limiting+1]=entry.resource end end
    candidate.seed_rounds=1+seed_extra;candidate.supported_rounds=1+extra
    candidate.stock_rounds={guaranteed=1+extra,seed_upper_bound=1+seed_extra,limiting_resources=limiting,
        future_round_cost={fertilizers=cost and cost.items or {},water_uses=futurewater},future_fertilizer_reason=why,
        assumptions={"NO_HARVEST_STOCK_CREDIT","FUTURE_SOIL_EMPTY","CONCRETE_FUTURE_FERTILIZER_GUARD_LOWER_BOUND","NO_FUTURE_RAIN","CURRENT_SEASON_ONLY","REFILL_AND_HEATING_SOURCES_REMAIN_USABLE"}}
end
local function evaluate_assignment(search,cluster,holes,counts,settings,inventory,yieldfn,assignment,safe,warnings)
    local snapshot=search.snapshot;local strict=settings.mode=="oversized"
    local out={id=cluster.id.."/",cluster=cluster.id,counts=copy(counts),assignment=assignment,layout_warnings=warnings,
        nutrients={},watering={},fertilizer_actions={},tending={},crossings={},warnings={},assumptions=copy(snapshot.world.assumptions or {}),oversized_eligible=safe,estimated_maturity=0,
        fertilizer_count=0,fertilizer_excess=0,fertilizer_cost=0,water_uses=0,seed_count=countmap(counts),perfect=false}
    for _,name in ipairs(keys(counts)) do if counts[name]>0 then out.id=out.id..name.."="..counts[name]..";" end end
    local bycell={};local seasonalrisk=0
    for _,crop in ipairs(assignment) do
        if crop.def.is_randomseed then out.oversized_eligible=false;out.warnings[#out.warnings+1]="RANDOM_SEED_WORST_CASE";if strict then return nil,"RANDOM_SEED_GIANT_UNCERTAIN" end end
        local killjoys=0;local radius=snapshot.tuning.killjoy_radius or 0
        for _,other in ipairs(snapshot.killjoys or {}) do if (crop.point.x-other.point.x)^2+(crop.point.z-other.point.z)^2<=radius*radius then killjoys=killjoys+1 end end
        if killjoys>(crop.def.max_killjoys_tolerance or snapshot.tuning.killjoy_tolerance or 0) then
            out.oversized_eligible=false;out.warnings[#out.warnings+1]="KILLJOY_STRESS"
            if strict then return nil,"KILLJOY_STRESS" end
        end
        crop.night_light=crop.existing and crop.existing.night_light or snapshot.night_light and snapshot.night_light(crop.point) or false
        crop.growth=Season.Predict(crop.def,snapshot.world,crop.existing or {night_light=crop.night_light})
        if not crop.growth.feasible then return nil,crop.growth.reason end
        if crop.growth.reason then out.warnings[#out.warnings+1]=crop.growth.reason end
        if not crop.growth.oversized_eligible then out.oversized_eligible=false;seasonalrisk=seasonalrisk+#crop.growth.risks end
        if strict and not crop.growth.oversized_eligible then return nil,crop.growth.reason or "SEASON_STRESS" end
        crop.remaining=crop.growth.stages[1] and crop.growth.stages[1].latest
        crop.moisture=crop.existing and crop.existing.moisture or {elapsed=0,hydrated=0}
        crop.tendable=crop.existing and crop.existing.tendable or false;crop.tended=crop.existing and crop.existing.tended or false
        crop.entity=crop.existing and crop.existing.entity
        if crop.existing and crop.existing.stress and crop.existing.stress>0 then out.oversized_eligible=false;if strict then return nil,"EXISTING_STRESS" end end
        out.estimated_maturity=math.max(out.estimated_maturity,crop.growth.maximum)
        bycell[crop.cell]=bycell[crop.cell] or {};bycell[crop.cell][#bycell[crop.cell]+1]=crop
        for _,cross in ipairs(crop.growth.crossings) do out.crossings[#out.crossings+1]={crop=crop.id,time=cross.time,from=cross.from,to=cross.to} end
    end
    local fertilizers=copy(inventory.fertilizers or {})
    local nutrition_all,nutrition_error,nutrition_choice=nutrition_for_cluster(bycell,cluster.cells,fertilizers,snapshot.tuning.nutrient_capacity,yieldfn)
    if not nutrition_all then return nil,nutrition_error end
    for _,cell in ipairs(cluster.cells) do
        local plants=bycell[cell.key] or {}
        local nutrition=nutrition_all[cell.key]
        out.nutrients[cell.key]=nutrition
        for _,action in ipairs(nutrition.actions) do out.fertilizer_actions[#out.fertilizer_actions+1]=action end
        out.fertilizer_count=out.fertilizer_count+nutrition.fertilizer.count
        out.fertilizer_excess=out.fertilizer_excess+nutrition.fertilizer.excess
        out.fertilizer_cost=out.fertilizer_cost+nutrition.fertilizer.cost
        local moisture=copy(cell.moisture or {})
        moisture.water_per_use=inventory.water and (inventory.water.soil_per_use or inventory.water.per_use)
        local base_drain=moisture.drain or 0;local drink,horizon,nightdrink=0,0,0
        for _,p in ipairs(plants) do local rate=math.abs((p.def.moisture or {}).drink_rate or p.moisture and p.moisture.rate or 0);drink=drink+rate;if p.night_light then nightdrink=nightdrink+rate end;horizon=math.max(horizon,p.remaining or 0) end
        moisture.drain=base_drain+drink
        moisture.weather=Season.EnvironmentTimeline(snapshot.world,horizon,base_drain,drink,moisture.weather,nightdrink)
        local water=Moisture.Predict(moisture,plants)
        out.watering[cell.key]=water
        if not water.feasible then
            out.oversized_eligible=false;out.warnings[#out.warnings+1]=water.reason
            if strict or water.reason=="MISSING_WATERING_CAN" or water.reason=="MOISTURE_DATA_UNAVAILABLE" then return nil,water.reason end
        end
        -- The complete-round reserve takes all remaining checkpoints into
        -- account. Later-stage doses are only dispatched on a fresh prediction.
        local future_uses=water.uses
        local bystage={}
        for _,p in ipairs(plants) do
            local previous=0
            for index,stage in ipairs(p.growth.stages) do
                if index>1 then
                    bystage[index]=bystage[index] or {}
                    bystage[index][#bystage[index]+1]={id=p.id..":"..stage.stage,def=p.def,remaining=stage.latest-previous,moisture={elapsed=0,hydrated=0}}
                end
                previous=stage.latest
            end
        end
        water.future_checkpoints={}
        for _,index in ipairs(keys(bystage)) do
            local future=copy(moisture);future.moisture=0;future.weather={}
            local forecast=Moisture.Predict(future,bystage[index]);future_uses=future_uses+forecast.uses
            water.future_checkpoints[#water.future_checkpoints+1]=forecast
            if not forecast.feasible and (strict or forecast.reason=="MISSING_WATERING_CAN") then return nil,forecast.reason end
        end
        water.round_uses=future_uses
        out.water_uses=out.water_uses+future_uses
    end
    out.fertilizer_excess=nutrition_choice.excess;out.fertilizer_cost=nutrition_choice.cost
    local water=inventory.water or {}
    if out.water_uses>(water.uses or 0) and not water.has_source then return nil,"INSUFFICIENT_WATER" end
    if out.water_uses>0 and #(water.cans or {})==0 and not water.capacity then return nil,"MISSING_WATERING_CAN" end
    local tool_uses={hoe=0,plow=0,hammer=0,shovel=0}
    if out.seed_count>0 then
        local tools=inventory.tools or {}
        local till=0;for _,p in ipairs(assignment) do if not p.existing and not p.soil then till=till+1 end end
        tool_uses.hoe=till
        if till>0 and (not tools.hoe or not tools.hoe.replenishable and (tools.hoe.uses or 0)<till) then return nil,"INSUFFICIENT_HOE_USES" end
        local plows=0;for _,cell in ipairs(cluster.cells) do if not cell.is_farm then plows=plows+1 end end
        tool_uses.plow=plows
        if plows>0 and (not tools.plow or (tools.plow.uses or 0)<plows) then return nil,"INSUFFICIENT_PLOW_USES" end
        local owned={};for _,cell in ipairs(cluster.cells) do owned[cell.key]=true end
        for _,entry in ipairs(snapshot.debris or {}) do if owned[entry.cell] then tool_uses.shovel=tool_uses.shovel+(entry.work or 1) end end
        if tool_uses.shovel>0 and (not tools.shovel or not tools.shovel.replenishable and (tools.shovel.uses or 0)<tool_uses.shovel) then return nil,"INSUFFICIENT_SHOVEL_USES" end
    end
    if out.oversized_eligible and snapshot.tuning.oversized_work then
        local hammer=(inventory.tools or {}).hammer
        local needed=#assignment*snapshot.tuning.oversized_work
        tool_uses.hammer=needed
        if not hammer or not hammer.replenishable and (hammer.uses or 0)<needed then return nil,"INSUFFICIENT_HAMMER_USES" end
    end
    out.tending=Tending.Predict(assignment,inventory.music,snapshot.tuning.music_range,snapshot.legal_music)
    if out.tending.reason then return nil,out.tending.reason end
    out.perfect=out.oversized_eligible
    out.self_balancing=out.fertilizer_count==0
    out.score={out.fertilizer_excess,out.fertilizer_count,seasonalrisk+#warnings+#out.warnings,out.fertilizer_cost,-out.seed_count,out.estimated_maturity}
    out.resources={fertilizers=fertilizers,water_uses=out.water_uses,seeds={},tool_uses=tool_uses}
    for name,n in pairs(counts) do out.resources.seeds[snapshot.defs[name].seed]=n end
    stock_rounds(out,snapshot,cluster,inventory,yieldfn)
    return out
end
local function evaluate(search,cluster,holes,counts,settings,inventory,yieldfn)
    local snapshot=search.snapshot;local strict=settings.mode=="oversized"
    local lighttype,uniform_light=nil,true
    for _,hole in ipairs(holes) do if not hole.plant or hole.plant.mature then
        local lit=snapshot.night_light and snapshot.night_light(hole.point) or false
        if lighttype==nil then lighttype=lit elseif lighttype~=lit then uniform_light=false end
        local killjoys=0;local r=snapshot.tuning.killjoy_radius or 0
        for _,other in ipairs(snapshot.killjoys or {}) do if (hole.point.x-other.point.x)^2+(hole.point.z-other.point.z)^2<=r*r then killjoys=killjoys+1 end end
        hole.quota_key=hole.cell.."|"..tostring(lit).."|"..killjoys
    end end
    if strict then
        for name,n in pairs(counts) do if n>0 then
            local possible=n
            for _,hole in ipairs(holes) do if hole.plant and not hole.plant.mature and hole.plant.crop==name then possible=possible+1 end end
            for _,p in ipairs(snapshot.neighbors or {}) do if p.crop==name and not p.family_excluded then possible=possible+1 end end
            if possible<(snapshot.defs[name].family_min_count or 1) then return nil,"NO_SAFE_FAMILY_LAYOUT" end
            -- Crop-level seasonal pruning is only valid when every available
            -- hole has the same verified night-light condition.
            if uniform_light then
                local growth=Season.Predict(snapshot.defs[name],snapshot.world,{night_light=lighttype})
                if not growth.feasible then return nil,growth.reason end
                if not growth.oversized_eligible then return nil,growth.reason or "SEASON_STRESS" end
            end
        end end
    end
    local best,failure=nil,"NO_SAFE_FAMILY_LAYOUT"
    Layout.Allocations(holes,counts,yieldfn,function(quotas)
        local assignment,safe,warnings=Layout.Assign(holes,counts,snapshot.defs,snapshot.neighbors,snapshot.tuning.max_plants,strict,yieldfn,quotas)
        if assignment then
            local candidate,err=evaluate_assignment(search,cluster,holes,counts,settings,inventory,yieldfn,assignment,safe,warnings)
            if candidate and scorebetter(candidate.score,best and best.score) then best=candidate end
            if err then failure=err end
            -- All costs preceding density/maturity have a proven zero lower
            -- bound, and the same count vector fixes density and growth bounds.
            if candidate and uniform_light and candidate.score[1]==0 and candidate.score[2]==0 and candidate.score[3]==0 and candidate.score[4]==0 then
                candidate.layout_optimal=true;return true
            end
        end
        return false
    end)
    if best then best.layout_optimal=true end
    return best,best and nil or failure
end
function M.NewSearch(snapshot,settings,presets)
    local search={snapshot=snapshot,settings=settings,presets=presets,recommendations={},recommendation_ids={},reason_counts={},nodes=0,feasible_count=0,
        complete=false,clusters=Layout.Clusters(snapshot.cells),status="searching",best={},provisional={},layout_failures={}}
    search.thread=coroutine.create(function()
        local inventory=copy(snapshot.resources or {});local selected=preset(settings,presets,snapshot.world.season)
        if selected.mode=="pause" then reason(search,"PRESET_PAUSED");search.status="waiting";search.complete=true;return end
        local function tick() search.nodes=search.nodes+1;coroutine.yield() end
        for _,cluster in ipairs(search.clusters) do
            local best=nil
            local densities=settings.density=="dynamic" and {6,7,8,9,10} or {tonumber(settings.density) or 9}
            for _,density in ipairs(densities) do
                local holes,err,diagnostic=Layout.Holes(cluster,density,snapshot.tuning.min_spacing,snapshot.legal_hole)
                if holes then
                    local empty=0;for _,h in ipairs(holes) do if not h.plant or h.plant.mature then empty=empty+1 end end
                    local candidates,maxima,counts={}, {},{}
                    for _,name in ipairs(keys(snapshot.defs)) do
                        local def=snapshot.defs[name];local stock=(inventory.seeds or {})[def.seed] or 0
                        local allowed=not def.is_randomseed or settings.allow_random
                        if selected.mode=="crop" and selected.crop~=name then allowed=false end
                        if selected.allowed and selected.allowed[name]==false then allowed=false end
                        if stock>0 and allowed then candidates[#candidates+1]=name;maxima[name]=math.min(empty,stock) end
                    end
                    local function consider()
                        tick()
                        local candidate,failure=evaluate(search,cluster,holes,counts,settings,inventory,tick)
                        if candidate then
                            candidate.density=density
                            search.feasible_count=search.feasible_count+1
                            if candidate.perfect and candidate.seed_count>0 and not search.recommendation_ids[candidate.id] then
                                search.recommendation_ids[candidate.id]=true
                                search.recommendations[#search.recommendations+1]=M.Summary(candidate)
                            end
                            if scorebetter(candidate.score,best and best.score) then best=candidate end
                            search.provisional[cluster.id]=best
                        else reason(search,failure or "NO_FEASIBLE_COMBINATION") end
                    end
                    if selected.mode=="fixed" or selected.mode=="ratio" then
                        local total=countmap(selected.ratio)
                        if total>0 and empty%total==0 then
                            local valid=true
                            for name,n in pairs(selected.ratio) do counts[name]=n*(empty/total);if not snapshot.defs[name] or counts[name]>(maxima[name] or 0) then valid=false end end
                            if valid then consider() else reason(search,"INCOMPLETE_ROUND_SEEDS") end
                        else reason(search,"RATIO_DOES_NOT_FIT_LAYOUT") end
                    else
                        local suffix={};suffix[#candidates+1]=0
                        for i=#candidates,1,-1 do suffix[i]=suffix[i+1]+maxima[candidates[i]] end
                        local function enumerate(index,left)
                            tick()
                            if left==0 then consider();return end
                            if index>#candidates or suffix[index]<left then return end
                            local name=candidates[index]
                            for n=0,math.min(left,maxima[name]) do
                                counts[name]=n
                                enumerate(index+1,left-n)
                            end
                            counts[name]=nil
                        end
                        enumerate(1,empty)
                    end
                else reason(search,err);if diagnostic then search.layout_failures[#search.layout_failures+1]=diagnostic end end
            end
            if best then
                search.best[#search.best+1]=best
                for seed,n in pairs(best.resources.seeds) do inventory.seeds[seed]=inventory.seeds[seed]-n end
                inventory.fertilizers=best.resources.fertilizers
                if inventory.water and not inventory.water.has_source then inventory.water.uses=inventory.water.uses-best.resources.water_uses end
                for name,n in pairs(best.resources.tool_uses) do local tool=(inventory.tools or {})[name];if tool and not tool.replenishable then tool.uses=math.max(0,(tool.uses or 0)-n) end end
            else search.status="waiting";reason(search,"NO_COMPLETE_ROUND");end
        end
        search.complete=true
        if search.status~="waiting" then search.status=#search.clusters>0 and "ready" or "waiting" end
        if #search.clusters==0 then reason(search,"NO_FARM_CELLS") end
    end)
    return search
end
function M.Resume(search,budget)
    if search.complete then return search end
    for _=1,budget or 1500 do
        local ok,err=coroutine.resume(search.thread)
        if not ok then search.error=tostring(err);search.status="blocked";search.complete=true;reason(search,"PLANNER_ERROR");break end
        if coroutine.status(search.thread)=="dead" then search.complete=true;break end
    end
    return search
end
function M.Refresh(snapshot,settings,chosen,yieldfn)
    local clusters={};for _,cluster in ipairs(Layout.Clusters(snapshot.cells)) do clusters[cluster.id]=cluster end
    local inventory=copy(snapshot.resources or {});local updated={}
    for _,old in ipairs(chosen) do
        local cluster=clusters[old.cluster];if not cluster then return nil,"LAYOUT_CHANGED" end
        for name,n in pairs(old.counts) do
            local def=snapshot.defs[name]
            if not def or ((inventory.seeds or {})[def.seed] or 0)<n then return nil,"INCOMPLETE_ROUND_SEEDS" end
        end
        local holes,reason=Layout.Holes(cluster,old.density or settings.density,snapshot.tuning.min_spacing,snapshot.legal_hole)
        if not holes then return nil,reason end
        local empty=0;for _,hole in ipairs(holes) do if not hole.plant or hole.plant.mature then empty=empty+1 end end
        if empty~=countmap(old.counts) then return nil,"LAYOUT_CHANGED" end
        local candidate,err=evaluate({snapshot=snapshot},cluster,holes,old.counts,settings,inventory,yieldfn)
        if not candidate then return nil,err end
        candidate.density=old.density;updated[#updated+1]=candidate
        for seed,n in pairs(candidate.resources.seeds) do inventory.seeds[seed]=inventory.seeds[seed]-n end
        inventory.fertilizers=candidate.resources.fertilizers
        if inventory.water and not inventory.water.has_source then inventory.water.uses=inventory.water.uses-candidate.water_uses end
        for name,n in pairs(candidate.resources.tool_uses) do local tool=(inventory.tools or {})[name];if tool and not tool.replenishable then tool.uses=math.max(0,(tool.uses or 0)-n) end end
    end
    return updated
end
function M.Page(search,offset,limit)
    local out={};offset=math.max(0,math.floor(offset or 0));limit=math.max(1,math.min(50,math.floor(limit or 20)))
    for i=offset+1,math.min(#search.recommendations,offset+limit) do out[#out+1]=search.recommendations[i] end
    return {items=out,offset=offset,total=#search.recommendations,complete=search.complete,next_offset=offset+#out,
        searching=not search.complete,nodes=search.nodes,snapshot_at=search.snapshot.now,optimality=search.complete and "complete" or "best_known"}
end
function M.CurrentBest(search)
    local out={}
    for _,cluster in ipairs(search.clusters) do
        local candidate=search.provisional[cluster.id]
        if candidate then out[#out+1]=candidate end
    end
    return out
end
M.Evaluate=evaluate
M.Preset=preset
M.NutritionForTile=nutrition_for_tile
function M.Summary(candidate)
    local positive={};for name,n in pairs(candidate.counts) do if n>0 then positive[name]=n end end
    local nutrients={net={0,0,0},deficit={0,0,0},final={0,0,0},minimum={0,0,0},tiles=0}
    for _,p in pairs(candidate.nutrients) do
        nutrients.tiles=nutrients.tiles+1
        for i=1,3 do for _,key in ipairs({"net","deficit","final","minimum"}) do nutrients[key][i]=nutrients[key][i]+(p[key][i] or 0) end end
    end
    local crossings,seen={},{}
    for _,cross in ipairs(candidate.crossings) do
        local key=cross.from..":"..cross.to..":"..string.format("%.1f",cross.time)
        if not seen[key] then crossings[#crossings+1]={from=cross.from,to=cross.to,time=cross.time};seen[key]=true end
    end
    return {id=candidate.id,cluster=candidate.cluster,counts=positive,estimated_maturity=candidate.estimated_maturity,
        crossings=crossings,nutrients=nutrients,fertilizer_count=candidate.fertilizer_count,
        fertilizer_excess=candidate.fertilizer_excess,water_uses=candidate.water_uses,oversized_eligible=candidate.oversized_eligible,
        self_balancing=candidate.self_balancing,warnings=copy(candidate.warnings),seed_rounds=candidate.seed_rounds,
        supported_rounds=candidate.supported_rounds,stock_rounds=copy(candidate.stock_rounds),assumptions=copy(candidate.assumptions or {})}
end
return M
