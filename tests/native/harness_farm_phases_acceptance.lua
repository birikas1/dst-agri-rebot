-- Codex native acceptance: actual 2x2 cleanup, preparation, planting and care.
local G=GLOBAL
local function log(s)print("[AGRI_NATIVE] "..s)end
local function check(ok,s)if not ok then G.error("FARM PHASE ASSERTION: "..s)end;log("PASS "..s)end
local function sleep(s)local untiltime=G.GetTime()+s;repeat G.coroutine.yield()until G.GetTime()>=untiltime end
local function rank(t)
    if t.kind=="CLEAR"then return 1 end
    if t.kind=="TILL"then return t.data.unsoil and 2 or 3 end
    if t.kind=="PLANT"then return 4 end
end
local function run(world)
    sleep(3)
    local registry=world.components.agrifarmgroup
    registry._task:Cancel()
    local portal
    for _,e in pairs(G.Ents)do if e.prefab=="multiplayer_portal"then portal=e;break end end
    check(portal~=nil,"four-plot fixture portal")
    local px,py,pz=portal.Transform:GetWorldPosition()
    local x,y,z=world.Map:GetTileCenterPoint(px+64,py,pz+48)
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
    for dx=-5,5 do for dz=-5,5 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.GRASS)end end
    for _,e in ipairs(G.TheSim:FindEntities(x,0,z,27,nil,{"CLASSIFIED","INLIMBO"}))do
        if e~=world and e~=portal and not e:HasTag("player")then e:Remove()end
    end
    local manager=world.components.farming_manager
    local soils,debris={},{}
    local centers={}
    for dx=0,1 do for dz=0,1 do
        world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.FARMING_SOIL)
        -- Tile scale is four; derive centres from the verified first centre.
        local cx,cz=x+dx*4,z+dz*4
        centers[#centers+1]={x=cx,z=cz}
        manager:AddSoilMoistureAtPoint(cx,0,cz,100000)
        manager:AddTileNutrients(tx+dx,tz+dz,100,100,100)
        local soil=G.SpawnPrefab("farm_soil");soil.Transform:SetPosition(cx+.7,0,cz-.9);soils[#soils+1]=soil
        local d=G.SpawnPrefab("farm_soil_debris");d.Transform:SetPosition(cx-.7,0,cz+.8);debris[#debris+1]=d
    end end
    local robot=G.SpawnPrefab("agribot");robot.Transform:SetPosition(x-2,0,z-2)
    local container=robot.components.container
    -- A normal hoe lasts only 25 holes; use the native golden tool so this
    -- 36-hole acceptance run has sufficient real durability.
    local hoe=G.SpawnPrefab("golden_farm_hoe");local shovel=G.SpawnPrefab("shovel")
    check(container:GiveItem(hoe,26)and container:GiveItem(shovel,27),"four-plot real hoe and shovel")
    local seeds=G.SpawnPrefab("carrot_seeds");seeds.components.stackable:SetStackSize(36)
    check(container:GiveItem(seeds,1),"four-plot real 36 seeds")
    local can=G.SpawnPrefab("wateringcan");can.components.finiteuses:SetUses(can.components.finiteuses.total)
    check(container:GiveItem(can,19),"four-plot real water can")
    sleep(.5)
    local group=registry:GetGroup(robot);group.settings.running=true;group.settings.radius=12
    group.settings.density="9";group.settings.plan={carrot=36}
    local scheduler=group.scheduler;local planner=robot.components.agriplanner
    local ids={}
    local function replan()
        local p=planner:Plan(group);group.plan=p;scheduler:SetPlan(p,group)
        for _,t in ipairs(p.tasks)do local r=rank(t);if r then ids[t.id]=r end end
        return p
    end
    local p=replan();local expected={0,0,0,0}
    for _,t in ipairs(p.tasks)do local r=rank(t);if r then expected[r]=expected[r]+1 end end
    log("FOUR_PLOT_COUNTS "..table.concat(expected,","))
    for _,r in ipairs(p.reasons or {})do log("FOUR_PLOT_REASON "..tostring(r.code).." "..tostring(r.cell))end
    -- Native legality correctly withholds grid points under the real debris
    -- and natural mounds. Later rescans expose them after cleanup.
    check(expected[1]==4 and expected[2]==4 and expected[3]>0 and expected[4]>0,"four-plot real planner covers all categories")
    local last,claimed=0,{}
    local claim=scheduler.Claim
    scheduler.Claim=function(self,worker)
        local t=claim(self,worker)
        if t and not t.parent_id and rank(t)and not claimed[t.id]then
            local r=rank(t)
            check(r>=last,"native stage order "..r.." after "..last)
            for id,prior in pairs(ids)do
                local earlier=self.tasks[id]
                local relevant=self.plan_ids[id]or self.claims:Get(id)
                if relevant and prior<r and earlier.state~="complete"then
                    G.error("native phase "..r.." bypassed "..id.." state="..tostring(earlier.state))
                end
            end
            last=r;claimed[t.id]=true
        end
        return t
    end
    local deadline=G.GetTime()+140;local nextplan=G.GetTime()+2
    while true do
        local done,planted=true,0
        for id,r in pairs(ids)do
            local t=scheduler.tasks[id]
            local relevant=scheduler.plan_ids[id]or scheduler.claims:Get(id)
            if relevant and t.state~="complete"then done=false end
            if r==4 and t.state=="complete"then planted=planted+1 end
            if relevant and(t.state=="blocked"or t.state=="failed")then G.error(id.." "..t.state.." "..tostring(t.reason))end
        end
        if done and planted==36 then break end
        if G.GetTime()>deadline then G.error("four-plot native work timed out at phase "..last)end
        if G.GetTime()>=nextplan then replan();nextplan=G.GetTime()+2 end
        G.coroutine.yield()
    end
    for _,d in ipairs(debris)do check(not d:IsValid(),"native plow debris removed")end
    for _,soil in ipairs(soils)do check(not soil:IsValid()or soil:HasTag("NOBLOCK"),"native stray hole removed")end
    local plants={}
    for _,e in ipairs(G.TheSim:FindEntities(x+2,0,z+2,7,{"farm_plant"},{"INLIMBO"}))do
        if e.prefab=="farm_plant_carrot"then plants[#plants+1]=e end
    end
    check(#plants==36,"native four-plot 36 real crops")
    check(not seeds:IsValid(),"native planting consumed exactly supplied seeds")
    -- Simulate an upcoming dry period after planting; only the planner may
    -- generate watering tasks. Check a real native use and live soil result.
    local c=centers[1];manager:AddSoilMoistureAtPoint(c.x,0,c.z,-100000)
    local before=can.components.finiteuses:GetUses();p=replan();local water
    for _,t in ipairs(p.tasks)do if t.kind=="WATER"and math.abs(t.point.x-c.x)<.01 and math.abs(t.point.z-c.z)<.01 then water=t end end
    check(water~=nil,"automatic care detects dry plot after batch")
    deadline=G.GetTime()+25
    while scheduler.tasks[water.id].state~="complete"do
        if G.GetTime()>deadline then G.error("four-plot water timeout")end
        G.coroutine.yield()
    end
    check(can.components.finiteuses:GetUses()==before-1,"four-plot water consumes one real native use")
    check(manager:IsSoilMoistAtPoint(c.x,0,c.z),"four-plot automatic care wets real soil")
    p=replan()
    for _,t in ipairs(p.tasks)do if t.kind=="WATER"then G.error("wet four-plot rescan queued redundant watering")end end
    check(true,"wet four-plot rescan avoids duplicate watering")
    log("COMPLETE native_four_plot_farm_phases")
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
