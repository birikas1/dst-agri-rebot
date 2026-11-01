-- Codex acceptance: exercise the real simple planner and scheduler together.
local clock=100
GetTime=function() return clock end
Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...)local o=setmetatable({},cls);ctor(o,...);return o end})
end
TheWorld={state={}}
TheSim={FindEntities=function()return {} end}
TUNING={}
local Planner=require("components/agriplanner")
local Scheduler=require("components/agrischeduler")
local Simple=require("agri/simple_planner")
local C=require("agri/constants")
local function entity(guid)
    return {GUID=guid,IsValid=function()return true end,HasTag=function()return false end}
end
local def={seed="carrot_seeds",prefab="farm_plant_carrot",good_seasons={autumn=true},
    grow_time={seed={100,100},sprout={100,100},small={100,100},med={100,100}},
    moisture={min_percent=.5,drink_rate=.01},nutrient_consumption={0,0,0},nutrient_restoration={}}
local function fixture(options)
    options=options or {}
    local a,b=entity(1),entity(2);a.components={};b.components={}
    local planner=Planner({})
    local scheduler=Scheduler(a)
    local settings={running=true,simple=true,radius=16,density="9",plan={carrot=options.quota or 36},mode="stable",continuous=true}
    local group={id="phases",settings=settings,members={a,b},scheduler=scheduler,center={x=2,z=2},revision=1}
    scheduler.group=group
    local s={now=clock,group_id=group.id,epoch=0,settings=settings,center=group.center,
        world={season="autumn",season_remaining=1000,season_order={"autumn"},season_lengths={autumn=1000}},
        defs={carrot=def},cells={},debris={},neighbors={},hole_cycles={},
        resources={seeds={carrot_seeds=100},fertilizers={},tools={hoe={count=1,uses=100}},
            water={uses=100,per_use=10,soil_per_use=10,cans={{guid=51,uses=100,carried=true}},has_source=true}},
        tuning={min_spacing=1.25,nutrient_capacity=100}}
    for i,p in ipairs({{2,2},{6,2},{2,6},{6,6}}) do
        local c={key="tile"..i,x=p[1],z=p[2],is_farm=true,plants={},soils={},nutrients={100,100,100},
            moisture={moisture=100,capacity=100,drain=.01,weather={}}}
        if not options.clean then
            c.soils={{id="soil:"..i,entity=entity(100+i),point={x=c.x+.7,z=c.z-.9}}}
            s.debris[#s.debris+1]={id=tostring(i),entity=entity(200+i),cell=c.key,point={x=c.x-.5,z=c.z+.5}}
        end
        if options.reuse then
            local p0=Simple.Points(c,9,1.25)[1]
            c.soils[#c.soils+1]={id="grid:"..i,entity=entity(300+i),point=p0}
        end
        s.cells[#s.cells+1]=c
    end
    local function plan()
        s.now=clock;s.settings=group.settings;s.epoch=group.planner_epoch or 0
        local p=planner:PlanSimple(group,s);group.plan=p;scheduler:SetPlan(p,group);return p
    end
    return {a=a,b=b,p=planner,s=s,g=group,q=scheduler,plan=plan}
end
local function stage(t)
    if t.kind=="CLEAR" then return 1 end
    if t.kind=="TILL" then return t.data.unsoil and 2 or 3 end
    if t.kind=="PLANT" then return 4 end
    if t.kind=="WATER" then return 5 end
    if t.kind=="TEND" or t.kind=="MUSIC_TEND" then return 6 end
end
local function counts(tasks)
    local n={}
    for _,t in ipairs(tasks)do local r=stage(t);if r then n[r]=(n[r] or 0)+1 end end
    return n
end
local failures,passed={},0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1 else failures[#failures+1]=name..": "..tostring(err) end
end

test("2x2 whole-work-plan order with reused soils",function()
    local f=fixture({reuse=true});local p=f.plan();local n=counts(p.tasks)
    assert(n[1]==4 and n[2]==4 and n[3]==32 and n[4]==36,"fixture must cover all four plots")
    local last,total=0,0
    while true do
        local t=f.q:Claim(f.a);if not t then break end
        local r=stage(t)
        assert(r and r>=last,"work interleaved at "..t.id.." after stage "..last)
        last=r;total=total+1;f.q:Complete(t.id,f.a)
    end
    assert(total==76,"not all work completed")
end)

test("second robot cannot start next phase while one clear is running",function()
    local f=fixture();f.plan()
    local first=f.q:Claim(f.a);f.q:Running(first,f.a)
    for _=1,3 do local t=f.q:Claim(f.b);assert(stage(t)==1);f.q:Complete(t.id,f.b) end
    assert(f.q:Claim(f.b)==nil,"unfinished clear was bypassed")
    f.q:Complete(first.id,f.a)
    assert(stage(f.q:Claim(f.b))==2)
end)

test("blocked clear blocks later phases",function()
    local f=fixture();f.plan()
    local t=f.q:Claim(f.a);f.q:Fail(t.id,f.a,"missing_tool",true)
    for _=1,3 do local other=f.q:Claim(f.b);assert(stage(other)==1);f.q:Complete(other.id,f.b) end
    assert(f.q:Claim(f.b)==nil,"blocked cleanup must not release planting")
    f.q:Unblock("resources");assert(stage(f.q:Claim(f.a))==1)
end)

test("unclaimable clear does not let equipped robots skip a phase",function()
    local f=fixture();f.plan()
    f.a.components.agriresource={FindActionItem=function(_,t)return t.kind~="CLEAR" and {} or nil end}
    assert(f.q:Claim(f.a)==nil,"lack of shovel cannot turn into early tilling")
    assert(stage(f.q:Claim(f.b))==1,"a helper with tools still runs")
end)

test("retry delay does not release following phase",function()
    local f=fixture();f.plan()
    local t=f.q:Claim(f.a);f.q:Fail(t.id,f.a,"action_rejected")
    for _=1,3 do local other=f.q:Claim(f.b);assert(stage(other)==1);f.q:Complete(other.id,f.b) end
    assert(f.q:Claim(f.b)==nil,"retrying clear was bypassed")
    clock=clock+10;assert(f.q:Claim(f.b).id==t.id)
end)

test("phase gate lets logistics child resolve its parent",function()
    local f=fixture();f.plan();local parent=f.q:Claim(f.a)
    local child=f.q:PushSubtask(f.a,parent,{kind="UNLOAD",data={}})
    assert(child and f.q:Claim(f.a).id==child.id,"phase gate deadlocked logistics")
    f.q:Complete(child.id,f.a)
    assert(f.q:Claim(f.a).id==parent.id)
end)

test("new cleanup inserted by rescan beats historical queued tills",function()
    local f=fixture({clean=true});f.plan()
    f.s.debris={{id="new",entity=entity(909),cell="tile4",point={x=6,z=6}}}
    f.plan()
    assert(stage(f.q:Claim(f.a))==1,"historical FIFO won over new phase")
end)

test("save load preserves cross-tile barriers",function()
    local f=fixture();f.plan()
    local first=f.q:Claim(f.a);f.q:Complete(first.id,f.a)
    local restored=Scheduler(f.a);restored.group=f.g;restored:Restore(f.q:Save());restored:LoadPostPass({})
    for _=1,3 do local t=restored:Claim(f.a);assert(stage(t)==1);restored:Complete(t.id,f.a) end
    local held=restored:Claim(f.a);assert(stage(held)==2)
    for _=1,3 do local t=restored:Claim(f.b);assert(stage(t)==2);restored:Complete(t.id,f.b) end
    assert(restored:Claim(f.b)==nil,"loaded unfinished removal was bypassed")
end)

test("current quota is global and is not silently repeated per tile",function()
    local f=fixture({quota=9,clean=true});local n=counts(f.plan().tasks)
    assert(n[4]==9 and n[3]==9,"compatibility semantics changed before user alignment")
end)

test("ordinary care follows planting then water then tending",function()
    local f=fixture({clean=true})
    f.p.Maintenance=function()
        return {{id="ordinary-tend",kind="TEND",priority=3,target=entity(811),data={}},
            {id="ordinary-water",kind="WATER",priority=3,point={x=2,z=2},data={cell="tile1",simple=true,water_below=.1}}},
            {water_reasons={},viability_failures={}}
    end
    f.plan();local last,n=0,0
    while true do
        local t=f.q:Claim(f.a);if not t then break end
        local r=stage(t);assert(r>=last,"ordinary care ran before its stage")
        last=r;n=n+1;f.q:Complete(t.id,f.a)
    end
    assert(n==74 and last==6)
end)

test("rescan newly discovered cleanup interrupts a running later phase",function()
    local f=fixture({clean=true});f.plan();local till=f.q:Claim(f.a)
    assert(stage(till)==3)
    f.s.debris={{id="late",entity=entity(910),cell="tile4",point={x=6,z=6}}};f.plan()
    assert(f.q:HigherPriority(till,f.a),"late first-phase work cannot interrupt later work")
end)

test("paused later work cannot resume ahead of new cleanup",function()
    local f=fixture({clean=true});f.plan();local till=f.q:Claim(f.a)
    assert(stage(till)==3);f.q:Pause(f.a,"player_edit")
    f.s.debris={{id="late-paused",entity=entity(911),cell="tile4",point={x=6,z=6}}};f.plan()
    local t=f.q:Claim(f.a);assert(t and stage(t)==1,"own paused task bypassed phase gate")
end)

test("later running work yields even when only its helper can clear",function()
    local f=fixture({clean=true});f.plan();local till=f.q:Claim(f.a)
    f.a.components.agriresource={FindActionItem=function(_,t)return t.kind~="CLEAR" and {} or nil end}
    f.s.debris={{id="helper-only",entity=entity(912),cell="tile4",point={x=6,z=6}}};f.plan()
    assert(f.q:HigherPriority(till,f.a),"running task crossed the barrier while its helper clears")
end)

test("pre-stage simple saves obey categories before first rescan",function()
    local f=fixture({reuse=true});f.plan();local data=f.q:Save()
    for _,t in ipairs(data.tasks)do t.stage=nil end
    local restored=Scheduler(f.a);restored.group=f.g;restored:Restore(data);restored:LoadPostPass({})
    local last,n=0,0
    while true do
        local t=restored:Claim(f.a);if not t then break end
        local r=stage(t);assert(r>=last,"pre-stage save executes old per-hole FIFO")
        last=r;n=n+1;restored:Complete(t.id,f.a)
    end
    assert(n==76)
end)

test("shrinking plan cancels abandoned plot work without blocking current plot",function()
    local f=fixture({clean=true});f.plan()
    f.g.settings.plan={carrot=9};f.plan()
    local n,last=0,0
    while true do
        local t=f.q:Claim(f.a);if not t then break end
        local r=stage(t);assert(r>=last);last=r;n=n+1;f.q:Complete(t.id,f.a)
    end
    assert(n==18,"abandoned plots stalled or executed after plan shrink")
end)

test("urgent measured moisture preempts a long preparation backlog",function()
    local f=fixture({clean=true});local c=f.s.cells[1]
    c.plants={{id="living",crop="carrot",def=def,entity=entity(701),stage="sprout",point={x=2,z=2},
        mature=false,tendable=true,moisture={elapsed=0,hydrated=0}}}
    f.plan();local first=f.q:Claim(f.a);assert(stage(first)==3)
    c.moisture.moisture=0
    local plan=f.plan();local water
    for _,t in ipairs(plan.tasks)do if t.kind=="WATER"then water=t end end
    assert(water,"dry existing crop has no water job")
    assert(f.q:HigherPriority(first,f.a),"dry crop water does not interrupt long batch")
    f.q:Pause(f.a,"priority")
    assert(f.q:Claim(f.a).kind=="WATER","dry crop water remains behind preparation")
    f.q:Complete(water.id,f.a);c.moisture.moisture=100;clock=clock+C.PLAN_INTERVAL
    local wet=f.plan();for _,t in ipairs(wet.tasks)do assert(t.kind~="WATER","wet soil got a redundant pour")end
end)

test("moisture reserve anticipates travel rather than waiting for dry soil",function()
    local f=fixture({clean=true});local c=f.s.cells[1]
    c.plants={{id="living",crop="carrot",def=def,entity=entity(701),stage="sprout",point={x=2,z=2},mature=false}}
    -- At .02/sec, 0.7 is 35 seconds of reserve: a 20-second-only cap is unsafe.
    c.moisture.moisture=.7
    local p=f.plan();local water
    for _,t in ipairs(p.tasks)do if t.kind=="WATER"then water=t end end
    assert(water,"no anticipatory water job despite a long backlog")
end)

test("replanning low moisture never stacks duplicate live water jobs",function()
    local f=fixture({clean=true});local c=f.s.cells[1]
    c.plants={{id="living",crop="carrot",def=def,entity=entity(701),stage="sprout",point={x=2,z=2},mature=false}}
    c.moisture.moisture=0
    local p=f.plan();local water
    for _,t in ipairs(p.tasks)do if t.kind=="WATER"then water=t end end
    assert(water)
    local first=f.q:Claim(f.a);assert(first.kind=="WATER")
    clock=clock+C.PLAN_INTERVAL;f.plan()
    local n=0
    for _,t in pairs(f.q.tasks)do if t.kind=="WATER" and t.state~="complete" and t.state~="cancelled" then n=n+1 end end
    assert(n==1,"duplicate water jobs across replan")
end)

test("queued water escalates between rescans",function()
    local f=fixture({clean=true});local c=f.s.cells[1]
    c.plants={{id="living",crop="carrot",def=def,entity=entity(701),stage="sprout",point={x=2,z=2},mature=false}}
    c.moisture.moisture=.7
    local p=f.plan();local water
    for _,t in ipairs(p.tasks)do if t.kind=="WATER"then water=t end end
    assert(water and water.priority==3 and water.deadline>clock,"fixture needs an initially ordinary water job")
    local till=f.q:Claim(f.a);assert(stage(till)==3)
    clock=water.deadline+.1
    assert(f.q:HigherPriority(till,f.a),"water did not escalate without another rescan")
end)

test("critical crop water preempts an unrelated logistics child",function()
    local f=fixture({clean=true});f.plan();local till=f.q:Claim(f.a)
    local fetch=f.q:PushSubtask(f.a,till,{kind="FETCH",data={requirements={seeds={carrot_seeds=20}}}})
    assert(f.q:Claim(f.a).id==fetch.id)
    local c=f.s.cells[1];c.plants={{id="living",crop="carrot",def=def,entity=entity(701),stage="sprout",point={x=2,z=2},mature=false}}
    c.moisture.moisture=0;f.plan()
    assert(f.q:HigherPriority(fetch,f.a),"critical crop water cannot interrupt a long supply trip")
    f.q:Pause(f.a,"priority");assert(f.q:Claim(f.a).kind=="WATER")
end)

test("urgent water refill child resolves without a priority loop",function()
    local f=fixture({clean=true});local c=f.s.cells[1]
    c.plants={{id="living",crop="carrot",def=def,entity=entity(701),stage="sprout",point={x=2,z=2},mature=false}}
    c.moisture.moisture=0;f.s.resources.water.uses=0;f.s.resources.water.cans[1].uses=0
    f.plan();local water=f.q:Claim(f.a);assert(water.kind=="WATER")
    local refill=f.q:PushSubtask(f.a,water,{kind="REFILL",data={}})
    assert(f.q:Claim(f.a).id==refill.id)
    assert(not f.q:HigherPriority(refill,f.a),"suspended water preempts its own refill")
    f.q:Complete(refill.id,f.a);assert(f.q:Claim(f.a).id==water.id)
end)

if #failures>0 then error(table.concat(failures,"\n")) end
return passed.." farm phase and moisture safety scenarios"
