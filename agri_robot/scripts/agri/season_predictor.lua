-- Native stage duration is selected at stage entry. A current growable target
-- is already a wall-clock deadline and is never scaled again across a season.
local M={}
local STAGES={"seed","sprout","small","med"}
local function calendar_at(world,time)
    local season,left=world.season,world.season_remaining
    if not season or type(left)~="number" then return nil,"CALENDAR_UNAVAILABLE" end
    local elapsed,crossings=0,{}
    for _=1,256 do
        if time<left or left==math.huge then return {season=season,left=left-time,crossings=crossings} end
        time=time-left;elapsed=elapsed+left
        local following
        for i,name in ipairs(world.season_order or {}) do if name==season then following=world.season_order[i%#world.season_order+1];break end end
        if not following then return nil,"CALENDAR_UNAVAILABLE" end
        if world.uncertain or (world.random_seasons or {})[following] then return nil,"CALENDAR_UNCERTAIN" end
        local length=(world.season_lengths or {})[following]
        if not length or length<0 then return nil,"CALENDAR_UNAVAILABLE" end
        crossings[#crossings+1]={time=elapsed,from=season,to=following}
        season,left=following,length
    end
    return nil,"CALENDAR_UNAVAILABLE"
end
local function seasons_between(world,first,last)
    local start,err=calendar_at(world,first);if not start then return nil,err end
    local finish;finish,err=calendar_at(world,last);if not finish then return nil,err end
    local seen={[start.season]=true,[finish.season]=true}
    for _,crossing in ipairs(finish.crossings) do if crossing.time>=first then seen[crossing.to]=true end end
    return seen
end
local function advance_growing(world,start,amount,upper,night_light)
    if night_light then return start+amount end
    if not world.day then return start+amount end -- explicit pure injected clock
    if not world.growth_windows or not world.current_awake then return nil,"DAYLIGHT_CALENDAR_UNAVAILABLE" end
    local time=start;local remaining=amount;local day=world.day;local origin=(world.time_of_day or 0)*day
    for _=1,4096 do
        if remaining<=0.000001 then return time end
        local at,err=calendar_at(world,time);if not at then return nil,err end
        local window=world.growth_windows[at.season];if not window then return nil,"DAYLIGHT_CALENDAR_UNAVAILABLE" end
        local elapsed=(origin+time)%day
        local cutoff=(origin+time<day) and world.current_awake or upper and window.min_awake or window.max_awake
        local boundary=math.min(at.left,day-elapsed)
        if elapsed<cutoff then
            local advance=math.min(remaining,cutoff-elapsed,boundary)
            time=time+advance;remaining=remaining-advance
        else
            if cutoff<=0 and at.left==math.huge then return nil,"NO_DAYLIGHT_GROWTH" end
            time=time+math.max(0.000001,boundary)
        end
    end
    return nil,"DAYLIGHT_HORIZON_EXCEEDED"
end
function M.Predict(def,world,plant)
    plant=plant or {}
    if plant.mature then return {feasible=true,minimum=0,maximum=0,stages={},crossings={},risks={},oversized_eligible=true} end
    if not world or type(world.season_remaining)~="number" then return {feasible=false,reason="CALENDAR_UNAVAILABLE"} end
    local index=plant.stage==nil and 1 or nil
    for i,name in ipairs(STAGES) do if name==plant.stage then index=i;break end end
    if not index then return {feasible=false,reason="NO_REMAINING_GROWTH_STAGE"} end
    local earliest,latest,stages,risks=0,0,{},{}
    for i=index,#STAGES do
        local name=STAGES[i];local range=def.grow_time and def.grow_time[name]
        if not range then return {feasible=false,reason="GROWTH_DATA_UNAVAILABLE"} end
        local low,high=range.min or range[1],range.max or range[2]
        if not low or not high then return {feasible=false,reason="GROWTH_DATA_UNAVAILABLE"} end
        if i==index and type(plant.remaining)=="number" then
            low,high=math.max(0,plant.remaining),math.max(0,plant.remaining)
        else
            local possible,err=seasons_between(world,earliest,latest)
            if not possible then return {feasible=false,reason=err} end
            local minfactor,maxfactor=1,.5
            for season in pairs(possible) do local factor=(def.good_seasons or {})[season] and .5 or 1;minfactor=math.min(minfactor,factor);maxfactor=math.max(maxfactor,factor) end
            low,high=low*minfactor,high*maxfactor
        end
        local err
        earliest,err=advance_growing(world,earliest,low,false,plant.night_light)
        if not earliest then return {feasible=false,reason=err} end
        latest,err=advance_growing(world,latest,high,true,plant.night_light)
        if not latest then return {feasible=false,reason=err} end
        local checkpoint,err=seasons_between(world,earliest,latest)
        if not checkpoint then return {feasible=false,reason=err} end
        for season in pairs(checkpoint) do if not (def.good_seasons or {})[season] then risks[season]=true end end
        local ending=calendar_at(world,latest)
        stages[#stages+1]={stage=name,earliest=earliest,latest=latest,season=ending.season,checkpoint=true}
    end
    local ending,err=calendar_at(world,latest)
    if not ending then return {feasible=false,reason=err} end
    local risklist={};for season in pairs(risks) do risklist[#risklist+1]=season end;table.sort(risklist)
    return {feasible=true,minimum=earliest,maximum=latest,stages=stages,crossings=ending.crossings,risks=risklist,
        oversized_eligible=#risklist==0 and not world.calendar_uncertainty,reason=world.calendar_uncertainty and "DAY_LENGTH_MODIFIER_UNCERTAIN" or nil,
        assumptions=world.assumptions or {},night_pauses=world.day~=nil}
end
M.CalendarAt=calendar_at
M.AdvanceGrowing=advance_growing
function M.EnvironmentTimeline(world,horizon,base_drain,plant_drain,weather,night_drain)
    if not world.day or not world.growth_windows or not world.current_awake then return weather or {} end
    local time,intervals=0,{};local day=world.day;local origin=(world.time_of_day or 0)*day
    for _=1,4096 do
        if time>=horizon-0.000001 then return intervals end
        local at=calendar_at(world,time);if not at then return intervals end
        local window=world.growth_windows[at.season];if not window then return intervals end
        local phase=(origin+time)%day
        local cutoff=origin+time<day and world.current_awake or window.max_awake
        local awake=phase<cutoff
        local length=math.min(horizon-time,at.left,awake and cutoff-phase or day-phase)
        local rain,untiltime=0,0
        for _,entry in ipairs(weather or {}) do
            untiltime=untiltime+(entry.duration or 0)
            if time<untiltime-0.000001 then rain=entry.rain or 0;length=math.min(length,untiltime-time);break end
        end
        length=math.max(0.000001,length)
        intervals[#intervals+1]={duration=length,rain=rain,drain=base_drain+(awake and plant_drain or (night_drain or 0))}
        time=time+length
    end
    return intervals
end
return M
