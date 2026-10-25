-- Independent native grid acceptance; loaded only into the disposable runtime.
local G=GLOBAL
local Simple=require("agri/simple_planner")
local function log(s) print("[AGRI_NATIVE] "..s) end
local function check(ok,s)
    if not ok then G.error("GRID ASSERTION FAILED: "..s) end
    log("PASS "..s)
end
local function sleep(s)
    local deadline=G.GetTime()+s
    repeat G.coroutine.yield() until G.GetTime()>=deadline
end
local function usable(c)
    local out={}
    for _,e in ipairs(G.TheSim:FindEntities(c.x,0,c.z,3,{"soil"},{"INLIMBO"})) do
        if e.prefab=="farm_soil" and not e:HasTag("NOBLOCK") then out[#out+1]=e end
    end
    return out
end
local function waittasks(scheduler,tasks)
    local deadline=G.GetTime()+70
    local nextlog=G.GetTime()+10
    while true do
        local done=true
        for _,t in ipairs(tasks) do
            local current=scheduler.tasks[t.id]
            if not current or current.state~="complete" then done=false end
            if current and (current.state=="blocked" or current.state=="failed") then
                G.error(t.id.." "..current.state.." "..tostring(current.reason))
            end
        end
        if done then return end
        if G.GetTime()>=nextlog then
            for _,t in ipairs(tasks) do
                local current=scheduler.tasks[t.id]
                if not current or current.state~="complete" then
                    log("GRID_PENDING "..t.id.." state="..tostring(current and current.state)..
                        " reason="..tostring(current and current.reason)..
                        " waiting="..tostring(current and current.waiting_reason))
                end
            end
            nextlog=G.GetTime()+10
        end
        if G.GetTime()>deadline then G.error("grid task timeout") end
        G.coroutine.yield()
    end
end
local function run(world)
    sleep(3)
    local registry=world.components.agrifarmgroup
    registry._task:Cancel()
    local portal
    for _,e in pairs(G.Ents) do if e.prefab=="multiplayer_portal" then portal=e;break end end
    check(portal~=nil,"grid fixture portal exists")
    local px,py,pz=portal.Transform:GetWorldPosition()
    local x,y,z=world.Map:GetTileCenterPoint(px+48,py,pz+48)
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
    for dx=-2,2 do for dz=-2,2 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.FARMING_SOIL) end end
    for _,e in ipairs(G.TheSim:FindEntities(x,0,z,11,nil,{"CLASSIFIED","INLIMBO"})) do
        if e~=world and e~=portal and not e:HasTag("player") then e:Remove() end
    end
    local robot=G.SpawnPrefab("agribot")
    robot.Transform:SetPosition(x-3,0,z)
    local hoe=G.SpawnPrefab("farm_hoe")
    check(robot.components.container:GiveItem(hoe,26),"grid fixture native hoe accepted")
    sleep(.5)
    local group=registry:GetGroup(robot)
    local scheduler=group.scheduler
    local spacing=G.GetFarmTillSpacing()
    log("GRID_NATIVE_SPACING "..tostring(spacing))
    local c={key="grid",x=x,z=z,is_farm=true,plants={},soils={}}
    for _,density in ipairs({8,9,16}) do
        -- Each case gets its own real tool: a native hoe has only 25 uses,
        -- fewer than the 33 holes across all three independent cases.
        if density~=8 then
            if hoe:IsValid() then
                local owner=hoe.components.inventoryitem.owner
                if owner and owner.components.container then owner.components.container:RemoveItem(hoe,true) end
                if owner and owner.components.inventory then owner.components.inventory:RemoveItem(hoe,true) end
                hoe:Remove()
            end
            sleep(.5)
            hoe=G.SpawnPrefab("farm_hoe")
            check(robot.components.container:GiveItem(hoe,26),"grid fixture fresh hoe accepted")
        end
        for _,soil in ipairs(usable(c)) do soil:PushEvent("collapsesoil") end
        sleep(.5)
        -- Test fixture represents intact and broken holes made by native plows.
        local intact=G.SpawnPrefab("farm_soil")
        intact.Transform:SetPosition(x+.7,0,z-.9)
        local broken=G.SpawnPrefab("farm_soil")
        broken.Transform:SetPosition(x-.9,0,z+.6)
        broken:PushEvent("breaksoil")
        c.soils={{id="soil:"..intact.GUID,entity=intact,point={x=x+.7,z=z-.9}}}
        c.broken_soils={{id="soil:"..broken.GUID,entity=broken,point={x=x-.9,z=z+.6}}}
        local before=hoe.components.finiteuses:GetUses()
        local snapshot={group_id=group.id,epoch=density,center={x=x,z=z},world={season="autumn"},
            defs={carrot={seed="carrot_seeds",prefab="farm_plant_carrot"}},cells={c},
            tuning={min_spacing=spacing},resources={seeds={},tools={hoe={count=1,uses=before}}},
            debris={},hole_cycles={},legal_hole=function(p) return world.Map:CanTillSoilAtPoint(p.x,0,p.z,false) end}
        local result=Simple.Build(snapshot,{density=tostring(density),plan={carrot=density}})
        local till,unsoil=0,0
        for _,t in ipairs(result.tasks) do
            if t.kind=="TILL" then
                if t.data.unsoil then unsoil=unsoil+1 else till=till+1 end
            end
            check(t.kind~="PLANT","zero-stock grid does not fabricate planting")
            scheduler:Add(t)
        end
        check(till==density and unsoil==2,"grid "..density.." plans full preparation and both removals")
        waittasks(scheduler,result.tasks)
        check((not intact:IsValid() or not intact:HasTag("soil")) and
            (not broken:IsValid() or not broken:HasTag("soil")),"grid "..density.." removes natural holes")
        local actual=usable(c)
        local expected=Simple.Points(c,density,spacing)
        check(#actual==density,"grid "..density.." native hole count")
        for _,p in ipairs(expected) do
            local found=false
            for _,e in ipairs(actual) do
                local ex,ey,ez=e.Transform:GetWorldPosition()
                if (ex-p.x)^2+(ez-p.z)^2<.0001 then found=true;break end
            end
            check(found,"grid "..density.." exact native hole position")
        end
        check(hoe.components.finiteuses:GetUses()==before-density,"grid "..density.." native durability exact")
    end
    log("COMPLETE native_grid_8_9_16_cleanup_and_preparation")
end
AddPrefabPostInit("world",function(world)
    if not world.ismastersim then return end
    local co=G.coroutine.create(function()run(world)end)
    local function step()
        local ok,err=G.coroutine.resume(co)
        if not ok then log("FAIL "..tostring(err).."\n"..G.debug.traceback(co)) end
        if not ok or G.coroutine.status(co)=="dead" then
            world:DoTaskInTime(1,function()G.TheSim:Quit()end)
        else world:DoTaskInTime(.25,step) end
    end
    world:DoTaskInTime(0,step)
end)
