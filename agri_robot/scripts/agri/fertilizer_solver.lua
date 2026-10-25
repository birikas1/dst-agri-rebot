local M = {}
local function enough(s,d) return s[1] >= d[1] and s[2] >= d[2] and s[3] >= d[3] end
local function better(a,b)
    if not b then return true end
    for i=1,3 do if a[i] ~= b[i] then return a[i] < b[i] end end
    return false
end
-- Exact bounded branch-and-bound. yieldfn lets the caller spread complete search
-- over server ticks. No inventory count, fertilizer type, or result is truncated.
function M.Solve(deficit, inventory, yieldfn)
    local d = { math.max(0,deficit[1] or 0), math.max(0,deficit[2] or 0), math.max(0,deficit[3] or 0) }
    if d[1]+d[2]+d[3] == 0 then return { feasible=true, items={}, supplied={0,0,0}, excess=0, count=0, cost=0, exact=true } end
    local items = {}
    for name, entry in pairs(inventory or {}) do
        local v, count = entry.nutrients, math.floor(entry.count or 0)
        if v and count > 0 and (v[1] or 0)+(v[2] or 0)+(v[3] or 0) > 0 then
            local bound=0
            for i=1,3 do if (v[i] or 0)>0 then bound=math.max(bound,math.ceil(d[i]/v[i])) end end
            -- Beyond this bound this item alone covers every dimension it can
            -- help: removing one always weakly improves excess, strictly count.
            count=math.min(count,bound)
            if count>0 then items[#items+1]={name=name,vector={v[1] or 0,v[2] or 0,v[3] or 0},count=count,cost=(entry.rarity or 0)+1/(1+(entry.count or 0))} end
        end
    end
    table.sort(items,function(a,b) return a.name < b.name end)
    local suffix={}; suffix[#items+1]={0,0,0}
    for j=#items,1,-1 do local q=items[j]; suffix[j]={}; for i=1,3 do suffix[j][i]=suffix[j+1][i]+q.vector[i]*q.count end end
    if not enough(suffix[1],d) then return {feasible=false,reason="INSUFFICIENT_FERTILIZER",deficit=d,exact=true} end
    local best, chosen, bestchosen, supplied, bestsupplied = nil, {}, nil, {0,0,0}, nil
    local nodes=0
    local function search(index,count,cost)
        nodes=nodes+1; if yieldfn then yieldfn() end
        local excess=math.max(0,supplied[1]-d[1])+math.max(0,supplied[2]-d[2])+math.max(0,supplied[3]-d[3])
        if best and excess>best[1] then return end
        if enough(supplied,d) then
            local score={excess,count,cost}
            if better(score,best) then best=score; bestchosen={}; for k,v in pairs(chosen) do if v>0 then bestchosen[k]=v end end; bestsupplied={supplied[1],supplied[2],supplied[3]} end
            return
        end
        if index>#items then return end
        for i=1,3 do if supplied[i]+suffix[index][i]<d[i] then return end end
        local item=items[index]
        for n=0,item.count do
            chosen[item.name]=n
            search(index+1,count+n,cost+n*item.cost)
            for i=1,3 do supplied[i]=supplied[i]+item.vector[i] end
        end
        for i=1,3 do supplied[i]=supplied[i]-item.vector[i]*(item.count+1) end
        chosen[item.name]=nil
    end
    search(1,0,0)
    if not best then return {feasible=false,reason="INSUFFICIENT_FERTILIZER",deficit=d,exact=true,nodes=nodes} end
    return {feasible=true,items=bestchosen,supplied=bestsupplied,excess=best[1],count=best[2],cost=best[3],exact=true,nodes=nodes}
end
-- Optimize the whole round, not each checkpoint greedily. A mixed fertilizer
-- may be best even when its second nutrient is only needed at a later stage.
-- Interleavings with the same remaining stock and pools are memoized.
function M.Schedule(windows,soil,inventory,capacity,baseline,yieldfn)
    capacity=capacity or math.huge;baseline=baseline or {0,0,0}
    local items={}
    for name,entry in pairs(inventory or {}) do
        if entry.nutrients and (entry.count or 0)>0 then
            local v=entry.nutrients
            if (v[1] or 0)+(v[2] or 0)+(v[3] or 0)>0 then items[#items+1]={name=name,vector={v[1] or 0,v[2] or 0,v[3] or 0},count=math.floor(entry.count),cost=(entry.rarity or 0)+1/(1+entry.count)} end
        end
    end
    table.sort(items,function(a,b)return a.name<b.name end)
    local used,supplied,steps,memo={}, {0,0,0},{},{}
    for i=1,#items do used[i]=0 end
    local best,beststeps,bestused,bestsupply,nodes=nil,nil,nil,nil,0
    local function copyvector(v) return {v[1] or 0,v[2] or 0,v[3] or 0} end
    local function copy_pools(pools) local out={};for key,v in pairs(pools) do out[key]=v end;return out end
    local function search(index,pools,count,cost)
        nodes=nodes+1;if yieldfn then yieldfn() end
        local excess=0;for i=1,3 do excess=excess+math.max(0,supplied[i]-baseline[i]) end
        if best and (excess>best[1] or excess==best[1] and count>best[2]) then return end
        if index>#windows then
            local score={excess,count,cost}
            if better(score,best) then
                best=score;beststeps={};for j,step in ipairs(steps) do beststeps[j]={window=step.window,name=step.name} end
                bestused={};for j,item in ipairs(items) do if used[j]>0 then bestused[item.name]=used[j] end end
                bestsupply=copyvector(supplied)
            end
            return
        end
        local w=windows[index]
        local cell=w.cell or "default";local pool=pools[cell]
        for i=1,3 do if w.consumption[i]>capacity then return end end
        if enough(pool,w.consumption) then
            local nextpool={};for i=1,3 do nextpool[i]=math.min(capacity,pool[i]-w.consumption[i]+w.restoration[i]) end
            local nextpools=copy_pools(pools);nextpools[cell]=nextpool
            search(index+1,nextpools,count,cost);return
        end
        local all={};for name in pairs(pools) do all[#all+1]=name end;table.sort(all)
        local values={};for _,name in ipairs(all) do values[#values+1]=name.."="..table.concat(pools[name],",") end
        local key=index..":"..table.concat(values,";")..":"..table.concat(used,",")
        if memo[key] then return end;memo[key]=true
        for i=1,3 do
            local available=pool[i]
            for j,item in ipairs(items) do available=available+(item.count-used[j])*item.vector[i] end
            if available<w.consumption[i] then return end
        end
        for j,item in ipairs(items) do if used[j]<item.count then
            local useful=false;local nextpool={}
            for i=1,3 do
                nextpool[i]=math.min(capacity,pool[i]+item.vector[i])
                if pool[i]<w.consumption[i] and nextpool[i]>pool[i] then useful=true end
            end
            if useful then
                used[j]=used[j]+1;for i=1,3 do supplied[i]=supplied[i]+item.vector[i] end
                steps[#steps+1]={window=index,name=item.name}
                local nextpools=copy_pools(pools);nextpools[cell]=nextpool
                search(index,nextpools,count+1,cost+item.cost)
                steps[#steps]=nil;used[j]=used[j]-1;for i=1,3 do supplied[i]=supplied[i]-item.vector[i] end
            end
        end end
    end
    local initial={}
    if type(soil[1])=="number" then initial.default=copyvector(soil) else for cell,v in pairs(soil) do initial[cell]=copyvector(v) end end
    search(1,initial,0,0)
    if not best then return {feasible=false,reason="INSUFFICIENT_FERTILIZER",exact=true,nodes=nodes} end
    local actions,bywindow={},{}
    for _,step in ipairs(beststeps) do
        local a=bywindow[step.window]
        if not a then a={window=step.window,cell=windows[step.window].cell,local_window=windows[step.window].local_window,items={},supplied={0,0,0},count=0,order={}};bywindow[step.window]=a;actions[#actions+1]=a end
        a.items[step.name]=(a.items[step.name] or 0)+1;a.count=a.count+1;a.order[#a.order+1]=step.name
        local v=inventory[step.name].nutrients;for i=1,3 do a.supplied[i]=a.supplied[i]+v[i] end
    end
    return {feasible=true,items=bestused,supplied=bestsupply,excess=best[1],count=best[2],cost=best[3],actions=actions,exact=true,nodes=nodes}
end
return M
