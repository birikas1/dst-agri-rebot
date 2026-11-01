-- Codex: appended equipment slots and real warehouse tool acquisition.
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

local failures,passed={},0
local function test(name,fn)local ok,err=pcall(fn);if ok then passed=passed+1 else failures[#failures+1]=name..": "..tostring(err)end end
local seq=100
local function equipment(prefab,action,left)
    local e=item(prefab);seq=seq+1;e.GUID=seq
    e.components.finiteuses={total=100,GetUses=function()return left or 100 end}
    function e:HasTag(tag)return prefab=="wateringcan" and tag=="wateringcan"end
    if action=="TILL"then e.components.farmtiller={}
    elseif action then e.components.tool={CanDoAction=function(_,a)return a==ACTIONS[action]end}end
    if prefab=="wateringcan"then e.components.fillable={};e.components.wateryprotection={addwetness=25}end
    return e
end
ACTIONS={DIG={},HAMMER={},CHOP={},MINE={}}
local function task(k,data)return {id="test:"..k,kind=k,priority=3,point={x=0,z=0},data=data or {}}end
test("all six categories have three dedicated slots after unchanged49 legacy slots",function()
    local f=fixture()
    for i,prefab in ipairs({"farm_hoe","shovel","hammer","axe","pickaxe","wateringcan"})do
        local e=equipment(prefab,i==1 and"TILL"or nil)
        local lo,hi=S.WarehouseEquipmentRange(e);assert(lo==50+(i-1)*3 and hi==lo+2)
        for n=lo,hi do assert(S.WarehouseTest(f.wc,e,n))end
        assert(not S.WarehouseTest(f.wc,e,49)and not S.WarehouseTest(f.wc,e,25))
        assert(not S.WarehouseTest(f.wc,e,lo==50 and 53 or 50))
    end
    assert(S.WarehouseTest(f.wc,item("bluegem"),49))
    TheWorld.ismastersim=false
    assert(S.ToolSlot(equipment("golden_farm_hoe"))==26)
    assert(S.WarehouseTest(f.wc,equipment("golden_farm_hoe"),52))
    TheWorld.ismastersim=true
end)
test("warehouse-only hoe can be claimed and fetch walks instead of teleporting",function()
    local f=fixture();local hoe=equipment("farm_hoe","TILL");f.wc:Place(hoe,50);f.robot.distance=100
    local t=task("TILL");assert(f.q:CanClaim(f.robot,t))
    local ok,why=f.r:Prepare(t,f.g);assert(not ok and why=="need_fetch")
    assert(f.wc:GetItemInSlot(50)==hoe and f.c:GetItemInSlot(26)==nil)
    local req=f.r:Demand(f.g,t);assert(req.equipment_task.kind=="TILL")
    assert(not f.r:Fetch(f.g,req))
    f.robot.distance=4;assert(f.r:Fetch(f.g,req))
    assert(f.c:GetItemInSlot(26)==hoe and f.wc:GetItemInSlot(50)==nil)
    local ready,_,borrowed=f.r:Prepare(t,f.g);assert(ready and borrowed==hoe)
    assert(f.r:Finish(t,true)and f.c:GetItemInSlot(26)==hoe)
end)
test("all five tool actions fetch into robot's matching dedicated slot",function()
    for i,case in ipairs({{"farm_hoe","TILL"},{"shovel","DIG"},{"hammer","HAMMER"},{"axe","CHOP"},{"pickaxe","MINE"}})do
        local f=fixture();local tool=equipment(case[1],case[2]);f.wc:Place(tool,50+(i-1)*3)
        local t=task(i==1 and"TILL"or"CLEAR",{tool_action=case[2]})
        -- CanClaim's standard CLEAR policy is DIG; use the resource's exact
        -- requested action here to verify all supported equipment types.
        assert(f.r:Fetch(f.g,f.r:Demand(f.g,t)))
        assert(f.c:GetItemInSlot(25+i)==tool)
    end
end)
test("full work cargo does not prevent fetching into an empty tool slot",function()
    local f=fixture();for i=1,18 do f.c:Place(item("carrot"),i)end
    local hoe=equipment("farm_hoe","TILL");f.wc:Place(hoe,51)
    assert(f.r:Fetch(f.g,f.r:Demand(f.g,task("TILL"))))
    assert(f.c:GetItemInSlot(26)==hoe and #S.Items(f.c)==19)
end)
test("full matching tool slot never drops or replaces either real tool",function()
    local f=fixture();local a=equipment("farm_hoe","TILL");local b=equipment("farm_hoe","TILL")
    f.c:Place(a,26);f.wc:Place(b,50)
    local req=f.r:Demand(f.g,task("TILL",{item_guid=b.GUID}))
    local ok,why=f.r:Fetch(f.g,req)
    assert(not ok and why=="equipment_slot_full" and f.c:GetItemInSlot(26)==a and f.wc:GetItemInSlot(50)==b)
end)
test("warehouse full can is fetched and borrowed for a water action",function()
    local f=fixture();local empty=equipment("wateringcan",nil,0);local full=equipment("wateringcan",nil,50)
    f.wc:Place(empty,65);f.wc:Place(full,66)
    local t=task("WATER");assert(f.q:CanClaim(f.robot,t))
    local ok,_,borrowed=f.r:Prepare(t,f.g)
    assert(ok and borrowed==full and f.wc:GetItemInSlot(65)==empty and f.wc:GetItemInSlot(66)==nil)
    f.r:Finish(t,true);assert(f.c:GetItemInSlot(19)==full)
end)
test("warehouse empty can is fetched then requests refill without refetch loop",function()
    local f=fixture();local can=equipment("wateringcan",nil,0);f.wc:Place(can,67)
    local t=task("WATER");local ok,why=f.r:Prepare(t,f.g)
    assert(not ok and why=="out_of_water"and f.c:GetItemInSlot(19)==can)
    ok,why=f.r:Prepare(t,f.g);assert(not ok and why=="out_of_water")
    assert(f.r:Prepare(task("REFILL"),f.g));f.r:Finish(nil,false)
    assert(f.c:GetItemInSlot(19)==can and #S.Items(f.wc)==0)
end)
test("spent normal tools are skipped and one stored tool cannot be duplicated",function()
    local f=fixture();local dead=equipment("farm_hoe","TILL",0);local live=equipment("farm_hoe","TILL",5)
    f.wc:Place(dead,50);f.wc:Place(live,51);local req=f.r:Demand(f.g,task("TILL"))
    assert(f.r:Fetch(f.g,req)and f.c:GetItemInSlot(26)==live and f.wc:GetItemInSlot(50)==dead)
    local other=fixture();other.g.warehouse=f.w
    assert(not other.r:Fetch(other.g,req)and other.c:GetItemInSlot(26)==nil)
end)
test("equipment transfer rollback preserves the same warehouse item",function()
    local f=fixture();local hoe=equipment("farm_hoe","TILL");f.wc:Place(hoe,50);f.c.reject=true
    assert(not f.r:Fetch(f.g,f.r:Demand(f.g,task("TILL"))))
    assert(f.wc:GetItemInSlot(50)==hoe and hoe.valid and #S.Items(f.c)==0)
end)
test("executor's FETCH child waits for equipment instead of finishing an empty seed batch",function()
    local f=fixture();local hoe=equipment("farm_hoe","TILL");f.wc:Place(hoe,50)
    local req=f.r:Demand(f.g,task("TILL"));local fetch=task("FETCH",{requirements=req})
    local finished;f.e.Finish=function(_,ok)finished=ok end
    assert(f.e:Manual(fetch,f.g)and finished==true and f.c:GetItemInSlot(26)==hoe)
end)
if #failures>0 then error(table.concat(failures,"\n"))end
return passed.." warehouse equipment slot and finite-supply scenarios"
