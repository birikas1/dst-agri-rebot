require("stategraphs/commonstates")
local events={CommonHandlers.OnLocomote(true,false)}
local states={
    State{name="idle",tags={"idle","canrotate"},onenter=function(inst)
        inst.components.locomotor:StopMoving()
        inst.AnimState:PlayAnimation("idle",true)
    end},
    State{name="agri_work",tags={"busy"},onenter=function(inst)
        inst.components.locomotor:StopMoving()
        inst.AnimState:PlayAnimation("pickup")
        inst.sg:SetTimeout(1.2)
        inst.sg.statemem.action=inst:GetBufferedAction()
    end,
    timeline={TimeEvent(10*FRAMES,function(inst)
        inst.sg.statemem.performed=true
        inst:PerformBufferedAction()
    end)},
    events={EventHandler("animover",function(inst) inst.sg:GoToState("idle") end)},
    ontimeout=function(inst) inst.sg:GoToState("idle") end,
    onexit=function(inst)
        if not inst.sg.statemem.performed and inst:GetBufferedAction()==inst.sg.statemem.action then inst:ClearBufferedAction() end
    end},
}
-- The native Winona robot has run_pre/run_loop/run_pst, not walk animations.
CommonStates.AddRunStates(states)
local handlers={}
for _, name in ipairs({"WALKTO","DEPLOY","DEPLOY_TILEARRIVE","TILL","PLANTSOIL","POUR_WATER_GROUNDTILE",
    "INTERACT_WITH","PICK","HAMMER","PICKUP","FILL","DIG"}) do
    if ACTIONS[name] then handlers[#handlers+1]=ActionHandler(ACTIONS[name],"agri_work") end
end
return StateGraph("agribot",states,events,"idle",handlers)
