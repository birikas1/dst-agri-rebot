-- Real asset/prefab integration; not a crafting-screen screenshot test.
local G=GLOBAL
local function check(ok,msg)if not ok then G.error(msg)end;print("[AGRI_NATIVE] PASS "..msg)end
AddPrefabPostInit("world",function(world)
    if not world.ismastersim then return end
    world:DoTaskInTime(3,function()
        local ok,err=G.pcall(function()
            check(G.AllRecipes.agribot.image=="winona_storage_robot.tex","robot recipe uses native robot body icon")
            check(G.AllRecipes.agriwarehouse.image=="treasurechest_cotl_basic.tex","warehouse recipe uses Flock chest icon")
            local chest=G.SpawnPrefab("agriwarehouse")
            local build=chest.AnimState:GetBuild()
            check(build=="treasure_chest" or build=="treasurechest_cotl_basic","warehouse has a valid native chest animation build")
            local x1,y1,x2,y2=chest.AnimState:GetVisualBB()
            check(x2>x1 and y2>y1,"native warehouse loads nonempty animation geometry")
            check(chest.components.container:GetNumSlots()==67,"Flock appearance keeps67-slot agricultural container")
            chest.components.container.onopenfn(chest)
            check(chest.AnimState:IsCurrentAnimation("open"),"Flock model supports warehouse open animation")
            chest.components.container.onclosefn(chest)
            check(chest.AnimState:IsCurrentAnimation("close"),"Flock model supports warehouse close animation")
            local placer=G.SpawnPrefab("agriwarehouse_placer")
            check(placer.AnimState:IsCurrentAnimation("closed"),"native warehouse placement ghost loads closed animation")
            placer:Remove();chest:Remove()
            print("[AGRI_NATIVE] NOTE skin pixels require graphical-client verification")
            print("[AGRI_NATIVE] COMPLETE native_appearance")
        end)
        if not ok then print("[AGRI_NATIVE] FAIL "..tostring(err))end
        world:DoTaskInTime(1,function()G.TheSim:Quit()end)
    end)
end)
