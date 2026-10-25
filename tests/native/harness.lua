-- Loaded by the staged test copy only. Results are written to the server log.
local G = GLOBAL
local function log(value) print("[AGRI_NATIVE] "..value) end
local function check(value, text)
    if not value then error("NATIVE ASSERTION FAILED: "..text) end
    log("PASS "..text)
end

AddPrefabPostInit("world", function(world)
    if not world.ismastersim then return end
    world:DoTaskInTime(3, function()
        local ok,err=G.xpcall(function()
            log("BEGIN engine="..tostring(G.APP_VERSION))
            check(world.components.agrifarmgroup~=nil,"world farm group component")
            check(world.components.agriblueprint~=nil,"world blueprint component")
            local portal
            for _,entity in pairs(G.Ents) do
                if entity.prefab=="multiplayer_portal" then portal=entity;break end
            end
            local x,y,z=0,0,0
            if portal then x,y,z=portal.Transform:GetWorldPosition() end
            for _,name in ipairs({"agribot","agriwarehouse","super_preserver_kit","scale_thermostat_module"}) do
                local entity=G.SpawnPrefab(name)
                check(entity~=nil,"spawn "..name)
                entity.Transform:SetPosition(x+5,y,z+5)
                if name=="agribot" then
                    check(entity.components.agriexecutor~=nil,"robot executor component")
                    check(entity.components.container.numslots>0,"robot native container initialized")
                    check(entity.sg~=nil and entity.brain~=nil,"robot stategraph and brain initialized")
                end
                entity:Remove()
            end
            log("COMPLETE boot_and_prefabs")
        end,G.debug.traceback)
        if not ok then log("FAIL "..tostring(err)) end
        world:DoTaskInTime(1,function() G.TheSim:Quit() end)
    end)
end)
