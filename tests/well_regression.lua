local Pick=require("agri/water_sources").Pick
local function source(id,distance,well,available)
    return {GUID=id,distance=distance,valid=true,components={watersource={available=available~=false}},
        IsValid=function(self)return self.valid end,HasTag=function(_,tag)return well and tag=="agriwell"end}
end
local robot={GetDistanceSqToInst=function(_,s)return s.distance end}
local pond=source(1,1,false);local a=source(2,25,true);local b=source(3,9,true)
assert(Pick({pond,a,b},robot)==b,"a closer pond defeated an available well")
b.components.watersource.available=false
assert(Pick({pond,a,b},robot)==a,"unavailable well selected")
a.valid=false
assert(Pick({pond,a,b},robot)==pond,"failed to fall back to natural source")
pond.components.watersource.available=false
assert(Pick({pond,a,b},robot)==nil,"unavailable sources were usable")
a=source(8,9,true);b=source(2,9,true)
assert(Pick({a,b},robot)==b and Pick({b,a},robot)==b,"source tie depends on search ordering")

Asset=function(kind,path)return {kind=kind,path=path}end
Prefab=function(name,fn,assets)return {name=name,fn=fn,assets=assets}end
MakePlacer=function(name,bank,build,anim)return {name=name,bank=bank,build=build,anim=anim}end
MakeObstaclePhysics=function()end
ACTIONS={HAMMER={}}
local marked={}
local near={center={x=0,z=0},settings={radius=16}}
local far={center={x=100,z=0},settings={radius=8}}
TheWorld={ismastersim=true,components={agrifarmgroup={groups={near,far},MarkDirty=function(_,g,reason)marked[g]=reason end}}}
CreateEntity=function()
    local e={components={},events={},tasks={}}
    e.entity=setmetatable({},{__index=function()return function()end end})
    e.Transform={GetWorldPosition=function()return 8,0,0 end}
    e.AnimState=setmetatable({},{__index=function()return function()end end})
    e.DynamicShadow={SetSize=function()end}
    e.tags={};function e:AddTag(t)self.tags[t]=true end
    function e:AddComponent(name)self.components[name]=setmetatable({available=name=="watersource"},{__index=function()return function()end end})end
    function e:ListenForEvent(name,fn)self.events[name]=fn end
    function e:DoTaskInTime(_,fn)self.tasks[#self.tasks+1]=fn end
    return e
end
local prefab,placer=assert(loadfile("agri_robot/scripts/prefabs/agriwell.lua"))()
local e=prefab.fn()
assert(e.components.watersource.available and e.tags.watersource and e.tags.agriwell)
e.events.onbuilt(e);assert(marked[near]=="resources"and not marked[far],"building a nearby well did not wake blocked resource work")
marked={};e.events.onremove(e);assert(marked[near]=="resources"and not marked[far])
TheWorld.ismastersim=false
local replica=prefab.fn();assert(replica.tags.watersource and replica.components.watersource==nil,"client needs replicated source tag, not a server component")
assert(placer.name=="agriwell_placer"and placer.bank=="agriwell"and placer.build=="agriwell")
return "8 well priority, availability, lifecycle and client/source contracts"
