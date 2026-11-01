-- Isolated engine integration only. Does not certify mouse/crafting UI.
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
            check(G.AllRecipes.agribot and G.AllRecipes.agribot.placer=="agribot_placer","recipe connects to agribot range placer")
            local def=G.Prefabs.agribot_placer;local dependency=false
            for _,name in ipairs(def and def.deps or {})do if name=="reticuleaoe"then dependency=true end end
            check(dependency,"placer explicitly preloads native circle")
            local portal
            for _,e in pairs(G.Ents)do if e.prefab=="multiplayer_portal"then portal=e;break end end
            check(portal~=nil,"native preview fixture portal")
            local x,_,z=portal.Transform:GetWorldPosition();x=x+4;z=z+4
            local robot=G.SpawnPrefab("agribot");robot.Transform:SetPosition(x,0,z)
            local group=reg:Register(robot);local marker=group.workcenter
            check(marker and marker:IsValid() and marker._agri_range==nil,"dedicated center creates no automatic hover graphics")
            local cx,_,cz=marker.Transform:GetWorldPosition()
            local placer=G.SpawnPrefab("agribot_placer")
            local function preview(px,pz)
                placer.Transform:SetPosition(px,0,pz)
                placer.components.placer.mouse_blocked=false
                placer.components.placer.onupdatetransform(placer)
                check(placer._agri_range and #placer._agri_range==1,"native preview creates one circle")
                return placer._agri_range[1]
            end
            local circle=preview(cx+2,cz)
            local rx,_,rz=circle.Transform:GetWorldPosition()
            check(circle:IsValid() and circle.prefab=="reticuleaoe" and circle.persists==false,"native circle asset instantiates without persistence")
            check(rx==cx and rz==cz,"nearby placement previews existing fixed group center")
            reg:UpdateSettings(group,{radius=8})
            check(preview(cx+3,cz)==circle and placer._agri_range.radius==8,"group radius update reuses native preview circle")
            local scale=circle.Transform:GetScale()
            check(math.abs(scale-2)<.00001,"native circle scale matches eight-unit radius")
            circle=preview(cx+80,cz+80);rx,_,rz=circle.Transform:GetWorldPosition()
            check(rx==cx+80 and rz==cz+80 and placer._agri_range.radius==16,"new group preview follows placement with default radius16")
            circle=preview(cx+84,cz+80);rx,_,rz=circle.Transform:GetWorldPosition()
            check(rx==cx+84 and rz==cz+80,"native preview moves with placement transform")
            placer.components.placer.mouse_blocked=true
            placer.components.placer.onupdatetransform(placer)
            check(not circle:IsValid() and placer._agri_range==nil,"HUD-blocked native preview clears circle")
            circle=preview(cx+84,cz+80)
            placer:Remove()
            check(not circle:IsValid() and marker:IsValid(),"native cancel removes circle while preserving group center")
            robot:Remove()
            print("[AGRI_NATIVE] COMPLETE native_range_preview")
        end)
        if not ok then print("[AGRI_NATIVE] FAIL "..tostring(err))end
        world:DoTaskInTime(1,function()G.TheSim:Quit()end)
    end)
end)
