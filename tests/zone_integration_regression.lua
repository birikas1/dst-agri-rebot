-- Codex acceptance for the actual world registry, planner, scheduler and leases.
local time=100
GetTime=function()return time end
Class=function(ctor)local c={};c.__index=c;return setmetatable(c,{__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end})end
TheWorld={state={season="autumn"},components={}}
TheSim={FindEntities=function()return {}end}
TUNING={}
package.preload["prefabs/farm_plant_defs"]=function()return {PLANT_DEFS={carrot={seed="carrot_seeds",product="carrot"},corn={seed="corn_seeds",product="corn"}}}end
local Registry=require("components/agrifarmgroup")
local Planner=require("components/agriplanner")
local Scheduler=require("components/agrischeduler")
local U=require("agri/util")
local C=require("agri/constants")
local function entity(id,x,z,user)
    return {GUID=id,userid=user,components={},IsValid=function()return true end,HasTag=function()return false end,
        Transform={GetWorldPosition=function()return x or 2,0,z or 2 end},
        DoTaskInTime=function()end,ListenForEvent=function()end,WatchWorldState=function()end,
        DoPeriodicTask=function()return {Cancel=function()end}end}
end
local function cell(x,z)return {key=x..":"..z,tile_x=x,tile_z=z,x=x*4+2,z=z*4+2,is_farm=true,plants={},soils={},nutrients={100,100,100},moisture={moisture=100,capacity=100,drain=0}}end
local function snapshot(cells,stock)
    local scanned={};for _,c in ipairs(cells)do scanned[c.tile_x..":"..c.tile_z]=true end
    return {now=time,cells=cells,scanned_tiles=scanned,defs={carrot={seed="carrot_seeds"},corn={seed="corn_seeds"},randomseed={seed="seeds",is_randomseed=true}},
        world={season="autumn"},resources={seeds=stock or {carrot_seeds=64,corn_seeds=64},water={cans={}},tools={hoe={count=1,uses=100}},fertilizers={}},
        tuning={min_spacing=1.25,nutrient_capacity=100},hole_cycles={},neighbors={},debris={}}
end
local function fixture(cells,stock)
    local world=entity(100);world.state={season="autumn"};local registry=Registry(world)
    TheWorld.components.agrifarmgroup=registry
    local robot=entity(1);local g=registry:NewGroup(robot)
    g.members={robot};g.primary=robot;g.settings.density="8";g.settings.plan={carrot=1}
    g.scheduler=Scheduler(robot);g.scheduler.group=g
    local planner=Planner(robot);robot.components.agriplanner=planner;robot.components.agrischeduler=g.scheduler
    local s=snapshot(cells or {cell(0,0),cell(2,0)},stock)
    local function plan()
        s.now=time;s.settings=g.settings
        local p=planner:PlanZones(g,s);g.plan=p;g.scheduler:SetPlan(p,g);registry:ApplyZoneHolds(g)
        return p
    end
    plan()
    return {reg=registry,g=g,q=g.scheduler,p=planner,s=s,robot=robot,plan=plan,player=entity(10,2,2,"one")}
