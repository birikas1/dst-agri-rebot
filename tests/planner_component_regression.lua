Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...) local o=setmetatable({},cls);ctor(o,...);return o end})
end
local Planner=require("components/agriplanner")
local function snapshot(now,remaining)
    local def={seed="carrot_seeds",prefab="farm_plant_carrot",good_seasons={autumn=true},
        grow_time={seed={10,10},sprout={10,10},small={10,10},med={10,10}},
        moisture={min_percent=0,drink_rate=0},nutrient_consumption={0,0,0},nutrient_restoration={},
        family_min_count=1,family_check_dist=4}
    return {now=now,revision=1,world={season="autumn",season_remaining=remaining,
            season_order={"autumn","winter"},season_lengths={autumn=100,winter=100}},
        defs={carrot=def},cells={{key="0:0",x=0,z=0,is_farm=true,plants={},soils={},
            nutrients={0,0,0},moisture={moisture=0,drain=0,capacity=100}}},
        resources={seeds={carrot_seeds=6},fertilizers={},tools={hoe={uses=6}},water={uses=0,cans={}}},
        tuning={min_spacing=.8,max_plants=9,nutrient_capacity=100},neighbors={}}
end
local group={settings={mode="oversized",density=6,allow_random=false,planting="auto"},presets={}}
local planner=Planner({})
local current=snapshot(0,100)
planner.Capture=function() return current end
local available=planner:GetRecommendations(group,1,8)
assert(available.complete and available.total>0,"fixture needs an initially safe recommendation")

-- Stock and plants can stay unchanged as the seasonal deadline approaches.
-- The completed recommendation cache must not keep advertising a giant plan
-- that now crosses into an unsuitable season.
current=snapshot(90,10)
local expired=planner:GetRecommendations(group,1,8)
assert(expired.complete and expired.total==0,"completed recommendations ignored seasonal time passing")
assert(planner.recommendation_search.snapshot.now==90,"recommendations reused an old forecast")

-- Simple watering follows the measured soil, not the stage forecast. The crop
-- here has an unknown growth forecast and an unrecoverable hydration history.
local function watering(options)
    local def={seed="carrot_seeds",prefab="farm_plant_carrot",good_seasons={autumn=true},grow_time={},
        moisture={min_percent=.5,drink_rate=.1},nutrient_consumption={0,0,0},nutrient_restoration={}}
    local cans=options.cans or {{guid=1,uses=10,capacity=40,addwetness=25,carried=true}}
    return {now=100,settings=options.settings or {mode="stable"},
        world={season="autumn",season_remaining=1000,season_order={"autumn"},season_lengths={autumn=1000}},
        cells={{key="farm",x=2,z=2,is_farm=true,soils={},nutrients={100,100,100},moisture={moisture=options.moisture,capacity=100,drain=.1,weather={}},
            plants={{id="p",crop="carrot",def=def,stage="sprout",remaining=10,point={x=2,z=2},moisture={elapsed=100,hydrated=0}}}}},
        resources={water={uses=10,per_use=25,soil_per_use=25,has_source=false,cans=cans},tools={}},tuning={nutrient_capacity=100},neighbors={}}
end
local function waters(tasks) local out={};for _,t in ipairs(tasks) do if t.kind=="WATER" then out[#out+1]=t end end;return out end
local function coded(summary,code) for _,r in ipairs(summary.water_reasons) do if r.code==code then return true end end;return false end
local tasks,summary=planner:Maintenance(watering({moisture=0}),true)
local w=waters(tasks)
assert(#w==1 and w[1].id=="water:farm:10" and w[1].data.simple and math.abs(w[1].data.water_below-4)<1e-9,"dry soil gets one current-soil water job")
assert(#waters(planner:Maintenance(watering({moisture=20}),true))==0,"moist soil is not watered again")
tasks,summary=planner:Maintenance(watering({}),true)
assert(#waters(tasks)==0 and coded(summary,"WATER_MOISTURE_UNKNOWN"),"unknown soil moisture is reported, not guessed")
tasks,summary=planner:Maintenance(watering({moisture=0,cans={}}),true)
assert(#waters(tasks)==0 and coded(summary,"WATER_NO_CAN"),"a missing can is reported")
tasks,summary=planner:Maintenance(watering({moisture=0,cans={{guid=1,uses=10,capacity=40,addwetness=25,carried=false}}}),true)
assert(#waters(tasks)==0 and coded(summary,"WATER_CAN_NOT_CARRIED"),"a warehouse-only can is reported")
tasks,summary=planner:Maintenance(watering({moisture=0,cans={{guid=1,uses=0,capacity=40,addwetness=25,carried=true}}}),true)
assert(#waters(tasks)==1 and coded(summary,"WATER_NO_SOURCE"),"an empty can still reaches the executor's REFILL stop")
local reuse=watering({moisture=0});reuse.water_tasks={farm="older-water"}
w=waters(planner:Maintenance(reuse,true))
assert(#w==1 and w[1].id=="older-water","a live water job keeps its id across rescans")
assert(#waters(planner:Maintenance(watering({moisture=0,settings={mode="stable",simple=false}}),true))==0,
    "simple=false keeps the forecast-gated planner")

-- PlanSimple keeps one live job per plot and retires blocked ones (and their
-- refill children) so the next soil read can retry.
local sched={tasks={},order={}}
local function add(id,kind,state,extra)
    local t={id=id,kind=kind,state=state,data={cell="farm"}};for k,v in pairs(extra or {}) do t[k]=v end
    sched.tasks[id]=t;sched.order[#sched.order+1]=id
end
add("water:farm:3","WATER","blocked");add("water:farm:3/p2/1","REFILL","blocked",{parent_id="water:farm:3",data={}})
add("water:farm:5","WATER","pending");add("water:farm:6","WATER","pending")
local plan=planner:PlanSimple({id="g",center={x=2,z=2},settings={radius=16,density="9",plan={}},scheduler=sched},watering({moisture=0}))
w=waters(plan.tasks)
local cancelled={};for _,id in ipairs(plan.cancel_ids) do cancelled[id]=true end
assert(#w==1 and w[1].id=="water:farm:5","the queued water job is reused instead of stacking another use")
assert(cancelled["water:farm:3"] and cancelled["water:farm:3/p2/1"] and cancelled["water:farm:6"] and not cancelled["water:farm:5"],
    "blocked and duplicate water jobs are retired")

print("planner component regressions passed")
