-- In-range ground tools are collected, equipped, and surplus is warehoused.
Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...)local o=setmetatable({},cls);ctor(o,...);return o end})
end
GetTime=function()return 100 end
TheWorld={ismastersim=true,components={}}
TheSim={FindEntities=function()return {}end}
TUNING={}
ACTIONS={DIG={},HAMMER={},CHOP={},MINE={}}
package.preload["prefabs/farm_plant_defs"]=function()
    return {PLANT_DEFS={carrot={seed="carrot_seeds",product="carrot"},corn={seed="corn_seeds",product="corn"}}}
end
package.preload.bufferedaction=function()return true end

local C=require("agri/constants")
local S=require("agri/storage")
local Adapter=require("agri/source_adapter")
local Resource=require("components/agriresource")

local failures,passed={},0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1 else failures[#failures+1]=name..": "..tostring(err) end
end

local function entity(prefab,opts)
    opts=opts or {}
    local e={prefab=prefab,valid=true,GUID=opts.GUID or prefab,components={},_tags={}}
    function e:IsValid()return self.valid end
    function e:HasTag(tag)return self._tags[tag]==true end
    e.Transform={GetWorldPosition=function()return opts.x or 0,0,opts.z or 0 end}
    e.components.inventoryitem={owner=opts.owner,canbepickedup=opts.canbepickedup}
    if opts.till then e.components.farmtiller={} end
    if opts.action then
        e.components.tool={CanDoAction=function(_,a)return a==ACTIONS[opts.action]end}
    end
    if opts.watering then
        function e:HasTag(tag)return tag=="wateringcan" or self._tags[tag]==true end
        e.components.finiteuses={total=100,GetUses=function()return 50 end}
        e.components.fillable={}
        e.components.wateryprotection={addwetness=25}
    end
    if opts.uses then
        e.components.finiteuses={total=100,GetUses=function()return opts.uses end}
    end
    return e
end

local center,radius={x=0,z=0},16
local function pickup(e,extra)
    local opts={point={x=e.Transform.GetWorldPosition()},center=center,radius=radius,seeds={carrot_seeds=true,seeds=true},products={carrot=true}}
    if extra then for k,v in pairs(extra) do opts[k]=v end end
    if opts.point==nil then opts.point={x=0,z=0} end
    return Adapter.IsGroundPickup(e,opts)
end

test("in-range ground tools and watering cans are collectable",function()
    assert(pickup(entity("farm_hoe",{till=true,x=4,z=0}))=="tool")
    assert(pickup(entity("golden_farm_hoe",{x=0,z=8}))=="tool")
    assert(pickup(entity("shovel",{action="DIG",x=-10,z=0}))=="tool")
    assert(pickup(entity("hammer",{action="HAMMER"}))=="tool")
    assert(pickup(entity("axe",{action="CHOP"}))=="tool")
    assert(pickup(entity("pickaxe",{action="MINE"}))=="tool")
    assert(pickup(entity("wateringcan",{watering=true,x=15,z=0}))=="tool")
end)

test("tools on the ground outside the work radius are not collected",function()
    local far=entity("farm_hoe",{till=true,x=20,z=0})
    assert(pickup(far)==nil)
    -- Even if FindEntities were to return it, the radius check still rejects it.
    assert(Adapter.IsGroundPickup(far,{point={x=20,z=0},center=center,radius=radius})==nil)
    assert(Adapter.IsGroundPickup(entity("shovel",{action="DIG",x=0,z=-16.1}),{point={x=0,z=-16.1},center=center,radius=radius})==nil)
end)

test("held, unpickable, or non-tool clutter is left alone",function()
    assert(pickup(entity("farm_hoe",{till=true,owner={}}))==nil)
    assert(pickup(entity("farm_hoe",{till=true,canbepickedup=false}))==nil)
    local heavy=entity("farm_hoe",{till=true});heavy._tags.heavy=true
    assert(pickup(heavy)==nil)
    assert(pickup(entity("rocks",{x=2,z=2}))==nil)
    assert(pickup(entity("twigs"))==nil)
    assert(pickup(entity("log"))==nil)
    assert(pickup(entity("goldnugget"))==nil)
    -- A seed or plow is still collected; this is existing farm loot, not a new grab.
    assert(pickup(entity("carrot_seeds"))=="loot")
    assert(pickup(entity("farm_plow_item"))=="plow")
    assert(S.IsWorkTool(entity("farm_plow_item"))==false)
end)

test("a tool already on a farm tile is still a tool pickup, not generic loot",function()
    local hoe=entity("farm_hoe",{till=true,x=2,z=2})
    assert(pickup(hoe,{cell={is_farm=true}})=="tool")
end)

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
local seq=100
local function equipment(prefab,action,left)
    local e=item(prefab);seq=seq+1;e.GUID=seq
    e.components.finiteuses={total=100,GetUses=function()return left or 100 end}
    function e:HasTag(tag)return prefab=="wateringcan" and tag=="wateringcan" end
    if action=="TILL" then e.components.farmtiller={}
    elseif action then e.components.tool={CanDoAction=function(_,a)return a==ACTIONS[action]end} end
    if prefab=="wateringcan" then e.components.fillable={};e.components.wateryprotection={addwetness=25} end
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
    local group={id="supply",center={x=0,z=0},settings={running=true,simple=true,radius=16,plan={}},
        members={robot},primary=robot,warehouse=warehouse,plan={tasks={}}}
    TheWorld.components.agrifarmgroup={GetGroup=function()return group end,MarkDirty=function()end}
    return {robot=robot,r=r,w=warehouse,g=group,c=robot.components.container,wc=warehouse.components.container}
end

test("a picked-up hoe is equipped into the dedicated tool slot",function()
    local f=fixture()
    local hoe=equipment("farm_hoe","TILL")
    f.c:Place(hoe,1)
    f.r:OrganizeTools()
    assert(f.c:GetItemInSlot(26)==hoe and f.c:GetItemInSlot(1)==nil)
    assert(not f.r:NeedsUnload())
    local surplus=f.r:SurplusEquipment()
    assert(#surplus==0)
end)

test("a second hoe is surplus and unloads into the warehouse tool slots",function()
    local f=fixture()
    local kept=equipment("farm_hoe","TILL")
    local extra=equipment("farm_hoe","TILL")
    f.c:Place(kept,26)
    f.c:Place(extra,1)
    f.r:OrganizeTools()
    assert(f.c:GetItemInSlot(26)==kept and f.c:GetItemInSlot(1)==extra)
    assert(f.r:NeedsUnload())
    local surplus=f.r:SurplusEquipment()
    assert(#surplus==1 and surplus[1].item==extra)
    local ok,why=f.r:Unload(f.g)
    assert(ok,tostring(why))
    assert(f.c:GetItemInSlot(26)==kept,"the equipped tool must stay with the robot")
    assert(f.c:GetItemInSlot(1)==nil)
    local stored
    for slot=50,52 do if f.wc:GetItemInSlot(slot)==extra then stored=slot end end
    assert(stored,"surplus hoe must occupy a warehouse hoe slot")
    assert(not f.r:NeedsUnload())
end)

test("surplus shovel uses the shovel warehouse range, not the hoe slots",function()
    local f=fixture()
    local kept=equipment("shovel","DIG")
    local extra=equipment("shovel","DIG")
    f.c:Place(kept,27)
    f.c:Place(extra,2)
    assert(f.r:Unload(f.g))
    assert(f.c:GetItemInSlot(27)==kept)
    local stored
    for slot=53,55 do if f.wc:GetItemInSlot(slot)==extra then stored=slot end end
    assert(stored)
    assert(f.wc:GetItemInSlot(50)==nil and f.wc:GetItemInSlot(51)==nil)
end)

test("no warehouse keeps the extra tool on the robot",function()
    local f=fixture()
    local kept=equipment("farm_hoe","TILL")
    local extra=equipment("farm_hoe","TILL")
    f.c:Place(kept,26)
    f.c:Place(extra,1)
    f.g.warehouse=nil
    assert(not f.r:NeedsUnload())
    assert(not f.r:Unload(f.g))
    assert(f.c:GetItemInSlot(26)==kept and f.c:GetItemInSlot(1)==extra)
end)

test("full warehouse tool slots leave the surplus hoe on the robot",function()
    local f=fixture()
    local kept=equipment("farm_hoe","TILL")
    local extra=equipment("farm_hoe","TILL")
    f.c:Place(kept,26)
    f.c:Place(extra,1)
    for i=50,52 do f.wc:Place(equipment("farm_hoe","TILL"),i) end
    assert(not f.r:NeedsUnload())
    local ok,why=f.r:Unload(f.g)
    assert(not ok and why=="warehouse_full")
    assert(f.c:GetItemInSlot(1)==extra and f.c:GetItemInSlot(26)==kept)
end)

test("pickup of a needed hoe is allowed even when work cargo is full",function()
    local f=fixture()
    for i=1,C.WORK_SLOTS do f.c:Place(item("carrot"),i) end
    local hoe=equipment("farm_hoe","TILL")
    assert(f.r:HasOutputSpace({kind="PICKUP",target=hoe,point={x=0,z=0}}))
end)

if #failures>0 then error(table.concat(failures,"\n"))end
return passed.." ground-tool pickup and surplus-warehouse scenarios"
