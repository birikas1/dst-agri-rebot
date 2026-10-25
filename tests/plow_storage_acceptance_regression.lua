-- Independent contracts for collection-only plows and lossless warehousing.
Class=function(ctor)
    local cls={};cls.__index=cls
    return setmetatable(cls,{__call=function(_,...)local o=setmetatable({},cls);ctor(o,...);return o end})
end
TheWorld={ismastersim=true,components={}}
GetTime=function()return 100 end
package.preload["prefabs/farm_plant_defs"]=function()return {PLANT_DEFS={carrot={seed="carrot_seeds",product="carrot"}}}end
local C=require("agri/constants")
local S=require("agri/storage")
local Resource=require("components/agriresource")
local Simple=require("agri/simple_planner")
local function item(prefab)
    return {prefab=prefab,components={},IsValid=function()return true end,HasTag=function()return false end}
end
local function container(size,filter,inventory)
    local slots={}
    local c={numslots=size,maxslots=size,itemtestfn=filter,inst={}}
    if inventory then c.itemslots=slots else c.slots=slots end
    function c:GetItemSlot(e)for i,v in pairs(slots)do if e==v then return i end end end
    function c:GetItemInSlot(i)return slots[i]end
    function c:RemoveItem(e,whole)
        assert(whole)
        local i=self:GetItemSlot(e)
        if i then slots[i]=nil;return e end
    end
    function c:GiveItem(e,i,position,drop)
        assert(drop==false,"internal transfer must not drop")
        if slots[i] or self.itemtestfn and not self.itemtestfn(self,e,i)then return false end
        slots[i]=e;return true
    end
    function c:Place(e,i)slots[i]=e end
    return c
end
local function fixture(slot)
    local robot={GUID=1,components={},IsValid=function()return true end}
    function robot:ListenForEvent()end
    function robot:DoTaskInTime()end
    function robot:GetDistanceSqToInst()return 0 end
    robot.components.container=container(30,S.RobotTest)
    robot.components.container.inst=robot
    robot.components.inventory=container(18,nil,true)
    local resource=Resource(robot)
    robot.components.agriresource=resource
    local dest=container(49,S.WarehouseTest)
    local group={settings={radius=16},members={robot},plan={tasks={}},scheduler={tasks={}},
        warehouse={components={container=dest},IsValid=function()return true end}}
    TheWorld.components.agrifarmgroup={GetGroup=function()return group end,MarkDirty=function()end}
    robot._agri_legacy_load=nil -- The native first-frame load window has ended.
    local plow=item("farm_plow_item")
    robot.components.container:Place(plow,slot or 1)
    return resource,group,plow,robot.components.container,dest
end
local passed,errors=0,{}
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1 else errors[#errors+1]=name..": "..tostring(err)end
end
test("five visible tools without plow; existing indices retained",function()
    assert(#C.TOOL_NAMES==5,"expected five tool labels")
    for _,name in ipairs(C.TOOL_NAMES)do assert(name~="耕地机")end
    assert(S.ToolSlot(item("farm_plow_item"))==nil,"plow is cargo")
    assert(S.ToolSlot(item("farm_hoe"))==26)
    local plow=item("farm_plow_item")
    for i=25,30 do assert(not S.RobotTest({inst={}},plow,i),"plow accepted by a tool slot")end
    assert(S.RobotTest({inst={}},plow,1),"plow needs temporary cargo storage")
end)
test("plow is accepted by output warehouse slots only",function()
    local p=item("farm_plow_item")
    assert(S.Category(p) and not S.IsCrop(p),"distinct non-food cargo category required")
    local lo,hi=S.WarehouseRange(S.Category(p))
    assert(lo==25 and hi==48,"existing cargo range must stay stable")
    assert(S.WarehouseTest({},p,lo) and not S.WarehouseTest({},p,1) and not S.WarehouseTest({},p,49))
end)
test("a single collected plow triggers immediate unload",function()
    local resource=fixture()
    assert(resource:NeedsUnload(),"must not wait for three crops or a full inventory")
end)
test("unload transfers same plow without duplication",function()
    local resource,group,p,src,dest=fixture()
    assert(resource:Unload(group))
    assert(src:GetItemSlot(p)==nil and dest:GetItemSlot(p),"same real item must reach warehouse")
end)
test("legacy slot25 plow can be warehoused",function()
    local resource,group,p,src,dest=fixture(25)
    assert(resource:Unload(group))
    assert(not src:GetItemSlot(p) and dest:GetItemSlot(p),"legacy hidden slot must not strand the plow")
end)
test("legacy slot25 migrates into visible cargo when space exists",function()
    local resource,group,p,src=fixture(25)
    resource:Recover()
    local slot=src:GetItemSlot(p)
    assert(slot and slot>=1 and slot<=18,"legacy plow must become accessible cargo")
end)
test("full robot preserves legacy plow until it can be unloaded",function()
    local resource,group,p,src,dest=fixture(25)
    for i=1,18 do src:Place(item("rocks"),i)end
    local warehouse=group.warehouse
    group.warehouse=nil
    resource:Recover()
    assert(src:GetItemSlot(p)==25,"legacy item must not be discarded when cargo is full")
    group.warehouse=warehouse
    assert(resource:Unload(group))
    assert(dest:GetItemSlot(p) and not src:GetItemSlot(p),"legacy item can unload without a free cargo slot")
end)
test("full warehouse preserves original plow",function()
    local resource,group,p,src,dest=fixture()
    for i=25,48 do dest:Place(item("carrot"),i)end
    local ok,why=resource:Unload(group)
    assert(not ok and why=="warehouse_full","must report full warehouse")
    assert(src:GetItemSlot(p) and not dest:GetItemSlot(p),"item must stay in robot")
end)
test("missing warehouse preserves original plow",function()
    local resource,group,p,src=fixture()
    group.warehouse=nil
    assert(not resource:Unload(group))
    assert(src:GetItemSlot(p),"item must not disappear without warehouse")
end)
test("plow stock and empty land never schedule deployment",function()
    local s={now=100,group_id="test",epoch=0,center={x=2,z=2},world={season="autumn"},cells={},
        defs={carrot={seed="carrot_seeds",prefab="farm_plant_carrot"}},
        resources={seeds={carrot_seeds=8},tools={plow={count=1,uses=4},hoe={count=1,uses=25}}},
        tuning={min_spacing=1.25},debris={},hole_cycles={}}
    local r=Simple.Build(s,{density="8",plan={carrot=8}},{plow_candidates={{key="a",x=2,z=2}}})
    for _,t in ipairs(r.tasks)do assert(t.kind~="PLOW","automatic plowing must be disabled")end
    assert(#r.reasons>0,"manual farmland requirement must be visible")
    for _,reason in ipairs(r.reasons)do assert(reason.code~="NEED_PLOW","must not ask for a plow tool")end
end)
if #errors>0 then error(table.concat(errors,"\n"))end
return passed.." independent collection-only plow scenarios"
