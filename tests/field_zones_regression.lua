-- Codex acceptance for connected fields, capacity, stable plans and finite stock.
local Z=require("agri/field_zones")
local function cell(x,z,farm)
    return {key=x..":"..z,tile_x=x,tile_z=z,x=x*4+2,z=z*4+2,is_farm=farm~=false,plants={},soils={}}
end
local function square()
    return {cell(0,0),cell(1,0),cell(0,1),cell(1,1)}
end
local function count(t)local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function total(t)local n=0;for _,v in pairs(t or {})do n=n+v end;return n end
local function equal(a,b)
    for k,v in pairs(a or {})do assert(b[k]==v,"different value at "..tostring(k))end
    assert(count(a)==count(b),"different map size")
end
local function setting(mode,values,density)
    return {mode=mode or "ratio",density=density or "8",weights=mode~="exact" and values or {},counts=mode=="exact" and values or {}}
end
local function store(cells)
    local s={records={},next_id=1};local zones=Z.Discover(cells)
    local ids=Z.Reconcile(s,zones,{group_id="g"});return s,ids,zones
end
local errors,passed={},0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1 else errors[#errors+1]=name..": "..tostring(err)end
end

test("four edge-connected tiles form exactly one management zone",function()
    local z=Z.Discover(square());assert(#z==1 and #z[1].cells==4)
end)
test("a nonfarm gap separates two nearby patches",function()
    local z=Z.Discover({cell(0,0),cell(1,0,false),cell(2,0)})
    assert(#z==2 and #z[1].cells==1 and #z[2].cells==1)
end)
test("diagonal contact alone is not a connected field",function()
    assert(#Z.Discover({cell(0,0),cell(1,1)})==2)
end)
test("L shape and negative coordinates work without rectangular assumptions",function()
    local z=Z.Discover({cell(-2,-1),cell(-1,-1),cell(-2,0)})
    assert(#z==1 and #z[1].cells==3)
end)
test("detection is stable under scan order and duplicate cells",function()
    local a=square();a[#a+1]=cell(4,2)
    local b={a[5],a[4],a[2],a[1],a[3],a[1]}
    local x,y=Z.Discover(a),Z.Discover(b);assert(#x==#y)
    for i=1,#x do assert(x[i].anchor==y[i].anchor and table.concat(x[i].tiles,",")==table.concat(y[i].tiles,","))end
end)
test("four tiles at eight holes produce 32 slots and equal crops16+16",function()
    local z=Z.Discover(square());z[1].density="8";Z.Geometry(z,1.25)
    assert(z[1].nominal==32 and z[1].usable==32)
    equal(Z.Targets(setting("ratio",{potato=1,tomato=1}),z[1].usable),{potato=16,tomato=16})
end)
test("exact counts belong to entire zone and are not multiplied by tiles",function()
    equal(Z.Targets(setting("exact",{potato=4,tomato=4}),32),{potato=4,tomato=4})
end)
test("ratio rounding conserves odd capacity deterministically",function()
    local a=Z.Allocate({carrot=1,corn=1},9);equal(a,{carrot=5,corn=4})
    equal(a,Z.Allocate({corn=1,carrot=1},9));assert(total(Z.Allocate({carrot=2,corn=1},8))==8)
end)
test("empty plan and zero capacity do not create crops",function()
    assert(count(Z.Allocate({},32))==0 and count(Z.Allocate({carrot=1},0))==0)
end)
test("exact plan beyond native capacity is reported and never creates phantom slots",function()
    local t,info=Z.Targets(setting("exact",{carrot=20,corn=20}),32)
    assert(total(t)<=32 and info.over_capacity==8 and info.requested==40)
end)
test("contiguous 16-hole layout respects actual cross-tile native spacing",function()
    local z=Z.Discover(square());z[1].density="16";Z.Geometry(z,1.25)
    assert(z[1].nominal==64 and z[1].usable<64 and z[1].spacing_lost>0)
    local p=z[1].slots
    for i=1,#p do for j=i+1,#p do
        local a,b=p[i].point,p[j].point
        assert((a.x-b.x)^2+(a.z-b.z)^2>=1.25^2-1e-8,"native spacing was bypassed")
    end end
end)
test("temporary holes and plants do not shrink geometric capacity",function()
    local a=Z.Discover(square());a[1].density="8";Z.Geometry(a,1.25)
    local b=square();b[1].soils={{point={x=2.7,z=1.1},pending=true}}
    b[2].plants={{point={x=6,z=2},crop="carrot"}};b[3].obstacles={{}}
    local z=Z.Discover(b);z[1].density="8";Z.Geometry(z,1.25)
    assert(z[1].usable==a[1].usable)
    for i,p in ipairs(a[1].slots)do assert(z[1].slots[i].key==p.key)end
end)
test("legacy selected crops become a ratio template",function()
    local t=Z.Template({density="8",plan={potato=4,tomato=4}})
    assert(t.mode=="ratio"and t.density=="8");equal(t.weights,{potato=4,tomato=4})
    equal(Z.Targets(t,32),{potato=16,tomato=16})
end)
test("a configured zone keeps its own plan when robot defaults change",function()
    local r={configured=true,settings=setting("exact",{corn=3})}
    local actual=Z.Effective(r,Z.Template({plan={carrot=9}}));assert(actual.mode=="exact"and actual.counts.corn==3)
end)
test("assigned crops stay on their slots through growth and harvest",function()
    local keys={"a","b","c","d"}
    local first=Z.AssignSlots(keys,{carrot=2,corn=2},{},{})
    local growing=Z.AssignSlots(keys,{carrot=2,corn=2},first,{a=first.a,c=first.c})
    equal(first,growing)
    equal(first,Z.AssignSlots(keys,{carrot=2,corn=2},growing,{c=first.c}))
end)
test("generic slot keeps its identity after the random crop is revealed",function()
    local t=Z.AssignSlots({"a","b"},{randomseed=1,corn=1},{a="randomseed",b="corn"},{a="carrot"})
    equal(t,{a="randomseed",b="corn"})
end)
test("healthy off-plan plant is preserved instead of overwritten",function()
    local t=Z.AssignSlots({"a","b"},{carrot=2},{},{a="corn"})
    assert(t.a==nil and t.b=="carrot")
end)
test("one finite stock ledger cannot allocate a seed to two zones",function()
    local original={carrot_seeds=1,seeds=2};local l=Z.NewLedger(original)
    assert(Z.Take(l,"carrot_seeds")and not Z.Take(l,"carrot_seeds"))
    assert(Z.Take(l,"seeds")and Z.Take(l,"seeds")and not Z.Take(l,"seeds"))
    assert(original.carrot_seeds==1 and original.seeds==2 and l.used.seeds==2)
end)
test("stable identity and plan survive rescans and border extension",function()
    local s,ids=store({cell(0,0)});local id=ids[1]
    s.records[id].configured=true;s.records[id].settings=setting("ratio",{carrot=1})
    local again=Z.Reconcile(s,Z.Discover({cell(1,0),cell(0,0)}),{group_id="replacement"})
    assert(again[1]==id and #s.records[id].tiles==2 and s.records[id].settings.weights.carrot==1)
end)
test("settings on an unobserved remote zone are retained",function()
    local s,ids=store({cell(0,0),cell(20,20)})
    local remote=ids[2];s.records[remote].configured=true;s.records[remote].settings=setting("exact",{corn=5})
    Z.Reconcile(s,Z.Discover({cell(0,0)}),{scanned={["0:0"]=true},group_id="g"})
    assert(not s.records[remote].gone and s.records[remote].settings.counts.corn==5)
end)
test("same-plan zones merge without losing their configuration",function()
    local s,ids=store({cell(0,0),cell(2,0)})
    for _,id in ipairs(ids)do s.records[id].configured=true;s.records[id].settings=setting("ratio",{carrot=1,corn=1})end
    local merged=Z.Reconcile(s,Z.Discover({cell(0,0),cell(1,0),cell(2,0)}))
    assert(#merged==1 and count(s.records)==1 and not s.records[merged[1]].review)
end)
test("different plans merge with review and both choices preserved",function()
    local s,ids=store({cell(0,0),cell(2,0)})
    for i,id in ipairs(ids)do s.records[id].configured=true;s.records[id].settings=setting("ratio",{[i==1 and "carrot"or"corn"]=1})end
    local merged=Z.Reconcile(s,Z.Discover({cell(0,0),cell(1,0),cell(2,0)}))
    local r=s.records[merged[1]];assert(r.review and #r.review.alternatives>=1)
    assert(r.settings.weights.carrot==1 and r.review.alternatives[1].settings.weights.corn==1)
end)
test("splitting an exact-count field requires review on both pieces",function()
    local s,ids=store({cell(0,0),cell(1,0),cell(2,0)});local r=s.records[ids[1]]
    r.configured=true;r.settings=setting("exact",{carrot=6})
    local out=Z.Reconcile(s,Z.Discover({cell(0,0),cell(2,0)}),{scanned={["0:0"]=true,["1:0"]=true,["2:0"]=true}})
    assert(#out==2 and s.records[out[1]].review and s.records[out[2]].review)
end)
test("world store roundtrip preserves plans, assignments, pauses and revision",function()
    local s,ids=store(square());local r=s.records[ids[1]]
    r.configured=true;r.settings=setting("exact",{randomseed=3});r.paused=true;r.revision=7;r.slots={a="randomseed"}
    local loaded=Z.LoadStore(Z.SaveStore(s));local same=loaded.records[r.id]
    assert(same and same.paused and same.revision==7 and same.settings.counts.randomseed==3 and same.slots.a=="randomseed")
    assert(loaded.next_id>s.next_id-1)
end)
test("gone farmland can recover its prior plan",function()
    local s,ids=store({cell(0,0)});local id=ids[1]
    s.records[id].configured=true;s.records[id].settings=setting("ratio",{corn=1})
    Z.Reconcile(s,{}, {scanned={["0:0"]=true}});assert(s.records[id].gone)
    local out=Z.Reconcile(s,Z.Discover({cell(0,0)}));assert(out[1]==id and not s.records[id].gone)
end)
test("strict edit validation accepts supported crops including generic",function()
    local clean=Z.Clean(setting("ratio",{carrot=1,randomseed=2}),{carrot={}})
    assert(clean and clean.weights.randomseed==2)
end)
test("strict edit validation rejects unknown fields and bad numeric inputs",function()
    local bad={-1,.5,math.huge,0/0,"1"}
    for _,n in ipairs(bad)do assert(not Z.Clean(setting("ratio",{carrot=n}),{carrot={}}))end
    local v=setting("ratio",{carrot=1});v.injected=true;assert(not Z.Clean(v,{carrot={}}))
    assert(not Z.Clean(setting("ratio",{unknown=1}),{carrot={}}))
    assert(not Z.Clean(setting("ratio",{carrot=1},"11"),{carrot={}}))
end)
test("saved settings and loaded records do not alias mutable source tables",function()
    local s,ids=store({cell(0,0)});local r=s.records[ids[1]]
    r.configured=true;r.settings=setting("ratio",{corn=1})
    local save=Z.SaveStore(s);local loaded=Z.LoadStore(save)
    loaded.records[r.id].settings.weights.corn=9
    assert(r.settings.weights.corn==1 and save.records[1].settings.weights.corn==1)
end)

test("simultaneous merge and split preserves both surviving field pieces",function()
    local s,ids=store({cell(0,0),cell(2,0),cell(3,0),cell(4,0)})
    for i,id in ipairs(ids)do s.records[id].configured=true;s.records[id].settings=setting("ratio",{[i==1 and"carrot"or"corn"]=1})end
    local out=Z.Reconcile(s,Z.Discover({cell(0,0),cell(1,0),cell(2,0),cell(4,0)}),
        {scanned={["0:0"]=true,["1:0"]=true,["2:0"]=true,["3:0"]=true,["4:0"]=true}})
    assert(#out==2 and s.records[out[1]]and s.records[out[2]],"merge deleted the record needed by a split piece")
    assert(s.records[out[1]].review,"different plans were merged without review")
end)
if #errors>0 then error(table.concat(errors,"\n"))end
return passed.." field geometry, ratio, reconciliation and finite-stock scenarios"
