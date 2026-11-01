-- Codex: fixed-origin lifecycle and client-local preview/hover contracts.
Class=function(ctor)local c={};c.__index=c;return setmetatable(c,{__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end})end
GetTime=function()return 100 end
local U=require("agri/util")
local C=require("agri/constants")
local function net(value)return {value=function(self)return self.v end,set=function(self,v)self.v=v end,v=value}end
local function entity(x,z)
    local e={valid=true,x=x or 0,z=z or 0,components={},events={},tasks={},tags={}}
    e.Transform={GetWorldPosition=function()return e.x,0,e.z end,SetPosition=function(_,a,b,c)e.x,e.z=a,c end,
        SetScale=function(_,a,b,c)e.scale={a,b,c}end}
    e.AnimState=setmetatable({SetLightOverride=function(_,v)e.light_override=v end},{__index=function()return function()end end})
    function e:IsValid()return self.valid end
    function e:Remove()self.valid=false;if self.events.onremove then self.events.onremove(self)end end
    function e:AddTag(tag)self.tags[tag]=true end
    function e:HasTag(tag)return self.tags[tag]==true end
    function e:ListenForEvent(name,fn)self.events[name]=fn end
    function e:DoPeriodicTask(_,fn)self.tasks[#self.tasks+1]=fn;return {Cancel=function()end}end
    function e:DoTaskInTime()end
    function e:WatchWorldState()end
    return e
end
local markers,outlines={},{}
SpawnPrefab=function(name)
    local e=entity();e.prefab=name
    if name=="agriworkcenter"then
        e._agri_radius=net(16);e._agri_order=net(1);e._agri_group=net("");markers[#markers+1]=e
    else outlines[#outlines+1]=e end
    return e
end
TheWorld={state={},components={}}
TheSim={FindEntities=function()local out={};for _,e in ipairs(markers)do if e.valid then out[#out+1]=e end end;return out end}
local Registry=require("components/agrifarmgroup")
local Range=require("agri/work_range")
local errors,passed={},0
local function test(name,fn)local ok,err=pcall(fn);if ok then passed=passed+1 else errors[#errors+1]=name..": "..tostring(err)end end
test("registration fixes origin before movement and primary takeover",function()
    markers={};local reg=Registry(entity());local a=entity(5,9);a.GUID=1
    local g=reg:Register(a);assert(g.center.x==5 and g.center.z==9 and #markers==1)
    a.x,a.z=20,20;reg:SelectPrimary(g)
    assert(g.center.x==5 and markers[1].x==5 and #markers==1)
    local b=entity(8,9);b.GUID=2;assert(reg:Register(b)==g)
    reg:Unregister(a);assert(g.primary==b and g.center.x==5 and #markers==1 and markers[1].valid)
    reg:UpdateSettings(g,{radius=24});assert(markers[1]._agri_radius:value()==24)
    reg:Unregister(b);assert(not markers[1].valid and reg.groups[g.id]==nil)
end)
test("world save/load preserves original center and creates exactly one derived marker",function()
    markers={};local reg=Registry(entity());local a=entity(5,9);a.GUID=1
    local g=reg:Register(a);a.x,a.z=20,20;local saved=reg:OnSave()
    reg:Unregister(a);markers={};local loaded=Registry(entity());loaded:OnLoad(saved)
    loaded:LoadPostPass({[1]={entity=a}})
    local restored=loaded.groups[g.id]
    assert(restored.center.x==5 and restored.center.z==9 and #markers==1)
    loaded:SelectPrimary(restored);loaded:Register(a);assert(#markers==1 and markers[1].x==5)
end)
test("native circle uses calibrated radius and reuses one local entity",function()
    outlines={};local marks=Range.Show(nil,10,-5,16);assert(#marks==1)
    assert(marks[1].x==10 and marks[1].z==-5 and marks[1].scale[1]==4 and marks[1].prefab=="reticuleaoe" and marks[1].persists==false)
    assert(marks[1].light_override==1,"range circle depends on ambient night light")
    assert(Range.Show(marks,10,-5,16)==marks and #outlines==1)
    Range.Show(marks,20,-5,24);assert(#outlines==1)
    assert(marks[1].x==20 and marks[1].scale[1]==6)
    marks[1]:Remove();Range.Show(marks,20,-5,24)
    assert(#outlines==2 and marks[1].valid and marks[1].x==20 and marks[1].scale[1]==6)
    Range.Clear(marks);for _,e in ipairs(marks)do assert(not e.valid)end
end)
test("placer follows cursor, joins oldest fixed center and clears on cancel",function()
    markers={};local placer=entity(100,100);placer.components.placer={}
    Range.SetupPlacer(placer);placer.components.placer.onupdatetransform()
    assert(placer._agri_range.x==100 and placer._agri_range.radius==16)
    placer.x=110;placer.components.placer.onupdatetransform();assert(placer._agri_range.x==110)
    local m=SpawnPrefab("agriworkcenter");m.x,m.z=108,100;m._agri_radius:set(24)
    placer.components.placer.onupdatetransform();assert(placer._agri_range.x==108 and placer._agri_range.radius==24)
    placer.components.placer.mouse_blocked=true;placer.components.placer.onupdatetransform()
    local n=#outlines;placer.components.placer.onupdatetransform()
    assert(placer._agri_range==nil and #outlines==n,"HUD-blocked preview kept allocating graphics")
    placer.components.placer.mouse_blocked=false;placer.components.placer.onupdatetransform()
    local marks=placer._agri_range;placer:Remove();for _,e in ipairs(marks)do assert(not e.valid)end
end)
test("marker hover and radius changes are client safe and cleanup on removal",function()
    local saveSpawn=SpawnPrefab
    CreateEntity=function()
        local e=entity();e.GUID=100
        e.entity=setmetatable({},{__index=function()return function()end end})
        function e:AddComponent(name)
            self.components[name]={}
            if name=="updatelooper"then self.components[name].AddOnWallUpdateFn=function(_,fn)self.wallupdate=fn end end
        end
        return e
    end
    Asset=function()end;Prefab=function(_,fn)return fn end
    net_smallbyte=function()return net(0)end;net_uint=net_smallbyte;net_string=function()return net("")end
    TheWorld.ismastersim=false;TheNet={IsDedicated=function()return false end}
    local hover;ThePlayer={};TheInput={GetHUDEntityUnderMouse=function()end,GetWorldEntityUnderMouse=function()return hover end}
    local fn=assert(loadfile("agri_robot/scripts/prefabs/agriworkcenter.lua"))();local e=fn();e._agri_radius:set(16)
    assert(e.persists==false and e.components.inspectable==nil)
    assert(#e.tasks==0 and e.wallupdate,"hover depends on paused simulation tasks")
    e.wallupdate();assert(e._agri_range==nil)
    hover=e;e.wallupdate();assert(e._agri_range.radius==16)
    TheInput.GetHUDEntityUnderMouse=function()return {}end
    e.wallupdate();assert(e._agri_range,"transparent HUD overlay suppressed real world target")
    e._agri_radius:set(24);e.wallupdate();assert(e._agri_range.radius==24)
    local marks=e._agri_range;hover=nil;e.wallupdate();assert(e._agri_range==nil and not marks[1].valid)
    e.components.highlight={highlit=true};e.wallupdate();assert(e._agri_range,"native highlight did not show circle")
    e.components.highlight=nil;hover=e;e.wallupdate();marks=e._agri_range;e:Remove();assert(not marks[1].valid)
    TheWorld.ismastersim=true;TheNet.IsDedicated=function()return true end
    local server=fn();assert(#server.tasks==0 and not server.wallupdate and server.components.inspectable and server._agri_radius:value()==16)
    SpawnPrefab=saveSpawn
end)
if #errors>0 then error(table.concat(errors,"\n"))end
return passed.." fixed origin, persistence, client range and dedicated-server scenarios"
