local M={}
local function dist(a,b) local x,z=a.x-b.x,a.z-b.z;return x*x+z*z end
function M.Predict(plants, music, radius, legal)
    local targets={}
    for _,plant in ipairs(plants or {}) do
        if not plant.mature and plant.tendable and not plant.tended then targets[#targets+1]=plant end
    end
    table.sort(targets,function(a,b) return tostring(a.id)<tostring(b.id) end)
    if #targets==0 then return {actions={},needed=0,covered=0} end
    if not music then
        local actions={};for _,p in ipairs(targets) do actions[#actions+1]={kind="TEND",target=p.entity,point=p.point,plants={p.id}} end
        return {actions=actions,needed=#targets,covered=#targets}
    end
    if not radius or radius<=0 then return {actions={},needed=#targets,covered=0,reason="MUSIC_RANGE_UNAVAILABLE"} end
    -- Candidate centres include plants and pair-circle intersections. An optimum
    -- fixed-radius cover has a centre at an input point or a two-point boundary.
    local centres={}
    for _,p in ipairs(targets) do centres[#centres+1]=p.point end
    for i=1,#targets do for j=i+1,#targets do
        local a,b=targets[i].point,targets[j].point
        local d2=dist(a,b)
        if d2>0 and d2<=4*radius*radius then
            local d=math.sqrt(d2);local h=math.sqrt(math.max(0,radius*radius-d2/4))
            local mx,mz=(a.x+b.x)/2,(a.z+b.z)/2;local dx,dz=-(b.z-a.z)/d,(b.x-a.x)/d
            centres[#centres+1]={x=mx+h*dx,z=mz+h*dz};centres[#centres+1]={x=mx-h*dx,z=mz-h*dz}
        end
    end end
    local covered,actions,count={}, {},0
    while count<#targets do
        local best,besttargets=nil,{}
        for _,point in ipairs(centres) do
            if not legal or legal(point) then
                local hit={}
                for _,p in ipairs(targets) do if not covered[p.id] and dist(point,p.point)<=radius*radius+0.000001 then hit[#hit+1]=p.id end end
                if #hit>#besttargets then best,besttargets=point,hit end
            end
        end
        if not best then return {actions=actions,needed=#targets,covered=count,reason="NO_LEGAL_MUSIC_POSITION"} end
        actions[#actions+1]={kind="MUSIC_TEND",point=best,plants=besttargets,radius=radius}
        for _,id in ipairs(besttargets) do covered[id]=true;count=count+1 end
    end
    return {actions=actions,needed=#targets,covered=count,method="GREEDY_MAXIMUM_UNCOVERED"}
end
return M
