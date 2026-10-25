GetTime=function()return 100 end
Class=function(ctor)
    local c={};c.__index=c
    return setmetatable(c,{__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end})
end
package.preload.bufferedaction=function()return true end
local Executor=require("components/agriexecutor")
local completed,returned=0,0
local group={settings={running=true},primary=nil}
group.scheduler={Complete=function()completed=completed+1 end,Release=function()end}
TheWorld={components={agrifarmgroup={GetGroup=function()return group end,MarkDirty=function()end}}}
local inst={GUID=1,components={agriresource={Finish=function()returned=returned+1;return true end}},
    DoPeriodicTask=function()return {Cancel=function()end}end}
local e=Executor(inst)
e.current={id="fertilize",kind="FERTILIZE"}
e.result={success=true,subkind="native"}
-- The native action already spent fertilizer. Pausing before the next half-
-- second executor tick must acknowledge it instead of repeating it on resume.
e:Interrupt("emergency",true)
assert(completed==1,"successful native action was discarded during interrupt")
assert(e.current==nil and e.result==nil)
e:Interrupt("emergency",true)
assert(completed==1,"interrupt completed the same action twice")
e.current={id="not-yet-planted",kind="PLANT"}
e.pending={};e.result=nil
e:Interrupt("player_edit",true)
assert(completed==1,"unexecuted action was falsely acknowledged")
return "committed action is recorded exactly once across interruption"
