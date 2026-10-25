local Moisture=require("agri/moisture_sim")
local Nutrients=require("agri/nutrient_sim")
local Fertilizer=require("agri/fertilizer_solver")
local Season=require("agri/season_predictor")
local Layout=require("agri/layout_planner")

local function near(actual,expected,message)
    assert(math.abs(actual-expected)<0.00001,(message or "unexpected number")..": "..tostring(actual).." ~= "..tostring(expected))
end
local function plant(id,minimum,earliest,latest,elapsed,hydrated)
    return {id=id,def={moisture={min_percent=minimum}},remaining=latest,
        moisture={elapsed=elapsed or 0,hydrated=hydrated or 0},
        growth={stages={{earliest=earliest,latest=latest}}}}
end
local dry={moisture=0,drain=1,capacity=100}

-- Existing wet-time credit can guarantee an uncertain checkpoint without a can.
local hydrated=Moisture.Predict(dry,{plant("hydrated",.5,1,10,100,100)})
assert(hydrated.feasible,hydrated.reason)
near(hydrated.water,0,"already safe plant must not be watered")
near(hydrated.uses,0)
local no_requirement=Moisture.Predict(dry,{plant("no requirement",0,1,10)})
assert(no_requirement.feasible,no_requirement.reason)
near(no_requirement.water,0,"zero threshold must not require a can")

-- Current soil alone can satisfy every possible checkpoint, not only the last.
local moist=Moisture.Predict({moisture=9,drain=1,capacity=100},{plant("soil",.5,1,10)})
assert(moist.feasible,moist.reason)
near(moist.water,0)

-- Late rain cannot rescue an earlier possible dry checkpoint.
local late_rain=Moisture.Predict({moisture=0,drain=1,capacity=100,water_per_use=10,
    weather={{duration=5,rain=0},{duration=5,rain=2}}}, {plant("late rain",.5,5,10)})
assert(late_rain.feasible,late_rain.reason)
assert(late_rain.water>0,"late rain must not hide early moisture stress")
assert(late_rain.due<=2.5+0.00001,"water must precede the earliest checkpoint")

-- An intermediate dry spell matters even when both endpoints are hydrated.
local dry_middle=Moisture.Predict({moisture=1,drain=1,capacity=100,water_per_use=10,
    weather={{duration=6,rain=0},{duration=4,rain=2}}}, {plant("dry middle",.5,1,10,2,2)})
assert(dry_middle.feasible,dry_middle.reason)
assert(dry_middle.water>0,"intermediate checkpoint stress must be detected")

-- Exact checkpoints retain the minimum necessary water and real-can requirement.
local exact=Moisture.Predict({moisture=0,drain=2,capacity=100,water_per_use=3},{plant("exact",.5,10,10)})
assert(exact.feasible,exact.reason)
near(exact.water,10)
near(exact.uses,4)
local missing_can=Moisture.Predict(dry,{plant("needs can",.5,10,10)})
assert(not missing_can.feasible and missing_can.reason=="MISSING_WATERING_CAN")

-- Sequential consumers must be funded even when the round is net-balanced.
local crops={
    {id="consumer",def={nutrient_consumption={4,0,0},nutrient_restoration={false,true,false}},growth={stages={{earliest=1,latest=1,checkpoint=true}}}},
    {id="restorer",def={nutrient_consumption={0,4,0},nutrient_restoration={true,false,false}},growth={stages={{earliest=2,latest=2,checkpoint=true}}}},
}
local nutrition=Nutrients.Simulate(crops,{0,0,0},100)
assert(nutrition.feasible)
near(nutrition.deficit[1],4)
near(nutrition.deficit[2],0)
near(nutrition.net[1],0)
near(nutrition.net[2],0)

-- Whole-round optimization must retain a mixed fertilizer for later demand.
local fertilizer=Fertilizer.Schedule({
    {consumption={1,0,0},restoration={0,0,0}},
    {consumption={0,1,0},restoration={0,0,0}},
}, {0,0,0}, {
    mixed={count=1,nutrients={1,1,0}},
    single_a={count=1,nutrients={1,0,0}},
    single_b={count=1,nutrients={0,1,0}},
},100,{1,1,0})
assert(fertilizer.feasible)
near(fertilizer.count,1)
assert(fertilizer.items.mixed==1)
near(fertilizer.excess,0)

-- Cross-tile family relationships are counted once; excluded plants give no help.
local def={family_check_dist=4,family_min_count=2}
local assignment={{id="a",crop="carrot",def=def,point={x=0,z=0},cell="0:0"}}
local neighbors={{id="a",crop="carrot",point={x=0,z=0},cell="0:0"},
    {id="b",crop="carrot",point={x=3,z=0},cell="1:0"}}
assert(Layout.Validate(assignment,neighbors,9))
neighbors[2].family_excluded=true
assert(not Layout.Validate(assignment,neighbors,9))

-- Growth pauses at night and crossing into a bad season loses giant eligibility.
local growth={grow_time={seed={2,2},sprout={2,2},small={2,2},med={2,2}},good_seasons={autumn=true}}
local world={season="autumn",season_remaining=3,season_order={"autumn","winter"},season_lengths={autumn=100,winter=100}}
local seasonal=Season.Predict(growth,world)
assert(seasonal.feasible)
assert(not seasonal.oversized_eligible)
assert(#seasonal.crossings==1 and seasonal.crossings[1].to=="winter")
local nightworld={season="autumn",season_remaining=100,season_order={"autumn"},season_lengths={autumn=100},
    day=10,time_of_day=.4,current_awake=5,growth_windows={autumn={min_awake=5,max_awake=5}}}
near(Season.AdvanceGrowing(nightworld,0,3,false,false),8)
near(Season.AdvanceGrowing(nightworld,0,3,false,true),3)

print("planner regressions passed")
