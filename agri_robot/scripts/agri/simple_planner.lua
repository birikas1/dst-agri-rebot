-- Simple planting plan: the player chooses holes per plot (density) and how
-- many plants of each crop to grow. No season/nutrient search gates planting.
-- Pure function over an injected snapshot so it can be regression tested.
local C=require("agri/constants")
local U=require("agri/util")
local M={}
local function positionkey(p) return string.format("%.2f:%.2f",p.x,p.z) end
local function add(tasks,id,kind,p,extra)
    local t={id=id,kind=kind,point=p,priority=3,deps={},state="pending",count=1,data={}}
    for k,v in pairs(extra or {}) do t[k]=v end
    tasks[#tasks+1]=t;return t
end
function M.Density(settings)
    local n=tonumber(settings and settings.density)
    return n or 9
end
-- Crop ids in a stable order; only crops with a positive count.
function M.PlanEntries(plan,defs)
    local out={}
    for _,crop in ipairs(U.Keys(plan or {})) do
        local count=math.floor(tonumber(plan[crop]) or 0)
        if count>0 and defs[crop] then out[#out+1]={crop=crop,count=count,def=defs[crop]} end
    end
    return out
end
function M.Total(plan)
    local n=0;for _,v in pairs(plan or {}) do n=n+math.max(0,math.floor(tonumber(v) or 0)) end;return n
end
local function plant_crop(plant,defs)
    if plant.crop and defs[plant.crop] then return plant.crop end
    if plant.def and plant.def.is_randomseed then return "randomseed" end
    return plant.crop
end
-- Regular hole grid for one farm plot: 3x3 (8 = 3x3 without the centre,
-- 6/7 = 3x3 minus fixed points) or 4x4 (16, 10). Returns grid holes in a
-- stable order, plus the existing soils that are off the grid (strays).
-- The pitch never drops below the native till spacing (normal mode 1.25).
local ON_GRID=0.1
local function dist2(a,b) local x,z=a.x-b.x,a.z-b.z;return x*x+z*z end
function M.Points(cell,density,min_spacing)
    local n=tonumber(density) or 9
    local side=(n==16 or n==10) and 4 or 3
    local spacing=4/side
    if min_spacing and spacing<min_spacing then spacing=min_spacing+C.FOUR_ROW_SOIL_MARGIN end
    if (side-1)*spacing>=4 then return nil end
    local out={}
    for row=1,side do for col=1,side do
        local use=true
        if n==8 and row==2 and col==2 then use=false end
        if n==6 and col==2 then use=false end
        if n==7 and (row==2 and col==2 or row==3 and col==3) then use=false end
        if n==10 and (row==4 or row==2 and (col==1 or col==4)) then use=false end
        if use then out[#out+1]={x=cell.x+(col-(side+1)/2)*spacing,z=cell.z+(row-(side+1)/2)*spacing} end
    end end
    return out
end
function M.Grid(cell,density,min_spacing,legal)
    local points=M.Points(cell,density,min_spacing)
    if not points then return {},{},"DENSITY_SPACING_UNSAFE" end
    local block=(min_spacing or 0.8)^2
    local holes,strays,matched,why={}, {},{},nil
    for _,soil in ipairs(cell.soils or {}) do if soil.pending then return {},{},"PLOW_IN_PROGRESS" end end
    for _,p in ipairs(points) do
        local hole={point=p,cell=cell.key};local blocked=false
        for _,plant in ipairs(cell.plants or {}) do
            local d=dist2(plant.point,p)
            if d<=ON_GRID^2 then hole.plant=plant;break elseif d<block then blocked=true end
        end
        if not hole.plant then
            for i,soil in ipairs(cell.soils or {}) do
                if not matched[i] and dist2(soil.point,p)<=ON_GRID^2 then hole.soil=soil.entity;hole.soil_id=soil.id;matched[i]=true;break end
            end
        end
        -- An off-grid crop keeps growing; its neighbouring grid point waits.
        if hole.plant or hole.soil or not blocked and (not legal or legal(p,cell)) then holes[#holes+1]=hole
        else why="LAYOUT_OBSTRUCTED" end
    end
    for i,soil in ipairs(cell.soils or {}) do if not matched[i] then strays[#strays+1]=soil end end
    for _,soil in ipairs(cell.broken_soils or {}) do strays[#strays+1]=soil end
    -- Existing holes first, then empty grid points.
    local ordered={}
    for _,h in ipairs(holes) do if h.soil or h.plant then ordered[#ordered+1]=h end end
    for _,h in ipairs(holes) do if not h.soil and not h.plant then ordered[#ordered+1]=h end end
    return ordered,strays,why
end
-- Stable removal identity: the soil entity, not its position. A natural hole
-- that reappears at the same point is a new entity and gets a new task.
local function soilkey(soil)
    if soil.id then return tostring(soil.id) end
    if soil.entity and soil.entity.GUID then return "soil:"..tostring(soil.entity.GUID) end
    return positionkey(soil.point)
end
-- opts: {group_id, epoch, layout_epoch, hole_cycles, active_plows=n}
-- (plow_candidates is ignored.) epoch names plant tasks (any plan change); layout_epoch names
-- till/removal tasks (density/radius change only).
function M.Build(snapshot,settings,opts)
    opts=opts or {}
    local tasks,reasons={}, {}
    local function reason(code,extra) local r={code=code};for k,v in pairs(extra or {}) do r[k]=v end;reasons[#reasons+1]=r end
    local defs=snapshot.defs or {}
    local entries=M.PlanEntries(settings.plan,defs)
    local total=0;for _,e in ipairs(entries) do total=total+e.count end
    local density=M.Density(settings)
    local summary={density=density,plan_total=total,farm_plots=0,needed_plots=0,planted=0,new_plants=0,plow=0,missing_seeds={},
        prepared_plots=0,capacity=0,till=0,unsoil=0,withheld=0}
    if total==0 then reason("PLAN_EMPTY");return {tasks=tasks,reasons=reasons,summary=summary} end
    local group=opts.group_id or snapshot.group_id or "farm";local epoch=tostring(opts.epoch or snapshot.epoch or 0)
    local layout=tostring(opts.layout_epoch or snapshot.layout_epoch or epoch)
    local cycles=opts.hole_cycles or snapshot.hole_cycles or {}
    -- Farm plots inside the work radius, nearest to the robot group first.
    local farms={}
    for _,cell in ipairs(snapshot.cells or {}) do if cell.is_farm then farms[#farms+1]=cell end end
    local center=snapshot.center or {x=0,z=0}
    table.sort(farms,function(a,b)
        local da,db=U.DistanceSq(a,center),U.DistanceSq(b,center)
        if da==db then return a.key<b.key end return da<db
    end)
    summary.farm_plots=#farms
    local needed=math.ceil(total/math.max(1,density));summary.needed_plots=needed
    -- Existing plants count toward the plan, wherever they stand on the farm.
    local have={}
    for _,cell in ipairs(farms) do for _,p in ipairs(cell.plants or {}) do
        local crop=plant_crop(p,defs);if crop then have[crop]=(have[crop] or 0)+1 end;summary.planted=summary.planted+1
    end end
    -- Automatic plowing is disabled: the robot never creates farmland, even
    -- with a plow in stock. Missing plots are manual work for the player; a
    -- native plow that was already deployed (active_plows) still counts.
    local missing_plots=needed-#farms-(opts.active_plows or 0)
    if missing_plots>0 then reason("NEED_FARMLAND",{count=missing_plots,manual=true}) end
    -- Remaining quota per crop, in plan order; same crops stay together so
    -- native family bonuses can apply. wanted ignores seed stock: holes are
    -- prepared for the whole plan, seeds only limit the PLANT tasks.
    local queue={};local wanted=0
    local seeds=(snapshot.resources or {}).seeds or {}
    local stock={}
    for _,e in ipairs(entries) do
        local want=e.count-(have[e.crop] or 0)
        local seed=e.def.seed
        if want>0 then
            wanted=wanted+want
            local available=seeds[seed] or 0
            local n=math.min(want,math.max(0,available-(stock[seed] or 0)))
            stock[seed]=(stock[seed] or 0)+n
            if n<want then summary.missing_seeds[seed]=(summary.missing_seeds[seed] or 0)+(want-n) end
            for _=1,n do queue[#queue+1]=e end
        end
    end
    if next(summary.missing_seeds) then reason("MISSING_SEEDS") end
    local hoe=((snapshot.resources or {}).tools or {}).hoe or {}
    local can_till=(hoe.count or 0)>0 or hoe.replenishable
    local legal=snapshot.legal_hole;local spacing=(snapshot.tuning or {}).min_spacing or 0.8
    local spacing2=spacing*spacing-1e-9
    -- Every farm grid first: on-grid soils of any plot are kept holes, and
    -- they and all crops anywhere fix the ground for the other plots.
    local grids,fixed={},{}
    for _,cell in ipairs(farms) do
        local holes,strays,why=M.Grid(cell,density,spacing,legal)
        grids[cell.key]={holes=holes,strays=strays,why=why}
        for _,h in ipairs(holes) do if h.soil then fixed[#fixed+1]={point=h.point,cell=cell.key} end end
        for _,soil in ipairs(cell.soils or {}) do if soil.pending then fixed[#fixed+1]={point=soil.point,cell=cell.key} end end
    end
    local seen={}
    local function plant_fixed(p,key)
        if p.id and seen[p.id] then return end
        if p.id then seen[p.id]=true end
        if p.point then fixed[#fixed+1]={point=p.point,cell=key or p.cell} end
    end
    for _,cell in ipairs(snapshot.cells or {}) do for _,p in ipairs(cell.plants or {}) do plant_fixed(p,cell.key) end end
    for _,p in ipairs(snapshot.neighbors or {}) do plant_fixed(p) end
    -- New holes of earlier plots, and removable strays of selected plots.
    local planned,removal={}, {}
    -- A new hole must keep native spacing from every hole and crop in other
    -- plots. Natural holes of a selected plot are removed first (dependency);
    -- natural holes elsewhere are left alone, so the point waits.
    local function cross_check(p,cellkey,deps)
        for _,f in ipairs(fixed) do if f.cell~=cellkey and dist2(f.point,p)<spacing2 then return "ADJACENT_PLOT_SPACING" end end
        for _,f in ipairs(planned) do if f.cell~=cellkey and dist2(f.point,p)<spacing2 then return "ADJACENT_PLOT_SPACING" end end
        local extra={}
        for _,cell in ipairs(farms) do if cell.key~=cellkey then
            for _,soil in ipairs(grids[cell.key].strays) do if dist2(soil.point,p)<spacing2 then
                local id=removal[soil]
                if not id then return "NEIGHBOR_NATURAL_HOLE" end
                extra[#extra+1]=id
            end end
        end end
        for _,id in ipairs(extra) do deps[#deps+1]=id end
        return nil
    end
    local q=1;local free=0;local need_till=false
    local lost={}
    for index,cell in ipairs(farms) do
        if wanted<=free then break end
        if not (index<=needed or free<wanted) then break end
        local grid=grids[cell.key]
        local holes,strays=grid.holes,grid.strays
        if grid.why then reason(grid.why,{cell=cell.key}) end
        summary.prepared_plots=summary.prepared_plots+1
        local deps={};for _,entry in ipairs(snapshot.debris or {}) do if entry.cell==cell.key then deps[#deps+1]="clear:"..entry.id end end
        -- Natural plow holes are off the grid: remove them first. Every till
        -- and every planting on this plot waits for that removal.
        local cleanup=U.Copy(deps);local blocked_cleanup=false
        if #holes>0 and #strays>0 then
            if can_till then
                for _,soil in ipairs(strays) do
                    -- The executor only collapses this exact entity (bound
                    -- target, remapped on reload); a new soil at the same
                    -- point is a different task.
                    local t=add(tasks,group..":epoch:"..layout..":unsoil:"..soilkey(soil),"TILL",soil.point,
                        {target=soil.entity,deps=U.Copy(deps),data={cell=cell.key,unsoil=true,simple=true,soil_id=soil.id,
                            soil_guid=soil.entity and soil.entity.GUID}})
                    removal[soil]=t.id;cleanup[#cleanup+1]=t.id;summary.unsoil=summary.unsoil+1
                end
            else blocked_cleanup=true;need_till=true end
        end
        for _,hole in ipairs(holes) do
            if not hole.plant then
                local key=positionkey(hole.point);local record=cycles[key] or {}
                local generation=record.generation or 0
                local d=U.Copy(cleanup);local ready=hole.soil~=nil
                if not hole.soil then
                    if can_till then
                        local tilldeps=U.Copy(cleanup)
                        local why=cross_check(hole.point,cell.key,tilldeps)
                        if why then lost[why]=lost[why] or {};lost[why][cell.key]=(lost[why][cell.key] or 0)+1
                            summary.withheld=summary.withheld+1
                        else
                            local till=add(tasks,group..":epoch:"..layout..":"..key..":"..tostring(generation)..":till","TILL",hole.point,
                                {deps=tilldeps,data={cell=cell.key,simple=true}})
                            planned[#planned+1]={point=hole.point,cell=cell.key}
                            summary.till=summary.till+1
                            d={till.id};ready=true
                        end
                    else need_till=true end
                end
                if ready and not blocked_cleanup then
                    free=free+1;summary.capacity=summary.capacity+1
                    if q<=#queue then
                        local e=queue[q];q=q+1
                        add(tasks,group..":epoch:"..epoch..":"..key..":"..tostring(generation)..":plant","PLANT",hole.point,{target=hole.soil,prefab=e.def.seed,deps=d,
                            data={crop=e.crop,cell=cell.key,hole_key=key,generation=generation,simple=true,season=snapshot.world and snapshot.world.season}})
                        summary.new_plants=summary.new_plants+1
                    end
                end
            end
        end
    end
    for _,why in ipairs(U.Keys(lost)) do
        for _,key in ipairs(U.Keys(lost[why])) do
            reason(why,{cell=key,count=lost[why][key],density=density,spacing=spacing,
                text=why=="ADJACENT_PLOT_SPACING" and "相邻地块孔距不足原生间距，该地块无法放满此密度" or "相邻地块的自然坑未清理，该孔位等待"})
        end
    end
    if need_till then reason("NEED_HOE") end
    if wanted>free and #farms>0 and not need_till then reason("NOT_ENOUGH_HOLES",{count=wanted-free}) end
    if #farms==0 and (summary.plow or 0)==0 and (opts.active_plows or 0)==0 then reason("NO_FARM_CELLS") end
    return {tasks=tasks,reasons=reasons,summary=summary}
end
return M
