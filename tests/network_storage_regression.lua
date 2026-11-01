-- Isolated Lua 5.1 contracts. These stubs exercise mod logic, not a running DST server.
local scenarios=0
local function test(name,fn)
    local ok,err=pcall(fn)
    assert(ok,name..": "..tostring(err))
    scenarios=scenarios+1
end
Class=function(base,ctor)
    if ctor==nil then ctor=base;base=nil end
    local cls={_ctor=ctor,_base=base};cls.__index=cls
    return setmetatable(cls,{__index=base,__call=function(_,...) local self=setmetatable({},cls);ctor(self,...);return self end})
end
local time=100
GetTime=function() return time end
TheWorld={ismastersim=true,components={}}
TUNING={BEARGERFUR_SACK_PRESERVER_RATE=0.1,FUMAROLETOOL_TEMPS={0,10,20,50}}
package.preload['prefabs/farm_plant_defs']=function()return {PLANT_DEFS={carrot={seed='carrot_seeds',product='carrot'}}}end
local C=require('agri/constants')
local U=require('agri/util')
local S=require('agri/storage')
local function item(prefab,count,maximum)
    local ent={prefab=prefab,valid=true,components={},tags={}}
    function ent:IsValid()return self.valid end
    function ent:HasTag(tag)return self.tags[tag]==true end
    if count then
        local stack={count=count,maxsize=maximum or 40}
        ent.components.stackable=stack
        function stack:StackSize()return self.count end
        function stack:IsFull()return self.count>=self.maxsize end
        function stack:CanStackWith(other)return other.prefab==prefab end
        function stack:Get(n)self.count=self.count-n;return item(prefab,n,self.maxsize)end
    end
    return ent
end
local function container(size,inventory)
    local c={numslots=size,maxslots=size,inst={},calls=0}
    local slots={}
    if inventory then c.itemslots=slots else c.slots=slots end
    function c:GetItemSlot(ent)for slot,v in pairs(slots)do if v==ent then return slot end end end
    function c:GetItemInSlot(slot)return slots[slot]end
    function c:RemoveItem(ent,whole)
        assert(whole==true,'transfer must remove whole real stack')
        local slot=self:GetItemSlot(ent);if slot then slots[slot]=nil;ent.owner=nil;return ent end
    end
    function c:GiveItem(ent,slot,position,drop)
        self.calls=self.calls+1
        assert(drop==false,'internal transfers must not drop on failure')
        if self.reject or self.itemtestfn and not self.itemtestfn(self,ent,slot) then return false end
        local existing=slots[slot]
        if not existing then slots[slot]=ent;ent.owner=self;return true end
        if not S.CanStack(existing,ent)then return false end
        local to,from=existing.components.stackable,ent.components.stackable
        local n=math.min(to.maxsize-to.count,from.count)
        to.count=to.count+n;from.count=from.count-n
        if from.count==0 then ent.valid=false;return true end
        return false -- Native GiveItem can merge part of a stack before failing.
    end
    function c:Place(ent,slot)slots[slot]=ent;ent.owner=self end
    function c:Total()local n=0;for _,ent in pairs(slots)do n=n+S.Count(ent)end;return n end
    return c
end

