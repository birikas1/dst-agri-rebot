local C=require("agri/constants")
local M={}
local function dist(a,b) local x,z=a.x-b.x,a.z-b.z;return x*x+z*z end
local function key(cell) return cell.key or tostring(math.floor(cell.x/4))..":"..tostring(math.floor(cell.z/4)) end
function M.Clusters(cells)
    local clusters,seen={},{}
    for i,cell in ipairs(cells or {}) do if not seen[i] then
        local cluster={id=key(cell),cells={},holes={},plants={}};local queue={i};seen[i]=true;local q=1
        while q<=#queue do local n=queue[q];q=q+1;local c=cells[n];cluster.cells[#cluster.cells+1]=c
            if key(c)<cluster.id then cluster.id=key(c) end
            for j,other in ipairs(cells) do if not seen[j] and dist(c,other)<=16.01 then seen[j]=true;queue[#queue+1]=j end end
        end
        table.sort(cluster.cells,function(a,b) if a.z==b.z then return a.x<b.x end return a.z<b.z end)
        clusters[#clusters+1]=cluster
    end end
    table.sort(clusters,function(a,b)return a.id<b.id end)
    return clusters
end
local function fixed_sixteen(cluster,spacing,min_spacing,legal)
    local holes,plants,occupied={}, {},{}
    local tolerance_sq=C.SOIL_TEMPLATE_MATCH_TOLERANCE^2
    for _,cell in ipairs(cluster.cells) do
        if cell.plow_pending then return nil,"PLOW_IN_PROGRESS" end
        for _,soil in ipairs(cell.soils or {}) do if soil.pending then return nil,"PLOW_IN_PROGRESS" end end
        local used={}
        for row=1,4 do for col=1,4 do
            local p={x=cell.x+(col-2.5)*spacing,z=cell.z+(row-2.5)*spacing}
            for _,other in ipairs(occupied) do
                if dist(other,p)<(min_spacing or .8)^2 then return nil,"LAYOUT_OBSTRUCTED" end
            end
            local plant,soil
            for _,candidate in ipairs(cell.plants or {}) do
                if dist(candidate.point,p)<=tolerance_sq then plant=candidate;used[candidate]=true;break end
            end
            if not plant then
                for _,candidate in ipairs(cell.soils or {}) do
                    if dist(candidate.point,p)<=tolerance_sq then soil=candidate;break end
                end
            end
            if not plant and not soil and legal and not legal(p,cell) then return nil,"LAYOUT_OBSTRUCTED" end
            local hole={id=plant and plant.id or soil and soil.id or key(cell)..":"..row..":"..col,
                point=p,cell=key(cell),plant=plant,soil=soil and soil.entity or nil,
                realign=not plant and not soil or false}
            holes[#holes+1]=hole;occupied[#occupied+1]=p
            if plant then plants[#plants+1]=plant end
        end end
        for _,plant in ipairs(cell.plants or {}) do if not used[plant] then return nil,"OFFGRID_PLANT" end end
    end
    table.sort(holes,function(a,b)if a.point.z==b.point.z then return a.point.x<b.point.x end return a.point.z<b.point.z end)
    return holes,plants
end
function M.Holes(cluster,density,min_spacing,legal)
    local holes,plants,occupied={}, {},{}
    local n=tonumber(density) or 9
    local side=(n==16 or n==10) and 4 or 3
    local spacing=4/side
    if side==4 and min_spacing then spacing=math.max(spacing,min_spacing+C.FOUR_ROW_SOIL_MARGIN) end
    if min_spacing and spacing<min_spacing or (side-1)*spacing>=4 then return nil,"DENSITY_SPACING_UNSAFE" end
    if n==16 then
        local fixed,existing,reason=fixed_sixteen(cluster,spacing,min_spacing,legal)
        if fixed then return fixed,existing end
        if existing~="OFFGRID_PLANT" then return nil,existing,reason end
    end
    for _,cell in ipairs(cluster.cells) do
        local k=key(cell)
        if cell.plow_pending then return nil,"PLOW_IN_PROGRESS" end
        local cell_occupied=0
        local diagnostic={cell=k,target=n,min_spacing=min_spacing,template_spacing=spacing,plants=#(cell.plants or {}),soils=#(cell.soils or {}),rejected={},collisions={}}
        for _,p in ipairs(cell.plants or {}) do
            if not p.mature then
                plants[#plants+1]=p;holes[#holes+1]={id=p.id,point=p.point,cell=k,plant=p};occupied[#occupied+1]=p.point
                cell_occupied=cell_occupied+1
            end
        end
        for _,p in ipairs(cell.plants or {}) do
            if p.mature and cell_occupied<n then
                plants[#plants+1]=p;holes[#holes+1]={id=p.id,point=p.point,cell=k,plant=p};occupied[#occupied+1]=p.point
                cell_occupied=cell_occupied+1
            end
        end
        for _,soil in ipairs(cell.soils or {}) do
            if cell_occupied<n then
                holes[#holes+1]={id=soil.id,point=soil.point,cell=k,soil=not soil.pending and soil.entity or nil,pending_soil=soil.pending};occupied[#occupied+1]=soil.point
                cell_occupied=cell_occupied+1
            end
        end
        local fixed_holes,fixed_occupied,fixed_count=#holes,#occupied,cell_occupied
        for row=1,side do for col=1,side do
            local use=not(n==8 and row==2 and col==2)
            if n==6 and col==2 then use=false end
            if n==7 and (row==2 and col==2 or row==3 and col==3) then use=false end
            if n==10 and (row==4 or row==2 and (col==1 or col==4)) then use=false end
            if use then
                local point={x=cell.x+(col-(side+1)/2)*spacing,z=cell.z+(row-(side+1)/2)*spacing}
                local free=true
                for _,p in ipairs(occupied) do if dist(p,point)<(min_spacing or 0.8)^2 then free=false;diagnostic.collisions[#diagnostic.collisions+1]={point=point,other={x=p.x,z=p.z},distance=math.sqrt(dist(p,point))};break end end
                local allowed=not legal or legal(point,cell)
                if not allowed then diagnostic.rejected[#diagnostic.rejected+1]={x=point.x,z=point.z} end
                if cell_occupied<n and free and allowed then
                    holes[#holes+1]={id=k..":"..row..":"..col,point=point,cell=k};occupied[#occupied+1]=point
                    cell_occupied=cell_occupied+1
                end
            end
        end end
        if cell_occupied<n and (n==8 or n==9) then
            -- Native plows leave real holes off the regular grid. Preserve
            -- them, discard only uncommitted proposed points, and try a wider
            -- three-by-three grid within this same tile. No soil is removed.
            for i=#holes,fixed_holes+1,-1 do holes[i]=nil end
            for i=#occupied,fixed_occupied+1,-1 do occupied[i]=nil end
            cell_occupied=fixed_count
            local wide=C.EXISTING_SOIL_GRID_HALFSPAN
            local pool,seen={},{}
            local function candidate(x,z)
                local p={x=cell.x+x,z=cell.z+z}
                local pk=string.format("%.4f:%.4f",p.x,p.z)
                if seen[pk]then return end;seen[pk]=true
                for _,other in ipairs(occupied)do if dist(p,other)<(min_spacing or .8)^2 then return end end
                if not legal or legal(p,cell)then pool[#pool+1]=p end
            end
            for row=-1,1 do for col=-1,1 do candidate(col*wide,row*wide)end end
            for row=-2,2 do for col=-2,2 do candidate(col*wide/2,row*wide/2)end end
            for row=-1,1 do for col=-1,1 do candidate(col*4/3,row*4/3)end end
            local chosen,nodes={},0
            local function fill(start,remaining)
                if remaining==0 then return true end
                if #pool-start+1<remaining or nodes>=C.LAYOUT_FALLBACK_NODES then return false end
                nodes=nodes+1
                for i=start,#pool-remaining+1 do
                    local free=true
                    for _,other in ipairs(chosen)do if dist(pool[i],other)<(min_spacing or .8)^2 then free=false;break end end
                    if free then
                        chosen[#chosen+1]=pool[i]
                        if fill(i+1,remaining-1)then return true end
                        chosen[#chosen]=nil
                    end
                end
                return false
            end
            if fill(1,n-cell_occupied)then
                for i,p in ipairs(chosen)do
                    holes[#holes+1]={id=k..":adapt:"..i,point=p,cell=k}
                    occupied[#occupied+1]=p;cell_occupied=cell_occupied+1
                end
            end
            diagnostic.fallback_nodes=nodes
        end
        if cell_occupied<n then diagnostic.placed=cell_occupied;return nil,"LAYOUT_OBSTRUCTED",diagnostic end
    end
    table.sort(holes,function(a,b) if a.point.z==b.point.z then return a.point.x<b.point.x end return a.point.z<b.point.z end)
    return holes,plants
end
function M.Validate(assignment,neighbors,maxplants)
    local warnings,crowding,assigned={}, {},{}
    for _,p in ipairs(assignment) do assigned[p.id]=true end
    for _,p in ipairs(assignment) do crowding[p.cell]=(crowding[p.cell] or 0)+1 end
    for _,p in ipairs(neighbors or {}) do if not assigned[p.id] then crowding[p.cell]=(crowding[p.cell] or 0)+1 end end
    for _,p in ipairs(assignment) do
        local family=0;local range=p.def.family_check_dist
        if not range then warnings[#warnings+1]={code="FAMILY_DATA_UNAVAILABLE",id=p.id}
        else
            for _,other in ipairs(assignment) do if other.crop==p.crop and not other.family_excluded and dist(p.point,other.point)<=range*range then family=family+1 end end
            for _,other in ipairs(neighbors or {}) do if not assigned[other.id] and other.crop==p.crop and not other.family_excluded and dist(p.point,other.point)<=range*range then family=family+1 end end
            if family<(p.def.family_min_count or 1) then warnings[#warnings+1]={code="FAMILY_STRESS",id=p.id,count=family,required=p.def.family_min_count} end
        end
        if maxplants and crowding[p.cell]>maxplants then warnings[#warnings+1]={code="CROWDING_STRESS",id=p.id,count=crowding[p.cell],maximum=maxplants} end
    end
    return #warnings==0,warnings
end
function M.Assign(holes,counts,defs,neighbors,maxplants,strict,yieldfn,cell_counts)
    if strict and maxplants then
        local totals={};for _,hole in ipairs(holes) do totals[hole.cell]=(totals[hole.cell] or 0)+1 end
        for _,n in pairs(totals) do if n>maxplants then return nil,false,{{code="CROWDING_STRESS",count=n,maximum=maxplants}} end end
    end
    local fixed,empty,assignment,names={}, {},{},{}
    for _,h in ipairs(holes) do
        if h.plant and not h.plant.mature then
            local p=h.plant;local a={id=p.id,crop=p.crop,def=p.def or defs[p.crop],point=p.point,cell=h.cell,existing=p,family_excluded=p.family_excluded}
            if a.def then fixed[#fixed+1]=a end
        else empty[#empty+1]=h end
    end
    for name,n in pairs(counts) do if n>0 then names[#names+1]=name end end;table.sort(names)
    local remaining={};for name,n in pairs(counts) do remaining[name]=n end
    local quotas={}
    for cell,values in pairs(cell_counts or {}) do quotas[cell]={};for name,n in pairs(values) do quotas[cell][name]=n end end
    for _,p in ipairs(fixed) do assignment[#assignment+1]=p end
    local function possible(p)
        local range=p.def.family_check_dist;if not range then return false end
        local nearby=0
        for _,other in ipairs(assignment) do if other.crop==p.crop and dist(p.point,other.point)<=range*range then nearby=nearby+1 end end
        for _,other in ipairs(neighbors or {}) do
            local own=false;for _,h in ipairs(holes) do if h.id==other.id then own=true;break end end
            if not own and other.crop==p.crop and not other.family_excluded and dist(p.point,other.point)<=range*range then nearby=nearby+1 end
        end
        local potential=0
        for index=#assignment-#fixed+1,#empty do if dist(p.point,empty[index].point)<=range*range then potential=potential+1 end end
        return nearby+math.min(potential,remaining[p.crop] or 0)>=(p.def.family_min_count or 1)
    end
    local function assign(index)
        if yieldfn then yieldfn() end
        if index>#empty then return M.Validate(assignment,neighbors,maxplants) end
        local h=empty[index]
        local quota=h.quota_key or h.cell
        for _,name in ipairs(names) do if remaining[name]>0 and (not cell_counts or (quotas[quota][name] or 0)>0) then
            remaining[name]=remaining[name]-1
            if cell_counts then quotas[quota][name]=quotas[quota][name]-1 end
            local p={id=h.id,crop=name,def=defs[name],point=h.point,cell=h.cell,soil=h.soil,
                realign=h.realign==true,harvest=h.plant and h.plant.mature and h.plant or nil}
            assignment[#assignment+1]=p
            local valid=true
            if strict or cell_counts then for _,a in ipairs(assignment) do if not possible(a) then valid=false;break end end end
            if valid then
                if not strict then if assign(index+1) then return true end
                elseif assign(index+1) then return true end
            end
            assignment[#assignment]=nil;remaining[name]=remaining[name]+1
            if cell_counts then quotas[quota][name]=quotas[quota][name]+1 end
        end end
        return false
    end
    if not strict and not cell_counts then
        for _,name in ipairs(names) do for _=1,remaining[name] do local h=empty[#assignment-#fixed+1];if h then assignment[#assignment+1]={id=h.id,crop=name,def=defs[name],point=h.point,cell=h.cell,soil=h.soil,realign=h.realign==true,harvest=h.plant and h.plant.mature and h.plant or nil} end end end
        local safe,warnings=M.Validate(assignment,neighbors,maxplants)
        return assignment,safe,warnings
    end
    if assign(1) then return assignment,true,{} end
    -- Stable mode also permits pressure. Search the quota-constrained layouts
    -- for the smallest warning count; a zero-warning layout already returned.
    if not strict and cell_counts then
        local best,bestwarnings
        local function explore(index)
            if yieldfn then yieldfn() end
            if index>#empty then
                local _,warnings=M.Validate(assignment,neighbors,maxplants)
                if not bestwarnings or #warnings<#bestwarnings then
                    best={};for i,p in ipairs(assignment) do best[i]=p end;bestwarnings=warnings
                end
                return
            end
            local h=empty[index]
            local quota=h.quota_key or h.cell
            for _,name in ipairs(names) do if (quotas[quota][name] or 0)>0 then
                quotas[quota][name]=quotas[quota][name]-1
                assignment[#assignment+1]={id=h.id,crop=name,def=defs[name],point=h.point,cell=h.cell,soil=h.soil,realign=h.realign==true,harvest=h.plant and h.plant.mature and h.plant or nil}
                explore(index+1)
                assignment[#assignment]=nil;quotas[quota][name]=quotas[quota][name]+1
            end end
        end
        explore(1)
        if best then return best,false,bestwarnings end
    end
    return nil,false,{{code="NO_SAFE_FAMILY_LAYOUT"}}
end
-- Enumerate cell count allocations, not every crop-to-hole permutation. Soil,
-- moisture and stock cost depend on these quotas; family geometry is then
-- solved once for each quota vector. This removes factorial equivalent work.
function M.Allocations(holes,counts,yieldfn,visit)
    local capacity,cells,names,remaining={}, {},{},{}
    for _,hole in ipairs(holes) do if not hole.plant or hole.plant.mature then local key=hole.quota_key or hole.cell;capacity[key]=(capacity[key] or 0)+1 end end
    for cell in pairs(capacity) do cells[#cells+1]=cell end;table.sort(cells)
    for name,n in pairs(counts) do if n>0 then names[#names+1]=name;remaining[name]=n end end;table.sort(names)
    local quotas={}
    local function allocate(ci)
        if yieldfn then yieldfn() end
        if ci>#cells then return visit(quotas)==true end
        local cell=cells[ci];quotas[cell]={}
        local function fill(ni,left)
            if yieldfn then yieldfn() end
            if ni>#names then if left==0 then return allocate(ci+1) end;return false end
            local name=names[ni];local maximum=math.min(left,remaining[name])
            local available=0;for j=ni+1,#names do available=available+remaining[names[j]] end
            local minimum=math.max(0,left-available)
            if ci==#cells then minimum=remaining[name];maximum=minimum end
            for n=maximum,minimum,-1 do if n<=left then
                quotas[cell][name]=n;remaining[name]=remaining[name]-n
                if fill(ni+1,left-n) then return true end
                remaining[name]=remaining[name]+n
            end end
            quotas[cell][name]=nil;return false
        end
        return fill(1,capacity[cell])
    end
    if #cells==0 then return visit({}) end
    return allocate(1)
end
return M
