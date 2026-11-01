-- Disposable graphical-world fixture. Copied only to the UI test mod.
local G=GLOBAL
AddPlayerPostInit(function(player)
    if not (G.TheWorld and G.TheWorld.ismastersim)then return end
    player:DoTaskInTime(1,function()
        local world=G.TheWorld
        if world._agri_zone_ui_ready then return end
        world._agri_zone_ui_ready=true
        local px,py,pz=player.Transform:GetWorldPosition()
        player.components.health:SetInvincible(true)
        if #G.TheSim:FindEntities(px,0,pz,40,{"agribot"},{"INLIMBO"})>0 then
            player:DoPeriodicTask(10,function()
                player.components.hunger:SetPercent(1);player.components.sanity:SetPercent(1)
            end)
            print("[AGRI_ZONE_UI] RESUMED existing saved scene without regenerating terrain")
            return
        end
        local x,y,z=world.Map:GetTileCenterPoint(px+4,py,pz+4)
        local tx,tz=world.Map:GetTileCoordsAtPoint(x,y,z)
        for dx=-6,9 do for dz=-6,6 do world.Map:SetTile(tx+dx,tz+dz,G.WORLD_TILES.GRASS)end end
        for _,e in ipairs(G.TheSim:FindEntities(x+6,0,z,30,nil,{"CLASSIFIED","INLIMBO"}))do
            if e~=world and not e:HasTag("player")and e.prefab~="multiplayer_portal"then e:Remove()end
        end
        for _,p in ipairs({{0,0},{1,0},{0,1},{1,1},{3,0},{5,0}})do
            world.Map:SetTile(tx+p[1],tz+p[2],G.WORLD_TILES.FARMING_SOIL)
            world.components.farming_manager:AddSoilMoistureAtPoint(x+p[1]*4,0,z+p[2]*4,100000)
            world.components.farming_manager:AddTileNutrients(tx+p[1],tz+p[2],100,100,100)
        end
        player.Transform:SetPosition(x+6,0,z-6)
        player.components.health:SetInvincible(true)
        local robot=G.SpawnPrefab("agribot");robot.Transform:SetPosition(x+8,0,z)
        robot.components.container:GiveItem(G.SpawnPrefab("golden_farm_hoe"),26)
        robot.components.container:GiveItem(G.SpawnPrefab("shovel"),27)
        local can=G.SpawnPrefab("wateringcan");can.components.finiteuses:SetUses(can.components.finiteuses.total)
        robot.components.container:GiveItem(can,19)
        local warehouse=G.SpawnPrefab("agriwarehouse");warehouse.Transform:SetPosition(x+8,0,z-8)
        for i,prefab in ipairs({"carrot_seeds","corn_seeds","seeds"})do
            local seed=G.SpawnPrefab(prefab);seed.components.stackable:SetStackSize(40)
            warehouse.components.container:GiveItem(seed,i)
        end
        player:DoTaskInTime(.5,function()
            local reg=world.components.agrifarmgroup;local group=reg:GetGroup(robot)
            group.settings.radius=24;group.settings.density="8";group.settings.plan={carrot=1,corn=1}
            reg:SetWarehouse(group,warehouse);reg:MarkDirty(group,"zone_ui_fixture")
            print("[AGRI_ZONE_UI] READY real player + 4 connected cells + 2 isolated patches")
            player:DoPeriodicTask(10,function()
                player.components.hunger:SetPercent(1);player.components.sanity:SetPercent(1)
                if group.zone_view then
                    for id,v in pairs(group.zone_view)do
                        print("[AGRI_ZONE_UI] STATE "..id.." tiles="..v.tiles.." mode="..v.mode.." nominal="..v.nominal.." use="..v.usable.." configured="..tostring(v.configured))
                    end
                end
            end)
        end)
    end)
end)
