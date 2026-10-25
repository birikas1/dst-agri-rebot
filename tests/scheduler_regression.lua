local time=100
GetTime=function() return time end
Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...) local o=setmetatable({},cls);ctor(o,...);return o end})
end
TheWorld={state={}}
TheSim={FindEntities=function() return {} end}
TUNING={}
local Scheduler=require("components/agrischeduler")
local Resource=require("components/agriresource")
local function robot(id)
    return {GUID=id,components={},IsValid=function()return true end}
end
local a,b=robot(1),robot(2)
local function scheduler()
    local s=Scheduler(a)
    s.group={settings={running=true},members={a,b},revision=1,center={x=0,z=0}}
    return s
end

-- One target has a single owner and releases its downstream hole immediately.
local s=scheduler()
s:Add({id="till1",kind="TILL"});s:Add({id="plant1",kind="PLANT",deps={"till1"}})
assert(s:Claim(a).id=="till1")
assert(s:Claim(b)==nil)
s:Complete("till1",a)
assert(s:Claim(b).id=="plant1")

-- Removing a worker during P2 must not resume the parent before the child.
s=scheduler()
local parent=s:Add({id="till",kind="TILL"})
s:Claim(a)
local child=s:PushSubtask(a,parent,{kind="PICKUP"})
s:Claim(a)
s:Release(a)
assert(parent.suspended_by==child.id,"worker release lost P2 continuation")
assert(s:Claim(b)==child,"child must run first")
assert(s:Claim(a)==nil,"parent must wait while another robot clears its blocker")
s:Complete(child.id,b)
assert(s:Claim(a)==parent,"parent should resume after child completes")

-- Planner exceptions freeze all work until a verified plan replaces them.
s=scheduler();s:Add({id="seed",kind="PLANT"})
s.group.planner_error=true
assert(s:IsFrozen() and s:Claim(a)==nil,"stale plan remained executable after planner error")
s.group.planner_error=nil
assert(s:Claim(a).id=="seed")

-- Completed steps are not included in subsequent batch-fetch demand.
local group={plan={tasks={
    {id="planted",kind="PLANT",prefab="tomato_seeds"},
    {id="future",kind="PLANT",prefab="potato_seeds"},
    {id="fertilized",kind="FERTILIZE",prefab="poop"},
}},scheduler={tasks={planted={state="complete"},future={state="pending"},fertilized={state="cancelled"}}}}
local demand=Resource.Demand({},group)
assert(demand.seeds.tomato_seeds==nil,"batch fetch counted already planted seeds")
assert(demand.seeds.potato_seeds==1)
assert(demand.fertilizers.poop==nil,"batch fetch counted cancelled fertilizer")

-- Concurrent dangers suspend once, and only the last cleared danger resumes.
s=scheduler();local paused=s:Add({id="original",kind="PLANT"})
s:Claim(a)
s:SetEmergency({boss={kind="boss"},frograin={kind="frograin"}})
assert(paused.state=="paused" and s:Claim(a)==nil)
s:SetEmergency({frograin={kind="frograin"}})
assert(s:Claim(b)==nil,"one remaining P0 threat must still freeze the farm")
s:SetEmergency({})
assert(s:Claim(a)==paused,"original owner must resume its paused task")

-- Repeated native rejection stops after the retry limit.
s=scheduler();s:Add({id="unreachable",kind="TILL"})
for i=1,3 do
    assert(s:Claim(a).id=="unreachable")
    s:Fail("unreachable",a,"action_rejected")
    time=time+10
end
assert(s.tasks.unreachable.state=="blocked" and s:Claim(a)==nil)

-- Restoring a missing worker retains a suspended dependency and reassigns it.
s=scheduler()
s:Restore({tasks={
    {id="parent",kind="TILL",state="paused",owner_guid=99,suspended_by="child"},
    {id="child",kind="PICKUP",state="paused",owner_guid=99,parent_id="parent",priority=2},
}})
s:LoadPostPass({})
assert(s:Claim(a).id=="child")
assert(s:Claim(b)==nil,"load with missing owner must not bypass unfinished child")
s:Complete("child",a)
assert(s:Claim(b).id=="parent")
return "7 scenarios: claim/DAG, P2 transfer/reload, planner failure, demand, multiple P0, retry bound"
