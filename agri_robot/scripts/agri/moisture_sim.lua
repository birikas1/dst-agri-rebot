local M={}
local EPS=0.000001
-- The no-irrigation trajectory respects the native soil cap. Every checkpoint
-- is a segment boundary, so shared hydration requirements are prefix constraints.
local function trajectory(tile,horizon,checkpoints)
    local boundaries={0,horizon};local elapsed=0
    for _,weather in ipairs(tile.weather or {}) do elapsed=elapsed+(weather.duration or 0);if elapsed>0 and elapsed<horizon then boundaries[#boundaries+1]=elapsed end end
    for _,time in ipairs(checkpoints or {}) do if time>0 and time<horizon then boundaries[#boundaries+1]=time end end
    table.sort(boundaries)
    local times={};for _,time in ipairs(boundaries) do if times[#times]~=time then times[#times+1]=time end end
    local water=math.max(0,math.min(tile.capacity or math.huge,tile.moisture or 0));local wet=0;local segments={}
    for i=1,#times-1 do
        local start,finish=times[i],times[i+1];local duration=finish-start;local rain=0;local drain=tile.drain or 0;local untiltime=0
        for _,weather in ipairs(tile.weather or {}) do
            untiltime=untiltime+(weather.duration or 0)
            if start<untiltime-EPS then rain=weather.rain or 0;drain=weather.drain or drain;break end
        end
        local rate=drain-rain
        local hydrated
        if rate>0 then hydrated=math.min(duration,water/rate)
        elseif water>0 or rate<0 then hydrated=duration
        else hydrated=0 end
        local segment={start=start,finish=finish,wet_before=wet,wet=hydrated,dry_start=start+hydrated,
            dry=math.max(0,duration-hydrated),rate=math.max(EPS,rate),selected=0}
        segments[#segments+1]=segment;wet=wet+hydrated
        water=math.max(0,math.min(tile.capacity or math.huge,water-rate*duration))
    end
    return segments,wet,water
end
function M.Project(tile,seconds,added)
    local input={};for k,v in pairs(tile) do input[k]=v end;input.moisture=(tile.moisture or 0)+(added or 0)
    local _,wet,water=trajectory(input,math.max(0,seconds),{})
    return wet,water
end
local function hydrated_at(segments,time)
    local wet=0
    for _,segment in ipairs(segments) do
        wet=wet+math.max(0,math.min(segment.wet,time-segment.start))
        -- Irrigation occupies the selected suffix of a dry interval.
        wet=wet+math.max(0,math.min(segment.selected,time-(segment.finish-segment.selected)))
    end
    return wet
end
local function already_safe(segments,p)
    local function safe_at(time)
        return p.hydrated+hydrated_at(segments,time)+EPS>=p.minimum_percent*(p.elapsed+time)
    end
    if not safe_at(p.earliest) or not safe_at(p.remaining) then return false end
    -- Hydration and the required wet time are linear between these boundaries.
    -- Checking only the latest checkpoint could overlook an earlier dry spell
    -- followed by rain, while freezing the earliest dry budget can overwater a
    -- plant whose accumulated hydration already covers the whole interval.
    for _,segment in ipairs(segments) do
        for _,time in ipairs({segment.start,segment.start+segment.wet,
                segment.finish-segment.selected,segment.finish}) do
            if time>p.earliest and time<p.remaining and not safe_at(time) then return false end
        end
    end
    return true
end
function M.Predict(tile,plants)
    if type(tile.moisture)~="number" or type(tile.drain)~="number" then
        return {feasible=false,reason="MOISTURE_DATA_UNAVAILABLE",water=0,uses=0,plants={},assumptions={"NO_UNVERIFIED_RAIN_CREDIT"}}
    end
    local constraints,checkpoints={},{};local horizon=0
    for _,plant in ipairs(plants or {}) do
        local timing=plant.moisture or {}
        local remaining=math.max(0,plant.remaining or (plant.growth and plant.growth.stages[1] and plant.growth.stages[1].latest) or 0)
        local earliest=plant.growth and plant.growth.stages[1] and plant.growth.stages[1].earliest or remaining
        constraints[#constraints+1]={id=plant.id,remaining=remaining,earliest=math.max(0,math.min(remaining,earliest)),elapsed=timing.elapsed or 0,hydrated=timing.hydrated or 0,
            minimum_percent=(plant.def.moisture or {}).min_percent or 0}
        checkpoints[#checkpoints+1]=remaining;horizon=math.max(horizon,remaining)
    end
    table.sort(constraints,function(a,b) if a.remaining==b.remaining then return tostring(a.id)<tostring(b.id) end return a.remaining<b.remaining end)
    local segments=trajectory(tile,horizon,checkpoints)
    local feasible,minimum,first_due=true,0,math.huge
    for _,p in ipairs(constraints) do
        local baseline,selected=0,0;local available={}
        for _,segment in ipairs(segments) do if segment.finish<=p.remaining+EPS then
            baseline=baseline+segment.wet;selected=selected+segment.selected
            if segment.dry-segment.selected>EPS then available[#available+1]=segment end
        end end
        local denominator=p.elapsed+p.remaining
        p.predicted_percent=denominator>0 and (p.hydrated+baseline)/denominator or 1
        p.recoverable=p.elapsed+p.earliest==0 or p.hydrated+p.earliest+EPS>=p.minimum_percent*(p.elapsed+p.earliest)
        if not p.recoverable then feasible=false end
        -- If the native checkpoint can fall anywhere in [earliest, latest],
        -- keep its earliest dry-time allowance for the entire uncertainty
        -- interval. This cannot postpone irrigation past an earlier checkpoint.
        local required=already_safe(segments,p) and 0 or math.max(0,
            p.minimum_percent*(p.elapsed+p.earliest)-p.hydrated+(p.remaining-p.earliest))
        local deficit=math.max(0,required-baseline-selected)
        p.required_wet_seconds=required
        -- Nested checkpoint requirements: cheapest available dry intervals first
        -- is an exact fractional minimum for the stated piecewise weather model.
        -- Ties use later intervals, leaving room for rain to remove the need.
        table.sort(available,function(a,b) if a.rate==b.rate then return a.finish>b.finish end return a.rate<b.rate end)
        p.water=0
        for _,segment in ipairs(available) do
            local take=math.min(deficit,segment.dry-segment.selected)
            if take>EPS then
                local due=segment.finish-segment.selected-take
                first_due=math.min(first_due,due);minimum=minimum+take*segment.rate;p.water=p.water+take*segment.rate
                segment.selected=segment.selected+take;deficit=deficit-take
            end
            if deficit<=EPS then break end
        end
        if deficit>EPS then feasible=false end
        p.due=first_due<math.huge and first_due or nil
    end
    local peruse=tile.water_per_use
    local effective=peruse and math.min(peruse,tile.capacity or math.huge)
    local uses=minimum>EPS and effective and effective>0 and math.ceil(minimum/effective-0.000000001) or 0
    if minimum>EPS and (not peruse or peruse<=0) then feasible=false end
    local room=tile.capacity and math.max(0,tile.capacity-(tile.moisture or 0)) or minimum
    local schedule={}
    for _,segment in ipairs(segments) do if segment.selected>EPS then
        schedule[#schedule+1]={start=segment.finish-segment.selected,finish=segment.finish,water=segment.selected*segment.rate}
    end end
    return {feasible=feasible,reason=not feasible and ((not peruse or peruse<=0) and "MISSING_WATERING_CAN" or "MOISTURE_CHECKPOINT_UNRECOVERABLE") or nil,
        water=minimum,uses=uses,plants=constraints,soil=tile.moisture,drain=tile.drain,weather=tile.weather or {},
        due=first_due<math.huge and first_due or nil,repeated=minimum>room,now_water=math.min(minimum,room),schedule=schedule,
        assumptions={"NO_UNVERIFIED_FUTURE_RAIN_CREDIT","SOIL_CAP_ENFORCED","PIECEWISE_RATE_MINIMUM","EARLIEST_CHECKPOINT_DRY_BUDGET"}}
end
return M
