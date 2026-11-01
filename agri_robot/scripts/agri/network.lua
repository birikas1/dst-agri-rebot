local C = require("agri/constants")
local U = require("agri/util")
local V = require("agri/rpc_validation")
local json = require("json")
local M = { NAMESPACE="agri_robot" }

local function definitions()
    return require("agri/source_adapter").GetCropDefs()
end

function M.Register(env)
    local G=env.GLOBAL
    local function reply(player,robot,data)
        local ok,encoded=pcall(json.encode,data)
        if not ok then return false end
        if #encoded>C.SNAPSHOT_MAX_BYTES then
            if data.snapshot then
                local current=data.snapshot
                local plan=current.plan or {}
                current.plan={status=plan.status,reasons=plan.reasons,summary=plan.summary}
                local tasks=current.tasks or {}
                current.tasks={counts=tasks.counts,paused=tasks.paused}
                current.detail_truncated=true
            end
            data.error="计划较大，请使用推荐分页查看。"
            ok,encoded=pcall(json.encode,data)
            if not ok then return false end
            if #encoded>C.SNAPSHOT_MAX_BYTES then
                -- Forecast/recommendation pages can themselves be large. Keep
                -- the management state, so an open reply never builds a broken
                -- screen with a missing snapshot.
                data.forecast=nil
                data.recommendations=nil
                data.warnings=nil
                if data.snapshot then
                    data.snapshot.resources={}
                    data.snapshot.metrics=nil
                end
                ok,encoded=pcall(json.encode,data)
                if not ok then return false end
            end
            if #encoded>C.SNAPSHOT_MAX_BYTES then
                return false
            end
        end
        G.SendModRPCToClient(G.GetClientModRPC(M.NAMESPACE,"snapshot"),player.userid,robot,encoded)
        return true
    end
    local function snapshot(reg,group)
        local data=reg:Snapshot(group)
        local crops={}
        for key,def in pairs(definitions()) do
            if not def.is_randomseed then crops[#crops+1]={id=key,seed=def.seed,product=def.product} end
        end
        table.sort(crops,function(a,b)return a.id<b.id end)
        crops[#crops+1]={id="randomseed",seed="seeds",random=true}
        data.crop_options=crops
        return data
    end
    local function open(player,robot)
        if not U.Valid(player) or not U.Valid(robot) or not robot:HasTag("agribot") then return false end
        local reg=G.TheWorld and G.TheWorld.components.agrifarmgroup
        if not reg then return false end
        local ok,reason=reg:AcquireLock(player,robot)
        if ok then
            if not reply(player,robot,{open=true,snapshot=snapshot(reg,reg:GetGroup(robot))}) then
                reg:ReleaseLock(player,robot)
                if player.components.talker then player.components.talker:Say("农场状态过大，暂时无法打开面板。") end
                return false
            end
        else
            if player.components.talker then player.components.talker:Say(reason) end
        end
        return ok
    end
    env.AddClientModRPCHandler(M.NAMESPACE,"snapshot",function(robot,encoded)
        if not G.ThePlayer or not G.ThePlayer.HUD or type(encoded)~="string" then return end
        local ok,data=pcall(json.decode,encoded)
        if not ok or type(data)~="table" then return end
        local panel=G.ThePlayer.HUD._agri_panel
        if data.open and U.Valid(robot) and type(data.snapshot)=="table" then
            -- A repeated open renews the same server lock. Closing this panel
            -- here would send CLOSE after that renewal and release the new lock.
            if panel and panel.robot==robot and not panel.closed then panel:Receive(data);return end
            if panel then panel:Close() end
            local Panel=require("screens/agribotpanel")
            panel=Panel(robot,data.snapshot,function(intent)
                G.SendModRPCToServer(G.GetModRPC(M.NAMESPACE,"intent"),robot,json.encode(intent))
            end)
            G.ThePlayer.HUD._agri_panel=panel
            G.TheFrontEnd:PushScreen(panel)
        elseif panel and panel.robot==robot then
            panel:Receive(data)
        end
    end)
    env.AddModRPCHandler(M.NAMESPACE,"intent",function(player,robot,encoded)
        if not U.Valid(player) or not U.Valid(robot) or not robot:HasTag("agribot") or type(encoded)~="string" or #encoded>C.RPC_MAX_BYTES then return end
        local reg=G.TheWorld and G.TheWorld.components.agrifarmgroup
        if not reg then return end
        local ok,request=pcall(json.decode,encoded)
        if not ok or not V.Envelope(request) then return end
        if request.cmd=="close" then reg:ReleaseLock(player,robot); return end
        if request.cmd=="close_inventory" then
            local container=robot.components.container
            if container and container.openlist[player] then container:Close(player) end
            return
        end
        if request.cmd=="open" then open(player,robot); return end
        if not reg:HasLock(player,robot) then reply(player,robot,{error="编辑锁已释放，请重新打开面板。",locked=false}); return end
        -- Allow a short burst (a heartbeat and a user click may share a frame)
        -- while keeping sustained expensive requests bounded.
        robot._agri_rpc_times=robot._agri_rpc_times or {}
        local time=G.GetTime()
        local budget=robot._agri_rpc_times[player.userid] or {time=time,tokens=5}
        budget.tokens=math.min(5,budget.tokens+math.max(0,time-budget.time)*10)
        budget.time=time
        robot._agri_rpc_times[player.userid]=budget
        if budget.tokens<1 then reply(player,robot,{error="操作过快，请稍后重试。"});return end
        budget.tokens=budget.tokens-1
        reg:AcquireLock(player,robot)
        local group=reg:GetGroup(robot)
        local result={}
        local cmd=request.cmd
        if cmd=="ping" then
            result.snapshot=snapshot(reg,group)
        elseif cmd=="settings" then
            local clean,reason=V.Settings(request.data,definitions())
            if clean then reg:UpdateSettings(group,clean) else result.error=reason end
        elseif cmd=="preset" or cmd=="preview" then
            local clean,reason=V.Preset(request.season,request.data,definitions())
            if clean then
                if cmd=="preset" then
                    group.presets[request.season]=clean
                    group.revision=group.revision+1
                    reg:MarkDirty(group,"preset")
                end
                local planner=group.primary.components.agriplanner
                if planner and planner.Preview then
                    local detail_page=tonumber(request.detail_page) or 1
                    if not U.Finite(detail_page) then detail_page=1 end
                    detail_page=math.max(1,math.min(10000,math.floor(detail_page)))
                    local success,forecast=pcall(function()return planner:Preview(group,request.season,clean,detail_page)end)
                    if success then result.forecast=forecast else result.error="模拟失败，请查看服务器日志";print("[AgriRobot] preview: "..tostring(forecast)) end
                end
            else result.error=reason end
        elseif cmd=="blueprint" then
            if not U.Finite(request.revision) or request.revision%1~=0 or request.revision~=group.revision then
                result.error="农场设置已更新，请刷新蓝图后再确认。"
            else
                local applied,reason=G.TheWorld.components.agriblueprint:Apply(group,request.cells)
                if not applied then result.error=reason else result.draft=U.Copy(group.blueprint.cells);result.draft_confirmed=true end
            end
        elseif cmd=="fill" then
            result.draft,result.warnings=G.TheWorld.components.agriblueprint:Fill(group)
        elseif cmd=="recalculate" then
            reg:MarkDirty(group,"blueprint_recalculate")
        elseif cmd=="visibility" then
            if type(request.visible)=="boolean" then group.blueprint.visible=request.visible end
        elseif cmd=="range" then
            result.range=true
        elseif cmd=="inventory" then
            local container=robot.components.container
            if container and (container.openlist[player] or container:CanOpen()) then
                container:Open(player)
                result.inventory_open=container.openlist[player]~=nil
                if not result.inventory_open then result.error="无法打开机器人库存，请靠近机器人后重试。" end
            else result.error="机器人库存正在使用" end
        elseif cmd=="warehouse" then
            local id=request.guid
            local warehouse=type(id)=="number" and G.Ents[id] or nil
            if U.Valid(warehouse) and warehouse:HasTag("agriwarehouse") and U.DistanceSq(group.center,{x=warehouse.Transform:GetWorldPosition(),z=select(3,warehouse.Transform:GetWorldPosition())})<=(group.settings.radius+8)^2 then
                reg:SetWarehouse(group,warehouse)
            else result.error="仓库不存在或不在附近" end
        elseif cmd=="recommendations" then
            local planner=group.primary.components.agriplanner
            local page=tonumber(request.page) or 1
            if not U.Finite(page) then page=1 end
            page=math.max(1,math.min(100000,math.floor(page)))
            if planner and planner.GetRecommendations then result.recommendations=planner:GetRecommendations(group,page,8) end
        end
        if not result.snapshot then result.snapshot=snapshot(reg,group) end
        if not reply(player,robot,result) then reply(player,robot,{error="状态数据过大，请缩小蓝图或切换分页重试。"}) end
    end)
    -- Zone HUD channel, separate from the robot panel: no robot entity, no
    -- robot lock. List replies are read-only and rate limited; editor
    -- commands need the server-side zone lock and current revision.
    local function zonereply(player,data)
        local ok,encoded=pcall(json.encode,data)
        if not ok then return false end
        if #encoded>C.ZONE_REPLY_MAX_BYTES and type(data.list)=="table" then
            while #data.list>0 and #encoded>C.ZONE_REPLY_MAX_BYTES do
                data.list[#data.list]=nil;data.truncated=true
                ok,encoded=pcall(json.encode,data)
                if not ok then return false end
            end
        end
        if #encoded>C.ZONE_REPLY_MAX_BYTES and type(data.detail)=="table" then
            data.detail.crops=nil;data.detail.withheld_reasons=nil;data.truncated=true
            ok,encoded=pcall(json.encode,data)
            if not ok then return false end
        end
        if #encoded>C.ZONE_REPLY_MAX_BYTES then return false end
        G.SendModRPCToClient(G.GetClientModRPC(M.NAMESPACE,"zones"),player.userid,encoded)
        return true
    end
    M.ZoneReply=zonereply
    env.AddClientModRPCHandler(M.NAMESPACE,"zones",function(encoded)
        if type(encoded)~="string" or #encoded>C.ZONE_REPLY_MAX_BYTES then return end
        local hud=G.ThePlayer and G.ThePlayer.HUD
        local widget=hud and hud.controls and hud.controls.agri_zone_hud
        if not widget then return end
        local ok,data=pcall(json.decode,encoded)
        if ok and type(data)=="table" then widget:Receive(data) end
    end)
    env.AddModRPCHandler(M.NAMESPACE,"zone",function(player,encoded)
        if not U.Valid(player) or type(player.userid)~="string" or type(encoded)~="string" or #encoded>C.ZONE_RPC_MAX_BYTES then return end
        local reg=G.TheWorld and G.TheWorld.components.agrifarmgroup
        if not reg then return end
        local ok,request=pcall(json.decode,encoded)
        if not ok or not V.ZoneRequest(request) then return end
        local time=G.GetTime()
        local budget=reg.zone_budget[player.userid] or {time=time,tokens=5,list_at=-math.huge}
        reg.zone_budget[player.userid]=budget
        local cmd,zid=request.cmd,request.zone
        if cmd=="list" then
            -- Read-only polling: at most one reply per interval per player.
            if time-budget.list_at<C.ZONE_LIST_INTERVAL then return end
            budget.list_at=time
            zonereply(player,{list=reg:ZoneList(player)})
            return
        end
        budget.tokens=math.min(5,budget.tokens+math.max(0,time-budget.time)*4)
        budget.time=time
        if budget.tokens<1 then zonereply(player,{zone=zid,error="操作过快，请稍后重试。"});return end
        budget.tokens=budget.tokens-1
        if cmd=="close" then reg:ReleaseZoneLock(player,zid);zonereply(player,{closed=zid});return end
        if cmd=="open" or cmd=="ping" then
            local acquired,why=reg:AcquireZoneLock(player,zid)
            if not acquired then zonereply(player,{zone=zid,error=why,closed=zid});return end
            local _,group=reg:ZoneAccess(player,zid)
            local detail=reg:ZoneDetail(zid,group)
            if not detail or not zonereply(player,{open=cmd=="open",detail=detail}) then
                reg:ReleaseZoneLock(player,zid);zonereply(player,{zone=zid,error="田块数据暂不可用。",closed=zid})
            end
            return
        end
        local saved,why,stale=reg:UpdateZone(player,zid,request.rev,cmd,request.settings)
        local _,group=reg:ZoneAccess(player,zid)
        local result={zone=zid,saved=saved or nil,error=not saved and why or nil,stale=stale or nil}
        if reg:HasZoneLock(player,zid) then result.detail=reg:ZoneDetail(zid,group) else result.closed=zid end
        zonereply(player,result)
    end)
    function M.SendZone(request)
        local ok,encoded=pcall(json.encode,request)
        if ok and #encoded<=C.ZONE_RPC_MAX_BYTES then G.SendModRPCToServer(G.GetModRPC(M.NAMESPACE,"zone"),encoded) end
    end
    local manage=env.AddAction("AGRI_MANAGE","管理农业机器人",function(act)return open(act.doer,act.target)end)
    manage.priority=10
    manage.rmb=true
    manage.distance=3
    env.AddComponentAction("SCENE","inspectable",function(inst,doer,actions,right)
        if right and inst:HasTag("agribot") then actions[#actions+1]=manage end
    end)
    env.AddStategraphActionHandler("wilson",G.ActionHandler(manage,"doshortaction"))
    env.AddStategraphActionHandler("wilson_client",G.ActionHandler(manage,"doshortaction"))
end
return M
