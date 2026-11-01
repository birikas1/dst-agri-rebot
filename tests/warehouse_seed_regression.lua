-- Codex contracts for real-item supply and retention across plan rescans.
Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...)local o=setmetatable({},cls);ctor(o,...);return o end})
end
GetTime=function()return 100 end
TheWorld={ismastersim=true,components={}}
TheSim={FindEntities=function()return {}end}
TUNING={}
ACTIONS={}
package.preload["prefabs/farm_plant_defs"]=function()
    return {PLANT_DEFS={carrot={seed="carrot_seeds",product="carrot"},corn={seed="corn_seeds",product="corn"}}}
end
package.preload.bufferedaction=function()return true end
local C=require("agri/constants")
local S=require("agri/storage")
local Resource=require("components/agriresource")
local Scheduler=require("components/agrischeduler")
local Executor=require("components/agriexecutor")
local function item(prefab,n)
    local e={prefab=prefab,valid=true,components={}}
    function e:IsValid()return self.valid end
    function e:HasTag()return false end
    if n then
        local stack={n=n,maxsize=40}
        e.components.stackable=stack
        function stack:StackSize()return self.n end
        function stack:IsFull()return self.n>=self.maxsize end
        function stack:CanStackWith(other)return other.prefab==prefab end
        function stack:Get(amount)self.n=self.n-amount;return item(prefab,amount)end
    end
    return e
end
local function container(inst,n,inventory,filter)
    local slots={}
    local c={inst=inst,numslots=n,maxslots=n,itemtestfn=filter}
    if inventory then c.itemslots=slots else c.slots=slots end
    function c:GetItemSlot(e)for slot,v in pairs(slots)do if v==e then return slot end end end
    function c:GetItemInSlot(i)return slots[i]end
    function c:RemoveItem(e,whole)
        assert(whole==true);local slot=self:GetItemSlot(e)
        if slot then slots[slot]=nil;return e end
    end
    function c:GiveItem(e,slot,pos,drop)
        assert(drop==false,"supply must preserve real items, no dropped rollback")
        if self.reject or self.itemtestfn and not self.itemtestfn(self,e,slot)then return false end
        local old=slots[slot]
        if not old then slots[slot]=e;return true end
        if not S.CanStack(old,e)then return false end
        local a,b=old.components.stackable,e.components.stackable
        local amount=math.min(a.maxsize-a.n,b.n);a.n=a.n+amount;b.n=b.n-amount
        if b.n==0 then e.valid=false;return true end
        return false
    end
    function c:Place(e,slot)slots[slot]=e end
    return c
end
local function fixture()
    local robot={GUID=1,components={},IsValid=function()return true end,HasTag=function()return false end,
        ListenForEvent=function()end,DoTaskInTime=function()end,DoPeriodicTask=function()return {Cancel=function()end}end,
        GetDistanceSqToInst=function(self)return self.distance or 4 end,
        Transform={GetWorldPosition=function()return 0,0,0 end}}
    robot.components.container=container(robot,C.ROBOT_SLOTS,false,S.RobotTest)
    robot.components.inventory=container(robot,C.WORK_SLOTS,true)
    robot.components.agrithermal={NeedsHeat=function()return false end,Refresh=function()end}
    local r=Resource(robot);robot.components.agriresource=r
    local warehouse={GUID=2,components={},IsValid=function()return true end,HasTag=function()return false end,
        Transform={GetWorldPosition=function()return 2,0,0 end}}
    warehouse.components.container=container(warehouse,C.WAREHOUSE_SLOTS,false,S.WarehouseTest)
    local group={id="supply",center={x=0,z=0},settings={running=true,simple=true,radius=16,plan={carrot=9}},
        members={robot},primary=robot,warehouse=warehouse,plan={tasks={}}}
    local q=Scheduler(robot);group.scheduler=q;q.group=group
    TheWorld.components.agrifarmgroup={GetGroup=function()return group end,MarkDirty=function()end}
    local e=Executor(robot);robot.components.agriexecutor=e
    e.WalkNear=function()return true end
    return {robot=robot,r=r,w=warehouse,g=group,q=q,e=e,c=robot.components.container,wc=warehouse.components.container}
end
local function plant(id,prefab)
    return {id=id,kind="PLANT",prefab=prefab or "carrot_seeds",priority=3,count=1,point={x=0,z=0},data={simple=true}}
end
local function install(f,tasks)
    f.g.plan={tasks=tasks};f.q:SetPlan(f.g.plan,f.g)
