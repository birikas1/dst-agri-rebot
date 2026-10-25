-- Real automatic scan -> PICKUP -> idle UNLOAD -> warehouse ownership.
local G=GLOBAL
local function log(s)print("[AGRI_NATIVE] "..s)end
local function check(ok,s)if not ok then G.error("PLOW STORAGE ASSERTION: "..s)end;log("PASS "..s)end
local function sleep(s)local untiltime=G.GetTime()+s;repeat G.coroutine.yield()until G.GetTime()>=untiltime end
local function run(world)
    sleep(3)
    local registry=world.components.agrifarmgroup
    registry._task:Cancel()
    local portal
    for _,e in pairs(G.Ents)do if e.prefab=="multiplayer_portal"then portal=e;break end end
    check(portal~=nil,"plow recovery fixture portal")
    local px,py,pz=portal.Transform:GetWorldPosition()
    -- Stay clear of saved robots from the grid and watering smoke fixtures.
    local x,y,z=world.Map:GetTileCenterPoint(px+80,py,pz+96)
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
    for dx=-2,2 do for dz=-2,2 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.GRASS)end end
    for _,e in ipairs(G.TheSim:FindEntities(x,0,z,11,nil,{"CLASSIFIED","INLIMBO"}))do
        if e~=world and e~=portal and not e:HasTag("player")then e:Remove()end
    end
    local robot=G.SpawnPrefab("agribot")
    robot.Transform:SetPosition(x,0,z)
    local warehouse=G.SpawnPrefab("agriwarehouse")
    warehouse.Transform:SetPosition(x+4,0,z+4)
    local plow=G.SpawnPrefab("farm_plow_item")
    plow.Transform:SetPosition(x+2,0,z)
    sleep(.5)
    local group=registry:GetGroup(robot)
    group.settings.running=true
    group.settings.radius=12
    group.settings.plan={carrot=8}
    check((group.center.x-(x+2))^2+(group.center.z-z)^2<=12^2,"fixture plow is inside actual group radius")
    registry:SetWarehouse(group,warehouse)
    local planner=robot.components.agriplanner
    local plan=planner:Plan(group)
    local pickup
    for _,t in ipairs(plan.tasks)do
        check(t.kind~="PLOW","no automatic plow deployment on empty ground")
        if t.kind=="PICKUP" and t.target==plow then pickup=t end
    end
    check(pickup~=nil,"automatic scan finds ground plow outside cultivated tiles")
    local original_guid=plow.GUID
    local uses=plow.components.finiteuses:GetUses()
    group.scheduler:SetPlan(plan,group)
    local deadline=G.GetTime()+35
    while plow.components.inventoryitem.owner~=warehouse do
        if G.GetTime()>deadline then G.error("plow was not delivered to warehouse")end
        G.coroutine.yield()
    end
    check(plow.GUID==original_guid and plow:IsValid(),"same native plow reaches warehouse")
    check(plow.components.finiteuses:GetUses()==uses,"collected plow was never deployed")
    local slot=warehouse.components.container:GetItemSlot(plow)
    check(slot and slot>=25 and slot<=48,"plow stored in warehouse cargo range")
    for i=25,30 do check(robot.components.container:GetItemInSlot(i)~=plow,"no plow retained in tool slots")end
    check(world.Map:GetTileAtPoint(x+2,0,z)==G.WORLD_TILES.GRASS,"ground remains uncultivated")
    -- Simulate an old queued deployment from before the feature was disabled.
    warehouse.components.container:RemoveItem(plow,true)
    check(robot.components.container:GiveItem(plow,1),"legacy queued-plow fixture has real cargo plow")
    group.scheduler:Add({id="legacy_queued_plow",kind="PLOW",point={x=x+2,z=z},data={}})
    sleep(4)
    check(plow:IsValid() and plow.components.finiteuses:GetUses()==uses,"old queued task cannot deploy plow")
    check(world.Map:GetTileAtPoint(x+2,0,z)==G.WORLD_TILES.GRASS,"old queued task cannot cultivate ground")
    log("COMPLETE native_collection_only_plow_storage")
end
AddPrefabPostInit("world",function(world)
    if not world.ismastersim then return end
    local co=G.coroutine.create(function()run(world)end)
    local function step()
        local ok,err=G.coroutine.resume(co)
        if not ok then log("FAIL "..tostring(err).."\n"..G.debug.traceback(co))end
        if not ok or G.coroutine.status(co)=="dead"then world:DoTaskInTime(1,function()G.TheSim:Quit()end)
        else world:DoTaskInTime(.25,step)end
    end
    world:DoTaskInTime(0,step)
end)
