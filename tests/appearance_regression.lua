-- Renderer-side replication callbacks. Native smoke covers engine loading;
-- these assertions do not certify the rendered skin pixels.
Asset=function(kind,path)return {kind=kind,path=path}end
Prefab=function(name,fn,assets)return {name=name,fn=fn,assets=assets}end
MakePlacer=function(name,bank,build,anim,a,b,c,d,e,f,postinit)return {name=name,postinit=postinit}end
MakeObstaclePhysics=function()end
TheWorld={ismastersim=false};TheNet={IsDedicated=function()return false end}
local function entity()
    local e={tasks={},components={},tags={}}
    e.entity=setmetatable({},{__index=function()return function()end end})
    e.AnimState=setmetatable({SetSkin=function(_,skin,base)e.skin,e.base=skin,base end,
        SetBuild=function(_,build)e.build=build;e.skin=nil end},
        {__index=function()return function()end end})
    function e:AddTag(tag)self.tags[tag]=true end
    function e:DoTaskInTime(_,fn)self.tasks[#self.tasks+1]=fn end
    return e
end
CreateEntity=entity
local prefab,placer=assert(loadfile("agri_robot/scripts/prefabs/agriwarehouse.lua"))()
local e=prefab.fn()
assert(e.OnEntityReplicated and #e.tasks==1,"renderer does not reapply appearance after network initialization")
e.AnimState:SetBuild("treasure_chest")
e.OnEntityReplicated(e)
assert(e.skin=="treasurechest_cotl_basic"and e.base=="treasure_chest")
e.AnimState:SetBuild("treasure_chest");e.tasks[1](e)
assert(e.skin=="treasurechest_cotl_basic","loaded/host renderer stays on initial default chest")
local ghost=entity();placer.postinit(ghost)
assert(ghost.skin==e.skin and ghost.base==e.base,"placement ghost and replicated warehouse choose different visual resources")
return "2 renderer replication and matching placement appearance scenarios (skin pixels not certified)"
