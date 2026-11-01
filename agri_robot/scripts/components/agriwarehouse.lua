local C = require("agri/constants")
local S = require("agri/storage")
local AgriWarehouse = Class(function(self, inst)
    self.inst = inst
    self.mode = "ordinary"
    local container = inst.components.container
    local original_open = container.Open
    container.Open = function(c, player, ...)
        if not S.Valid(player) or player:HasTag("playerghost") then return end
        if inst:GetDistanceSqToInst(player) > C.INTERACT_DISTANCE * C.INTERACT_DISTANCE then return end
        if not c.openlist[player] and not c:CanOpen() then return end
        return original_open(c, player, ...)
    end
    inst:ListenForEvent("itemget", function() self:Refresh(true) end)
    inst:ListenForEvent("itemlose", function() self:Refresh(true) end)
    self._watch = inst:DoPeriodicTask(1, function()
        for _, player in ipairs(container:GetOpeners()) do
            if not S.Valid(player) or player:HasTag("playerghost")
                or not player.userid or inst:GetDistanceSqToInst(player) > C.INTERACT_DISTANCE * C.INTERACT_DISTANCE then
                container:Close(player)
            end
        end
        self:Refresh()
    end)
    inst:DoTaskInTime(0, function() self:Refresh() end)
end)

function AgriWarehouse:Refresh(changed)
    local item = self.inst.components.container:GetItemInSlot(C.WAREHOUSE_MODULE_SLOT)
    local mode = item and item.prefab == "bluegem" and "fridge"
        or item and item.prefab == "super_preserver_kit" and "super" or "ordinary"
    if mode ~= self.mode then
        changed = true
        self.mode = mode
        if self.inst.components.preserver then self.inst:RemoveComponent("preserver") end
        self.inst:RemoveTag("fridge")
        if mode == "fridge" then
            self.inst:AddTag("fridge")
        elseif mode == "super" then
            self.inst:AddComponent("preserver")
            self.inst.components.preserver:SetPerishRateMultiplier(function()
                return TUNING.BEARGERFUR_SACK_PRESERVER_RATE
            end)
        end
    end
    local registry = TheWorld.components.agrifarmgroup
    if changed and registry then
        for _, group in pairs(registry.groups) do
            if group.warehouse == self.inst then registry:MarkDirty(group, "resources") end
        end
    end
end

function AgriWarehouse:GetStatus()
    local container = self.inst.components.container
    local out = { mode = self.mode, groups = {} }
    for _, name in ipairs({ "seed", "fertilizer", "crop", "hoe", "shovel", "hammer", "axe", "pickaxe", "water" }) do
        local lo, hi = S.WarehouseRange(name)
        out.groups[name] = { capacity = hi - lo + 1, free = S.FreeSlots(container, lo, hi) }
    end
    return out
end

function AgriWarehouse:OnLoad()
    self.inst:DoTaskInTime(0, function() self:Refresh() end)
end

function AgriWarehouse:OnRemoveFromEntity()
    if self._watch then self._watch:Cancel() end
end

return AgriWarehouse
