-- Codex follow-up: exactly one worker, generic and crop seeds stored together.
local G=GLOBAL
local S=require("agri/storage")
local Simple=require("agri/simple_planner")
local function log(s)print("[AGRI_NATIVE] "..s)end
local function check(ok,s)if not ok then G.error("MIXED SEED ASSERTION: "..s)end;log("PASS "..s)end
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
    local registry=world.components.agrifarmgroup;registry._task:Cancel()
    local portal
    for _,e in pairs(G.Ents)do if e.prefab=="multiplayer_portal"then portal=e;break end end
    check(portal~=nil,"mixed seed fixture portal")
    local px,py,pz=portal.Transform:GetWorldPosition()
    local x,y,z=world.Map:GetTileCenterPoint(px+160,py,pz+112)
    local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
    for dx=-5,5 do for dz=-5,5 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.GRASS)end end
    for _,e in ipairs(G.TheSim:FindEntities(x,0,z,27,nil,{"CLASSIFIED","INLIMBO"}))do
        if e~=world and e~=portal and not e:HasTag("player")then e:Remove()end
    end
    world.Map:SetTile(tx,tz,G.WORLD_TILES.FARMING_SOIL)
    world.components.farming_manager:AddSoilMoistureAtPoint(x,0,z,100000)
    for _,p in ipairs(Simple.Points({x=x,z=z},9,G.GetFarmTillSpacing()))do
        G.SpawnPrefab("farm_soil").Transform:SetPosition(p.x,0,p.z)
    end
    local robot=G.SpawnPrefab("agribot");robot.Transform:SetPosition(x-3,0,z)
    local warehouse=G.SpawnPrefab("agriwarehouse");warehouse.Transform:SetPosition(x+8,0,z+3)
    local function stock(prefab,n,slot)
        local e=G.SpawnPrefab(prefab);e.components.stackable:SetStackSize(n)
        check(warehouse.components.container:GiveItem(e,slot),"mixed warehouse accepts "..prefab)
    end
    stock("seeds",4,1);stock("carrot_seeds",2,2);stock("corn_seeds",1,3)
    sleep(.5)
    local group=registry:GetGroup(robot);group.settings.running=true;group.settings.radius=16
    group.settings.density="9";group.settings.plan={carrot=2}
    check(#group.members==1,"exactly one robot in mixed-seed work group")
    local function plants()
        local all,carrot=0,0
        for _,e in ipairs(G.TheSim:FindEntities(x,0,z,3,{"farm_plant"},{"INLIMBO"}))do
            all=all+1;if e.prefab=="farm_plant_carrot"then carrot=carrot+1 end
        end
        return all,carrot
    end
    local nexttick=G.GetTime();local deadline=G.GetTime()+30
    while true do
        if G.GetTime()>=nexttick then registry:Tick();nexttick=G.GetTime()+2 end
        local _,carrot=plants();if carrot==2 then break end
        if G.GetTime()>deadline then G.error("specific seed planting failed with mixed stock")end
        G.coroutine.yield()
    end
    check(count(robot,"carrot_seeds")+count(warehouse,"carrot_seeds")==0,"specific crop consumes exactly its two real seeds")
    check(count(warehouse,"seeds")==4 and count(warehouse,"corn_seeds")==1,"specific plan preserves generic and unrelated seeds")
    sleep(.6)
    group.settings.plan={randomseed=1};registry:MarkDirty(group,"settings")
    deadline=G.GetTime()+30
    while true do
        if G.GetTime()>=nexttick then registry:Tick();nexttick=G.GetTime()+2 end
        local all=plants();if all==3 then break end
        if G.GetTime()>deadline then G.error("generic seed plan cannot use mixed warehouse")end
        G.coroutine.yield()
    end
    check(count(robot,"seeds")+count(warehouse,"seeds")==3,"generic plan fetches and consumes exactly one ordinary seed")
    check(count(warehouse,"corn_seeds")==1,"generic plan preserves specific corn seed")
    check(#group.members==1,"both mixed-seed phases use a single robot")
    log("COMPLETE native_single_robot_mixed_seed_supply")
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