test('partial merges continue to other compatible slots',function()
    local src,dst=container(1),container(3)
    local moving=item('carrot_seeds',12,10);src:Place(moving,1)
    dst:Place(item('carrot_seeds',8,10),1);dst:Place(item('carrot_seeds',7,10),2)
    assert(S.Transfer(src,dst,moving,nil,1,3))
    assert(src:Total()==0 and dst:Total()==27 and dst.calls==3)
    assert(dst:GetItemInSlot(3)==moving and S.Count(moving)==7)
end)
test('partial destination preserves real remainder in original source',function()
    local src,dst=container(1),container(1)
    local moving=item('carrot_seeds',6,10);src:Place(moving,1);dst:Place(item('carrot_seeds',8,10),1)
    local ok,why=S.Transfer(src,dst,moving,nil,1,1)
    assert(not ok and why=='destination_full')
    assert(src:GetItemInSlot(1)==moving and src:Total()==4 and dst:Total()==10)
end)
test('split count conserves source and requested amount',function()
    local src,dst=container(1),container(1)
    local moving=item('carrot_seeds',9);src:Place(moving,1)
    assert(S.Transfer(src,dst,moving,3,1,1))
    assert(src:GetItemInSlot(1)==moving and src:Total()==6 and dst:Total()==3)
end)
test('invalid transfer counts do not remove items',function()
    local src,dst=container(1),container(1)
    local moving=item('carrot_seeds',9);src:Place(moving,1)
    for _,n in ipairs({0,-1,math.huge,-math.huge,0/0,'2'})do
        local ok,why=S.Transfer(src,dst,moving,n,1,1)
        assert(not ok and why=='invalid_count')
    end
    assert(src:Total()==9 and dst:Total()==0)
end)
test('blocked rollback returns same detached entity for recovery',function()
    local src,dst=container(1),container(1)
    local moving=item('carrot_seeds',6);src:Place(moving,1)
    src.reject=true;dst.reject=true
    local ok,why,stranded=S.Transfer(src,dst,moving,nil,1,1)
    assert(not ok and why=='rollback_blocked' and stranded==moving and S.Count(stranded)==6)
end)
test('inventory itemslots enumeration and same-container tool move',function()
    local inventory=container(3,true);local a=item('carrot_seeds',2);inventory:Place(a,2)
    assert(#S.Items(inventory)==1 and S.Items(inventory)[1].slot==2)
    local c=container(30);local hoe=item('farm_hoe');c:Place(hoe,1)
    assert(S.Transfer(c,c,hoe,nil,26,26))
    assert(c:GetItemInSlot(1)==nil and c:GetItemInSlot(26)==hoe and c:Total()==1)
end)
test('agricultural slot filters preserve sections and reservations',function()
    local c=container(49)
    assert(S.WarehouseTest(c,item('carrot_seeds'),1))
    assert(not S.WarehouseTest(c,item('carrot'),1))
    assert(S.WarehouseTest(c,item('carrot'),25))
    assert(S.WarehouseTest(c,item('bluegem'),49))
    assert(not S.WarehouseTest(c,item('bluegem'),48))
    c.inst._agri_reserved_slots={[1]=true}
    assert(not S.RobotTest(c,item('carrot'),1))
    c.inst._agri_internal_transfer=true
    assert(S.RobotTest(c,item('carrot'),1))
    assert(S.RobotTest(c,item('farm_hoe'),26))
    assert(not S.RobotTest(c,item('farm_hoe'),27))
end)

local V=require('agri/rpc_validation')
local defs={carrot={seed='carrot_seeds',product='carrot'}}
test('RPC rejects malformed settings and unsafe presets',function()
    assert(not V.Envelope({cmd='delete_world'}))
    assert(not V.Envelope('open'))
    assert(not V.Settings({radius=math.huge},defs))
    assert(not V.Settings({running=1},defs))
    assert(not V.Settings({injected=true},defs))
    assert(not V.Preset('spring',{mode='ratio',ratio={carrot=0/0}},defs))
    assert(not V.Preset('spring',{mode='ratio',ratio={carrot=1.5}},defs))
    assert(not V.Preset('spring',{mode='crop',crop='missing'},defs))
    assert(V.Settings({running=false,density=9},defs).density=='9')
    assert(V.Preset('winter',{mode='crop',crop='carrot'},defs).crop=='carrot')
end)

-- Capture registered callbacks; JSON is a token transport so payload size branches
-- can be forced deterministically without relying on an unavailable game encoder.
local records,serial={},0
local force_size
local json={}
function json.encode(data)
    if force_size=='error' then error('encoder failed') end
    if force_size=='always' or force_size=='large' and
        (data.snapshot and (data.snapshot.plan.clusters or data.snapshot.resources.large) or data.forecast)then
        return string.rep('x',C.SNAPSHOT_MAX_BYTES+1)
    end
    serial=serial+1;local token='json'..serial;records[token]=U.Copy(data);return token
end
function json.decode(token)assert(records[token],'malformed JSON');return records[token]end
package.loaded.json=json
package.loaded['agri/source_adapter']={GetCropDefs=function()return defs end}
local received,handlers={},{}
local robot={GUID=20,prefab='agribot',components={},IsValid=function()return true end,HasTag=function(_,tag)return tag=='agribot'end}
local player={userid='one',components={},IsValid=function()return true end,HUD={}}
local group={id='farm1',revision=3,settings={radius=16},blueprint={cells={{x=2,z=2}}},primary=robot}
local reg={acquired=0,released=0,updates=0,applied=0,groups={}}
function reg:AcquireLock(p,r)self.acquired=self.acquired+1;if self.deny then return false,'busy'end;self.lock=p.userid;return true end
function reg:ReleaseLock(p,r)if self.lock==p.userid then self.lock=nil;self.released=self.released+1 end end
function reg:HasLock(p,r)return self.lock==p.userid end
function reg:GetGroup(r)return group end
function reg:Snapshot(g)return {group_id=g.id,revision=g.revision,blueprint=U.Copy(g.blueprint),settings=U.Copy(g.settings),presets={},plan={clusters={}},tasks={},resources={large=true}}end
function reg:UpdateSettings(g,settings)self.updates=self.updates+1;g.settings=U.Copy(settings);g.revision=g.revision+1 end
function reg:MarkDirty()end
TheWorld.components.agrifarmgroup=reg
TheWorld.components.agriblueprint={Apply=function(_,g,cells)reg.applied=reg.applied+1;g.blueprint.cells=U.Copy(cells);g.revision=g.revision+1;return true end}
local G={TheWorld=TheWorld,ThePlayer=player,TheFrontEnd={PushScreen=function()end},GetTime=GetTime,
    GetClientModRPC=function()return 'snapshot'end,GetModRPC=function()return 'intent'end,Ents={},ActionHandler=function()return {}end}
G.SendModRPCToClient=function(_,_,r,encoded)received[#received+1]={robot=r,data=json.decode(encoded),size=#encoded}end
G.SendModRPCToServer=function()end
local env={GLOBAL=G,AddClientModRPCHandler=function(_,n,fn)handlers["client_"..n]=fn;if n=="snapshot"then handlers.client=fn end end,
    AddModRPCHandler=function(_,n,fn)handlers["server_"..n]=fn;if n=="intent"then handlers.server=fn end end,
    AddAction=function(_,_,fn)handlers.action=fn;return {}end,AddComponentAction=function()end,AddStategraphActionHandler=function()end}
require('agri/network').Register(env)
local function request(value)handlers.server(player,robot,json.encode(value))end
local function reset_network()received={};robot._agri_rpc_times=nil;reg.lock=player.userid;force_size=nil end

test('heartbeat and same-frame setting both succeed',function()
    reset_network();local before=reg.updates
    request({cmd='ping'});request({cmd='settings',data={running=false}})
    assert(reg.updates==before+1 and #received==2)
end)
test('server rate limit bounds bursts and replenishes',function()
    reset_network();local before=reg.updates
    for i=1,6 do request({cmd='settings',data={running=false}})end
    assert(reg.updates==before+5 and received[6].data.error)
    time=time+0.2;request({cmd='settings',data={running=true}})
    assert(reg.updates==before+6)
end)
test('stale blueprint revision cannot mutate farm',function()
    reset_network();local before=reg.applied
    request({cmd='blueprint',revision=group.revision-1,cells={{x=6,z=2}}})
    assert(reg.applied==before and received[#received].data.error)
    request({cmd='blueprint',revision=group.revision,cells={{x=6,z=2}}})
    assert(reg.applied==before+1 and received[#received].data.draft_confirmed==true)
end)
test('unlocked and malformed requests cannot mutate settings',function()
    reset_network();reg.lock='other';local before=reg.updates
    request({cmd='settings',data={running=true}})
    assert(reg.updates==before and received[1].data.locked==false)
    handlers.server(player,robot,'bad json')
    handlers.server(player,robot,string.rep('x',C.RPC_MAX_BYTES+1))
    assert(reg.updates==before)
end)
test('oversized opening snapshots retain usable management state',function()
    reset_network();force_size='large'
    assert(handlers.action({doer=player,target=robot})==true)
    local reply=received[#received]
    assert(reply.data.open and reply.data.snapshot and reply.size<=C.SNAPSHOT_MAX_BYTES)
    assert(reply.data.snapshot.blueprint.cells[1] and reply.data.snapshot.detail_truncated)
    assert(reply.data.snapshot.resources.large==nil)
    force_size=nil
end)
test('unserializable sized snapshot releases acquired lock',function()
    reset_network();force_size='always';local before=reg.released
    assert(handlers.action({doer=player,target=robot})==false)
    assert(reg.lock==nil and reg.released==before+1 and #received==0)
    force_size=nil
end)
test('snapshot encoder failure cannot leave editing lock held',function()
    reset_network();force_size='error';local before=reg.released
    assert(handlers.action({doer=player,target=robot})==false)
    assert(reg.lock==nil and reg.released==before+1 and #received==0)
    force_size=nil
end)
test('same robot open refreshes panel without sending close',function()
    reset_network();local closed,refreshed=0,0
    player.HUD._agri_panel={robot=robot,Close=function()closed=closed+1 end,Receive=function()refreshed=refreshed+1 end}
    handlers.client(robot,json.encode({open=true,snapshot=reg:Snapshot(group)}))
    assert(closed==0 and refreshed==1)
    player.HUD._agri_panel=nil
    handlers.client(robot,json.encode({open=true}))
    assert(player.HUD._agri_panel==nil)
end)

-- Load panel methods without constructing native widgets.
for _,name in ipairs({'screen','widget','text','textbutton','image'})do package.loaded['widgets/'..name]={}end
package.loaded['screens/agribotpanel']=nil
local Panel=require('screens/agribotpanel')
local function panel()
    local p=setmetatable({snapshot={group_id='farm1',revision=1,blueprint={cells={{x=2,z=2}}}},
        draft={{x=2,z=2}},draft_revision=1,draft_dirty=false,page='blueprint',renders=0,
        notice={SetString=function()end}}, {__index=Panel})
    function p:Render()self.renders=self.renders+1 end
    return p
end
test('dirty blueprint preserves original revision across server snapshots',function()
    local p=panel();p.draft={{x=6,z=2}};p.draft_dirty=true
    p:Receive({snapshot={group_id='farm1',revision=2,blueprint={cells={{x=10,z=2}}}}})
    assert(p.draft[1].x==6 and p.draft_revision==1 and p.renders==0)
    p:Receive({draft={{x=6,z=2}},draft_confirmed=true})
    assert(p.draft_revision==2 and p.draft_dirty==false)
end)
test('clean blueprint refreshes both data and displayed grid',function()
    local p=panel()
    p:Receive({snapshot={group_id='farm1',revision=2,blueprint={cells={{x=10,z=2}}}}})
    assert(p.draft[1].x==10 and p.draft_revision==2 and p.renders==1)
    p:Receive({snapshot={group_id='farm1',revision=2,blueprint={cells={{x=10,z=2}}}}})
    assert(p.renders==1,'unchanged heartbeat should not destroy an in-progress mouse drag')
end)
test('range-fill draft remains unconfirmed until apply response',function()
    local p=panel();p:Receive({draft={{x=6,z=2}}})
    assert(p.draft_dirty and p.draft_revision==1)
    p:Receive({snapshot={group_id='farm1',revision=2,blueprint={cells={}}}})
    assert(p.draft[1].x==6 and p.draft_revision==1)
end)

-- Exercise actual thermal component methods with inventory ownership and native
-- sleep-clock callbacks modeled explicitly. No temperature API is substituted.
local Thermal=require('components/agrithermal')
local function thermal_owner()
    local owner={components={container=container(30)},listeners={}}
    function owner:DoPeriodicTask()return {Cancel=function()end}end
    function owner:ListenForEvent(event,fn,target)self.listeners[target or self]=fn end
    function owner:RemoveEventCallback(event,fn,target)self.listeners[target or self]=nil end
    function owner:DoTaskInTime()end
    local thermal=Thermal(owner)
    local tool=item('fumarolehammer');local temp=15
    local native={elapsed=0,sleeps=0}
    function native:UpdateTemperature(dt)self.elapsed=self.elapsed+dt;temp=temp+dt;return true end
    function native:OnEntitySleep()self.sleeps=self.sleeps+1;self._entitysleeptime=time end
    tool.components.inventoryitemtemperature=native
    tool.components.inventoryitem={GetGrandOwner=function()return tool.owner and tool.owner.inst end,
        GetTemperature=function()return temp end,SetTemperature=function(_,v)temp=v end}
    tool.IsInLimbo=function()return true end
    owner.components.container.inst=owner;owner.components.container:Place(tool,28)
    return thermal,owner,tool,native
end
test('thermostat clamps only currently owned tools and releases listeners',function()
    local thermal,owner,tool,native=thermal_owner()
    owner.components.container:Place(item('scale_thermostat_module'),C.MODULE_SLOT)
    thermal:Refresh()
    assert(tool.components.inventoryitem:GetTemperature()==70 and thermal.watched[tool])
    owner.components.container:RemoveItem(tool,true)
    tool.components.inventoryitem:SetTemperature(20);thermal:Clamp(tool);thermal:Refresh()
    assert(tool.components.inventoryitem:GetTemperature()==20 and thermal.watched[tool]==nil)
end)
test('native passive heating runs once per elapsed interval while stored',function()
    local thermal,owner,tool,native=thermal_owner()
    thermal:Refresh();time=time+2;thermal:Refresh();thermal:Refresh()
    assert(native.elapsed==2 and native._entitysleeptime==time)
    native.temperatureupdatetask={};time=time+2;thermal:Refresh()
    assert(native.elapsed==2,'live native updater must not be double-driven')
end)

test('warehouse upgrades preserve contents and restore ordinary behavior',function()
    local Warehouse=require('components/agriwarehouse')
    local c=container(49);c.Open=function()end
    local inst={components={container=c},tags={}}
    function inst:ListenForEvent()end
    function inst:DoPeriodicTask()return {Cancel=function()end}end
    function inst:DoTaskInTime()end
    function inst:AddTag(tag)self.tags[tag]=true end
    function inst:RemoveTag(tag)self.tags[tag]=nil end
    function inst:AddComponent(name)
        self.components[name]={SetPerishRateMultiplier=function(self,mult)self.mult=mult end}
    end
    function inst:RemoveComponent(name)self.components[name]=nil end
    local warehouse=Warehouse(inst)
    local seed=item('carrot_seeds',10);c:Place(seed,1)
    c:Place(item('bluegem'),49);warehouse:Refresh()
    assert(warehouse.mode=='fridge' and inst.tags.fridge)
    local kit=item('super_preserver_kit');c:Place(kit,49);warehouse:Refresh()
    assert(warehouse.mode=='super' and not inst.tags.fridge)
    assert(inst.components.preserver.mult()==TUNING.BEARGERFUR_SACK_PRESERVER_RATE)
    assert(c:GetItemInSlot(1)==seed and S.Count(seed)==10 and c:GetItemInSlot(49)==kit)
    local status=warehouse:GetStatus()
    assert(status.groups.seed.capacity==12 and status.groups.seed.free==11 and status.groups.crop.capacity==24)
    c:RemoveItem(kit,true);warehouse:Refresh()
    assert(warehouse.mode=='ordinary' and not inst.tags.fridge and not inst.components.preserver)
end)

test('container registration synchronizes all network slots',function()
    local layouts={params={},MAXITEMSLOTS=12};package.loaded.containers=layouts
    require('agri/containers').Register({GLOBAL={Vector3=function(x,y,z)return {x=x,y=y,z=z}end}})
    assert(#layouts.params.agribot.widget.slotpos==30)
    assert(#layouts.params.agriwarehouse.widget.slotpos==67 and layouts.MAXITEMSLOTS==67)
    for i,a in ipairs(layouts.params.agriwarehouse.widget.slotpos)do
        assert(math.abs(a.x)+32<=448 and math.abs(a.y)+32<=342,"warehouse slot outside panel")
        for j,b in ipairs(layouts.params.agriwarehouse.widget.slotpos)do
            if i<j then assert(math.abs(a.x-b.x)>=64 or math.abs(a.y-b.y)>=64,"warehouse slots overlap")end
        end
    end
    assert(layouts.params.agriwarehouse.openlimit==1 and layouts.params.agribot.openlimit==1)
end)
test('lunar forging kit remains tied to crafting station',function()
    local recipes={}
    require('agri/recipes').Register({GLOBAL={Ingredient=function(...)return {...}end,
        TECH={SCIENCE_ONE=1,LUNARFORGING_TWO=2},STRINGS={NAMES={},RECIPE_DESC={},CHARACTERS={GENERIC={DESCRIBE={}}}},
        GetInventoryItemAtlas=function()return 'atlas'end},AddRecipe2=function(name,ingredients,tech,config)recipes[name]=config end})
    assert(recipes.super_preserver_kit.nounlock==true and recipes.super_preserver_kit.station_tag=='lunar_forge')
end)
return tostring(scenarios)..' scenarios: transfers, slot filters, RPC locks/limits, payload fallback, blueprint revisions, thermal ownership, container slots and recipes'

