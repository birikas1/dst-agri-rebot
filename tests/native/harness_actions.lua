-- This test injects deterministic tasks while using the real native engine,
-- scheduler, executor, brain and stategraph. Harvest maturity is a test fixture.
local G = GLOBAL
local function log(s) print("[AGRI_NATIVE] "..s) end
local function check(value,s)
    if not value then error("NATIVE ASSERTION FAILED: "..s) end
    log("PASS "..s)
end
local function sleep(seconds)
    local deadline=G.GetTime()+seconds
    repeat G.coroutine.yield() until G.GetTime()>=deadline
end
local function count(robot,name)
    local n=0
    for _,component in ipairs({robot.components.container,robot.components.inventory}) do
        for _,item in pairs(component.slots or component.itemslots or {}) do
            if item.prefab==name then n=n+(item.components.stackable and item.components.stackable:StackSize() or 1) end
        end
    end
    return n
end
local function near(point,name)
    for _,entity in ipairs(G.TheSim:FindEntities(point.x,0,point.z,1.5)) do
        if entity.prefab==name then return entity end
    end
end
local function wait_task(scheduler,id,timeout)
    local deadline=G.GetTime()+timeout
    while true do
        local task=scheduler.tasks[id]
        if task and task.state=="complete" then return end
        if not task or task.state=="blocked" or task.state=="failed" or G.GetTime()>deadline then
            error("Task "..id.." state="..tostring(task and task.state).." reason="..tostring(task and task.reason))
        end
        G.coroutine.yield()
    end
