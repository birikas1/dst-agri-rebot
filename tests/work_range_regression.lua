-- 0.3.2: craftable work center, robot placement only inside a center,
-- no automatic centers, center overlap rejection, flingomatic-style rings.
Class=function(ctor)local c={};c.__index=c;return setmetatable(c,{__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end})end
GetTime=function()return 100 end
ACTIONS={HAMMER={}}
ANIM_ORIENTATION={OnGround=1};LAYER_BACKGROUND=1
MakeObstaclePhysics=function()end
local U=require("agri/util")
local C=require("agri/constants")
local function net(value)return {value=function(self)return self.v end,set=function(self,v)self.v=v end,v=value}end
local all={}
local function entity(x,z)
    local e={valid=true,x=x or 0,z=z or 0,components={},events={},tasks={},tags={}}
    e.Transform={GetWorldPosition=function()return e.x,0,e.z end,SetPosition=function(_,a,b,c)e.x,e.z=a,c end,
        SetScale=function(_,a,b,c)e.scale={a,b,c}end}
    e.AnimState=setmetatable({SetLightOverride=function(_,v)e.light_override=v end,SetRayTestOnBB=function(_,v)e.ray_bb=v end,
        SetBank=function(_,v)e.bank=v end,PlayAnimation=function(_,v)e.anim=v end,
        SetAddColour=function(_,r,g,b)e.colour={r,g,b}end},
        {__index=function()return function()end end})
    e.entity=setmetatable({SetParent=function(_,p)e.parent=p end},{__index=function()return function()end end})
    function e:IsValid()return self.valid end
    function e:Remove()if not self.valid then return end;self.valid=false;for _,fn in ipairs(self.events.onremove or {})do fn(self)end end
    function e:AddTag(tag)self.tags[tag]=true end
    function e:HasTag(tag)return self.tags[tag]==true end
    function e:ListenForEvent(name,fn)self.events[name]=self.events[name] or {};table.insert(self.events[name],fn)end
    function e:PushEvent(name,data)for _,fn in ipairs(self.events[name] or {})do fn(self,data)end end
    function e:DoPeriodicTask(_,fn)return {Cancel=function()end}end
    function e:DoTaskInTime(_,fn)if fn then self.tasks[#self.tasks+1]=fn end end
    function e:WatchWorldState()end
    function e:AddComponent(name)
        local comp=setmetatable({},{__index=function()return function()end end})
        self.components[name]=comp
        if name=="updatelooper"then comp.AddOnWallUpdateFn=function(_,fn)self.wallupdate=fn end end
        if name=="deployhelper"then
            comp.AddRecipeFilter=function(c,n)local f=rawget(c,"recipefilters") or {};rawset(c,"recipefilters",f);f[n]=true end
        end
        if name=="placer"then comp.linked={};comp.LinkEntity=function(c,v)table.insert(c.linked,v)end end
        return comp
    end
    all[#all+1]=e
    return e
end
CreateEntity=function()return entity()end
local function flush(e)local tasks=e.tasks;e.tasks={};for _,fn in ipairs(tasks)do fn(e)end end
TheWorld={state={},components={},ismastersim=true}
TheNet={IsDedicated=function()return true end}
Asset=function(kind,path)return {kind=kind,path=path}end
local prefabs_made={}
Prefab=function(name,fn,assets,deps)local p={name=name,fn=fn,assets=assets,deps=deps};prefabs_made[name]=p;return p end
MakePlacer=function(name,bank,build,anim,onground,snap,metersnap,scale,fco,facing,postinit)
    local p=Prefab(name,function()
        local e=entity();e:AddComponent("placer");e.bank=bank;e.onground=onground
        if scale then e.Transform:SetScale(scale,scale,scale)end
        if postinit then postinit(e)end
        return e
    end)
    p.bank,p.scale,p.onground=bank,scale,onground
    return p
end
net_smallbyte=function()return net(0)end;net_uint=net_smallbyte;net_string=function()return net("")end
-- Load the real center prefab file once: it returns the prefab AND its placer.
local center_prefab,center_placer=assert(loadfile("agri_robot/scripts/prefabs/agriworkcenter.lua"))()
local function spawn_center(x,z)
    local e=center_prefab.fn();e.prefab="agriworkcenter";e.GUID=#all+1000;e.x,e.z=x,z
    return e
end
SpawnPrefab=function(name)
    if name=="agriworkcenter"then return spawn_center(0,0)end
    local e=entity();e.prefab=name;return e
end
local function dist2(e,x,z)return (e.x-x)^2+(e.z-z)^2 end
TheSim={FindEntities=function(_,x,_,z,r,must)
    local out={}
    for _,e in ipairs(all)do
        local ok=e.valid and dist2(e,x,z)<=r*r
        for _,t in ipairs(must or {})do if not e.tags[t]then ok=false end end
        if ok then out[#out+1]=e end
    end
    return out
end}
local function count_centers()local n=0;for _,e in ipairs(all)do if e.valid and e.tags.agriworkcenter then n=n+1 end end;return n end
local Registry=require("components/agrifarmgroup")
local Range=require("agri/work_range")
local errors,passed={},0
local function test(name,fn)local ok,err=pcall(fn);if ok then passed=passed+1 else errors[#errors+1]=name..": "..tostring(err)end end
local function fresh()
    all={};TheWorld.components={};local reg=Registry(entity());TheWorld.components.agrifarmgroup=reg;return reg
end
local function robot(x,z)local r=entity(x,z);r.GUID=#all;r:AddTag("agribot");r.prefab="agribot";return r end
local function build_center(x,z)local c=spawn_center(x,z);c:PushEvent("onbuilt",{});flush(c);return c end

test("center prefab file returns the prefab and a flingomatic-style placer",function()
    assert(center_prefab and center_prefab.name=="agriworkcenter")
    assert(center_placer and center_placer.name=="agriworkcenter_placer","placer must be returned from the prefab file")
    assert(center_placer.bank=="firefighter_placement" and center_placer.onground==true)
    assert(math.abs(center_placer.scale-Range.RingScale(C.DEFAULT_RADIUS))<1e-9)
    local found=false
    for _,a in ipairs(center_prefab.assets)do if a.path=="anim/firefighter_placement.zip"then found=true end end
    assert(found,"ring anim asset must be loaded by the center prefab")
    local p=center_placer.fn()
    assert(#p.components.placer.linked==1 and p.components.placer.linked[1].bank=="sign_mini","sign art linked to placer")
    local s=p.components.placer.linked[1].scale[1]
    assert(math.abs(s*Range.RingScale(C.DEFAULT_RADIUS)-1)<1e-9,"linked sign keeps normal size")
    assert(p.components.placer.TestCanBuild==nil or rawget(p.components.placer,"TestCanBuild")==nil,"no TestCanBuild override (old bug hid the placer)")
end)
test("recipes: center 1 board + placer + testfn, robot placer + testfn, valid icon",function()
    local recipes={}
    local G={Ingredient=function(t,n)return {type=t,amount=n}end,TECH={SCIENCE_ONE=1,LUNARFORGING_TWO=2},
        STRINGS={NAMES={},RECIPE_DESC={},CHARACTERS={GENERIC={DESCRIBE={}}}}}
    require("agri/recipes").Register({GLOBAL=G,AddRecipe2=function(name,ing,tech,config,filters)recipes[name]={ing=ing,config=config}end})
    local c=recipes.agriworkcenter
    assert(c and #c.ing==1 and c.ing[1].type=="boards" and c.ing[1].amount==1)
    assert(c.config.placer=="agriworkcenter_placer" and c.config.testfn==Range.CenterPlacementTest)
    assert(c.config.image=="minisign_item.tex","vanilla mini sign icon is minisign_item.tex")
    local b=recipes.agribot
    assert(b.config.placer=="agribot_placer" and b.config.testfn==Range.RobotPlacementTest)
    assert(G.STRINGS.NAMES.AGRIWORKCENTER and G.STRINGS.RECIPE_DESC.AGRIWORKCENTER)
end)
test("robot placement refused with no center, allowed inside, refused outside",function()
    fresh()
    assert(Range.RobotPlacementTest({x=0,z=0})==false,"no center: robot must be refused")
    local c=build_center(0,0)
    assert(Range.RobotPlacementTest({x=10,z=0})==true)
    assert(Range.RobotPlacementTest({x=16,z=0})==true,"edge of radius")
    assert(Range.RobotPlacementTest({x=17,z=0})==false)
    c._agri_radius:set(24);assert(Range.RobotPlacementTest({x=20,z=0})==true,"uses replicated radius")
end)
test("center overlap rejection",function()
    fresh()
    assert(Range.CenterPlacementTest({x=0,z=0})==true)
    build_center(0,0)
    assert(Range.CenterPlacementTest({x=20,z=0})==false)
    assert(Range.CenterPlacementTest({x=31.9,z=0})==false)
    assert(Range.CenterPlacementTest({x=32,z=0})==true,"touching rings do not overlap")
end)
test("placing a robot never auto-spawns a center",function()
    local reg=fresh()
    local r=robot(5,5);local before=count_centers()
    assert(reg:Register(r)==nil and reg:GetGroup(r)==nil)
    flush(r);assert(count_centers()==before and before==0,"robot spawned a center")
    for _,g in pairs(reg.groups)do error("robot created a group "..tostring(g.id))end
    reg:Tick();assert(count_centers()==0)
end)
test("multiple robots share one center and bind to it",function()
    local reg=fresh()
    local c=build_center(0,0);local g=reg.groups[c._agri_group_id]
    assert(g and g.workcenter==c and count_centers()==1)
    local a,b,d=robot(3,0),robot(-5,4),robot(0,-12)
    assert(reg:Register(a)==g and reg:Register(b)==g and reg:Register(d)==g and #g.members==3)
    a.x,a.z=40,40;reg:SelectPrimary(g)
    assert(g.center.x==0 and g.center.z==0 and reg:GetGroup(a)==g,"moving robot keeps its center")
    local out=robot(60,0);assert(reg:Register(out)==nil,"robot outside every center stays idle")
    assert(count_centers()==1)
end)
test("robots join the center whose range they are in",function()
    local reg=fresh()
    local c1,c2=build_center(0,0),build_center(40,0)
    local g1,g2=reg.groups[c1._agri_group_id],reg.groups[c2._agri_group_id]
    assert(g1~=g2 and g1 and g2)
    local r=robot(35,0);assert(reg:Register(r)==g2)
    reg:Unregister(r);r.x=4;assert(reg:Register(r)==g1)
end)
test("new center adopts idle robots in range; hammering detaches without respawn",function()
    local reg=fresh()
    local r1,r2=robot(2,0),robot(30,0)
    assert(reg:Register(r1)==nil and reg:Register(r2)==nil)
    local c=build_center(0,0);local g=reg.groups[c._agri_group_id]
    assert(reg:GetGroup(r1)==g and reg:GetGroup(r2)==nil and #g.members==1)
    local gid=g.id;c:Remove()
    assert(reg.groups[gid]==nil and reg:GetGroup(r1)==nil and count_centers()==0,"hammering must not respawn a center")
end)
test("server safety: overlapping center refunded; radius growth cannot overlap",function()
    local reg=fresh()
    local c1=build_center(0,0);local g1=reg.groups[c1._agri_group_id]
    local c2=spawn_center(10,0);local dropped=false
    c2.components.lootdropper={DropLoot=function()dropped=true end}
    c2:PushEvent("onbuilt",{})
    assert(not c2.valid and dropped and count_centers()==1)
    local c3=build_center(36,0);local g3=reg.groups[c3._agri_group_id];assert(g3)
    reg:UpdateSettings(g1,{radius=24});assert(g1.settings.radius==16,"radius 24 would overlap neighbour")
    reg:UpdateSettings(g1,{radius=20});assert(g1.settings.radius==20 and c1._agri_radius:value()==20)
end)
test("save/load: craftable center restored, no duplicate, robots rebind",function()
    local reg=fresh()
    local c=build_center(5,9);local g=reg.groups[c._agri_group_id]
    local r=robot(6,9);assert(reg:Register(r)==g)
    local saved=reg:OnSave()
    local loaded=Registry(entity());TheWorld.components.agrifarmgroup=loaded;loaded:OnLoad(saved)
    -- robot post-pass may run before the world post-pass
    r._agri_group_id=g.id;loaded:Register(r,{group_id=g.id})
    loaded:LoadPostPass({[c.GUID]={entity=c},[r.GUID]={entity=r}})
    local lg=loaded.groups[g.id]
    assert(lg.workcenter==c and loaded:GetGroup(r)==lg and #lg.members==1 and count_centers()==1)
end)
test("legacy save without center entity: robots idle, no center spawned, plans adopted later",function()
    local reg=fresh()
    local data={schema_version=1,next_order=3,next_group=2,groups={{id="farm_1",center={x=0,z=0},
        settings={radius=16,density="8"},members={{guid=7,order=1}}}}}
    reg:OnLoad(data)
    local r=robot(2,0);r.GUID=7;r._agri_group_id="farm_1"
    reg:Register(r,{group_id="farm_1"}) -- robot post-pass before world post-pass
    reg:LoadPostPass({[7]={entity=r}})
    assert(count_centers()==0,"legacy load spawned a center")
    assert(reg:GetGroup(r)==nil and reg.groups.farm_1 and reg.groups.farm_1.dormant)
    flush(r);reg:Register(r,{group_id="farm_1"});assert(reg:GetGroup(r)==nil,"robot joined a centerless group")
    reg:Tick();assert(count_centers()==0)
    assert(Range.CenterPlacementTest({x=0,z=0})==true,"dormant group must not block a new center")
    local c=build_center(1,0)
    assert(c._agri_group_id=="farm_1","new center adopts the dormant group's plans")
    assert(reg.groups.farm_1.settings.density=="8" and reg:GetGroup(r)==reg.groups.farm_1)
end)
test("client: hover and nearby placers show one ring scaled to the radius",function()
    all={};TheNet.IsDedicated=function()return false end;TheWorld.ismastersim=false
    local hover,mouse=nil,{x=100,z=100}
    ThePlayer={};TheInput={GetWorldEntityUnderMouse=function()return hover end,GetHUDEntityUnderMouse=function()end,
        GetWorldPosition=function()return mouse end}
    local e=spawn_center(0,0);e._agri_radius:set(16)
    assert(e.ray_bb==true and e.wallupdate and e.components.deployhelper)
    assert(e.components.deployhelper.recipefilters.agribot and e.components.deployhelper.recipefilters.agriworkcenter)
    e.wallupdate(e);assert(e._agri_ring==nil)
    hover=e;e.wallupdate(e)
    local ring=e._agri_ring
    assert(ring and ring.bank=="firefighter_placement" and ring.persists==false and ring.parent==e.entity)
    assert(ring.tags.NOCLICK and ring.tags.FX and math.abs(ring.scale[1]-Range.RingScale(16))<1e-9)
    e._agri_radius:set(24);e.wallupdate(e);assert(e._agri_ring==ring and math.abs(ring.scale[1]-Range.RingScale(24))<1e-9)
    hover=nil;e.wallupdate(e);assert(e._agri_ring==nil and not ring.valid)
    mouse={x=.5,z=.3};e.wallupdate(e);assert(e._agri_ring,"cursor on the sign footprint counts as hover")
    mouse={x=100,z=100};e.wallupdate(e);assert(e._agri_ring==nil)
    -- deployhelper: robot placer inside this center highlights the ring
    local dh=e.components.deployhelper
    dh.onenablehelper(e,true,"agribot");local placer=entity(5,0)
    dh.onstarthelper(e,"agribot",placer);assert(e._agri_ring and e._agri_ring._agri_active==true)
    placer.x=60;dh.onstarthelper(e,"agribot",placer);assert(e._agri_ring._agri_active==false)
    dh.onenablehelper(e,false);assert(e._agri_ring==nil)
    hover=e;e.wallupdate(e);ring=e._agri_ring;e:Remove();assert(not ring.valid)
    TheNet.IsDedicated=function()return true end;TheWorld.ismastersim=true
    local server=spawn_center(0,0)
    assert(server.wallupdate==nil and server.components.deployhelper==nil and server._agri_radius:value()==16)
    assert(server.components.workable and server.components.lootdropper and server.components.inspectable)
    assert(server.persists==true and server.anim=="idle","no missing 'place' animation")
end)
if #errors>0 then error(table.concat(errors,"\n"))end
return passed.." center placer/recipe, placement rules, no auto-center, overlap, save/load, legacy and client ring scenarios"
