-- Connected farm zones. Pure functions over plain tables (no entities, no
-- world access) so discovery, reconciliation, capacity and crop allocation
-- can be tested directly.
--
-- A zone is a set of native farm tiles connected through shared edges
-- (4-neighbourhood). Diagonal-only contact or any non-farm tile in between
-- makes separate zones. Zone records live in a world-level store and keep
-- their plan (settings), stable slot assignment and review state.
local Simple=require("agri/simple_planner")
local M={}
M.MODES={ratio=true,exact=true}
M.DENSITIES={"6","7","8","9","10","16"}
M.MAX_RECORDS=256
M.MAX_CROPS=32          -- crop kinds in one zone plan (covers every vanilla crop + generic seeds)
M.MAX_WEIGHT=64         -- ratio weight per crop
M.MAX_COUNT=1024        -- exact count per crop and per zone total
M.MAX_ALTERNATIVES=4    -- conflicting plans kept for review
M.ON_GRID=0.1           -- same tolerance as simple_planner.Grid

local function sortedkeys(t)
    local out={};for k in pairs(t or {}) do out[#out+1]=k end
    table.sort(out,function(a,b)return tostring(a)<tostring(b)end)
    return out
end
local function copy(v)
    if type(v)~="table" then return v end
    local o={};for k,x in pairs(v) do o[k]=copy(x) end;return o
end
local function finiteint(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge and n%1==0 end
local function dist2(a,b) local x,z=a.x-b.x,a.z-b.z;return x*x+z*z end

-- Tile coordinates of a captured cell: the native tile indices when the
-- capture provides them, otherwise the 4-unit grid of the cell centre.
function M.TileCoords(cell)
    if type(cell.tile_x)=="number" and type(cell.tile_z)=="number" then return cell.tile_x,cell.tile_z end
    return math.floor(cell.x/4),math.floor(cell.z/4)
end
function M.TileKey(tx,tz) return tostring(tx)..":"..tostring(tz) end
function M.ParseTile(key)
    local a,b=tostring(key):match("^(%-?%d+):(%-?%d+)$")
    return tonumber(a),tonumber(b)
end
-- Stable tile order: row (tz) first, then column (tx).
function M.TileLess(a,b)
    local ax,az=M.ParseTile(a);local bx,bz=M.ParseTile(b)
    if az~=bz then return (az or 0)<(bz or 0) end
    if ax~=bx then return (ax or 0)<(bx or 0) end
    return tostring(a)<tostring(b)
end
local function idnum(id) return tonumber(tostring(id):match("^z(%d+)$")) or math.huge end
local function idless(a,b)
    local na,nb=idnum(a),idnum(b)
    if na~=nb then return na<nb end
    return tostring(a)<tostring(b)
end
M.IdLess=idless

-- Discover(cells) -> zones
-- Only cells with is_farm=true count. Each zone:
--   {tiles={tilekey...} (tile order), tileset={[tilekey]=true}, cells={cell...}
--    (tile order), anchor=first tile key}
-- Zones are returned in anchor tile order; the result does not depend on
-- the input order.
function M.Discover(cells)
    local bykey,keys={},{}
    for _,cell in ipairs(cells or {}) do
        if cell.is_farm then
            local tx,tz=M.TileCoords(cell);local key=M.TileKey(tx,tz)
            if not bykey[key] then bykey[key]={tx=tx,tz=tz,cell=cell};keys[#keys+1]=key end
        end
    end
    table.sort(keys,M.TileLess)
    local zones,seen={}, {}
    for _,start in ipairs(keys) do
        if not seen[start] then
            local zone={tiles={},tileset={},cells={}}
            local queue,q={start},1;seen[start]=true
            while q<=#queue do
                local key=queue[q];q=q+1
                local entry=bykey[key]
                zone.tiles[#zone.tiles+1]=key;zone.tileset[key]=true
                for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                    local other=M.TileKey(entry.tx+d[1],entry.tz+d[2])
                    if bykey[other] and not seen[other] then seen[other]=true;queue[#queue+1]=other end
                end
            end
            table.sort(zone.tiles,M.TileLess)
            for _,key in ipairs(zone.tiles) do zone.cells[#zone.cells+1]=bykey[key].cell end
            zone.anchor=zone.tiles[1]
            zones[#zones+1]=zone
        end
    end
    return zones
end

-- Settings ------------------------------------------------------------------
-- settings = {mode="ratio"|"exact", density="6".."16",
--             weights={crop=int 1..64}, counts={crop=int 1..1024}}
-- Clean(data,crops) validates an RPC payload strictly: any malformed field
-- rejects the whole request. crops is a set/map of allowed crop ids
-- ("randomseed" is always allowed).
function M.Clean(data,crops)
    if type(data)~="table" then return nil,"设置格式错误" end
    for key in pairs(data) do
        if key~="mode" and key~="density" and key~="weights" and key~="counts" then return nil,"未知设置项" end
    end
    local out={mode=data.mode,weights={},counts={}}
    if not M.MODES[out.mode] then return nil,"模式无效" end
    local density=data.density
    if type(density)=="number" and finiteint(density) then density=tostring(density) end
    local okd=false;for _,d in ipairs(M.DENSITIES) do if d==density then okd=true end end
    if not okd then return nil,"密度无效" end
    out.density=density
    local function list(value,limit,total_limit,field)
        if value==nil then return {} end
        if type(value)~="table" then return nil,"作物列表格式错误" end
        local clean,kinds,total={},0,0
        for crop,n in pairs(value) do
            if type(crop)~="string" or #crop>40 or not (crop=="randomseed" or crops and crops[crop]) then return nil,"作物无效" end
            if not finiteint(n) or n<0 or n>limit then return nil,"数量无效" end
            if n>0 then
                kinds=kinds+1;total=total+n
                if kinds>M.MAX_CROPS then return nil,"作物种类过多" end
                if total_limit and total>total_limit then return nil,"总数过大" end
                clean[crop]=n
            end
        end
        return clean
    end
    local w,why=list(data.weights,M.MAX_WEIGHT,nil,"weights");if not w then return nil,why end
    local c,why2=list(data.counts,M.MAX_COUNT,M.MAX_COUNT,"counts");if not c then return nil,why2 end
    out.weights,out.counts=w,c
    return out
end
-- Input budget is nominal ground capacity, not temporarily usable holes.
-- Only the active mode counts; the other map is kept for mode switching.
function M.SelectionTotal(settings)
    local total=0
    for _,n in pairs(settings and settings[settings.mode=="exact" and "counts" or "weights"] or {}) do total=total+n end
    return total
end
function M.InputCapacity(settings,tiles)
    return math.max(0,math.floor(tonumber(tiles) or 0))*(tonumber(settings and settings.density) or 0)
end
function M.CheckCapacity(settings,tiles)
    local total,limit=M.SelectionTotal(settings),M.InputCapacity(settings,tiles)
    return total<=limit,"已选 "..total.." / 上限 "..limit.."，请减少作物数量。",total,limit
end
-- Sanitize(data) is the lenient load-time variant: invalid parts are
-- dropped instead of rejecting the record.
function M.Sanitize(data)
    if type(data)~="table" then return nil end
    local out={mode=M.MODES[data.mode] and data.mode or "ratio",density="9",weights={},counts={}}
    for _,d in ipairs(M.DENSITIES) do if d==tostring(data.density) then out.density=d end end
    for _,field in ipairs({"weights","counts"}) do
        local limit=field=="weights" and M.MAX_WEIGHT or M.MAX_COUNT
        local kinds=0
        for _,crop in ipairs(sortedkeys(type(data[field])=="table" and data[field] or {})) do
            local n=data[field][crop]
            if type(crop)=="string" and #crop<=40 and finiteint(n) and n>0 and kinds<M.MAX_CROPS then
                out[field][crop]=math.min(limit,n);kinds=kinds+1
            end
        end
    end
    return out
end
-- Template(group_settings): the old global crop plan becomes a default
-- RATIO template (each zone fills its own capacity).
function M.Template(settings)
    settings=settings or {}
    local weights={}
    local kinds=0
    for _,crop in ipairs(sortedkeys(settings.plan)) do
        local n=tonumber(settings.plan[crop])
        if n and n>=1 and kinds<M.MAX_CROPS then weights[crop]=math.min(M.MAX_WEIGHT,math.floor(n));kinds=kinds+1 end
    end
    local density=tostring(settings.density or "9")
    local ok=false;for _,d in ipairs(M.DENSITIES) do if d==density then ok=true end end
    return {mode="ratio",density=ok and density or "9",weights=weights,counts={}}
end
-- Effective settings of a record: its own once configured, else the template.
function M.Effective(record,template)
    if record and record.configured and type(record.settings)=="table" then return record.settings end
    return template or {mode="ratio",density="9",weights={},counts={}}
end
function M.SettingsKey(s)
    if not s then return "none" end
    local out={s.mode or "ratio",tostring(s.density)}
    local field=s.mode=="exact" and "counts" or "weights"
    for _,crop in ipairs(sortedkeys(s[field])) do out[#out+1]=crop.."="..tostring(s[field][crop]) end
    return table.concat(out,"|")
end

-- Allocation ----------------------------------------------------------------
-- Allocate(weights,capacity) -> {crop=n}, summing exactly to capacity
-- (when any weight is positive). Largest remainder rounding in integers;
-- ties go to the larger weight, then the smaller crop id.
function M.Allocate(weights,capacity)
    local names,total={},0
    for crop,w in pairs(weights or {}) do if type(w)=="number" and w>0 then names[#names+1]=crop;total=total+w end end
    local out={}
    capacity=math.max(0,math.floor(capacity or 0))
    if total<=0 or capacity==0 then return out end
    table.sort(names)
    local rem,used={},0
    for _,crop in ipairs(names) do
        local num=weights[crop]*capacity
        out[crop]=math.floor(num/total);rem[crop]=num-out[crop]*total;used=used+out[crop]
    end
    local order={};for i,c in ipairs(names) do order[i]=c end
    table.sort(order,function(a,b)
        if rem[a]~=rem[b] then return rem[a]>rem[b] end
        if weights[a]~=weights[b] then return weights[a]>weights[b] end
        return a<b
    end)
    for i=1,capacity-used do local crop=order[(i-1)%#order+1];out[crop]=out[crop]+1 end
    for crop,n in pairs(out) do if n==0 then out[crop]=nil end end
    return out
end
-- Targets(settings,usable) -> targets {crop=n}, info
-- ratio: weights fill the usable capacity. exact: the counts are the whole
-- zone total; when they exceed the usable capacity they are scaled down
-- deterministically and info.over_capacity reports the excess.
function M.Targets(settings,usable)
    settings=settings or {}
    local info={mode=settings.mode or "ratio",requested=0,over_capacity=0}
    if settings.mode=="exact" then
        local total=0;for _,n in pairs(settings.counts or {}) do total=total+n end
        info.requested=total
        if total<=usable then return copy(settings.counts or {}),info end
        info.over_capacity=total-usable
        return M.Allocate(settings.counts,usable),info
    end
    info.requested=usable
    return M.Allocate(settings.weights,usable),info
end

-- Geometry ------------------------------------------------------------------
-- Geometry(zones,min_spacing) assigns every zone its stable geometric slots:
-- the regular grid of each tile (simple_planner.Points) at the zone density,
-- minus points that would break native till spacing against an already
-- accepted point of another tile. Tiles are processed in global tile order,
-- so the result depends only on tiles and densities, never on debris, seed
-- stock or scan order. Each zone gets:
--   zone.slots = {{key,point,cell,tile}...} (tile order, row-major inside)
--   zone.nominal = tiles*density, zone.usable = #slots,
--   zone.spacing_lost = nominal-usable, zone.unsafe = true when the density
--   cannot be laid out at all.
-- zone.density must be set (string or number) before calling.
local function positionkey(p) return string.format("%.2f:%.2f",p.x,p.z) end
M.PositionKey=positionkey
function M.Geometry(zones,min_spacing)
    local spacing=min_spacing or 0.8
    local spacing2=spacing*spacing-1e-9
    local entries={}
    for zi,zone in ipairs(zones) do
        zone.slots,zone.usable,zone.spacing_lost,zone.unsafe={},0,0,false
        zone.nominal=#zone.cells*(tonumber(zone.density) or 9)
        for _,cell in ipairs(zone.cells) do
            local tx,tz=M.TileCoords(cell)
            entries[#entries+1]={zi=zi,cell=cell,tx=tx,tz=tz,key=M.TileKey(tx,tz)}
        end
    end
    table.sort(entries,function(a,b) if a.tz~=b.tz then return a.tz<b.tz end if a.tx~=b.tx then return a.tx<b.tx end return a.zi<b.zi end)
    local buckets={}
    for _,e in ipairs(entries) do
        local zone=zones[e.zi]
        local points=Simple.Points(e.cell,zone.density,spacing)
        if not points then zone.unsafe=true;points={} end
        local mine={}
        for _,p in ipairs(points) do
            local ok=true
            for dx=-1,1 do for dz=-1,1 do
                if ok and (dx~=0 or dz~=0) then
                    for _,q in ipairs(buckets[M.TileKey(e.tx+dx,e.tz+dz)] or {}) do
                        if dist2(p,q)<spacing2 then ok=false;break end
                    end
                end
            end end
            if ok then
                mine[#mine+1]=p
                zone.slots[#zone.slots+1]={key=positionkey(p),point=p,cell=e.cell.key,tile=e.key}
            end
        end
        buckets[e.key]=mine
    end
    for _,zone in ipairs(zones) do
        zone.usable=#zone.slots
        zone.spacing_lost=math.max(0,zone.nominal-zone.usable)
    end
    return zones
end

-- AssignSlots(slots,targets,previous,plants) -> assignment {slotkey=crop}
-- slots: ordered slot keys. plants: {slotkey=crop} of plants standing on a
-- slot. previous: the stored assignment. Order of precedence:
--   1. a standing plant keeps its slot and counts against its crop target
--      (a plant grown from a generic seed in a "randomseed" slot counts as
--      randomseed); a plant beyond every target stays untouched, unassigned;
--   2. a free slot keeps its previous crop while that crop has target left;
--   3. remaining free slots are filled in slot order, crops in id order,
--      so equal crops stay together.
-- The result depends only on these inputs, never on seed stock.
function M.AssignSlots(slots,targets,previous,plants)
    previous,plants=previous or {},plants or {}
    local left={};for crop,n in pairs(targets or {}) do left[crop]=n end
    local out={}
    for _,key in ipairs(slots) do
        local crop=plants[key]
        if crop then
            local as
            if previous[key]=="randomseed" and (left.randomseed or 0)>0 then as="randomseed"
            elseif (left[crop] or 0)>0 then as=crop end
            if as then out[key]=as;left[as]=left[as]-1 end
        end
    end
    for _,key in ipairs(slots) do
        local crop=previous[key]
        if not plants[key] and crop and (left[crop] or 0)>0 then out[key]=crop;left[crop]=left[crop]-1 end
    end
    local names=sortedkeys(left)
    local ci=1
    for _,key in ipairs(slots) do
        if not plants[key] and not out[key] then
            while ci<=#names and (left[names[ci]] or 0)<=0 do ci=ci+1 end
            if ci>#names then break end
            local crop=names[ci];out[key]=crop;left[crop]=left[crop]-1
        end
    end
    return out
end

-- Shared finite stock ---------------------------------------------------------
-- NewLedger(stock) -> ledger; Take(ledger,seed) -> true while stock lasts.
-- One ledger per planning pass is shared by all zones so the same last
-- seeds are never allocated to two plans.
function M.NewLedger(stock)
    local ledger={left={},used={}}
    for seed,n in pairs(stock or {}) do ledger.left[seed]=math.max(0,math.floor(tonumber(n) or 0)) end
    return ledger
end
function M.Take(ledger,seed)
    if (ledger.left[seed] or 0)>0 then
        ledger.left[seed]=ledger.left[seed]-1;ledger.used[seed]=(ledger.used[seed] or 0)+1
        return true
    end
    return false
end

-- Reconciliation ----------------------------------------------------------------
-- store = {records={[id]=record}, next_id=n}
-- record = {id="z<n>", tiles={tilekey...}, anchor=tilekey, configured=bool,
--   settings=nil|settings, paused=bool, review=nil|{reason,alternatives},
--   revision=n, slots={[slotkey]=crop}, slot_layout=string, layout_epoch=n,
--   config_key=string, group_id=string, gone=bool}
-- Reconcile(store,zones,opts) -> ids, events
--   zones: Discover output. opts.scanned: set of tile keys this scan could
--   see (defaults to the discovered tiles); tiles of a record outside it are
--   kept unchanged. opts.group_id tags NEW records only (ownership of an
--   existing record is decided by the caller).
--   ids[zi] = record id for zones[zi]. events: list of {kind,id,...}.
-- Rules: one overlapping record => it keeps the zone (new adjacent land
-- extends it). Several records merging into one zone: the oldest keeps its
-- id; equal effective plans merge silently, different configured plans keep
-- the oldest settings, store the others as alternatives and mark review.
-- One record split over several zones: the zone with most of its tiles
-- (then the one holding its anchor) keeps the id; the other pieces get a new
-- record with a copy of the settings. Copies of a configured EXACT plan are
-- marked review on every piece, so exact quotas are never doubled silently.
-- A record whose scanned tiles all disappeared is marked gone and revived if
-- farmland reappears on its tiles.
local function newrecord(store,zone,opts)
    local n=store.next_id or 1
    store.next_id=n+1
    local record={id="z"..tostring(n),tiles=copy(zone.tiles),anchor=zone.anchor,configured=false,
        paused=false,revision=1,slots={},slot_layout="",layout_epoch=0,group_id=opts.group_id}
    store.records[record.id]=record
    return record
end
function M.Reconcile(store,zones,opts)
    opts=opts or {}
    store.records=store.records or {};store.next_id=store.next_id or 1
    local events={}
    local scanned=opts.scanned
    if not scanned then scanned={};for _,zone in ipairs(zones) do for _,t in ipairs(zone.tiles) do scanned[t]=true end end end
    local ids={}
    local rids=sortedkeys(store.records);table.sort(rids,idless)
    local owner={}
    for _,rid in ipairs(rids) do
        local r=store.records[rid]
        if not r.gone then for _,t in ipairs(r.tiles or {}) do owner[t]=owner[t] or {};owner[t][#owner[t]+1]=rid end end
    end
    local overlap,K={}, {}
    for zi,zone in ipairs(zones) do
        for _,t in ipairs(zone.tiles) do
            for _,rid in ipairs(owner[t] or {}) do
                overlap[rid]=overlap[rid] or {}
                if not overlap[rid][zi] then K[rid]=K[rid] or {};K[rid][#K[rid]+1]=zi end
                overlap[rid][zi]=(overlap[rid][zi] or 0)+1
            end
        end
    end
    local H,S={}, {}
    for _,rid in ipairs(rids) do
        local list=K[rid]
        if list then
            local r=store.records[rid]
            local home
            for _,zi in ipairs(list) do
                if not home then home=zi
                else
                    local a,b=overlap[rid][zi],overlap[rid][home]
                    local ahas,bhas=zones[zi].tileset[r.anchor],zones[home].tileset[r.anchor]
                    if a>b or a==b and (ahas and not bhas or (ahas==bhas) and zi<home) then home=zi end
                end
            end
            H[home]=H[home] or {};H[home][#H[home]+1]=rid
            for _,zi in ipairs(list) do if zi~=home then S[zi]=S[zi] or {};S[zi][#S[zi]+1]=rid end end
            if #list>1 then
                local exact=r.configured and r.settings and r.settings.mode=="exact"
                if exact then r.review=r.review or {reason="split"} end
                events[#events+1]={kind="split",id=rid,pieces=#list,review=exact or nil}
            end
        end
    end
    -- Snapshot of every matched record before any merge deletes one: a record
    -- can be merged into one zone and still be the parent of a split piece
    -- in another zone of the same scan.
    local source={}
    for _,rid in ipairs(rids) do
        local r=store.records[rid]
        if K[rid] then
            source[rid]={id=rid,configured=r.configured==true,settings=copy(r.settings),paused=r.paused==true,review=r.review~=nil}
        end
    end
    local function settle(record,zone)
        local tiles={}
        for _,t in ipairs(record.tiles or {}) do if not scanned[t] and not zone.tileset[t] then tiles[#tiles+1]=t end end
        local before=table.concat(record.tiles or {},",")
        for _,t in ipairs(zone.tiles) do tiles[#tiles+1]=t end
        table.sort(tiles,M.TileLess)
        record.tiles=tiles
        local has=false;for _,t in ipairs(tiles) do if t==record.anchor then has=true end end
        if not has then record.anchor=zone.anchor end
        record.gone=nil
        if before~=table.concat(tiles,",") then events[#events+1]={kind="extend",id=record.id} end
    end
    for zi,zone in ipairs(zones) do
        local home=H[zi]
        local record
        if home and #home>0 then
            table.sort(home,idless)
            record=store.records[home[1]]
            if #home>1 then
                local key=record.configured and M.SettingsKey(record.settings) or "template"
                local same=true
                local alternatives={}
                for i=2,#home do
                    local other=store.records[home[i]]
                    local okey=other.configured and M.SettingsKey(other.settings) or "template"
                    if okey~=key then
                        same=false
                        if other.configured and #alternatives<M.MAX_ALTERNATIVES then alternatives[#alternatives+1]={from=other.id,settings=copy(other.settings)} end
                    end
                    if other.paused then record.paused=true end
                    if other.review then same=false end
                    store.records[other.id]=nil
                end
                if not same then
                    -- An unconfigured survivor takes the first configured plan
                    -- as its own so nothing configured is silently dropped.
                    if not record.configured and alternatives[1] then
                        record.settings=copy(alternatives[1].settings);record.configured=true
                        table.remove(alternatives,1)
                    end
                    local old=record.review and record.review.alternatives or {}
                    for _,a in ipairs(old) do if #alternatives<M.MAX_ALTERNATIVES then alternatives[#alternatives+1]=a end end
                    record.review={reason="merge",alternatives=alternatives}
                    record.revision=(record.revision or 1)+1
                end
                events[#events+1]={kind="merge",id=record.id,merged=#home-1,review=not same or nil}
            end
            settle(record,zone)
        elseif S[zi] and #S[zi]>0 then
            table.sort(S[zi],idless)
            local parent=source[S[zi][1]]
            record=newrecord(store,zone,opts)
            record.configured=parent.configured
            record.settings=copy(parent.settings)
            record.paused=parent.paused
            if parent.configured and parent.settings and parent.settings.mode=="exact" then record.review={reason="split",from=parent.id} end
            events[#events+1]={kind="split_piece",id=record.id,from=parent.id,review=record.review and true or nil}
            settle(record,zone)
        else
            -- Revive a gone record on the same ground, else a fresh record.
            local revive
            for _,rid in ipairs(rids) do
                local r=store.records[rid]
                if r and r.gone then
                    for _,t in ipairs(r.tiles or {}) do if zone.tileset[t] then revive=r;break end end
                end
                if revive then break end
            end
            if revive then record=revive;events[#events+1]={kind="revive",id=record.id}
            else record=newrecord(store,zone,opts);events[#events+1]={kind="new",id=record.id} end
            settle(record,zone)
        end
        ids[zi]=record.id
    end
    -- Records this scan did not match: drop only tiles the scan could see.
    local matched={};for _,id in pairs(ids) do matched[id]=true end
    for _,rid in ipairs(rids) do
        local r=store.records[rid]
        if r and not r.gone and not matched[rid] then
            local keep,lost={},false
            for _,t in ipairs(r.tiles or {}) do if scanned[t] then lost=true else keep[#keep+1]=t end end
            if lost then
                if #keep==0 then r.gone=true;events[#events+1]={kind="gone",id=rid}
                else r.tiles=keep;local has=false;for _,t in ipairs(keep) do if t==r.anchor then has=true end end;if not has then r.anchor=keep[1] end end
            end
        end
    end
    M.Prune(store)
    return ids,events
end
-- Keep the store bounded: gone records go first, oldest first.
function M.Prune(store,limit)
    limit=limit or M.MAX_RECORDS
    local all=sortedkeys(store.records);table.sort(all,idless)
    local n=#all
    for _,rid in ipairs(all) do
        if n<=limit then break end
        if store.records[rid].gone then store.records[rid]=nil;n=n-1 end
    end
    for _,rid in ipairs(all) do
        if n<=limit then break end
        if store.records[rid] then store.records[rid]=nil;n=n-1 end
    end
end
-- Load-time sanitation of a saved store.
function M.LoadStore(data)
    local store={records={},next_id=1}
    if type(data)~="table" then return store end
    store.next_id=math.max(1,math.floor(tonumber(data.next_id) or 1))
    for _,saved in pairs(type(data.records)=="table" and data.records or {}) do
        if type(saved)=="table" and type(saved.id)=="string" and idnum(saved.id)<math.huge then
            local r={id=saved.id,tiles={},anchor=nil,configured=saved.configured==true,settings=M.Sanitize(saved.settings),
                paused=saved.paused==true,revision=math.max(1,math.floor(tonumber(saved.revision) or 1)),slots={},
                slot_layout=type(saved.slot_layout)=="string" and saved.slot_layout or "",
                layout_epoch=math.max(0,math.floor(tonumber(saved.layout_epoch) or 0)),
                config_key=type(saved.config_key)=="string" and saved.config_key or nil,
                group_id=type(saved.group_id)=="string" and saved.group_id or nil,gone=saved.gone==true or nil}
            for _,t in ipairs(type(saved.tiles)=="table" and saved.tiles or {}) do if M.ParseTile(t) then r.tiles[#r.tiles+1]=t end end
            table.sort(r.tiles,M.TileLess)
            r.anchor=type(saved.anchor)=="string" and M.ParseTile(saved.anchor) and saved.anchor or r.tiles[1]
            for key,crop in pairs(type(saved.slots)=="table" and saved.slots or {}) do
                if type(key)=="string" and type(crop)=="string" and #crop<=40 then r.slots[key]=crop end
            end
            if not r.configured then r.settings=nil end
            if type(saved.review)=="table" then
                r.review={reason=saved.review.reason=="merge" and "merge" or "split",alternatives={}}
                for _,a in ipairs(type(saved.review.alternatives)=="table" and saved.review.alternatives or {}) do
                    local s=type(a)=="table" and M.Sanitize(a.settings)
                    if s and #r.review.alternatives<M.MAX_ALTERNATIVES then r.review.alternatives[#r.review.alternatives+1]={from=type(a.from)=="string" and a.from or nil,settings=s} end
                end
            end
            if #r.tiles>0 then
                store.records[r.id]=r
                store.next_id=math.max(store.next_id,idnum(r.id)+1)
            end
        end
    end
    M.Prune(store)
    return store
end
function M.SaveStore(store)
    local out={next_id=store.next_id,records={}}
    for _,rid in ipairs(sortedkeys(store.records)) do
        local r=store.records[rid]
        out.records[#out.records+1]={id=r.id,tiles=copy(r.tiles),anchor=r.anchor,configured=r.configured,settings=copy(r.settings),
            paused=r.paused,review=copy(r.review),revision=r.revision,slots=copy(r.slots),slot_layout=r.slot_layout,
            layout_epoch=r.layout_epoch,config_key=r.config_key,group_id=r.group_id,gone=r.gone}
    end
    return out
end
return M