end
AddPrefabPostInit("agribot",function(inst)
    if not G.TheWorld.ismastersim then return end
    local save,load=inst.OnSave,inst.OnLoad
    inst.OnSave=function(entity,data,...)
        local result=save and save(entity,data,...)
        data.native_smoke=entity._native_smoke
        return result
    end
    inst.OnLoad=function(entity,data,...)
        if load then load(entity,data,...) end
        entity._native_smoke=data and data.native_smoke
    end
end)
local function run(world)
    sleep(3)
    log("BEGIN engine="..tostring(G.APP_VERSION))
    local registry=world.components.agrifarmgroup
    check(registry~=nil,"world farm group component")
    check(world.components.agriblueprint~=nil,"world blueprint component")
    registry._task:Cancel() -- Controlled task list, no planner rescan.
    for _,entity in pairs(G.Ents) do
        if entity.prefab=="agribot" and entity._native_smoke=="reload" then
            local group=registry:GetGroup(entity)
            check(group and group.primary==entity,"save reload group and primary restored")
            check(group.settings.running==false,"save reload paused setting restored")
            check(group.warehouse and group.warehouse.prefab=="agriwarehouse","save reload warehouse reference restored")
            check(count(entity,"carrot_seeds")==7,"save reload seven seeds preserved")
            check(group.scheduler.tasks.native_persist~=nil,"save reload scheduler task restored")
            check(entity.components.agriexecutor.current==nil,"paused loaded robot executed no task")
            log("COMPLETE save_reload")
            return
        end
    end
    local portal
    for _,entity in pairs(G.Ents) do if entity.prefab=="multiplayer_portal" then portal=entity;break end end
    check(portal~=nil,"native world portal exists")
    local x,y,z=portal.Transform:GetWorldPosition()
    x,y,z=world.Map:GetTileCenterPoint(x+24,y,z)
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
    for dx=-2,2 do for dz=-2,2 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.FARMING_SOIL) end end
    for _,entity in ipairs(G.TheSim:FindEntities(x,0,z,12,nil,{"CLASSIFIED","INLIMBO"})) do
        if entity~=world and entity~=portal and not entity:HasTag("player") then entity:Remove() end
    end
    local point={x=x,z=z}
    check(world.Map:CanTillSoilAtPoint(x,0,z,false),"native test tile can be tilled")
    local robot=G.SpawnPrefab("agribot")
    check(robot~=nil,"spawn agribot")
    robot.Transform:SetPosition(x-8,0,z)
    check(robot.components.agriexecutor~=nil,"robot executor component")
    check(robot.components.container.numslots==30,"robot native 30-slot container initialized")
    check(robot.sg~=nil and robot.brain~=nil,"robot stategraph and brain initialized")
    for _,name in ipairs({"agriwarehouse","super_preserver_kit","scale_thermostat_module"}) do
        local entity=G.SpawnPrefab(name)
        check(entity~=nil,"spawn "..name)
        entity:Remove()
    end
    local hoe=G.SpawnPrefab("farm_hoe")
    local uses=hoe.components.finiteuses:GetUses()
    check(robot.components.container:GiveItem(hoe,26),"real farm hoe accepted in tool slot")
    local seed=G.SpawnPrefab("carrot_seeds")
    seed.components.stackable:SetStackSize(5)
    check(robot.components.container:GiveItem(seed,1),"real five-seed stack accepted")
    local can=G.SpawnPrefab("wateringcan")
    can.components.finiteuses:SetUses(can.components.finiteuses.total)
    local wateruses=can.components.finiteuses:GetUses()
    check(robot.components.container:GiveItem(can,19),"real watering can accepted")
    sleep(0.25)
    local group=registry:GetGroup(robot)
    check(group and group.scheduler,"robot group registered")
    local scheduler=group.scheduler
    scheduler:Add({id="native_till",kind="TILL",point=point})
    wait_task(scheduler,"native_till",35)
    check(near(point,"farm_soil")~=nil,"TILL created native soil")
    check(hoe.components.finiteuses:GetUses()==uses-1,"TILL consumed exactly one native hoe use")
    local rx,ry,rz=robot.Transform:GetWorldPosition()
    check((rx-(x-8))^2+(rz-z)^2>9,"robot physically moved to work target")
    check(hoe.components.inventoryitem.owner==robot,"real tool returned to robot")
    scheduler:Add({id="native_plant",kind="PLANT",point=point,prefab="carrot_seeds"})
    wait_task(scheduler,"native_plant",20)
    local plant=near(point,"farm_plant_carrot")
    check(plant~=nil,"PLANT created native carrot plant")
    check(count(robot,"carrot_seeds")==4,"PLANT consumed exactly one seed from stack")
    plant.components.farmplanttendable:SetTendable(true)
    scheduler:Add({id="native_tend",kind="TEND",target=plant,point=point})
    wait_task(scheduler,"native_tend",20)
    check(not plant:HasTag("tendable_farmplant"),"TEND cleared native tendable flag")
    scheduler:Add({id="native_water",kind="WATER",point=point})
    wait_task(scheduler,"native_water",20)
    check(can.components.finiteuses:GetUses()<wateruses,"WATER consumed native watering can water")
    plant.no_oversized=true
    for i,stage in ipairs(plant.components.growable.stages) do
        if stage.name=="full" then plant.components.growable:SetStage(i);break end
    end
    check(plant.components.pickable:CanBePicked(),"native crop forced mature for harvest fixture")
    scheduler:Add({id="native_harvest",kind="HARVEST",target=plant,point=point})
    wait_task(scheduler,"native_harvest",20)
    check(count(robot,"carrot")>=1,"HARVEST stored real carrot product")
    local second=G.SpawnPrefab("agribot")
    second.Transform:SetPosition(x+2,0,z+2)
    sleep(0.25)
    check(registry:GetGroup(second)==group and #group.members==2,"two robots joined shared farm group")
    scheduler:Add({id="native_persist",kind="TILL",point={x=x+4,z=z},not_before=G.GetTime()+100000})
    robot:Remove()
    check(group.primary==second,"primary removal promoted second robot")
    check(group.scheduler.tasks.native_persist~=nil,"primary removal preserved scheduler task")
    local warehouse=G.SpawnPrefab("agriwarehouse")
    warehouse.Transform:SetPosition(x+5,0,z+5)
    registry:SetWarehouse(group,warehouse)
    group.settings.running=false
    local savedseeds=G.SpawnPrefab("carrot_seeds")
    savedseeds.components.stackable:SetStackSize(7)
    check(second.components.container:GiveItem(savedseeds,1),"save fixture seven seeds stored")
    second._native_smoke="reload"
    log("COMPLETE movement_tools_plant_tend_water_harvest_primary_transfer")
end
AddPrefabPostInit("world",function(world)
    if not world.ismastersim then return end
    local co=G.coroutine.create(function() run(world) end)
    local function step()
        local ok,err=G.coroutine.resume(co)
        if not ok then log("FAIL "..tostring(err).."\n"..G.debug.traceback(co)) end
        if not ok or G.coroutine.status(co)=="dead" then
            world:DoTaskInTime(1,function() G.TheSim:Quit() end)
        else world:DoTaskInTime(0.25,step) end
    end
    world:DoTaskInTime(0,step)
end)
