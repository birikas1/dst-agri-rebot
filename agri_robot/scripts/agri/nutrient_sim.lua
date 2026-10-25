local M = {}
local function vec(v) return { v and v[1] or 0, v and v[2] or 0, v and v[3] or 0 } end
local function recovery(def)
    local c, r, total, n = def.nutrient_consumption or {}, {}, 0, 0
    for i = 1, 3 do total = total + (c[i] or 0); if (def.nutrient_restoration or {})[i] then n = n + 1 end end
    for i = 1, 3 do r[i] = n > 0 and (def.nutrient_restoration or {})[i] and math.floor(total / n) or 0 end
    return r
end
-- Overlapping checkpoint ranges form a conservative window. Every consumer in
-- that window runs before any restorer, including uncertain native RNG remainders.
function M.Events(assignment)
    local events = {}
    for _, crop in ipairs(assignment or {}) do
        for _, stage in ipairs(crop.growth and crop.growth.stages or {}) do
            if stage.checkpoint then events[#events + 1] = { earliest = stage.earliest, latest = stage.latest,
                crop = crop.id, stage = stage.stage, consumption = vec(crop.def.nutrient_consumption), restoration = recovery(crop.def) } end
        end
    end
    table.sort(events, function(a,b) if a.earliest == b.earliest then return tostring(a.crop) < tostring(b.crop) end return a.earliest < b.earliest end)
    local windows = {}
    for _, event in ipairs(events) do
        local w = windows[#windows]
        if not w or event.earliest > w.latest then w = { earliest = event.earliest, latest = event.latest, events = {}, consumption = {0,0,0}, restoration = {0,0,0} }; windows[#windows + 1] = w end
        w.latest = math.max(w.latest, event.latest)
        w.events[#w.events + 1] = event
        for i = 1, 3 do w.consumption[i] = w.consumption[i] + event.consumption[i]; w.restoration[i] = w.restoration[i] + event.restoration[i] end
    end
    return windows
end
function M.Simulate(assignment, soil, capacity)
    capacity = capacity or math.huge
    local pools, minima, deficit, net = vec(soil), vec(soil), {0,0,0}, {0,0,0}
    local windows, topups = M.Events(assignment), {}
    local feasible = true
    for index, w in ipairs(windows) do
        w.before, w.deficit = vec(pools), {0,0,0}
        for i = 1, 3 do
            w.deficit[i] = math.max(0, w.consumption[i] - pools[i])
            deficit[i] = deficit[i] + w.deficit[i]
            if w.consumption[i] > capacity then feasible = false end
            pools[i] = pools[i] + w.deficit[i] - w.consumption[i]
            minima[i] = math.min(minima[i], pools[i])
            pools[i] = math.min(capacity, pools[i] + w.restoration[i])
            net[i] = net[i] + w.restoration[i] - w.consumption[i]
        end
        w.after = vec(pools)
        if w.deficit[1] + w.deficit[2] + w.deficit[3] > 0 then topups[#topups + 1] = { window = index, before = w.earliest, deficit = vec(w.deficit) } end
    end
    return { feasible = feasible, reason = not feasible and "NUTRIENT_WINDOW_EXCEEDS_CAPACITY" or nil,
        windows = windows, minimum = minima, deficit = deficit, final = pools, net = net, topups = topups,
        assumptions = { "OVERLAPPING_CHECKPOINT_CONSUMPTION_FIRST", "RANDOM_RESTORATION_REMAINDER_IGNORED" } }
end
-- Recompute against a proposed actual fertilizer supply, including soil caps.
function M.Apply(pools, supplied, capacity)
    local result = {}; for i = 1, 3 do result[i] = math.min(capacity or math.huge, (pools[i] or 0) + (supplied[i] or 0)) end; return result
end
return M
