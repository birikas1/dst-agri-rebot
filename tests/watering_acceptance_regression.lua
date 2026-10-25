-- Independent automatic-watering acceptance, rather than injected WATER tasks.
Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...)local o=setmetatable({},cls);ctor(o,...);return o end})
end
local Planner=require("components/agriplanner")
local function snapshot(options)
    options=options or {}
    local def={seed="carrot_seeds",prefab="farm_plant_carrot",good_seasons={autumn=true},
        grow_time={seed={10,10},sprout={10,10},small={10,10},med={10,10}},
        moisture={min_percent=.5,drink_rate=.1},nutrient_consumption={0,0,0},nutrient_restoration={}}
    if options.unknown_growth then def.grow_time={} end
    local p={id="dry-carrot",crop="carrot",def=def,stage="sprout",remaining=10,
        mature=options.mature or false,point={x=2,z=2},
        moisture={elapsed=options.elapsed or 0,hydrated=0}}
    return {now=100,settings={mode="stable"},world={season="autumn",season_remaining=1000,
        season_order={"autumn"},season_lengths={autumn=1000}},
        cells={{key="farm",x=2,z=2,is_farm=true,plants={p},soils={},nutrients={100,100,100},
            moisture={moisture=options.wet and 100 or 0,capacity=100,drain=.1,weather={}}}},
        resources={water={uses=options.empty and 0 or 10,per_use=5,soil_per_use=5,
            has_source=options.has_source or false,cans={{guid=1,uses=options.empty and 0 or 10,capacity=40,addwetness=5}}},tools={}},
        tuning={nutrient_capacity=100},neighbors={}}
end
local planner=Planner({})
local failures,passed={},0
local function test(name,opts,expected)
    local ok,err=pcall(function()
        local tasks=planner:Maintenance(snapshot(opts),true)
        local n=0
        for _,t in ipairs(tasks) do if t.kind=="WATER" then n=n+1 end end
        assert(n==expected,"expected "..expected.." WATER task(s), got "..n)
    end)
    if ok then passed=passed+1 else failures[#failures+1]=name..": "..tostring(err) end
end
test("fresh dry crop",{},1)
test("dry crop still watered after current hydration target is unrecoverable",{elapsed=100},1)
test("dry crop care survives unknown growth forecast",{unknown_growth=true},1)
test("wet soil avoids unnecessary watering",{wet=true},0)
test("mature crop is harvested rather than watered",{mature=true},0)
test("empty can with a water source retains water/refill work",{empty=true,has_source=true},1)
if #failures>0 then error(table.concat(failures,"\n")) end
return passed.." independent automatic watering scenarios"
