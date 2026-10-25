local C = require("agri/constants")
local S = require("agri/storage")
local WHITE = {
    fumarolehammer = true, fumaroleaxe = true, fumarolepickaxe = true,
    fumaroleshovel = true, fumarole_farm_hoe = true,
}

local AgriThermal = Class(function(self, inst)
    self.inst = inst
    self.watched = {}
    self.native_clock = {}
    self._clamping = false
    self._task = inst:DoPeriodicTask(0.5, function() self:Refresh() end)
    for _, event in ipairs({ "itemget", "itemlose", "equip", "unequip" }) do
        inst:ListenForEvent(event, function()
            self:Refresh()
            inst:DoTaskInTime(0, function() self:Refresh() end)
        end)
    end
end)

function AgriThermal:HasModule()
    local container = self.inst.components.container
    local item = container and container:GetItemInSlot(C.MODULE_SLOT)
    return S.Valid(item) and item.prefab == "scale_thermostat_module"
end

function AgriThermal:Owns(item)
    local inventoryitem = S.Valid(item) and item.components.inventoryitem
    return inventoryitem ~= nil and inventoryitem:GetGrandOwner() == self.inst
end

function AgriThermal:IsWhitelisted(item)
    return item ~= nil and WHITE[item.prefab] == true
end

function AgriThermal:Clamp(item)
    if self._clamping or not self:HasModule() or not self:IsWhitelisted(item) or not self:Owns(item) then return end
    local inventoryitem = item.components.inventoryitem
    if inventoryitem:GetTemperature() ~= C.THERMOSTAT_TEMPERATURE then
        self._clamping = true
        inventoryitem:SetTemperature(C.THERMOSTAT_TEMPERATURE)
        self._clamping = false
    end
end

function AgriThermal:Refresh()
    local owned,current = {},{}
    local function collect(items)
        for _, item in pairs(items or {}) do
            if self:IsWhitelisted(item) and self:Owns(item) then owned[item] = true end
        end
    end
    collect(self.inst.components.container and self.inst.components.container.slots)
    collect(self.inst.components.inventory and self.inst.components.inventory.itemslots)
    collect(self.inst.components.inventory and self.inst.components.inventory.equipslots)
    local active=self.inst.components.inventory and self.inst.components.inventory.activeitem
    if active and self:IsWhitelisted(active) and self:Owns(active) then owned[active]=true end
    local module=self:HasModule()
    if module then current=owned end
    for item, fn in pairs(self.watched) do
        if not current[item] then
            self.inst:RemoveEventCallback("temperaturedelta", fn, item)
            self.watched[item] = nil
        end
    end
    for item in pairs(current) do
        if not self.watched[item] then
            local fn = function() self:Clamp(item) end
            self.watched[item] = fn
            self.inst:ListenForEvent("temperaturedelta", fn, item)
        end
        self:Clamp(item)
    end
    local time=GetTime and GetTime() or 0
    for item in pairs(self.native_clock) do if not owned[item] then self.native_clock[item]=nil end end
    for item in pairs(owned) do
        local last=self.native_clock[item]
        self.native_clock[item]=time
        -- One owner drives passive environmental heat/cooling, including while
        -- scheduling is paused. Event refreshes in the same frame have dt=0.
        if not module and last then self:UpdateOwnedTemperature(item,math.max(0,time-last)) end
        local temperature=item.components.inventoryitemtemperature
        if temperature and temperature.temperatureupdatetask==nil and item.IsInLimbo and item:IsInLimbo() then
            -- Native wake catches up from _entitysleeptime. Its own sleep hook
            -- refreshes that timestamp after the owner already simulated time,
            -- so returning this item to the world cannot apply the interval twice.
            temperature:OnEntitySleep()
        end
    end
end

function AgriThermal:NeedsHeat(item)
    local thermal = S.Valid(item) and item.components.fumaroletool
    if not thermal then return false end
    if self:HasModule() then self:Clamp(item) end
    return thermal.broken == true
end

function AgriThermal:HeatReady(item)
    local thermal = S.Valid(item) and item.components.fumaroletool
    if not thermal then return true end
    local temp = item.components.inventoryitem:GetTemperature()
    local thresholds = TUNING.FUMAROLETOOL_TEMPS
    return not thermal.broken and temp >= thresholds[4]
end

function AgriThermal:UpdateOwnedTemperature(item, elapsed)
    if not self:IsWhitelisted(item) or not self:Owns(item) or self:HasModule() then return false end
    local temperature=item.components.inventoryitemtemperature
    if not temperature or elapsed<=0 then return false end
    -- Inventory items are in LIMBO; native OnEntitySleep cancels their standalone
    -- updater. Drive the original environmental simulation for this real owned
    -- tool, and never double-drive a live native updater.
    if temperature.temperatureupdatetask~=nil then return false end
    return temperature:UpdateTemperature(elapsed)
end

function AgriThermal:FindFurnace(group)
    if S.Valid(self.furnace) and self.furnace.prefab == "dragonflyfurnace" then return self.furnace end
    local x, _, z = self.inst.Transform:GetWorldPosition()
    local radius = group and group.settings.radius or C.DEFAULT_RADIUS
    local candidates = TheSim:FindEntities(x, 0, z, radius + 8, { "HASHEATER" }, { "INLIMBO" })
    local nearest, distance
    for _, furnace in ipairs(candidates) do
        if furnace.prefab == "dragonflyfurnace" then
            local d = self.inst:GetDistanceSqToInst(furnace)
            if not distance or d < distance then nearest, distance = furnace, d end
        end
    end
    self.furnace = nearest
    return nearest
end

function AgriThermal:OnSave()
    if S.Valid(self.furnace) then return { furnace = self.furnace.GUID }, { self.furnace.GUID } end
end

function AgriThermal:LoadPostPass(newents, data)
    local entry = data and data.furnace and newents[data.furnace]
    if entry and S.Valid(entry.entity) and entry.entity.prefab == "dragonflyfurnace" then self.furnace = entry.entity end
    self:Refresh()
end

function AgriThermal:OnRemoveFromEntity()
    if self._task then self._task:Cancel() end
    for item, fn in pairs(self.watched) do self.inst:RemoveEventCallback("temperaturedelta", fn, item) end
    self.watched = {}
    self.native_clock = {}
end

return AgriThermal