end
local failures,passed={},0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1 else failures[#failures+1]=name..": "..tostring(err)end
end

test("warehouse batch transfers actual matching seeds",function()
    local f=fixture();local seed=item("carrot_seeds",12);f.wc:Place(seed,1)
    assert(f.r:Fetch(f.g,{seeds={carrot_seeds=9},fertilizers={}}))
    assert(f.r:CountPrefab("carrot_seeds")==9 and S.Count(seed)==3)
end)

test("faraway warehouse cannot remotely transfer seeds",function()
    local f=fixture();f.robot.distance=100;f.wc:Place(item("carrot_seeds",9),1)
    local ok,why=f.r:Fetch(f.g,{seeds={carrot_seeds=9}})
    assert(not ok and why=="need_fetch" and f.r:CountPrefab("carrot_seeds")==0)
    assert(S.Count(f.wc:GetItemInSlot(1))==9)
end)

test("unload retains pending work omitted by a fresh public plan",function()
    local f=fixture();install(f,{plant("pending")});f.c:Place(item("carrot_seeds",1),1)
    f.c:Place(item("carrot",1),2)
    f.g.plan={tasks={}};f.q:SetPlan(f.g.plan,f.g)
    assert(f.r:Unload(f.g))
    assert(f.r:CountPrefab("carrot_seeds")==1,"live planting seed was deposited as surplus")
    assert(f.wc:GetItemInSlot(25).prefab=="carrot","real products must still unload")
end)

test("unload retains suspended planting parent during logistics",function()
    local f=fixture();install(f,{plant("parent")});local parent=f.q:Claim(f.robot)
    f.q:PushSubtask(f.robot,parent,{kind="UNLOAD",data={}})
    f.c:Place(item("carrot_seeds",1),1);f.g.plan={tasks={}}
    assert(f.r:Unload(f.g))
    assert(f.r:CountPrefab("carrot_seeds")==1,"active parent's seed was lost during its own unload")
end)

test("retention considers crops beyond the fetch batching cutoff",function()
    local f=fixture();local tasks={}
    for i=1,C.WORK_SLOTS*2 do tasks[#tasks+1]=plant("earlier"..i,"corn_seeds")end
    tasks[#tasks+1]=plant("later-carrot")
    install(f,tasks);f.c:Place(item("carrot_seeds",1),1)
    assert(f.r:Unload(f.g))
    assert(f.r:CountPrefab("carrot_seeds")==1,"batch cutoff discarded a later crop's required seed")
end)

test("terminal work releases surplus but blocked work keeps its seed",function()
    local f=fixture();install(f,{plant("complete"),plant("cancelled"),plant("failed"),plant("blocked")})
    f.q.tasks.complete.state="complete";f.q.tasks.cancelled.state="cancelled";f.q.tasks.failed.state="failed";f.q.tasks.blocked.state="blocked"
    f.c:Place(item("carrot_seeds",4),1);assert(f.r:Unload(f.g))
    assert(f.r:CountPrefab("carrot_seeds")==1 and S.Count(f.wc:GetItemInSlot(1))==3)
end)

test("live and public copies of the same task are not double-counted",function()
    local f=fixture();install(f,{plant("same")});f.c:Place(item("carrot_seeds",4),1)
    assert(f.r:Unload(f.g));assert(f.r:CountPrefab("carrot_seeds")==1)
    assert(S.Count(f.wc:GetItemInSlot(1))==3)
end)

test("current requested crop survives a full earlier batch",function()
    local f=fixture();local tasks={}
    for i=1,C.WORK_SLOTS*2 do tasks[#tasks+1]=plant("first"..i,"corn_seeds")end
    local current=plant("current","carrot_seeds");tasks[#tasks+1]=current;install(f,tasks)
    local d=f.r:Demand(f.g,current)
    assert((d.seeds.carrot_seeds or 0)>=1,"fetch omitted current seed in favor of future work")
end)

test("missing future batch material cannot block a usable current seed",function()
    local f=fixture();local tasks={plant("current","carrot_seeds"),plant("future","corn_seeds")};install(f,tasks)
    local parent=f.q:Claim(f.robot)
    local child=f.q:PushSubtask(f.robot,parent,{kind="FETCH",data={requirements=f.r:Demand(f.g,parent)}})
    assert(f.q:Claim(f.robot).id==child.id)
    f.wc:Place(item("carrot_seeds",1),1)
    f.e.current=child;assert(f.e:Manual(child,f.g))
    assert(f.r:CountPrefab("carrot_seeds")==1,"real current seed was not transferred")
    assert(f.q.tasks[child.id].state=="complete" and parent.state~="blocked","unrelated future shortage blocked supplied current action")
    assert(f.q:Claim(f.robot).id==parent.id,"planting cannot resume after useful partial fetch")
end)

test("no matching seed produces a visible bounded stop",function()
    local f=fixture();install(f,{plant("current")});local parent=f.q:Claim(f.robot)
    local child=f.q:PushSubtask(f.robot,parent,{kind="FETCH",data={requirements=f.r:Demand(f.g,parent)}})
    f.q:Claim(f.robot);f.e.current=child;f.e:Manual(child,f.g)
    assert(parent.state=="blocked" and f.q.tasks[child.id].state=="blocked")
    assert(parent.reason and f.q:Claim(f.robot)==nil)
end)

test("full destination preserves all real seed stock",function()
    local f=fixture()
    for i=1,C.WORK_SLOTS do f.c:Place(item("carrot",40),i)end
    f.wc:Place(item("carrot_seeds",9),1)
    assert(not f.r:Fetch(f.g,{seeds={carrot_seeds=9}}))
    assert(S.Count(f.wc:GetItemInSlot(1))==9 and f.r:CountPrefab("carrot_seeds")==0)
end)

test("one shared planting need does not retain duplicate stock on both workers",function()
    local f,b=fixture(),fixture();b.robot.GUID=77;f.g.members={f.robot,b.robot}
    install(f,{plant("shared")});f.c:Place(item("carrot_seeds",1),1);b.c:Place(item("carrot_seeds",1),1)
    assert(f.r:Unload(f.g)and b.r:Unload(f.g))
    assert(f.r:CountPrefab("carrot_seeds")+b.r:CountPrefab("carrot_seeds")==1)
    assert(S.Count(f.wc:GetItemInSlot(1))==1)
end)

test("another worker's claimed input is not treated as spare stock",function()
    local f,b=fixture(),fixture();b.robot.GUID=77;f.g.members={f.robot,b.robot}
    install(f,{plant("b-owned"),plant("unclaimed")});f.c:Place(item("carrot_seeds",1),1);b.c:Place(item("carrot_seeds",1),1)
    assert(f.q:Claim(b.robot).id=="b-owned")
    assert(f.r:Unload(f.g)and b.r:Unload(f.g))
    assert(f.r:CountPrefab("carrot_seeds")==1 and b.r:CountPrefab("carrot_seeds")==1)
end)

test("empty worker cannot strand a task supplied by its teammate",function()
    local f,b=fixture(),fixture();b.robot.GUID=77;f.g.members={f.robot,b.robot}
    install(f,{plant("team-supplied")});b.c:Place(item("carrot_seeds",1),1)
    assert(f.q:Claim(f.robot)==nil,"empty worker claimed and will block a supplied teammate's planting")
    assert(f.q:Claim(b.robot).id=="team-supplied")
end)

test("resource recovery retires detached blocked fetch children",function()
    local f=fixture();install(f,{plant("parent")});local parent=f.q:Claim(f.robot)
    local child=f.q:PushSubtask(f.robot,parent,{kind="FETCH",data={requirements=f.r:Demand(f.g,parent)}})
    f.q:Claim(f.robot);f.q:Fail(child.id,f.robot,"resources_unavailable",true)
    assert(parent.state=="blocked"and not parent.suspended_by)
    f.q:Unblock("resources")
    assert(child.state=="cancelled"and f.q:Claim(f.robot).id==parent.id,"detached fetch reran ahead of resumed parent")
end)

test("obsolete child failure does not block a resumed parent",function()
    local f=fixture();install(f,{plant("parent")});local parent=f.q:Claim(f.robot)
    local child=f.q:PushSubtask(f.robot,parent,{kind="FETCH",data={}})
    parent.suspended_by=nil;parent.state="pending"
    f.q:Fail(child.id,f.robot,"resources_unavailable",true)
    assert(parent.state~="blocked","stale child blocked a parent it no longer owns")
end)

test("optional stock progress is not enough when current seed is still missing",function()
    local f=fixture();local parent=plant("current");install(f,{parent,plant("future","corn_seeds")})
    f.wc:Place(item("corn_seeds",1),1)
    local ok,reason=f.r:Fetch(f.g,f.r:Demand(f.g,parent))
    assert(not ok and reason and f.r:CountPrefab("carrot_seeds")==0)
    assert(f.r:CountPrefab("corn_seeds")==1,"optional real seed must still be conserved")
end)

test("old saved fetch requirements accept a useful partial batch",function()
    local f=fixture();f.wc:Place(item("carrot_seeds",2),1)
    assert(f.r:Fetch(f.g,{seeds={carrot_seeds=9,corn_seeds=9},fertilizers={}}))
    assert(f.r:CountPrefab("carrot_seeds")==2)
end)

test("mixed warehouse uses the specific seed requested by planting",function()
    local f=fixture();local t=plant("specific")
    install(f,{t});f.wc:Place(item("seeds",4),1);f.wc:Place(item("carrot_seeds",2),2)
    assert(f.r:Fetch(f.g,f.r:Demand(f.g,t)))
    assert(f.r:CountPrefab("carrot_seeds")==1 and f.r:CountPrefab("seeds")==0)
    assert(S.Count(f.wc:GetItemInSlot(1))==4)
end)

test("generic seed plan fetches generic seed without consuming specific stock",function()
    local f=fixture();local t=plant("generic","seeds")
    install(f,{t});f.wc:Place(item("seeds",4),1);f.wc:Place(item("carrot_seeds",2),2)
    assert(f.r:Fetch(f.g,f.r:Demand(f.g,t)))
    assert(f.r:CountPrefab("seeds")==1 and f.r:CountPrefab("carrot_seeds")==0)
    assert(S.Count(f.wc:GetItemInSlot(2))==2)
end)

test("generic stock cannot silently replace a missing specific seed",function()
    local f=fixture();local t=plant("specific")
    install(f,{t});f.wc:Place(item("seeds",4),1)
    local ok,reason=f.r:Prepare(t,f.g)
    assert(not ok and reason=="missing_seed")
    assert(S.Count(f.wc:GetItemInSlot(1))==4 and f.r:CountPrefab("seeds")==0)
end)

if #failures>0 then error(table.concat(failures,"\n"))end
return passed.." warehouse seed supply and retention scenarios"
