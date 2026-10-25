local Simple=require("agri/simple_planner")
local U=require("agri/util")
local V=require("agri/rpc_validation")
local carrot={seed="carrot_seeds",prefab="farm_plant_carrot"}
local corn={seed="corn_seeds",prefab="farm_plant_corn"}
local random={seed="seeds",prefab="farm_plant_randomseed",is_randomseed=true}
local function cell(key,x,z,farm) return {key=key,x=x,z=z,is_farm=farm~=false,plants={},soils={}} end
local function snap(o)
    o=o or {}
    return {now=0,group_id="g",epoch=0,center={x=2,z=2},world={season="autumn"},
        defs={carrot=carrot,corn=corn,randomseed=random},
        cells=o.cells or {cell("0:0",2,2)},
        resources={seeds=o.seeds or {carrot_seeds=20,corn_seeds=20,seeds=5},
            tools=o.tools or {hoe={count=1,uses=10},plow={count=1,uses=4}}},
        tuning={min_spacing=1.25},debris=o.debris or {},hole_cycles={}}
end
local function kinds(r) local k={};for _,t in ipairs(r.tasks) do k[t.kind]=(k[t.kind] or 0)+1 end;return k end
local function has(r,code) for _,x in ipairs(r.reasons) do if x.code==code then return true end end;return false end
local n=0
local function scenario(fn) fn();n=n+1 end