end
local function plants(plan,zid)local n=0;for _,t in ipairs(plan.tasks)do if t.kind=="PLANT"and(not zid or t.data.zone_id==zid)then n=n+1 end end;return n end
local errors,passed={},0
local function test(name,fn)local ok,err=pcall(fn);if ok then passed=passed+1 else errors[#errors+1]=name..": "..tostring(err)end end

test("real newly created groups enable zones automatically",function()
    local f=fixture();assert(f.g.zones_enabled and #f.g.zone_order==2 and plants(f.g.plan)==16)
end)
test("read-only badge list never creates edit locks or holds",function()
    local f=fixture();local list=f.reg:ZoneList(f.player)
    assert(#list==2 and next(f.reg.zone_locks)==nil and next(f.g.zone_holds)==nil and not f.g.editing)
end)
test("edit lease freezes only its own zone including P2 children",function()
    local f=fixture();local a,b=f.g.zone_order[1],f.g.zone_order[2]
    assert(f.reg:AcquireZoneLock(f.player,a));local t=f.q:Claim(f.robot)
    assert(t and t.data.zone_id==b,"editing one zone froze another zone")
    local child=f.q:PushSubtask(f.robot,t,{kind="FETCH",data={}})
    assert(child and not f.q:ZoneHeld(child))
    f.reg:ReleaseZoneLock(f.player,a);assert(next(f.g.zone_holds)==nil)
end)
test("another player cannot take a live edit lease",function()
    local f=fixture();local id=f.g.zone_order[1];assert(f.reg:AcquireZoneLock(f.player,id))
    assert(not f.reg:AcquireZoneLock(entity(11,2,2,"two"),id))
end)
test("stale edit revisions and remote players are rejected",function()
    local f=fixture();local id=f.g.zone_order[1];assert(f.reg:AcquireZoneLock(f.player,id))
    local rev=f.reg.zones.records[id].revision
    assert(not f.reg:UpdateZone(f.player,id,rev-1,"save",{mode="exact",density="8",weights={},counts={corn=2}}))
    assert(not f.reg:AcquireZoneLock(entity(12,200,200,"far"),id))
end)
test("one zone's exact edit leaves the neighbouring zone unchanged",function()
    local f=fixture();local a,b=f.g.zone_order[1],f.g.zone_order[2]
    assert(f.reg:AcquireZoneLock(f.player,a));local rev=f.reg.zones.records[a].revision
    assert(f.reg:UpdateZone(f.player,a,rev,"save",{mode="exact",density="8",weights={},counts={corn=2}}))
    f.reg:ReleaseZoneLock(f.player,a);local p=f.plan()
    assert(plants(p,a)==2 and plants(p,b)==8)
end)
test("paused zone does not reserve the last seed needed by another zone",function()
    local f=fixture(nil,{carrot_seeds=1});local a,b=f.g.zone_order[1],f.g.zone_order[2]
    assert(f.reg:AcquireZoneLock(f.player,a));local rev=f.reg.zones.records[a].revision
    assert(f.reg:UpdateZone(f.player,a,rev,"pause"));f.reg:ReleaseZoneLock(f.player,a)
    local p=f.plan();assert(plants(p,b)==1,"paused field consumed the shared seed ledger")
end)
test("another live group cannot steal an owned zone by scanning it",function()
    local f=fixture({cell(0,0)});local id=f.g.zone_order[1]
    local other=entity(2);local g=f.reg:NewGroup(other);g.members={other};g.primary=other
    g.settings.density="8";g.settings.plan={corn=1};g.scheduler=Scheduler(other);g.scheduler.group=g
    local p=Planner(other):PlanZones(g,snapshot({cell(0,0)}))
    assert(f.reg.zones.records[id].group_id==f.g.id and plants(p)==0,"live ownership was overwritten during reconciliation")
end)

local function wire(f)
    local callbacks,replies,records={},{},{};local serial=0
    local json={}
    function json.encode(v)serial=serial+1;local token="j"..serial;records[token]=v;return token end
    function json.decode(v)assert(records[v],"invalid JSON");return records[v]end
    package.loaded.json=json;package.loaded["agri/network"]=nil
    local G={TheWorld=TheWorld,GetTime=GetTime,ActionHandler=function()return {}end,
        GetClientModRPC=function(_,n)return n end,GetModRPC=function(_,n)return n end,
        SendModRPCToClient=function(_,who,encoded)replies[#replies+1]={who=who,data=json.decode(encoded)}end}
    require("agri/network").Register({GLOBAL=G,
        AddModRPCHandler=function(_,n,fn)callbacks[n]=fn end,AddClientModRPCHandler=function()end,
        AddAction=function()return {}end,AddComponentAction=function()end,AddStategraphActionHandler=function()end})
    return function(request,player)callbacks.zone(player or f.player,json.encode(request))end,replies,callbacks
end
test("zone RPC list polling is readonly and rate limited",function()
    local f=fixture();local send,replies=wire(f)
    send({cmd="list"});send({cmd="list"})
    assert(#replies==1 and #replies[1].data.list==2 and next(f.reg.zone_locks)==nil)
    time=time+C.ZONE_LIST_INTERVAL;send({cmd="list"});assert(#replies==2)
end)
test("zone RPC open/save/close uses current revision and its own lock",function()
    local f=fixture();local id=f.g.zone_order[1];local send,replies=wire(f)
    send({cmd="open",zone=id});assert(replies[1].data.open and f.reg:HasZoneLock(f.player,id))
    send({cmd="save",zone=id,rev=f.reg.zones.records[id].revision,settings={mode="exact",density="8",counts={corn=2},weights={}}})
    assert(replies[2].data.saved and f.reg.zones.records[id].settings.counts.corn==2)
    send({cmd="close",zone=id});assert(not f.reg:HasZoneLock(f.player,id) and not f.g.zone_holds[id])
end)

test("zone RPC rejects malformed, stale and distant writes",function()
    local f=fixture();local id=f.g.zone_order[1];local send,replies=wire(f)
    send({cmd="save",zone=id,rev=1,settings={mode="ratio",density="8",weights={corn=1}}})
    assert(not f.reg.zones.records[id].configured)
    send({cmd="open",zone=id});local rev=f.reg.zones.records[id].revision
    send({cmd="save",zone=id,rev=rev+1,settings={mode="ratio",density="8",weights={corn=1}}})
    assert(replies[#replies].data.stale and not f.reg.zones.records[id].configured)
    send({cmd="save",zone=id,rev=rev,settings={mode="ratio",density="8",weights={unknown=1}}})
    assert(not f.reg.zones.records[id].configured)
    send({cmd="open",zone=id},entity(15,200,200,"remote"))
    assert(f.reg.zone_locks[id].userid==f.player.userid)
    local n=#replies;send({cmd="list",injected=true});assert(#replies==n)
end)
test("foreign close and second editor cannot release another player's lease",function()
    local f=fixture();local id=f.g.zone_order[1];local send=wire(f)
    send({cmd="open",zone=id});local other=entity(15,2,2,"other")
    send({cmd="close",zone=id},other);send({cmd="open",zone=id},other)
    assert(f.reg.zone_locks[id].userid==f.player.userid)
end)
test("disconnect releases zone holds and editing only its own zones",function()
    local f=fixture();local a,b=f.g.zone_order[1],f.g.zone_order[2]
    assert(f.reg:AcquireZoneLock(f.player,a));local other=entity(15,2,2,"other")
    assert(f.reg:AcquireZoneLock(other,b));f.reg:ReleasePlayer(f.player)
    assert(f.reg.zone_locks[a]==nil and f.reg.zone_locks[b]and not f.g.zone_holds[a]and f.g.zone_holds[b])
end)

test("badge totals include crops beyond the abbreviated icon list",function()
    local f=fixture();local id=f.g.zone_order[1];local view=f.g.zone_view[id]
    view.targets={};view.have={};view.planted=50;view.usable=32
    for i=1,8 do view.targets["crop"..i]=1;view.have["crop"..i]=3 end
    view.have.unrelated=42
    local badge=f.reg:ZoneBadge(id,view)
    assert(#badge.tg==6 and badge.tt==8 and badge.td==8 and badge.use==32)
end)
test("one eight-hole tile rejects both oversized active modes atomically",function()
    for _,mode in ipairs({"ratio","exact"})do
        local f=fixture({cell(0,0)});local id=f.g.zone_order[1]
        assert(f.reg:AcquireZoneLock(f.player,id));local r=f.reg.zones.records[id];local rev=r.revision
        local s={mode=mode,density="8",weights={},counts={}}
        s[mode=="ratio"and"weights"or"counts"]={carrot=8,corn=1}
        assert(not f.reg:UpdateZone(f.player,id,rev,"save",s),mode.." accepted nine selections for eight holes")
        assert(r.revision==rev and not r.configured,"rejected write mutated plan/revision")
        s[mode=="ratio"and"weights"or"counts"]={carrot=7,corn=1}
        assert(f.reg:UpdateZone(f.player,id,rev,"save",s),mode.." rejected exactly eight")
    end
end)

test("four connected eight-hole tiles accept32 and reject33 including generic seeds",function()
    for _,mode in ipairs({"ratio","exact"})do
        local f=fixture({cell(0,0),cell(1,0),cell(0,1),cell(1,1)});local id=f.g.zone_order[1]
        assert(f.reg:AcquireZoneLock(f.player,id));local r=f.reg.zones.records[id]
        local s={mode=mode,density="8",weights={},counts={}}
        s[mode=="ratio"and"weights"or"counts"]={carrot=16,corn=16,randomseed=1}
        assert(not f.reg:UpdateZone(f.player,id,r.revision,"save",s),"33 exceeded32 but saved")
        s[mode=="ratio"and"weights"or"counts"].randomseed=nil
        assert(f.reg:UpdateZone(f.player,id,r.revision,"save",s),"exact nominal32 rejected")
    end
end)

test("server cap follows submitted density and authoritative tiles not stale usable view",function()
    local f=fixture({cell(0,0)});local id=f.g.zone_order[1];local r=f.reg.zones.records[id]
    assert(f.reg:AcquireZoneLock(f.player,id))
    f.g.zone_view[id].tiles=20;f.g.zone_view[id].usable=160
    assert(not f.reg:UpdateZone(f.player,id,r.revision,"save",{mode="exact",density="6",weights={},counts={corn=7}}),"trusted stale client/planner capacity")
    f.g.zone_view[id].usable=0
    assert(f.reg:UpdateZone(f.player,id,r.revision,"save",{mode="exact",density="8",weights={},counts={corn=8}}),"temporary blocked holes reduced nominal cap")
end)

test("oversized default template cannot bypass zone save capacity",function()
    local f=fixture({cell(0,0)});local id=f.g.zone_order[1];local r=f.reg.zones.records[id]
    assert(f.reg:AcquireZoneLock(f.player,id))
    f.g.settings.plan={carrot=28,corn=3}
    local ok=f.reg:UpdateZone(f.player,id,r.revision,"template")
    if ok then
        local d=f.reg:ZoneDetail(id,f.g);local active=d.settings.mode=="exact"and d.settings.counts or d.settings.weights
        local n=0;for _,v in pairs(active or {})do n=n+v end
        assert(n<=8,"template command bypassed eight-hole input cap")
    end
end)

if #errors>0 then error(table.concat(errors,"\n"))end
return passed.." zone integration and lease scenarios"
