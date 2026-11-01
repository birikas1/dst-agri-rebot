-- Diagnostic: inspect native circle's world-space visual bounds.
local G=GLOBAL
AddPrefabPostInit("world",function(world)
    if not world.ismastersim then return end
    world:DoTaskInTime(3,function()
        local r=G.SpawnPrefab("reticuleaoe")
        for _,scale in ipairs({1,2,4,6})do
            r.Transform:SetScale(scale,scale,scale)
            print("[AGRI_RANGE_MEASURE]",scale,r.AnimState:GetVisualBB())
        end
        r:Remove()
        print("[AGRI_RANGE_MEASURE] COMPLETE")
        world:DoTaskInTime(1,function()G.TheSim:Quit()end)
    end)
end)
