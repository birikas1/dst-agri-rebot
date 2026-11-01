-- Codex: actual world registry, native ground, per-zone plans and real seeds.
local G=GLOBAL
local S=require("agri/storage")
local function log(s)print("[AGRI_NATIVE] "..s)end
local function check(ok,s)if not ok then G.error("ZONE ASSERTION: "..s)end;log("PASS "..s)end
local function sleep(s)local untiltime=G.GetTime()+s;repeat G.coroutine.yield()until G.GetTime()>=untiltime end
local function count(inst,prefab)
    local n=0
    for _,c in ipairs({inst.components.container,inst.components.inventory})do
        for _,e in ipairs(S.Items(c))do if e.item.prefab==prefab then n=n+S.Count(e.item)end end
    end
    return n
end
local function run(world)
    sleep(3);local reg=world.components.agrifarmgroup;reg._task:Cancel()
    local portal;for _,e in pairs(G.Ents)do if e.prefab=="multiplayer_portal"then portal=e;break end end
    check(portal~=nil,"zone fixture portal")
    local px,py,pz=portal.Transform:GetWorldPosition();local x,y,z=world.Map:GetTileCenterPoint(px+64,py,pz+64)
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
    for dx=-6,9 do for dz=-6,6 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.GRASS)end end
    for _,e in ipairs(G.TheSim:FindEntities(x+8,0,z,42,nil,{"CLASSIFIED","INLIMBO"}))do
        if e~=world and e~=portal and not e:HasTag("player")then e:Remove()end
    end
    for _,p in ipairs({{0,0},{1,0},{0,1},{1,1},{3,0},{5,0}})do
        world.Map:SetTile(tx+p[1],tz+p[2],G.WORLD_TILES.FARMING_SOIL)
        world.components.farming_manager:AddSoilMoistureAtPoint(x+p[1]*4,0,z+p[2]*4,100000)
        world.components.farming_manager:AddTileNutrients(tx+p[1],tz+p[2],100,100,100)
    end
    local robot=G.SpawnPrefab("agribot");robot.Transform:SetPosition(x+8,0,z)
    local warehouse=G.SpawnPrefab("agriwarehouse");warehouse.Transform:SetPosition(x+8,0,z-8)
    check(robot.components.container:GiveItem(G.SpawnPrefab("golden_farm_hoe"),26),"zone native golden hoe")
    local function stock(prefab,n,slot)
        local e=G.SpawnPrefab(prefab);e.components.stackable:SetStackSize(n)
        check(warehouse.components.container:GiveItem(e,slot),"zone warehouse stock "..prefab)
    end
    stock("carrot_seeds",16,1);stock("corn_seeds",18,2);stock("seeds",2,3)
    sleep(.5);local group=reg:GetGroup(robot)
    group.settings.radius=24;group.settings.density="8";group.settings.plan={};group.settings.running=true
    reg:SetWarehouse(group,warehouse);reg:Tick()
    local marker=group.workcenter
    check(marker and marker:IsValid() and marker.prefab=="agriworkcenter" and marker.persists==false,"native nonpersistent work center exists")
    local cx,_,cz=marker.Transform:GetWorldPosition()
    check(cx==x+8 and cz==z and marker._agri_radius:value()==24,"native marker uses original placement and current radius")
    robot.Transform:SetPosition(x+10,0,z);reg:SelectPrimary(group)
    check(group.center.x==cx and marker.Transform:GetWorldPosition()==cx and group.workcenter==marker,"native moving robot cannot move or duplicate work center")
    robot.Transform:SetPosition(x+8,0,z)
    local placer=G.SpawnPrefab("agribot_placer")
    check(placer and placer.components.placer.onupdatetransform~=nil,"native build placer loads range callback")
    placer:Remove()
    check(group.zones_enabled and #group.zone_order==3,"native 4 connected tiles and two separated tiles become3 zones")
    local a,b,c
    for _,id in ipairs(group.zone_order)do local v=group.zone_view[id]
        if v.tiles==4 then a=id elseif v.points[1].x<x+16 then b=id else c=id end
    end
    check(a and b and c,"native zone identities match separate patches")
    local admin={userid="native-zone-fixture",IsValid=function()return true end,HasTag=function()return false end,
        Transform={GetWorldPosition=function()return x+8,0,z end}}
    local function configure(id,mode,values)
        check(reg:AcquireZoneLock(admin,id),"zone edit lock "..id)
        local settings={mode=mode,density="8",weights=mode=="ratio"and values or {},counts=mode=="exact"and values or {}}
        check(reg:UpdateZone(admin,id,reg.zones.records[id].revision,"save",settings),"zone save "..id)
        reg:ReleaseZoneLock(admin,id)
    end
    for _,case in ipairs({{b,8},{a,32}})do
        local id,cap=case[1],case[2]
        check(reg:AcquireZoneLock(admin,id),"native capacity edit lock")
        local rev=reg.zones.records[id].revision
        for _,mode in ipairs({"ratio","exact"})do
            local data={mode=mode,density="8",weights={},counts={}}
            data[mode=="ratio"and"weights"or"counts"]={carrot=cap,randomseed=1}
            check(not reg:UpdateZone(admin,id,rev,"save",data),"native "..mode.." rejects over cap "..cap)
            check(reg.zones.records[id].revision==rev,"native capacity rejection leaves revision unchanged")
        end
        reg:ReleaseZoneLock(admin,id)
    end
    configure(a,"ratio",{carrot=1,corn=1});configure(b,"exact",{corn=2});configure(c,"exact",{randomseed=2})
    reg:Tick()
    check(group.zone_view[a].targets.carrot==16 and group.zone_view[a].targets.corn==16 and group.zone_view[a].usable==32,"native four-tile ratio32 splits16+16")
    check(group.zone_view[b].targets.corn==2 and group.zone_view[c].targets.randomseed==2,"native exact totals stay independent")
    local function planted()
        local n=0;for _,e in ipairs(G.TheSim:FindEntities(x+8,0,z,22,{"farm_plant"},{"INLIMBO"}))do n=n+1 end;return n
    end
    local deadline=G.GetTime()+145;local nexttick=G.GetTime();local nextlog=G.GetTime()+10
    while planted()<36 do
        if G.GetTime()>=nexttick then reg:Tick();nexttick=G.GetTime()+2 end
        if G.GetTime()>=nextlog then log("ZONE_PROGRESS plants="..planted());nextlog=G.GetTime()+10 end
        if G.GetTime()>deadline then G.error("native zone planting timeout plants="..planted())end
        G.coroutine.yield()
    end
    check(planted()==36,"native zones grow36 real plants with separate plans")
    for _,seed in ipairs({"carrot_seeds","corn_seeds","seeds"})do
        check(count(robot,seed)+count(warehouse,seed)==0,"native exact seed consumption "..seed)
    end
    local saved=reg:OnSave();local Fields=require("agri/field_zones")
    local restored=Fields.LoadStore(saved.zones)
    check(restored.records[a].settings.weights.carrot==1 and restored.records[b].settings.counts.corn==2,"native world save retains independent zone settings")
    log("COMPLETE native_connected_zone_plans")
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
