require("behaviours/doaction")
require("behaviours/standstill")
local AgriBotBrain = Class(Brain,function(self,inst) Brain._ctor(self,inst) end)
function AgriBotBrain:OnStart()
    local root = PriorityNode({
        DoAction(self.inst,function(inst)
            local executor=inst.components.agriexecutor
            return executor and executor:GetAction() or nil
        end,"Agriculture",true,require("agri/constants").TASK_TIMEOUT),
        StandStill(self.inst),
    },0.25)
    self.bt=BT(self.inst,root)
end
return AgriBotBrain
