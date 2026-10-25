-- Independent acceptance checks; use native normal-mode spacing, not 0.8.
local Simple = require("agri/simple_planner")
local function cell(key,x)
    return {key=key,x=x,z=2,is_farm=true,plants={},soils={}}
end
local function snapshot(cells,seeds)
    return {group_id="acceptance",epoch=0,center={x=2,z=2},world={season="autumn"},
        defs={carrot={seed="carrot_seeds",prefab="farm_plant_carrot"}},cells=cells,
        tuning={min_spacing=1.25},resources={seeds={carrot_seeds=seeds},
        tools={hoe={count=1,uses=100},plow={count=1,uses=4}}},debris={},hole_cycles={}}
end
local function build(cells,seeds,density,count)
    return Simple.Build(snapshot(cells,seeds),{density=tostring(density),plan={carrot=count}})
end
local function count(result,kind)
    local n=0
    for _,t in ipairs(result.tasks) do
        if t.kind==kind and not (t.data and t.data.unsoil) then n=n+1 end
    end
    return n
end
local errors,passed={},0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1 else errors[#errors+1]=name..": "..tostring(err) end
end
test("prepare full 3x3 with zero seed stock",function()
    local r=build({cell("a",2)},0,9,9)
    assert(count(r,"TILL")==9,"expected nine preparation tasks")
    assert(count(r,"PLANT")==0,"must not plant nonexistent seeds")
end)
test("partial planting quota still prepares selected plot",function()
    local r=build({cell("a",2)},1,8,1)
    assert(count(r,"TILL")==8,"expected eight grid holes")
    assert(count(r,"PLANT")==1,"expected one real seed planted")
end)
test("adjacent 4x4 tasks respect native spacing",function()
    local r=build({cell("a",2),cell("b",6)},32,16,32)
    local points={}
    for _,t in ipairs(r.tasks) do
        if t.kind=="TILL" and not (t.data and t.data.unsoil) then points[#points+1]=t.point end
    end
    assert(#points>=16,"a safe first plot must remain usable")
    for i=1,#points do for j=i+1,#points do
        local a,b=points[i],points[j]
        local d=(a.x-b.x)^2+(a.z-b.z)^2
        assert(d>=1.25^2-1e-8,"conflicting holes distance="..math.sqrt(d))
    end end
    if #points<32 then assert(#(r.reasons or {})>0,"unavailable capacity must be reported") end
end)
test("existing grid soil planting waits for natural-hole cleanup",function()
    local c=cell("a",2)
    c.soils={
        {id="soil:301",entity={GUID=301},point={x=2-4/3,z=2-4/3}},
        {id="soil:302",entity={GUID=302},point={x=2.7,z=1.1}}}
    local r=build({c},8,8,8)
    local removals,byid={},{}
    for _,t in ipairs(r.tasks) do
        byid[t.id]=t
        if t.data and t.data.unsoil then removals[#removals+1]=t.id end
    end
    assert(#removals==1,"one stray hole should be cleared")
    local function depends(task,id,seen)
        seen=seen or {}
        if seen[task.id] then return false end
        seen[task.id]=true
        for _,dep in ipairs(task.deps or {}) do
            if dep==id or byid[dep] and depends(byid[dep],id,seen) then return true end
        end
        return false
    end
    for _,t in ipairs(r.tasks) do
        if t.kind=="PLANT" then assert(depends(t,removals[1]),"planting can race with cleanup") end
    end
end)
test("no-hoe mode does not remove natural holes",function()
    local c=cell("a",2)
    c.soils={{id="soil:201",entity={GUID=201},point={x=2.7,z=1.1}}}
    local s=snapshot({c},8)
    s.resources.tools.hoe={count=0,uses=0}
    local r=Simple.Build(s,{density="8",plan={carrot=8}})
    for _,t in ipairs(r.tasks) do assert(not (t.data and t.data.unsoil),"cleanup needs a hoe") end
end)
test("reappearing natural hole gets a new removal identity",function()
    local function ids(guid)
        local c=cell("a",2)
        c.soils={{id="soil:"..guid,entity={GUID=guid},point={x=2.7,z=1.1}}}
        local r=build({c},8,8,8)
        for _,t in ipairs(r.tasks) do if t.data and t.data.unsoil then return t.id end end
    end
    local a,b=ids(101),ids(102)
    assert(a and b and a~=b,"new soil must not reuse a completed removal task ID")
end)
test("returning to an earlier density schedules fresh preparation",function()
    Class=function(ctor)
        local cls={};cls.__index=cls
        return setmetatable(cls,{__call=function(_,...) local o=setmetatable({},cls);ctor(o,...);return o end})
    end
    local Planner=require("components/agriplanner")
    local planner=Planner({})
    planner.Maintenance=function()return {},{} end
    local group={id="acceptance",center={x=2,z=2},settings={radius=16,density="8",plan={carrot=1}},
        scheduler={tasks={}}}
    local function plan(density)
        group.settings.density=density
        local s=snapshot({cell("a",2)},0)
        local r=planner:PlanSimple(group,s)
        for _,t in ipairs(r.tasks) do
            if t.kind=="TILL" then
                local old=group.scheduler.tasks[t.id]
                assert(not old or old.state~="complete","returned layout reuses completed till ID")
                group.scheduler.tasks[t.id]={id=t.id,kind=t.kind,state="complete",point=t.point,data=t.data}
            end
        end
    end
    plan("8");plan("9");plan("8")
end)
if #errors>0 then error(table.concat(errors,"\n")) end
return passed.." independent grid acceptance scenarios"
