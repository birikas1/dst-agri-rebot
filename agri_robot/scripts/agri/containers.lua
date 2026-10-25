local C = require("agri/constants")
local S = require("agri/storage")
local M = {}

function M.Register(env)
    local G = env.GLOBAL or env
    local containers = require("containers")
    local Vector3 = G.Vector3
    local robot = {
        widget = { slotpos = {}, bgatlas = "images/global.xml", bgimage = "square.tex",
            pos = Vector3(0, 180, 0), side_align_tip = 160 },
        type = "chest", itemtestfn = S.RobotTest, openlimit = 1, acceptsstacks = true,
        usespecificslotsforitems = true,
    }
    for row = 0, 2 do
        for col = 0, 5 do robot.widget.slotpos[#robot.widget.slotpos + 1] = Vector3((col - 2.5) * 72, 102 - row * 72, 0) end
    end
    for col = 0, 4 do robot.widget.slotpos[#robot.widget.slotpos + 1] = Vector3((col - 2) * 72, -250, 0) end
    robot.widget.slotpos[C.MODULE_SLOT] = Vector3(0, 210, 0)
    -- Five visible tools 26..30, centred. Legacy slot 25 keeps a position
    -- beside the module so an unmigrated old plow is never invisible.
    robot.widget.slotpos[C.LEGACY_PLOW_SLOT] = Vector3(-160, 210, 0)
    for col=0,4 do robot.widget.slotpos[C.TOOL_FIRST+col]=Vector3((col-2)*72,-145,0) end
    local warehouse = {
        widget = { slotpos = {}, bgatlas = "images/global.xml", bgimage = "square.tex",
            pos = Vector3(0, 180, 0), side_align_tip = 160 },
        type = "chest", itemtestfn = S.WarehouseTest, openlimit = 1, acceptsstacks = true,
        usespecificslotsforitems = true,
    }
    local function section(cols, rows, left)
        for row = 0, rows - 1 do
            for col = 0, cols - 1 do
                warehouse.widget.slotpos[#warehouse.widget.slotpos + 1] = Vector3(left + col * 68, 108 - row * 68, 0)
            end
        end
    end
    section(3, 4, -400)
    section(3, 4, -176)
    section(6, 4, 48)
    warehouse.widget.slotpos[C.WAREHOUSE_MODULE_SLOT] = Vector3(0, 220, 0)
    containers.params.agribot = robot
    containers.params.agriwarehouse = warehouse
    containers.MAXITEMSLOTS = math.max(containers.MAXITEMSLOTS or 0, C.WAREHOUSE_MODULE_SLOT)
    if env.AddClassPostConstruct then
        env.AddClassPostConstruct("widgets/containerwidget", function(widget)
            local open, close = widget.Open, widget.Close
            local function clear(self)
                for _, child in ipairs(self._agri_decoration or {}) do child:Kill() end
                self._agri_decoration = nil
            end
            widget.Open = function(self, container, doer, ...)
                clear(self)
                local result = open(self, container, doer, ...)
                if container.prefab ~= "agribot" and container.prefab ~= "agriwarehouse" then return result end
                local Image, Text = require("widgets/image"), require("widgets/text")
                self._agri_decoration = {}
                local function remember(child)
                    self._agri_decoration[#self._agri_decoration + 1] = child
                    return child
                end
                local function panel(x, y, w, h)
                    local backdrop = remember(self:AddChild(Image("images/global.xml", "square.tex")))
                    backdrop:SetPosition(x, y)
                    backdrop:SetSize(w, h)
                    backdrop:SetTint(0.08, 0.105, 0.075, 0.95)
                    if backdrop.SetClickable then backdrop:SetClickable(false) end
                    backdrop:MoveToBack()
                end
                local function label(x, y, value)
                    local text = remember(self:AddChild(Text(G.BODYTEXTFONT, 24, value)))
                    text:SetPosition(x, y)
                    text:SetColour(0.89, 0.84, 0.66, 1)
                end
                if self.bgimage and self.bgimage.Hide then self.bgimage:Hide() end
                if container.prefab == "agriwarehouse" then
                    panel(0, 49, 896, 440)
                    label(-332, 158, "种子 ×12")
                    label(-108, 158, "肥料 ×12")
                    label(218, 158, "作物/回收物 ×24")
                    label(0, 274, "仓库升级")
                else
                    panel(0, -15, 470, 660)
                    label(0, 158, "工作库存 ×18")
                    for col=0,4 do
                        local t=remember(self:AddChild(Text(G.BODYTEXTFONT,18,C.TOOL_NAMES[col+1])))
                        t:SetPosition((col-2)*72,-96)
                    end
                    label(0, -199, "水壶 ×5")
                    label(0, 262, "恒温模块")
                    -- Shown only while an old save's plow still waits there to
                    -- be moved to work inventory or the warehouse.
                    local legacy = self.inv and self.inv[C.LEGACY_PLOW_SLOT]
                    local replica = container.replica and container.replica.container
                    if legacy then
                        if replica and replica:GetItemInSlot(C.LEGACY_PLOW_SLOT) then
                            legacy:Show()
                            local t=remember(self:AddChild(Text(G.BODYTEXTFONT,18,"旧耕地机·待入库")))
                            t:SetPosition(-160,262)
                            t:SetColour(0.89, 0.84, 0.66, 1)
                        else
                            legacy:Hide()
                        end
                    end
                end
                return result
            end
            widget.Close = function(self, ...)
                clear(self)
                return close(self, ...)
            end
        end)
    end
end

return M
