-- Native facts live in SOURCE_VERIFICATION.md (build 756039). Keep all native
-- reads here; the algorithms accept injected plain snapshots for verification.
local U=require("agri/util")
local C=require("agri/constants")
local M={}
local cached_defs
local function point(inst) local x,_,z=inst.Transform:GetWorldPosition();return {x=x,z=z} end
local function valid(inst) return type(inst)=="table" and type(inst.IsValid)=="function" and inst:IsValid() end
local function wake_returning_plow_item(item)
    local inventoryitem=item.components.inventoryitem
    if inventoryitem==nil or inventoryitem.owner~=nil or inventoryitem.canbepickedup~=false
        or item._agri_fold_watch~=nil then return end
    -- The original plow returns an temporarily unpickable item and finishes
    -- its fold animation before allowing PICKUP. Off-screen sleep can strand
    -- that animation at a hole position. Let the original callback finish.
    item.entity:SetCanSleep(false)
    item._agri_fold_watch=item:DoPeriodicTask(.5,function(inst)
        local held=inst.components.inventoryitem
        if held==nil or held.owner~=nil or held.canbepickedup~=false then
            inst._agri_fold_watch:Cancel()
            inst._agri_fold_watch=nil
            inst.entity:SetCanSleep(true)
        end
    end)
end
function M.WakeReturnedPlowAtSpawn(item)
    if not valid(item) or item.prefab~="farm_plow_item" then return end
    -- The native Finished callback sets canbepickedup=false only after the
    -- spawn event. Prevent sleep now; inspect that native state next tick.
    item.entity:SetCanSleep(false)
    item:DoTaskInTime(0,function(inst)
        local inventoryitem=inst.components.inventoryitem
        if inventoryitem and inventoryitem.owner==nil and inventoryitem.canbepickedup==false then
            wake_returning_plow_item(inst)
        else
            inst.entity:SetCanSleep(true)
        end
    end)
end
function M.IsUsableSoil(inst)
    return valid(inst) and inst.prefab=="farm_soil" and inst:HasTag("soil") and not inst:HasTag("NOBLOCK")
end
function M.DescribeSoil(inst)
    if type(inst)~="table" then return {valid=false,target_type=type(inst)} end
    local alive=valid(inst)
    return {valid=alive and true or false,guid=inst.GUID,prefab=inst.prefab,
        soil=alive and inst.HasTag and inst:HasTag("soil") or false,noclick=alive and inst.HasTag and inst:HasTag("NOCLICK") or false,
        noblock=alive and inst.HasTag and inst:HasTag("NOBLOCK") or false,persists=inst.persists}
end
local function call(object,name,...)
    if not object or type(object[name])~="function" then return nil end
    local ok,a,b,c=pcall(object[name],object,...);if ok then return a,b,c end
end
local function clone(v) return U.Copy(v) end
function M.GetCropDefs()
    if not cached_defs then
        local ok,defs=pcall(require,"prefabs/farm_plant_defs")
        cached_defs=ok and defs.PLANT_DEFS or {}
    end
    return cached_defs