scenario(function() -- empty plan does nothing
    local r=Simple.Build(snap(),{density="9",plan={}})
    assert(#r.tasks==0 and has(r,"PLAN_EMPTY"))
end)
scenario(function() -- plan on one plot: till then plant, in plan order
    local r=Simple.Build(snap(),{density="9",plan={carrot=5,corn=2}})
    local k=kinds(r);assert(k.TILL==9 and k.PLANT==7,"full grid prepared; planting follows crop quota")
    local seen={}
    for _,t in ipairs(r.tasks) do
        if t.kind=="PLANT" then
            assert(#t.deps==1 and t.deps[1]:match(":till$"),"plant waits for its hole")
            seen[t.prefab]=(seen[t.prefab] or 0)+1
        end
    end
    assert(seen.carrot_seeds==5 and seen.corn_seeds==2)
    assert(r.summary.needed_plots==1 and #r.reasons==0)
end)
scenario(function() -- missing seeds: plant what exists, report the rest
    local r=Simple.Build(snap({seeds={carrot_seeds=2}}),{density="9",plan={carrot=5}})
    assert(kinds(r).PLANT==2 and has(r,"MISSING_SEEDS") and r.summary.missing_seeds.carrot_seeds==3)
end)
scenario(function() -- missing farmland requires manual cultivation; candidates are ignored
    local s=snap({cells={}})
    local r=Simple.Build(s,{density="9",plan={carrot=12}},{plow_candidates={{x=6,z=2,key="1:0"},{x=10,z=2,key="2:0"},{x=14,z=2,key="3:0"}}})
    assert((kinds(r).PLOW or 0)==0,"automatic plowing is disabled")
    assert(r.summary.needed_plots==2 and has(r,"NEED_FARMLAND"))
end)
scenario(function() -- one farm exists, one active plow already counts
    local r=Simple.Build(snap(),{density="9",plan={carrot=12}},{active_plows=1,plow_candidates={{x=6,z=2,key="1:0"}}})
    assert((kinds(r).PLOW or 0)==0 and kinds(r).PLANT==9)
end)
scenario(function() -- missing farmland does not request a plow tool
    local r=Simple.Build(snap({cells={},tools={hoe={count=1}}}),{density="9",plan={carrot=3}},{plow_candidates={{x=6,z=2,key="1:0"}}})
    assert((kinds(r).PLOW or 0)==0 and has(r,"NEED_FARMLAND") and not has(r,"NEED_PLOW"))
end)
scenario(function() -- existing plants count toward the plan
    local c=cell("0:0",2,2)
    for i=1,3 do c.plants[i]={id="p"..i,crop="carrot",def=carrot,point={x=2+(i-2)*4/3,z=2-4/3}} end
    local r=Simple.Build(snap({cells={c}}),{density="9",plan={carrot=5}})
    assert(kinds(r).PLANT==2,"only the missing two are planted")
end)
scenario(function() -- existing holes are reused, remaining grid points are prepared
    local c=cell("0:0",2,2)
    c.soils={{id="s1",point={x=2,z=2},entity={}},{id="s2",point={x=3.33,z=2},entity={}}}
    local r=Simple.Build(snap({cells={c}}),{density="9",plan={carrot=2}})
    local k=kinds(r);assert(k.PLANT==2 and k.TILL==7)
    for _,t in ipairs(r.tasks) do if t.kind=="PLANT" then
        assert(t.target==c.soils[1].entity or t.target==c.soils[2].entity,"existing holes are reused first")
    end end
end)
scenario(function() -- no hoe and no holes
    local r=Simple.Build(snap({tools={plow={count=1}}}),{density="9",plan={carrot=2}})
    assert((kinds(r).PLANT or 0)==0 and has(r,"NEED_HOE"))
end)
scenario(function() -- 16 holes per plot, two plots
    local s=snap({cells={cell("0:0",2,2),cell("1:0",6,2)}})
    local r=Simple.Build(s,{density="16",plan={carrot=20}})
    assert(kinds(r).PLANT==20 and r.summary.needed_plots==2)
end)
scenario(function() -- generic seeds
    local r=Simple.Build(snap(),{density="9",plan={randomseed=3}})
    local p=0;for _,t in ipairs(r.tasks) do if t.kind=="PLANT" then assert(t.prefab=="seeds");p=p+1 end end
    assert(p==3)
end)
scenario(function() -- settings + RPC validation
    local s=U.Settings({density=16,plan={carrot=3,corn=0,bad="x"}})
    assert(s.density=="16" and s.plan.carrot==3 and s.plan.corn==nil and s.plan.bad==nil)
    assert(U.Settings({}).density=="9" and next(U.Settings({}).plan)==nil)
    local defs={carrot=carrot,corn=corn}
    assert(V.Settings({plan={carrot=4,corn=0}},defs).plan.carrot==4)
    assert(V.Settings({plan={randomseed=2}},defs))
    assert(not V.Settings({plan={nope=1}},defs))
    assert(not V.Settings({plan={carrot=1.5}},defs))
    assert(not V.Settings({plan={carrot=65}},defs))
    assert(not V.Settings({density="11"},defs))
    assert(V.Settings({density="6"},defs).density=="6")
end)
local function near(a,b) return math.abs(a.x-b.x)<1e-6 and math.abs(a.z-b.z)<1e-6 end
scenario(function() -- grid shapes: 8 = 3x3 without centre, 16 = 4x4 inside the tile
    local c=cell("0:0",2,2)
    local p8=Simple.Points(c,"8",1.25);assert(#p8==8)
    for _,p in ipairs(p8) do assert(not near(p,{x=2,z=2}),"8 has no centre") end
    local p9=Simple.Points(c,"9",1.25);assert(#p9==9 and near(p9[1],{x=2-4/3,z=2-4/3}))
    local p16=Simple.Points(c,"16",1.25);assert(#p16==16)
    for _,p in ipairs(p16) do assert(math.abs(p.x-2)<2 and math.abs(p.z-2)<2) end
    assert(math.abs((p16[2].x-p16[1].x)-1.28)<1e-6,"4x4 respects till spacing")
end)
scenario(function() -- natural plow holes are removed, then the regular grid is tilled
    local c=cell("0:0",2,2)
    c.soils={{id="n1",point={x=2.7,z=1.1},entity={}},{id="n2",point={x=0.9,z=3.0},entity={}},{id="g",point={x=2-4/3,z=2-4/3},entity={}}}
    local r=Simple.Build(snap({cells={c}}),{density="8",plan={carrot=8}})
    local unsoil={}
    for _,t in ipairs(r.tasks) do if t.data.unsoil then unsoil[#unsoil+1]=t.id end end
    assert(#unsoil==2,"both off-grid holes removed")
    local grid=Simple.Points(c,"8",.8);local plants,tills=0,0
    for _,t in ipairs(r.tasks) do
        if t.kind=="PLANT" then
            plants=plants+1
            local ok=false;for _,p in ipairs(grid) do if near(p,t.point) then ok=true end end
            assert(ok,"plant on grid");assert(not near(t.point,{x=2.7,z=1.1}))
        elseif t.kind=="TILL" and not t.data.unsoil then
            tills=tills+1
            for _,id in ipairs(unsoil) do assert(U.Contains(t.deps,id),"till waits for removal") end
        end
    end
    assert(plants==8 and tills==7,"on-grid hole reused, 7 new")
end)
scenario(function() -- broken mounds are removed too; nothing removed without a hoe
    local c=cell("0:0",2,2);c.broken_soils={{id="b",point={x=1,z=1.5},entity={},broken=true}}
    local r=Simple.Build(snap({cells={c}}),{density="9",plan={carrot=1}})
    local found=false;for _,t in ipairs(r.tasks) do if t.data.unsoil and near(t.point,{x=1,z=1.5}) then found=true end end
    assert(found)
    local c2=cell("0:0",2,2);c2.soils={{id="n",point={x=2.7,z=1.1},entity={}}}
    local r2=Simple.Build(snap({cells={c2},tools={plow={count=1}}}),{density="9",plan={carrot=1}})
    assert(#r2.tasks==0 and has(r2,"NEED_HOE"),"never plants into an off-grid hole")
end)
local function native(o) local s=snap(o);s.tuning.min_spacing=1.25;return s end
scenario(function() -- full plot prepared with zero or partial seed stock (native 1.25)
    local r=Simple.Build(native({seeds={}}),{density="9",plan={carrot=9}})
    assert(kinds(r).TILL==9 and (kinds(r).PLANT or 0)==0 and has(r,"MISSING_SEEDS"))
    r=Simple.Build(native({seeds={carrot_seeds=1}}),{density="8",plan={carrot=1}})
    assert(kinds(r).TILL==8 and kinds(r).PLANT==1)
end)
scenario(function() -- adjacent 4x4 at native 1.25: unsafe points withheld and reported
    local r=Simple.Build(native({cells={cell("0:0",2,2),cell("1:0",6,2)},seeds={carrot_seeds=32}}),{density="16",plan={carrot=32}})
    local points={}
    for _,t in ipairs(r.tasks) do if t.kind=="TILL" then points[#points+1]=t.point end end
    for i=1,#points do for j=i+1,#points do
        local dx,dz=points[i].x-points[j].x,points[i].z-points[j].z
        assert(dx*dx+dz*dz>=1.25^2-1e-8,"holes keep native spacing")
    end end
    assert(#points==28 and r.summary.withheld==4 and r.summary.capacity==28)
    local found=false
    for _,x in ipairs(r.reasons) do if x.code=="ADJACENT_PLOT_SPACING" then found=x.cell=="1:0" and x.count==4 end end
    assert(found and has(r,"NOT_ENOUGH_HOLES"),"lost capacity is explicit")
end)
scenario(function() -- removal bound to the soil entity; grid-soil planting waits for it
    local function build(guid)
        local c=cell("0:0",2,2)
        local stray={GUID=guid}
        c.soils={{id="soil:"..guid,entity=stray,point={x=2.7,z=1.1}},{id="soil:9",entity={GUID=9},point={x=2-4/3,z=2-4/3}}}
        local r=Simple.Build(native({cells={c}}),{density="8",plan={carrot=8}})
        local removal
        for _,t in ipairs(r.tasks) do if t.data.unsoil then removal=t end end
        assert(removal.target==stray and removal.data.soil_guid==guid)
        for _,t in ipairs(r.tasks) do
            if t.kind=="PLANT" and t.target then assert(U.Contains(t.deps,removal.id),"existing hole waits for cleanup") end
        end
        return removal.id
    end
    assert(build(101)~=build(102),"reappearing hole is a new removal")
end)
scenario(function() -- plan-only change keeps till identities; plant identities follow the plan
    local a=Simple.Build(native(),{density="9",plan={carrot=3}},{epoch=1,layout_epoch="L16x9"})
    local b=Simple.Build(native(),{density="9",plan={carrot=5}},{epoch=2,layout_epoch="L16x9"})
    local till={}
    for _,t in ipairs(a.tasks) do if t.kind=="TILL" then till[t.id]=true end end
    for _,t in ipairs(b.tasks) do
        if t.kind=="TILL" then assert(till[t.id],"till id stable") end
        if t.kind=="PLANT" then assert(t.id:match(":epoch:2:"),"plant id follows plan epoch") end
    end
end)
scenario(function() -- PlanSimple layout generation: plan shrink/expand, reload, return to a layout
    Class=Class or function(ctor)
        local cls={};cls.__index=cls
        return setmetatable(cls,{__call=function(_,...) local o=setmetatable({},cls);ctor(o,...);return o end})
    end
    local planner=require("components/agriplanner")({})
    planner.Maintenance=function() return {},{} end
    local group={id="g",center={x=2,z=2},settings={radius=16,density="9",plan={carrot=18}},scheduler={tasks={}}}
    -- Minimal SetPlan: existing ids are never re-added, cancel_ids cancel.
    local function plan(density,count)
        group.settings.density,group.settings.plan=density,{carrot=count}
        local r=planner:PlanSimple(group,snap({cells={cell("0:0",2,2),cell("1:0",6,2)},seeds={}}))
        local tills={}
        for _,t in ipairs(r.tasks) do
            if t.kind=="TILL" then
                tills[#tills+1]=t.id
                if not group.scheduler.tasks[t.id] then group.scheduler.tasks[t.id]={id=t.id,kind=t.kind,state="pending",data=t.data} end
            end
        end
        for _,id in ipairs(r.cancel_ids) do
            local t=group.scheduler.tasks[id]
            if t and t.state~="complete" and t.state~="cancelled" then t.state,t.reason="cancelled","plan_invalidated" end
        end
        return tills
    end
    local function state(id) return group.scheduler.tasks[id].state end
    local full=plan("9",18);assert(#full==18)
    local first=full[1];group.scheduler.tasks[first].state="complete"
    local shrunk=plan("9",9);assert(#shrunk==9)
    local kept={};for _,id in ipairs(shrunk) do kept[id]=true end
    local dropped=0
    for _,id in ipairs(full) do
        if kept[id] then assert(id==first or state(id)=="pending","plan-only change keeps queued tills")
        else assert(state(id)=="cancelled");dropped=dropped+1 end
    end
    assert(dropped==9)
    local grown=plan("9",18)
    for i,id in ipairs(grown) do assert(id==full[i],"same layout keeps till ids") end
    for _,id in ipairs(full) do if id~=first then assert(state(id)=="pending","expanded plan revives its tills") end end
    -- Reload: only planner_epoch/planner_config persist on the group.
    group={id="g",center=group.center,settings=group.settings,scheduler=group.scheduler,
        planner_epoch=group.planner_epoch,planner_config=group.planner_config}
    assert(group.planner_config:match("#L%d+$"))
    for i,id in ipairs(plan("9",18)) do assert(id==full[i],"layout generation survives reload") end
    local old={};for _,id in ipairs(full) do old[id]=true end
    plan("8",16) -- two plots; no plow expansion in this fixture
    local back=plan("9",18)
    assert(#back==18)
    for _,id in ipairs(back) do assert(not old[id] and state(id)=="pending","returned layout gets fresh ids") end
end)
return n.." scenarios:empty plan, till+plant order, missing seeds, plow expansion, active plows, no plow, existing plants, reuse holes, no hoe, density 16, generic seeds, settings/RPC, grid shapes, natural hole removal, broken mounds, full-plot preparation, adjacent 4x4 native spacing, bound removal identity, layout epoch, planner layout generation"
