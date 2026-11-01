-- Runs only against the isolated world's save from the zone acceptance run.
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
            local count=0
            for _,group in pairs(reg.groups)do
                if #group.members>0 then
                    count=count+1
                    local marker=group.workcenter
                    check(marker and marker:IsValid(),"actual world reload restores work center")
                    local x,_,z=marker.Transform:GetWorldPosition()
                    check(x==group.center.x and z==group.center.z,"reloaded marker matches persisted original center")
                    check(marker._agri_radius:value()==group.settings.radius,"reloaded center has saved radius")
                    local marks=G.TheSim:FindEntities(x,0,z,.1,{"agriworkcenter"})
                    check(#marks==1,"actual reload creates one marker without persisted duplicates")
                    local robot=group.primary
                    robot.Transform:SetPosition(x+6,0,z)
                    reg:SelectPrimary(group)
                    check(group.workcenter==marker and marker.Transform:GetWorldPosition()==x,"native restored robot movement retains origin")
                    local helper=G.SpawnPrefab("agribot");helper.Transform:SetPosition(x,0,z)
                    reg:Register(helper)
                    check(reg:GetGroup(helper)==group,"native new teammate joins fixed group")
                    robot:Remove()
                    check(group.primary==helper and group.workcenter==marker and marker:IsValid(),"native original robot removal keeps center for teammate")
                    helper:Remove()
                    check(not marker:IsValid() and reg.groups[group.id]==nil,"native last robot removal cleans center")
                end
            end
            check(count>0,"native saved group exists")
            print("[AGRI_NATIVE] COMPLETE native_workcenter_reload")
        end)
        if not ok then print("[AGRI_NATIVE] FAIL "..tostring(err))end
        world:DoTaskInTime(1,function()G.TheSim:Quit()end)
    end)
end)
