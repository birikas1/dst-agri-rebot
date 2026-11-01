local C = require("agri/constants")
local U = require("agri/util")
local M = {}

function M.Settings(data, crops)
    if type(data)~="table" then return nil,"设置格式错误" end
    local out={}
    for key,value in pairs(data) do
        if key=="running" or key=="allow_random" or key=="continuous" then
            if type(value)~="boolean" then return nil,"开关参数错误" end
        elseif key=="radius" then
            if not U.Contains(C.RADII,value) then return nil,"半径无效" end
        elseif key=="mode" then
            if value~="stable" and value~="oversized" then return nil,"农业模式无效" end
        elseif key=="density" then
            if not U.Contains(C.DENSITIES,tostring(value)) then return nil,"密度无效" end
            value=tostring(value)
        elseif key=="plan" then
            if type(value)~="table" then return nil,"种植方案格式错误" end
            local clean,total={},0
            for crop,count in pairs(value) do
                if type(crop)~="string" or not (crops[crop] or crop=="randomseed") then return nil,"作物无效" end
                if not U.Finite(count) or count%1~=0 or count<0 or count>C.PLAN_MAX_PER_CROP then return nil,"作物数量无效" end
                total=total+count
                if total>C.PLAN_MAX_TOTAL then return nil,"种植方案过大" end
                if count>0 then clean[crop]=count end
            end
            value=clean
        elseif key=="planting" then
            if not U.Contains({"auto","crop","pause"},value) then return nil,"种植策略无效" end
        elseif key=="crop" then
            if type(value)~="string" or not crops[value] then return nil,"作物无效" end
        else return nil,"未知设置项" end
        out[key]=value
    end
    return out
end

function M.Preset(season,data,crops)
    if not U.Contains(C.SEASONS,season) or type(data)~="table" then return nil,"季节预设格式错误" end
    if not U.Contains({"auto","fixed","crop","ratio","pause"},data.mode) then return nil,"预设类型无效" end
    local out={mode=data.mode}
    if data.mode=="crop" then
        if not crops[data.crop] then return nil,"作物无效" end
        out.crop=data.crop
    elseif data.mode=="ratio" or data.mode=="fixed" then
        if type(data.ratio)~="table" then return nil,"请提供作物比例" end
        local total,types=0,0
        out.ratio={}
        for crop,count in pairs(data.ratio) do
            if not crops[crop] or not U.Finite(count) or count%1~=0 or count<1 or count>64 then return nil,"作物或比例无效" end
            total=total+count; types=types+1
            if total>128 or types>32 then return nil,"比例过大" end
            out.ratio[crop]=count
        end
        if total==0 then return nil,"比例不能为空" end
        if data.mode=="fixed" and type(data.candidate_id)=="string" and #data.candidate_id<256 then out.candidate_id=data.candidate_id end
    end
    -- A valid but suboptimal preset is saved; forecast warnings do not reject it.
    return out
end

-- Zone HUD requests (separate from the robot panel envelope):
--   {cmd="list"}                                   read-only badge list
--   {cmd="open"|"ping"|"close", zone="z<n>"}       editor lock
--   {cmd="save", zone, rev, settings={mode,density,weights,counts}}
--   {cmd="pause"|"resume"|"template", zone, rev}
-- Only the envelope is checked here; settings are validated by
-- field_zones.Clean and access/lock/revision by the registry.
M.ZONE_COMMANDS={list=true,open=true,ping=true,close=true,save=true,pause=true,resume=true,template=true}
M.ZONE_EDITS={save=true,pause=true,resume=true,template=true}
function M.ZoneRequest(value)
    if type(value)~="table" or type(value.cmd)~="string" or not M.ZONE_COMMANDS[value.cmd] then return false end
    for key in pairs(value) do
        if key~="cmd" and key~="zone" and key~="rev" and key~="settings" then return false end
    end
    if value.cmd=="list" then return value.zone==nil and value.rev==nil and value.settings==nil end
    if type(value.zone)~="string" or #value.zone>16 or not value.zone:match("^z%d+$") then return false end
    if M.ZONE_EDITS[value.cmd] then
        if not U.Finite(value.rev) or value.rev%1~=0 or value.rev<1 then return false end
        if value.cmd=="save" then return type(value.settings)=="table" end
        return value.settings==nil
    end
    return value.rev==nil and value.settings==nil
end

function M.Envelope(value)
    if type(value)~="table" or type(value.cmd)~="string" or #value.cmd>32 then return false end
    return U.Contains({"open","close","ping","settings","preset","preview","blueprint","fill","recalculate","range","visibility","warehouse","inventory","close_inventory","recommendations"},value.cmd)
end
return M
