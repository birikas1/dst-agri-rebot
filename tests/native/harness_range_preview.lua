-- Isolated engine integration only. Does not certify mouse/crafting UI.
-- 0.3.2 contract: center recipe + placer, robot only inside a center,
-- no automatic centers, overlap rejection, flingomatic-style ring assets.
local G=GLOBAL
local function check(ok,msg)
    if not ok then G.error(msg)end
    print("[AGRI_NATIVE] PASS "..msg)
end
AddPrefabPostInit("world",function(world)
    if not world.ismastersim then return end
    world:DoTaskInTime(3,function()
        local ok,err=G.pcall(function()
            local reg=world.components.agrifarmgroup;reg._task:Cancel()
            local bot,center=G.AllRecipes.agribot,G.AllRecipes.agriworkcenter
            check(bot and bot.placer=="agribot_placer" and bot.testfn~=nil,"robot recipe has placer and center-range testfn")
            check(center and center.placer=="agriworkcenter_placer" and center.testfn~=nil,"center recipe has placer and overlap testfn")
            check(center.ingredients[1].type=="boards" and center.ingredients[1].amount==1,"center costs one board")
            check(G.Prefabs.agriworkcenter_placer~=nil and G.Prefabs.agribot_placer~=nil,"both placer prefabs registered")
            local placer=G.SpawnPrefab("agriworkcenter_placer")
            check(placer and placer.components.placer and #placer.components.placer.linked==1,"center placer is ring + linked sign")
            placer:Remove()
            local portal
            for _,e in pairs(G.Ents)do if e.prefab=="multiplayer_portal"then portal=e;break end end
            check(portal~=nil,"native preview fixture portal")
            local x,_,z=portal.Transform:GetWorldPosition();x=x+40;z=z+40
            check(not bot.testfn(G.Vector3(x,0,z)),"robot refused with no center")
            local before=#G.TheSim:FindEntities(x,0,z,30,{"agriworkcenter"})
            local robot=G.SpawnPrefab("agribot");robot.Transform:SetPosition(x,0,z)
            check(reg:Register(robot)==nil,"robot without center stays idle")
            check(#G.TheSim:FindEntities(x,0,z,30,{"agriworkcenter"})==before,"robot never spawns a center")
            local c=G.SpawnPrefab("agriworkcenter");c.Transform:SetPosition(x+3,0,z)
            local group=reg:RegisterCenter(c)
            check(group and group.workcenter==c and reg:GetGroup(robot)==group,"new center adopts idle robot in range")
            check(bot.testfn(G.Vector3(x+6,0,z)) and not bot.testfn(G.Vector3(x+40,0,z)),"robot allowed inside, refused outside")
            check(not center.testfn(G.Vector3(x+20,0,z)) and center.testfn(G.Vector3(x+40,0,z)),"overlapping center refused")
            robot:Remove();c:Remove()
            print("[AGRI_NATIVE] COMPLETE native_range_preview")
        end)
        if not ok then print("[AGRI_NATIVE] FAIL "..tostring(err))end
        world:DoTaskInTime(1,function()G.TheSim:Quit()end)
    end)
end)
