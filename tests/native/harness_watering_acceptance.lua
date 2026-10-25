-- Exercise automatic planning with native moisture, plants, can and actions.
-- No WATER task is injected by this test.
local G=GLOBAL
local function log(s)print("[AGRI_NATIVE] "..s)end
local function check(ok,s)
    if not ok then G.error("WATERING ASSERTION FAILED: "..s)end
    log("PASS "..s)
end
local function sleep(s)
    local deadline=G.GetTime()+s
    repeat G.coroutine.yield() until G.GetTime()>=deadline
end
local function run(world)
    sleep(3)
    local registry=world.components.agrifarmgroup
    registry._task:Cancel()
    local portal
    for _,e in pairs(G.Ents)do if e.prefab=="multiplayer_portal"then portal=e;break end end
    check(portal~=nil,"automatic watering fixture portal")
    local px,py,pz=portal.Transform:GetWorldPosition()
    local x,y,z=world.Map:GetTileCenterPoint(px+64,py,pz+48)
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
    for dx=-2,2 do for dz=-2,2 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.FARMING_SOIL)end end
    for _,e in ipairs(G.TheSim:FindEntities(x,0,z,11,nil,{"CLASSIFIED","INLIMBO"}))do
        if e~=world and e~=portal and not e:HasTag("player")then e:Remove()end
    end
    local robot=G.SpawnPrefab("agribot")
    robot.Transform:SetPosition(x-3,0,z)
    local can=G.SpawnPrefab("wateringcan")
    can.components.finiteuses:SetUses(can.components.finiteuses.total)
    check(robot.components.container:GiveItem(can,19),"filled watering can accepted in water slot")
    local plant=G.SpawnPrefab("farm_plant_carrot")
    plant.Transform:SetPosition(x,0,z)
    local growable=plant.components.growable
    for i,stage in ipairs(growable.stages)do if stage.name=="sprout"then growable:SetStage(i);break end end
    sleep(1)
    local group=registry:GetGroup(robot)
    group.settings.plan={}
    group.settings.running=true
    local manager=world.components.farming_manager
    manager:AddSoilMoistureAtPoint(x,0,z,-100000)
    check(not manager:IsSoilMoistAtPoint(x,0,z),"native soil initially dry")
    local drinker=plant.components.farmsoildrinker
    check(drinker~=nil,"native growing crop hydration component")
    drinker.time.wet=0
    drinker.time.dry=100000
    drinker.timer_start_time=G.GetTime()
    local planner=robot.components.agriplanner
    local snapshot=planner:Capture(group)
    local nativecell
    for _,c in ipairs(snapshot.cells)do if c.x==x and c.z==z then nativecell=c;break end end
    check(nativecell and #nativecell.plants==1,"adapter captures real growing crop")
    log("WATER_DIAGNOSTIC moisture="..tostring(nativecell.moisture.moisture)..
        " can_uses="..tostring(snapshot.resources.water.uses).." per_use="..tostring(snapshot.resources.water.per_use))
    check(snapshot.resources.water.uses>0,"resource snapshot recognizes filled can")
    local plan=planner:Plan(group)
    local water
    for _,t in ipairs(plan.tasks)do if t.kind=="WATER"then water=t;break end end
    if not water then
        for _,r in ipairs(plan.reasons or {})do log("WATER_REASON "..tostring(r.code))end
    end
    check(water~=nil,"automatic planner waters crop despite unrecoverable hydration history")
    local before=can.components.finiteuses:GetUses()
    group.scheduler:SetPlan(plan,group)
    local deadline=G.GetTime()+30
    while group.scheduler.tasks[water.id].state~="complete"do
        local t=group.scheduler.tasks[water.id]
        if t.state=="failed" or t.state=="blocked" then
            G.error("automatic water task "..t.state..": "..tostring(t.reason))
        end
        if G.GetTime()>deadline then G.error("automatic watering timeout: "..tostring(t.state).." "..tostring(t.reason))end
        G.coroutine.yield()
    end
    check(can.components.finiteuses:GetUses()==before-1,"automatic watering consumes exactly one native use")
    check(manager:IsSoilMoistAtPoint(x,0,z),"automatic watering actually wets native soil")
    local wetplan=planner:Plan(group)
    local extra=0
    for _,t in ipairs(wetplan.tasks)do if t.kind=="WATER"then extra=extra+1 end end
    check(extra==0,"wet-soil rescan avoids redundant water tasks")
    check(can.components.inventoryitem.owner==robot,"watering can returns to robot")
    log("COMPLETE native_automatic_watering")
end
AddPrefabPostInit("world",function(world)
    if not world.ismastersim then return end
    local co=G.coroutine.create(function()run(world)end)
    local function step()
        local ok,err=G.coroutine.resume(co)
        if not ok then log("FAIL "..tostring(err).."\n"..G.debug.traceback(co))end
        if not ok or G.coroutine.status(co)=="dead"then
            world:DoTaskInTime(1,function()G.TheSim:Quit()end)
        else world:DoTaskInTime(.25,step)end
    end
    world:DoTaskInTime(0,step)
end)
