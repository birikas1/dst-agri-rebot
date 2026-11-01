-- Codex acceptance: zoned tasks retain crop identity and share actual stock.
local Fields=require("agri/field_zones")
local Planner=require("agri/zone_planner")
local function cell(x,z)
    return {key=x..":"..z,tile_x=x,tile_z=z,x=x*4+2,z=z*4+2,is_farm=true,plants={},soils={}}
end
local function fixture(cells,stock)
    local s={now=100,group_id="zones",epoch=0,world={season="autumn"},cells=cells,
        defs={carrot={seed="carrot_seeds"},corn={seed="corn_seeds"},randomseed={seed="seeds",is_randomseed=true}},
        resources={seeds=stock or {carrot_seeds=64,corn_seeds=64,seeds=64},tools={hoe={count=1,uses=100}}},
        tuning={min_spacing=1.25},neighbors={},debris={},hole_cycles={}}
    local zones=Fields.Discover(cells)
    for i,z in ipairs(zones)do z.id="z"..i;z.density="8";z.settings={mode="ratio",density="8",weights={carrot=1},counts={}}
        z.record={slots={},layout_epoch=0}end
    return s,zones
end
local function counts(result,kind)
    local n=0;for _,t in ipairs(result.tasks)do if t.kind==kind and not t.data.unsoil then n=n+1 end end;return n
end
local function same(a,b)
    for k,v in pairs(a)do assert(b[k]==v,"slot crop changed at "..k)end
    for k,v in pairs(b)do assert(a[k]==v,"unexpected slot added at "..k)end
end
local errors,passed={},0
local function test(name,fn)local ok,err=pcall(fn);if ok then passed=passed+1 else errors[#errors+1]=name..": "..tostring(err)end end

test("connected four-tile ratio plan creates32 planting tasks",function()
    local s,z=fixture({cell(0,0),cell(1,0),cell(0,1),cell(1,1)})
    z[1].settings.weights={carrot=1,corn=1}
    local r=Planner.Build(s,z);assert(counts(r,"PLANT")==32 and counts(r,"TILL")==32)
    local n={};for _,t in ipairs(r.tasks)do if t.kind=="PLANT"then n[t.prefab]=(n[t.prefab]or 0)+1 end end
    assert(n.carrot_seeds==16 and n.corn_seeds==16)
end)
test("separate fields receive separate crop choices",function()
    local s,z=fixture({cell(0,0),cell(2,0)})
    z[2].settings.weights={corn=1}
    local r=Planner.Build(s,z);assert(counts(r,"PLANT")==16)
    for _,t in ipairs(r.tasks)do if t.kind=="PLANT"then assert(t.prefab==(t.data.zone_id=="z1"and"carrot_seeds"or"corn_seeds"))end end
end)
test("exact mode does not multiply whole-zone counts",function()
    local s,z=fixture({cell(0,0),cell(1,0),cell(0,1),cell(1,1)})
    z[1].settings={mode="exact",density="8",counts={carrot=4,corn=4},weights={}}
    local r=Planner.Build(s,z);assert(counts(r,"PLANT")==8)
end)
test("one last seed is allocated only once across zones",function()
    local s,z=fixture({cell(0,0),cell(2,0)},{carrot_seeds=1})
    local r=Planner.Build(s,z);assert(counts(r,"PLANT")==1 and r.ledger.used.carrot_seeds==1)
    assert(r.summaries[1].missing_total+r.summaries[2].missing_total==15)
end)
test("review-held zone does not consume another zone's seed",function()
    local s,z=fixture({cell(0,0),cell(2,0)},{carrot_seeds=1});z[1].hold_planting=true
    local r=Planner.Build(s,z);assert(counts(r,"PLANT")==1)
    for _,t in ipairs(r.tasks)do assert(t.data.zone_id=="z2")end
end)
test("restocking preserves specific slots instead of redistributing crops",function()
    local s,z=fixture({cell(0,0),cell(1,0)},{carrot_seeds=1,corn_seeds=0})
    z[1].settings.weights={carrot=1,corn=1}
    local a=Planner.Build(s,z);local old=z[1].assignment;z[1].record.slots=old
    assert(counts(a,"PLANT")==1)
    s.resources.seeds={carrot_seeds=8,corn_seeds=8};local b=Planner.Build(s,z)
    same(old,z[1].assignment);assert(counts(b,"PLANT")==16)
end)
test("debris and natural hole cleanup remain explicit prerequisites",function()
    local c=cell(0,0);c.soils={{id="old",entity={GUID=40},point={x=2.7,z=1.1}}}
    local s,z=fixture({c});s.debris={{id=55,cell=c.key,point={x=1,z=1},entity={GUID=55}}}
    local r=Planner.Build(s,z);local removal
    for _,t in ipairs(r.tasks)do if t.data.unsoil then removal=t end end
    assert(removal and removal.deps[1]=="clear:55")
    for _,t in ipairs(r.tasks)do if t.kind=="TILL"and not t.data.unsoil then
        local seen={};for _,d in ipairs(t.deps)do seen[d]=true end
        assert(seen[removal.id]and seen["clear:55"])
    end end
end)
test("native temporary blocking withholds work without changing targets",function()
    local s,z=fixture({cell(0,0)});s.legal_hole=function()return false end
    local r=Planner.Build(s,z)
    assert(counts(r,"PLANT")==0 and r.summaries[1].usable==8 and r.summaries[1].targets.carrot==8)
    local old=z[1].assignment;z[1].record.slots=old;s.legal_hole=function()return true end
    r=Planner.Build(s,z);same(old,z[1].assignment);assert(counts(r,"PLANT")==8)
end)
test("healthy crop is retained and only remaining slots are planted",function()
    local c=cell(0,0);local s,z=fixture({c});Fields.Geometry(z,1.25)
    c.plants={{id="existing",point=z[1].slots[1].point,crop="carrot",entity={GUID=33}}}
    local r=Planner.Build(s,z);assert(counts(r,"PLANT")==7 and r.summaries[1].have.carrot==1)
    for _,t in ipairs(r.tasks)do assert(t.kind~="CLEAR"and t.target~=c.plants[1].entity)end
end)
test("all emitted work has zone identity and stable IDs",function()
    local s,z=fixture({cell(0,0),cell(2,0)})
    local a=Planner.Build(s,z);local ids={}
    for _,t in ipairs(a.tasks)do assert(t.data.zone_id and not ids[t.id]);ids[t.id]=true end
    local b=Planner.Build(s,z)
    for _,t in ipairs(b.tasks)do assert(ids[t.id],"rescan changed task identity")end
end)

if #errors>0 then error(table.concat(errors,"\n"))end
return passed.." zone planning and shared stock scenarios"
