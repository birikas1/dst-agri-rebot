-- Zone planting work: every connected zone gets its own plan, a stable slot
-- assignment and its own till/plant tasks. Pure function over an injected
-- snapshot (same shape as simple_planner) so it can be regression tested.
local Fields=require("agri/field_zones")
local U=require("agri/util")
local M={}
local ON_GRID=Fields.ON_GRID
local positionkey=Fields.PositionKey
local function dist2(a,b) local x,z=a.x-b.x,a.z-b.z;return x*x+z*z end
local function add(tasks,id,kind,p,extra)
    local t={id=id,kind=kind,point=p,priority=3,deps={},state="pending",count=1,data={}}
    for k,v in pairs(extra or {}) do t[k]=v end
    tasks[#tasks+1]=t;return t
end
local function plant_crop(plant,defs)
    if plant.def and plant.def.is_randomseed then return "randomseed" end
    if plant.crop and defs[plant.crop] then return plant.crop end
    return plant.crop
end
-- Stable removal identity, as in simple_planner: the soil entity.
local function soilkey(soil)
    if soil.id then return tostring(soil.id) end
    if soil.entity and soil.entity.GUID then return "soil:"..tostring(soil.entity.GUID) end
    return positionkey(soil.point)
end
M.SoilKey=soilkey
-- Build(snapshot,zones,opts) -> {tasks,summaries,reasons}
-- zones: Discover output, each extended with
--   id (record id), density, settings (effective), record (slots and
--   layout_epoch are read; record.slots is NOT written here), hold_planting
--   (true while the zone waits for review: no till/plant work is emitted),
--   hold_stock (true while the zone is paused or edited: tills are still
--   emitted, but no PLANT and no seed from the shared ledger;
--   summary.held_plants counts those slots).
-- opts: {hole_cycles, ledger (shared Fields ledger; created from
--   snapshot.resources.seeds when absent)}
-- Returns summaries[i] for zones[i] and zones[i].assignment (new slot map).
function M.Build(snapshot,zones,opts)
    opts=opts or {}
    local tasks,reasons,summaries={}, {},{}
    local defs=snapshot.defs or {}
    local cycles=opts.hole_cycles or snapshot.hole_cycles or {}
    local spacing=(snapshot.tuning or {}).min_spacing or 0.8
    local spacing2=spacing*spacing-1e-9
    local legal=snapshot.legal_hole
    local ledger=opts.ledger or Fields.NewLedger(((snapshot.resources or {}).seeds) or {})
    local hoe=((snapshot.resources or {}).tools or {}).hoe or {}
    local can_till=(hoe.count or 0)>0 or hoe.replenishable
    local season=snapshot.world and snapshot.world.season
    Fields.Geometry(zones,spacing)
    -- Index every captured cell by tile so spacing checks only look at the
    -- eight neighbouring tiles.
    local bytile,zoneof={}, {}
    for _,cell in ipairs(snapshot.cells or {}) do
        local tx,tz=Fields.TileCoords(cell);bytile[Fields.TileKey(tx,tz)]=cell
    end
    for zi,zone in ipairs(zones) do for _,cell in ipairs(zone.cells) do zoneof[cell.key]=zi end end
    -- Plants outside the captured cells (neighbours) still occupy ground.
    local inside={};for _,cell in ipairs(snapshot.cells or {}) do for _,p in ipairs(cell.plants or {}) do if p.id then inside[p.id]=true end end end
    local outside={};for _,p in ipairs(snapshot.neighbors or {}) do if p.point and not (p.id and inside[p.id]) then outside[#outside+1]=p end end
    -- Per cell: on-slot plants and soils, strays (off-slot or broken soils).
    local cellinfo={}
    for zi,zone in ipairs(zones) do
        local slotsof={}
        for _,s in ipairs(zone.slots) do slotsof[s.cell]=slotsof[s.cell] or {};slotsof[s.cell][#slotsof[s.cell]+1]=s end
        for _,cell in ipairs(zone.cells) do
            local info={plants={},soils={},strays={},offgrid={},pending=false,zone=zi}
            local matched={}
            for _,s in ipairs(slotsof[cell.key] or {}) do
                for _,p in ipairs(cell.plants or {}) do
                    if not matched[p] and dist2(p.point,s.point)<=ON_GRID^2 then info.plants[s.key]=p;matched[p]=true;break end
                end
            end
            for _,p in ipairs(cell.plants or {}) do if not matched[p] then info.offgrid[#info.offgrid+1]=p end end
            local used={}
            for _,soil in ipairs(cell.soils or {}) do if soil.pending then info.pending=true end end
            for _,s in ipairs(slotsof[cell.key] or {}) do
                if not info.plants[s.key] then
                    for i,soil in ipairs(cell.soils or {}) do
                        if not used[i] and not soil.pending and dist2(soil.point,s.point)<=ON_GRID^2 then info.soils[s.key]=soil;used[i]=true;break end
                    end
                end
            end
            for i,soil in ipairs(cell.soils or {}) do if not used[i] and not soil.pending then info.strays[#info.strays+1]=soil end end
            for _,soil in ipairs(cell.broken_soils or {}) do info.strays[#info.strays+1]=soil end
            cellinfo[cell.key]=info
        end
    end
    local function debrisdeps(cellkey)
        local deps={}
        for _,entry in ipairs(snapshot.debris or {}) do if entry.cell==cellkey then deps[#deps+1]="clear:"..entry.id end end
        return deps
    end
    local removal={}   -- stray soil -> unsoil task id (only zones that prepare)
    local need_till=false
    for zi,zone in ipairs(zones) do
        local record=zone.record or {}
        local zid=zone.id
        local layout=tostring(record.layout_epoch or 0)
        local s={id=zid,tiles=#zone.cells,density=tonumber(zone.density) or 9,mode=(zone.settings or {}).mode or "ratio",
            nominal=zone.nominal,usable=zone.usable,spacing_lost=zone.spacing_lost,unsafe=zone.unsafe or nil,
            withheld=0,withheld_reasons={},planted=0,offgrid=0,targets={},have={},missing={},missing_total=0,
            new_plants=0,till=0,unsoil=0,review=zone.hold_planting or nil}
        summaries[zi]=s
        local plants,slotkeys={}, {}
        for _,slot in ipairs(zone.slots) do
            slotkeys[#slotkeys+1]=slot.key
            local p=cellinfo[slot.cell].plants[slot.key]
            if p then plants[slot.key]=plant_crop(p,defs) or "unknown";s.planted=s.planted+1 end
        end
        for _,cell in ipairs(zone.cells) do s.offgrid=s.offgrid+#cellinfo[cell.key].offgrid end
        local targets,info=Fields.Targets(zone.settings,zone.usable)
        s.targets,s.requested,s.over_capacity=targets,info.requested,info.over_capacity>0 and info.over_capacity or nil
        local assignment=Fields.AssignSlots(slotkeys,targets,record.slots,plants)
        zone.assignment=assignment
        for key,crop in pairs(assignment) do if plants[key] then s.have[crop]=(s.have[crop] or 0)+1 end end
        if zone.unsafe then reasons[#reasons+1]={code="DENSITY_SPACING_UNSAFE",zone=zid} end
        if U.Count(targets)==0 and not zone.unsafe then s.empty=true end
        -- A zone with an empty plan, a pending review or an unsafe density is
        -- left as it is: no hole is removed, tilled or planted there.
        local prepare=not zone.hold_planting and not zone.unsafe and not s.empty
        local cleanup={}
        for _,cell in ipairs(zone.cells) do
            local deps=debrisdeps(cell.key)
            local ci=cellinfo[cell.key]
            if prepare and not ci.pending and #ci.strays>0 then
                if can_till then
                    for _,soil in ipairs(ci.strays) do
                        local t=add(tasks,zid..":L"..layout..":unsoil:"..soilkey(soil),"TILL",soil.point,
                            {target=soil.entity,deps=U.Copy(deps),data={cell=cell.key,unsoil=true,simple=true,soil_id=soil.id,
                                soil_guid=soil.entity and soil.entity.GUID,zone_id=zid}})
                        removal[soil]=t.id;deps[#deps+1]=t.id;s.unsoil=s.unsoil+1
                    end
                else need_till=true;cleanup[cell.key]=false end
            end
            if cleanup[cell.key]==nil then cleanup[cell.key]=deps end
        end
        local function withhold(code) s.withheld=s.withheld+1;s.withheld_reasons[code]=(s.withheld_reasons[code] or 0)+1 end
        -- Spacing against real ground objects outside this slot's own cell.
        local function blocked(slot,deps)
            local tx,tz=Fields.ParseTile(slot.tile)
            for dx=-1,1 do for dz=-1,1 do
                local cell=bytile[Fields.TileKey(tx+dx,tz+dz)]
                if cell then
                    local own=cell.key==slot.cell
                    for _,p in ipairs(cell.plants or {}) do
                        local d=dist2(p.point,slot.point)
                        if d<spacing2 and not (own and d<=ON_GRID^2) then return "OFFGRID_PLANT" end
                    end
                    if not own then
                        for _,soil in ipairs(cell.soils or {}) do
                            if dist2(soil.point,slot.point)<spacing2 then
                                local ci=cellinfo[cell.key]
                                if ci and ci.zone==zi and removal[soil] then deps[#deps+1]=removal[soil]
                                else return zoneof[cell.key] and zoneof[cell.key]~=zi and "ADJACENT_ZONE_SPACING" or "NEIGHBOR_NATURAL_HOLE" end
                            end
                        end
                        for _,soil in ipairs(cell.broken_soils or {}) do
                            if dist2(soil.point,slot.point)<spacing2 then
                                local ci=cellinfo[cell.key]
                                if ci and ci.zone==zi and removal[soil] then deps[#deps+1]=removal[soil] else return "NEIGHBOR_NATURAL_HOLE" end
                            end
                        end
                    end
                end
            end end
            for _,p in ipairs(outside) do if dist2(p.point,slot.point)<spacing2 then return "OFFGRID_PLANT" end end
            return nil
        end
        if prepare then
            for _,slot in ipairs(zone.slots) do
                local crop=assignment[slot.key]
                if crop and not plants[slot.key] then
                    local ci=cellinfo[slot.cell]
                    local soil=ci.soils[slot.key]
                    local deps=cleanup[slot.cell]
                    local cell=bytile[slot.tile]
                    local extra={}
                    local why
                    if ci.pending then why="PLOW_IN_PROGRESS"
                    elseif deps==false then why="NEED_HOE"
                    elseif not soil and legal and cell and not legal(slot.point,cell) then why="LAYOUT_OBSTRUCTED"
                    else why=blocked(slot,extra) end
                    if why then withhold(why)
                    else
                        local record_cycle=cycles[slot.key] or {}
                        local generation=record_cycle.generation or 0
                        local plantdeps=U.Copy(deps)
                        local ready=soil~=nil
                        if not soil then
                            if can_till then
                                local tilldeps=U.Copy(deps);for _,id in ipairs(extra) do tilldeps[#tilldeps+1]=id end
                                local till=add(tasks,zid..":L"..layout..":"..slot.key..":"..tostring(generation)..":till","TILL",slot.point,
                                    {deps=tilldeps,data={cell=slot.cell,simple=true,zone_id=zid}})
                                s.till=s.till+1;plantdeps={till.id};ready=true
                            else need_till=true end
                        end
                        if ready then
                            local def=defs[crop]
                            local seed=def and def.seed
                            -- A zone the player paused or is editing keeps its
                            -- targets and slots but takes no shared stock, so
                            -- its plantings cannot starve an active zone.
                            if zone.hold_stock then
                                s.held_plants=(s.held_plants or 0)+1
                            elseif seed and Fields.Take(ledger,seed) then
                                add(tasks,zid..":"..slot.key..":"..tostring(generation)..":plant:"..crop,"PLANT",slot.point,
                                    {target=soil and soil.entity or nil,prefab=seed,deps=plantdeps,
                                        data={crop=crop,cell=slot.cell,hole_key=slot.key,generation=generation,simple=true,season=season,zone_id=zid}})
                                s.new_plants=s.new_plants+1
                            elseif seed then
                                s.missing[seed]=(s.missing[seed] or 0)+1;s.missing_total=s.missing_total+1
                            end
                        end
                    end
                end
            end
        end
        if s.missing_total>0 then reasons[#reasons+1]={code="MISSING_SEEDS",zone=zid,count=s.missing_total} end
        if s.withheld>0 then reasons[#reasons+1]={code="ZONE_WITHHELD",zone=zid,count=s.withheld} end
        if zone.hold_planting then reasons[#reasons+1]={code="ZONE_REVIEW",zone=zid} end
    end
    if need_till then reasons[#reasons+1]={code="NEED_HOE"} end
    if #zones==0 then reasons[#reasons+1]={code="NO_FARM_CELLS"} end
    return {tasks=tasks,summaries=summaries,reasons=reasons,ledger=ledger}
end
return M
