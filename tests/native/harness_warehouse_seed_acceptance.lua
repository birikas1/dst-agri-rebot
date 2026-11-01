-- Codex native acceptance for automatic warehouse seed supply and retention.
local G=GLOBAL
local S=require("agri/storage")
local function log(s)print("[AGRI_NATIVE] "..s)end
local function check(ok,s)if not ok then G.error("WAREHOUSE SEED ASSERTION: "..s)end;log("PASS "..s)end
local function sleep(s)local untiltime=G.GetTime()+s;repeat G.coroutine.yield()until G.GetTime()>=untiltime end
local function count(inst,prefab)
    local n=0
    for _,c in ipairs({inst.components.container,inst.components.inventory})do
        for _,e in ipairs(S.Items(c))do if e.item.prefab==prefab then n=n+S.Count(e.item)end end
    end
    return n
end
local function run(world)
    sleep(3)
    local registry=world.components.agrifarmgroup
    registry._task:Cancel()
    local portal
    for _,e in pairs(G.Ents)do if e.prefab=="multiplayer_portal"then portal=e;break end end
    check(portal~=nil,"warehouse seed fixture portal")
    local px,py,pz=portal.Transform:GetWorldPosition()
    local x,y,z=world.Map:GetTileCenterPoint(px+112,py,pz+64)
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
    for dx=-5,5 do for dz=-5,5 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.GRASS)end end
    for _,e in ipairs(G.TheSim:FindEntities(x,0,z,27,nil,{"CLASSIFIED","INLIMBO"}))do
        if e~=world and e~=portal and not e:HasTag("player")then e:Remove()end
    end
    world.Map:SetTile(tx,tz,G.WORLD_TILES.FARMING_SOIL)
    world.components.farming_manager:AddSoilMoistureAtPoint(x,0,z,100000)
    world.components.farming_manager:AddTileNutrients(tx,tz,100,100,100)
    local robot=G.SpawnPrefab("agribot");robot.Transform:SetPosition(x-3,0,z)
    local warehouse=G.SpawnPrefab("agriwarehouse");warehouse.Transform:SetPosition(x+9,0,z+3)
    local hoe=G.SpawnPrefab("golden_farm_hoe")
    check(robot.components.container:GiveItem(hoe,26),"warehouse seed native hoe")
    local function stock(prefab,n,slot)
        local e=G.SpawnPrefab(prefab);e.components.stackable:SetStackSize(n)
        check(warehouse.components.container:GiveItem(e,slot),"warehouse accepts "..prefab)
        return e
    end
    stock("carrot_seeds",5,1);stock("corn_seeds",4,2)
    -- Product unloading must not bounce freshly fetched work seeds back.
    for i,prefab in ipairs({"carrot","corn","potato"})do
        check(robot.components.container:GiveItem(G.SpawnPrefab(prefab),i),"warehouse fixture carries "..prefab)
    end
    sleep(.5)
    local group=registry:GetGroup(robot)
    group.settings.running=true;group.settings.radius=16;group.settings.density="9"
    group.settings.plan={carrot=5,corn=4}
    check(count(robot,"carrot_seeds")==0 and count(robot,"corn_seeds")==0,"all working seeds start only in warehouse")
    check(robot:GetDistanceSqToInst(warehouse)>16,"fixture starts outside remote-transfer range")
    -- Let the actual world registry discover the warehouse and plan work.
    local scheduler=group.scheduler
    local seen_fetch,seen_unload,seen_carried=false,false,false
    local original_fetch=robot.components.agriresource.Fetch
    robot.components.agriresource.Fetch=function(self,g,requirements,...)
        check(self:CanUnload(g),"real seed fetch only occurs near warehouse")
        seen_fetch=true
        return original_fetch(self,g,requirements,...)
    end
    local original_unload=robot.components.agriresource.Unload
    robot.components.agriresource.Unload=function(self,g,...)
        seen_unload=true
        return original_unload(self,g,...)
    end
    local function plants()
        local counts={carrot=0,corn=0}
        for _,e in ipairs(G.TheSim:FindEntities(x,0,z,3,{"farm_plant"},{"INLIMBO"}))do
            if e.prefab=="farm_plant_carrot"then counts.carrot=counts.carrot+1 end
            if e.prefab=="farm_plant_corn"then counts.corn=counts.corn+1 end
        end
        return counts
    end
    local deadline=G.GetTime()+95;local nexttick=G.GetTime();local nextlog=G.GetTime()+10
    while true do
        if G.GetTime()>=nexttick then registry:Tick();nexttick=G.GetTime()+2 end
        if count(robot,"carrot_seeds")+count(robot,"corn_seeds")>0 then seen_carried=true end
        local p=plants()
        if p.carrot==5 and p.corn==4 then break end
        if G.GetTime()>=nextlog then
            log("WAREHOUSE_PROGRESS carrot="..p.carrot.." corn="..p.corn.." own="..
                count(robot,"carrot_seeds")..","..count(robot,"corn_seeds").." stored="..
                count(warehouse,"carrot_seeds")..","..count(warehouse,"corn_seeds"))
            for _,id in ipairs(scheduler.order)do local t=scheduler.tasks[id]
                if t.state=="blocked"then log("WAREHOUSE_BLOCKED "..t.kind.." "..tostring(t.reason))end
            end
            nextlog=G.GetTime()+10
        end
        if G.GetTime()>deadline then G.error("warehouse-only planting did not finish")end
        G.coroutine.yield()
    end
    check(group.warehouse==warehouse,"actual registry automatically discovers agricultural warehouse")
    check(seen_fetch and seen_carried,"real seeds were fetched into robot and used")
    check(seen_unload,"native product deposit occurred during working batch")
    check(count(warehouse,"carrot")==1 and count(warehouse,"corn")==1 and count(warehouse,"potato")==1,"actual products reach warehouse")
    check(count(warehouse,"carrot_seeds")==0 and count(warehouse,"corn_seeds")==0,"warehouse seeds consumed exactly for 5 carrot and 4 corn")
    check(count(robot,"carrot_seeds")==0 and count(robot,"corn_seeds")==0,"no phantom or stranded work seeds remain")

    -- Reuse the real scene for stock changing after a batch FETCH is planned.
    -- The current carrot can proceed even though another future seed is taken.
    for _,e in ipairs(G.TheSim:FindEntities(x,0,z,3,{"farm_plant"},{"INLIMBO"}))do e:Remove()end
    robot.Transform:SetPosition(x-3,0,z)
    stock("carrot_seeds",1,1)
    local withdrawn=stock("corn_seeds",1,2)
    group.settings.plan={carrot=1,corn=1};registry:MarkDirty(group,"settings")
    local pushed=scheduler.PushSubtask;local contended=false
    scheduler.PushSubtask=function(self,worker,parent,child)
        if not contended and child.kind=="FETCH"and parent.kind=="PLANT"and parent.prefab=="carrot_seeds"then
            local batch=child.data.requirements or child.data.manifest
            check(batch and (batch.seeds.corn_seeds or 0)>0,"planned batch originally includes future corn")
            warehouse.components.container:RemoveItem(withdrawn,true);withdrawn:Remove()
            contended=true
        end
        return pushed(self,worker,parent,child)
    end
    deadline=G.GetTime()+50;nexttick=G.GetTime()
    while plants().carrot~=1 do
        if G.GetTime()>=nexttick then registry:Tick();nexttick=G.GetTime()+2 end
        if G.GetTime()>deadline then G.error("available current carrot seed stranded by missing future corn")end
        G.coroutine.yield()
    end
    check(contended,"future stock removed after actual batch fetch was planned")
    check(count(robot,"carrot_seeds")==0 and count(warehouse,"carrot_seeds")==0,"available current seed fetched and consumed despite future shortage")
    check(plants().corn==0,"no corn seed is fabricated during shortage")
    stock("corn_seeds",1,2)
    deadline=G.GetTime()+22
    while plants().corn~=1 do
        if G.GetTime()>=nexttick then registry:Tick();nexttick=G.GetTime()+2 end
        if G.GetTime()>deadline then G.error("adding missing warehouse seed did not resume planting")end
        G.coroutine.yield()
    end
    check(count(robot,"corn_seeds")==0 and count(warehouse,"corn_seeds")==0,"real warehouse replenishment resumes and consumes exactly one corn seed")

    -- With the warehouse now empty, the worker already carrying the seed
    -- must get the task, rather than an empty worker blocking it first.
    for _,e in ipairs(G.TheSim:FindEntities(x,0,z,3,{"farm_plant"},{"INLIMBO"}))do e:Remove()end
    local helper=G.SpawnPrefab("agribot");helper.Transform:SetPosition(x-2,0,z-2)
    local carried=G.SpawnPrefab("carrot_seeds")
    check(helper.components.container:GiveItem(carried,1),"teammate holds one real seed")
    sleep(.5)
    check(registry:GetGroup(helper)==group,"teammate joins actual shared work group")
    local claim=scheduler.Claim;local planted_by
    scheduler.Claim=function(self,worker)
        local t=claim(self,worker)
        if t and t.kind=="PLANT"and not t.parent_id then
            -- Once the helper has borrowed its seed into the action bridge,
            -- another unsupplied job may legitimately report missing_seed.
            -- Enforce preference while the teammate's input is still usable.
            local usable=helper.components.agriresource:FindActionItem(t)
            if usable then
                check(worker==helper,"seed-carrying teammate claims planting instead of empty worker")
                planted_by=worker
            end
        end
        return t
    end
    group.settings.plan={carrot=1};registry:MarkDirty(group,"settings")
    deadline=G.GetTime()+30;nexttick=G.GetTime()
    while plants().carrot~=1 do
        if G.GetTime()>=nexttick then registry:Tick();nexttick=G.GetTime()+2 end
        if G.GetTime()>deadline then G.error("empty worker stranded teammate-supplied planting")end
        G.coroutine.yield()
    end
    check(planted_by==helper and count(helper,"carrot_seeds")==0,"teammate performs real planting and consumes its seed")
    log("COMPLETE native_warehouse_seed_supply")
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