end
function M.Calendar(world)
    local s=world.state or {};local day=TUNING and TUNING.TOTAL_DAY_TIME
    if not day then return {reason="CALENDAR_UNAVAILABLE"} end
    local calendar={season=s.season,season_remaining=type(s.remainingdaysinseason)=="number" and math.max(0,(s.remainingdaysinseason-(s.time or 0))*day) or nil,
        season_order=clone(C.SEASONS),season_lengths={},day=day,time_of_day=s.time or 0,wetness=s.wetness or 0,israining=s.israining or false,precipitationrate=s.precipitationrate or 0,
        assumptions={"CURRENT_NATIVE_DAY_LENGTH_RULES_UNCHANGED","NIGHT_PAUSE_UNLESS_VERIFIED_LIGHT","VERIFIED_LIGHTS_REMAIN_AVAILABLE"}}
    for _,name in ipairs(C.SEASONS) do if type(s[name.."length"])=="number" then calendar.season_lengths[name]=s[name.."length"]*day end end
    local native=world.net and world.net.components and world.net.components.seasons
    local data=call(native,"OnSave")
    if data then
        calendar.mode=data.mode;calendar.random_seasons=clone(data.israndom or {});calendar.premode=data.premode
        if data.mode~="cycle" and not data.premode then calendar.season_remaining=math.huge;calendar.eternal=true end
        if data.premode then calendar.uncertain=true end
        local clockdata=call(world.net and world.net.components and world.net.components.clock,"OnSave")
        local actual=clockdata and clockdata.segs;local bases=data.segs;local segtime=TUNING.SEG_TIME
        if actual and bases and segtime then
            calendar.current_awake=(actual.day+actual.dusk)*segtime;calendar.daylight={};calendar.growth_windows={}
            for i,name in ipairs(C.SEASONS) do
                local prior=C.SEASONS[(i-2)%#C.SEASONS+1];local following=C.SEASONS[i%#C.SEASONS+1]
                local a,b,c=bases[prior],bases[name],bases[following]
                if a and b and c then
                    local minimum=math.min(a.night,b.night,c.night,actual.night)
                    local maximum=math.max(a.night,b.night,c.night,actual.night)
                    calendar.growth_windows[name]={min_awake=math.max(0,day-maximum*segtime),max_awake=math.max(0,day-minimum*segtime)}
                    calendar.daylight[name]=calendar.growth_windows[name].min_awake
                end
            end
            local current=bases[s.season];local length=s[s.season.."length"]
            if current and length and length>0 and data.mode=="cycle" then
                local progress=1-(s.remainingdaysinseason or 0)/length;local neighbour
                for i,name in ipairs(C.SEASONS) do if name==s.season then neighbour=progress<.5 and C.SEASONS[(i-2)%#C.SEASONS+1] or C.SEASONS[i%#C.SEASONS+1] end end
                local other=bases[neighbour];local blend=.5-math.sin(math.pi*progress)*.5
                if other then
                    local expectedday=math.floor(current.day+blend*(other.day-current.day)+.5)
                    local expectednight=math.floor(current.night+blend*(other.night-current.night)+.5)
                    calendar.calendar_uncertainty=actual.day~=expectedday or actual.night~=expectednight
                end
            end
        else calendar.daylight_unavailable=true end
    end
    return calendar
end
local function hydration(inst,manager,now)
    local drinker=inst.components.farmsoildrinker
    if not drinker then return {elapsed=0,hydrated=0,rate=0} end
    local time=drinker.time or {};local wet,dry=time.wet or 0,time.dry or 0
    local since=math.max(0,now-(drinker.timer_start_time or now));local p=point(inst)
    if call(manager,"IsSoilMoistAtPoint",p.x,0,p.z) then wet=wet+since else dry=dry+since end
    return {elapsed=wet+dry,hydrated=wet,rate=call(drinker,"GetMoistureRate") or 0}
end
local function night_light_at(p,lights)
    for _,light in ipairs(lights or {}) do if (p.x-light.x)^2+(p.z-light.z)^2<light.radius*light.radius then return true end end
    return false
end
function M.CapturePlant(inst,defs,manager,now,lights)
    local def=inst.plant_def;local crop=nil
    for name,value in pairs(defs) do if value==def or value.prefab==inst.prefab then crop=name;def=value;break end end
    if not crop or not def then return nil end
    local g=inst.components.growable;local data=call(g,"GetCurrentStageData") or {}
    local remaining=g and (g.pausedremaining or g.targettime and math.max(0,g.targettime-now))
    local stress=inst.components.farmplantstress;local tend=inst.components.farmplanttendable
    local p=point(inst)
    local mature=call(inst.components.pickable,"CanBePicked") and true or false
    local record={id="plant:"..tostring(inst.GUID),entity=inst,crop=crop,def=def,point=p,cell=U.CellKey(p.x,p.z),stage=data.name,
        remaining=remaining,paused=g and g.pausedremaining~=nil or false,night_light=night_light_at(p,lights),mature=mature,stress=stress and stress.stress_points or 0,
        tended=stress and stress.stressors and stress.stressors.happiness==false or false,
        tendable=tend and tend.tendable or false,family_excluded=inst:HasTag("farm_plant_killjoy"),moisture=hydration(inst,manager,now)}
    record.nutrient_deficit=call(manager,"CycleNutrientsAtPoint",p.x,0,p.z,def.nutrient_consumption,def.nutrient_restoration,true)
    return record
end
local moisture_cache={}
local function moisture_snapshot(manager,now)
    if moisture_cache.manager==manager and moisture_cache.at==now then return moisture_cache.value,moisture_cache.reason end
    local saved=call(manager,"OnSave")
    if not saved or type(DecodeAndUnzipSaveData)~="function" then return nil,"MOISTURE_SNAPSHOT_UNAVAILABLE" end
    local ok,decoded=pcall(DecodeAndUnzipSaveData,saved)
    local grid=ok and type(decoded)=="table" and decoded.moisturegrid
    -- Accept a wrapped grid save as well as the bare tile-index table.
    if type(grid)=="table" and type(grid.grid)=="table" then grid=grid.grid end
    if type(grid)~="table" then return nil,"MOISTURE_SNAPSHOT_UNAVAILABLE" end
    moisture_cache={manager=manager,at=now,value=grid}
    return grid
end
-- Current soil moisture on the tile at x,z, read the same way Capture does.
-- nil means it could not be read; callers must not assume a value.
function M.SoilMoistureAt(world,x,z)
    local manager=world and world.components.farming_manager
    if not manager or not world.Map then return nil end
    local grid=moisture_snapshot(manager,GetTime())
    if not grid then return nil end
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,0,z)
    local raw=grid[tz*world.Map:GetSize()+tx]
    return math.max(raw or 0,world.state.wetness or 0)
end
local function dry_rate(x,z)
    local a,b=TUNING.SOIL_MIN_DRYING_TEMP,TUNING.SOIL_MAX_DRYING_TEMP
    local lo,hi=TUNING.SOIL_MIN_TEMP_DRY_RATE,TUNING.SOIL_MAX_TEMP_DRY_RATE
    if not a or not b or not lo or not hi then return nil end
    local temperature=GetTemperatureAtXZ and GetTemperatureAtXZ(x,z)
    if not temperature then return math.max(math.abs(lo),math.abs(hi)) end
    local alpha=(math.max(a,math.min(b,temperature))-a)/math.max(0.0001,b-a)
    return math.abs(lo+(hi-lo)*alpha)
end
local function random_definition(defs)
    local d={seed="seeds",prefab="farm_plant_randomseed",is_randomseed=true,good_seasons={},grow_time={},nutrient_consumption={0,0,0},nutrient_restoration={},moisture={min_percent=0,drink_rate=0},family_min_count=1,family_check_dist=0}
    for _,name in ipairs(C.SEASONS) do d.good_seasons[name]=true end
    for _,def in pairs(defs) do if not def.is_randomseed then
        for i=1,3 do d.nutrient_consumption[i]=math.max(d.nutrient_consumption[i],(def.nutrient_consumption or {})[i] or 0) end
        for _,name in ipairs(C.SEASONS) do if not (def.good_seasons or {})[name] then d.good_seasons[name]=nil end end
        for _,stage in ipairs({"seed","sprout","small","med"}) do
            local r=def.grow_time and def.grow_time[stage]
            if r then d.grow_time[stage]=d.grow_time[stage] or {min=0,max=0};d.grow_time[stage].min=math.max(d.grow_time[stage].min,r.min or r[1] or 0);d.grow_time[stage].max=math.max(d.grow_time[stage].max,r.max or r[2] or 0) end
        end
        local m=def.moisture or {};d.moisture.min_percent=math.max(d.moisture.min_percent,m.min_percent or 0);d.moisture.drink_rate=math.min(d.moisture.drink_rate,m.drink_rate or 0)
    end end
    return d
end
-- Automatic plowing is disabled: there is never a plowable-ground candidate.
-- Kept as an empty answer so no caller can start a scan or a deployment.
function M.PlowCandidates(group,robot,limit,skip)
    return {}
end
function M.Capture(group,robot)
    local world=TheWorld;local now=GetTime();local defs=M.GetCropDefs();local manager=world and world.components.farming_manager
    local result={now=now,revision=group.revision,world=M.Calendar(world),defs={},cells={},neighbors={},resources={},reasons={},tuning={},oversized={},pickups={},debris={},killjoys={},plow_dependencies={}}
    for name,def in pairs(defs) do if not def.is_randomseed then result.defs[name]=def end end
    result.defs.randomseed=random_definition(defs)
    result.tuning={max_plants=TUNING.FARM_PANT_OVERCROWDING_MAX_PLANTS,nutrient_capacity=100,
        min_spacing=GetFarmTillSpacing and GetFarmTillSpacing() or TUNING.FARM_TILL_SPACING,music_range=TUNING.WX78_MUSIC_RANGE,
        oversized_work=1,killjoy_radius=TUNING.FARM_PLANT_KILLJOY_RADIUS,killjoy_tolerance=TUNING.FARM_PLANT_KILLJOY_TOLERANCE,
        max_dry_rate=math.max(math.abs(TUNING.SOIL_MIN_TEMP_DRY_RATE or 0),math.abs(TUNING.SOIL_MAX_TEMP_DRY_RATE or 0))} -- OVERSIZED_MAXWORK is native local 1, Source-verified.
    if not manager then result.reasons[#result.reasons+1]="FARMING_MANAGER_UNAVAILABLE";return result end
    local resource=robot and robot.components.agriresource
    result.resources=resource and resource:Snapshot(group) or {seeds={},fertilizers={},water={},tools={}}
    local water=result.resources.water or {};water.soil_per_use=water.per_use;result.resources.water=water
    local moisture,moisture_error=moisture_snapshot(manager,now);if moisture_error then result.reasons[#result.reasons+1]=moisture_error end
    local map=world.Map;local width=map:GetSize();local cells,selected={},{}
    -- Every tile this capture looked at (farm or not), in field_zones tile
    -- keys: zone records keep tiles outside it unchanged.
    local scanned={};result.scanned_tiles=scanned
    local function add(x,z,blueprint)
        local cx,_,cz=map:GetTileCenterPoint(x,0,z);if not cx then return end
        local key=U.CellKey(cx,cz);if selected[key] then return end
        local tx,tz=map:GetTileCoordsAtPoint(cx,0,cz)
        if tx and tz then scanned[tostring(tx)..":"..tostring(tz)]=true end
        local farm=map:GetTileAtPoint(cx,0,cz)==WORLD_TILES.FARMING_SOIL
        if farm or blueprint then
            local a,b,c=manager:GetTileNutrients(tx,tz)
            local raw=moisture and moisture[tz*width+tx]
            local cell={key=key,x=cx,z=cz,tile_x=tx,tile_z=tz,is_farm=farm,blueprint=blueprint,plants={},soils={},nutrients={a or 0,b or 0,c or 0},
                moisture={moisture=raw~=nil and math.max(raw,world.state.wetness or 0) or moisture and (world.state.wetness or 0) or nil,capacity=TUNING.SOIL_MAX_MOISTURE_VALUE,drain=dry_rate(cx,cz),weather={},world_wetness=world.state.wetness or 0}}
            -- Credit only the next monitoring interval; later rainfall is unknown.
            if world.state.israining and (world.state.precipitationrate or 0)>0 then
                cell.moisture.weather={{duration=C.PLAN_INTERVAL,rain=(world.state.precipitationrate or 0)*(TUNING.SOIL_RAIN_MOD or 0)+(cell.moisture.drain or 0)}}
            end
            cells[#cells+1]=cell;selected[key]=cell
        end
    end
    local center,radius=group.center,group.settings.radius
    local cx,_,cz=map:GetTileCenterPoint(center.x,0,center.z)
    for dx=-math.ceil(radius/4),math.ceil(radius/4) do for dz=-math.ceil(radius/4),math.ceil(radius/4) do
        local x,z=cx+dx*4,cz+dz*4
        if (x-center.x)^2+(z-center.z)^2<=radius*radius then add(x,z,false) end
    end end
    if group.blueprint and group.blueprint.confirmed then for _,cell in ipairs(group.blueprint.cells or {}) do add(cell.x,cell.z,true) end end
    for id,t in pairs(group.scheduler and group.scheduler.tasks or {}) do
        -- Only an already deployed native plow is farmland in progress; an
        -- unstarted PLOW is blocked (automatic plowing is disabled).
        if t.kind=="PLOW" and t.point and t.state~="complete" and t.state~="cancelled" and t.state~="failed"
            and t.state~="blocked" and t.continuation and t.continuation.phase=="plowing" then
            local key=U.CellKey(t.point.x,t.point.z)
            result.plow_dependencies[key]=result.plow_dependencies[key] or {};result.plow_dependencies[key][#result.plow_dependencies[key]+1]=id
        end
    end
    for _,ids in pairs(result.plow_dependencies) do table.sort(ids) end
    local familyrange=TUNING.FARM_PLANT_KILLJOY_RADIUS or 0;for _,def in pairs(defs) do familyrange=math.max(familyrange,def.family_check_dist or 0) end
    local lights={}
    for _,entity in ipairs(TheSim:FindEntities(center.x,0,center.z,radius+(TUNING.DAYLIGHT_SEARCH_RANGE or 0),{"daylight","lightsource"})) do
        if valid(entity) and entity.Light then local p=point(entity);lights[#lights+1]={id=entity.GUID,x=p.x,z=p.z,radius=math.min(entity.Light:GetCalculatedRadius()*.7,TUNING.DAYLIGHT_SEARCH_RANGE or 0)} end
    end
    result.lights=lights;result.night_light=function(p)return night_light_at(p,lights)end
    local entities=TheSim:FindEntities(center.x,0,center.z,radius+familyrange,{"farm_plant"},{"INLIMBO","NOCLICK","FX"})
    for _,entity in ipairs(entities) do if valid(entity) then
        if entity:HasTag("farm_plant_killjoy") then result.killjoys[#result.killjoys+1]={entity=entity,point=point(entity),id=entity.GUID} end
        local p=M.CapturePlant(entity,defs,manager,now,lights)
        if p then
            local cell=selected[p.cell]
            if cell then cell.plants[#cell.plants+1]=p;p.in_assignment=true end
            result.neighbors[#result.neighbors+1]=p
        end
    end end
    -- Native broken/collapsed mounds can remain valid animations with the same
    -- prefab. Only actual soil-tagged, non-NOBLOCK piles are planting resources.
    -- Plowing temporarily adds NOCLICK, so it is not a broken-soil predicate.
    local soils=TheSim:FindEntities(center.x,0,center.z,radius,{"soil"},{"INLIMBO","NOBLOCK"})
    for _,entity in ipairs(soils) do if M.IsUsableSoil(entity) then
        local p=point(entity);local cell=selected[U.CellKey(p.x,p.z)]
        if cell then
            local pending=entity:HasTag("NOCLICK")
            cell.soils[#cell.soils+1]={id="soil:"..tostring(entity.GUID),point=p,entity=entity,pending=pending}
            if pending and not result.plow_dependencies[cell.key] then cell.plow_pending=true end
        end
    end end
    -- Broken mounds left beside earlier tilling: unusable, only to be removed.
    for _,entity in ipairs(TheSim:FindEntities(center.x,0,center.z,radius,{"soil","NOBLOCK"},{"INLIMBO"})) do
        if valid(entity) and entity.prefab=="farm_soil" and entity._plow==nil then
            local p=point(entity);local cell=selected[U.CellKey(p.x,p.z)]
            if cell then cell.broken_soils=cell.broken_soils or {};cell.broken_soils[#cell.broken_soils+1]={id="soil:"..tostring(entity.GUID),point=p,entity=entity,broken=true} end
        end
    end
    local loose=TheSim:FindEntities(center.x,0,center.z,radius,nil,{"INLIMBO","NOCLICK","FX"})
    result.obstacles={}
    local products,seeds,oversized={},{seeds=true},{}
    for _,def in pairs(defs) do if def.product then products[def.product]=true end;if def.seed then seeds[def.seed]=true end;if def.product_oversized then oversized[def.product_oversized]=true end end
    for _,entity in ipairs(loose) do if valid(entity) then
        local p=point(entity);local cell=selected[U.CellKey(p.x,p.z)]
        -- A folding returned plow anywhere in the work radius is kept awake
        -- until native code makes it pickable; only then is it collected.
        local plow_item=entity.prefab=="farm_plow_item"
        if plow_item then wake_returning_plow_item(entity) end
        if cell and not entity:HasTag("NOBLOCK") and not entity:HasTag("player")
            and not entity:HasTag("DECOR") and not entity:HasTag("soil") and not entity:HasTag("merm") then
            result.obstacles[#result.obstacles+1]={id=entity.GUID,point=p,prefab=entity.prefab}
        end
        if oversized[entity.prefab] then result.oversized[#result.oversized+1]={GUID=entity.GUID,entity=entity,x=p.x,z=p.z}
        elseif cell and (entity:HasTag("farm_debris") or entity:HasTag("weed")) and entity.components.workable and entity.components.workable:GetWorkAction()==ACTIONS.DIG then
            result.debris[#result.debris+1]={entity=entity,id=entity.GUID,point=p,cell=cell.key,work=call(entity.components.workable,"GetWorkLeft") or 1}
        elseif entity.components.inventoryitem and not entity.components.inventoryitem.owner
            and entity.components.inventoryitem.canbepickedup~=false
            and not entity:HasTag("irreplaceable") and not entity:HasTag("heavy") and not entity:HasTag("oversized_veggie")
            and (seeds[entity.prefab] or products[entity.prefab] or plow_item or cell and cell.is_farm) then
            -- Real debris loot and the returned plow can block the first hole
            -- before a complete layout exists. Clear safe loose items on the
            -- selected cultivated plot before asking for that complete layout.
            -- A ground plow anywhere in the radius is collected for the
            -- warehouse; held (owner), folding (not pickable) ones are not.
            result.pickups[#result.pickups+1]={entity=entity,id=entity.GUID,point=p,prefab=entity.prefab,
                priority=cell and cell.is_farm and 2 or 3,blocker=cell and cell.is_farm or false}
        end
    end end
    table.sort(cells,function(a,b)return a.key<b.key end)
    local function byid(a,b)return tostring(a.id)<tostring(b.id)end
    for _,cell in ipairs(cells) do table.sort(cell.plants,byid);table.sort(cell.soils,byid) end
    table.sort(result.killjoys,byid);table.sort(result.neighbors,byid);result.cells=cells
    table.sort(result.pickups,byid);table.sort(result.obstacles,byid)
    table.sort(result.lights,byid)
    result.legal_hole=function(p,cell) return map:CanTillSoilAtPoint(p.x,0,p.z,not cell.is_farm) end
    result.legal_music=function(p) return map:IsPassableAtPoint(p.x,0,p.z) end
    return result
end
return M
