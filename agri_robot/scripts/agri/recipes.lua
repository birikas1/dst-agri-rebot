local Range = require("agri/work_range")
local M = {}
function M.Register(env)
    local G = env.GLOBAL or env
    local I, TECH = G.Ingredient, G.TECH
    local names = {
        AGRIBOT = "农业机器人", AGRIWORKCENTER = "农业工作中心", AGRIWAREHOUSE = "农业仓库", AGRIWELL = "水井",
        SUPER_PRESERVER_KIT = "超级保鲜套件", SCALE_THERMOSTAT_MODULE = "龙鳞恒温模块",
    }
    local descriptions = {
        AGRIBOT = "只能放在农业工作中心范围内；用真实工具照顾农田。",
        AGRIWORKCENTER = "先放中心，再在圈内放机器人；悬停显示工作范围。",
        AGRIWAREHOUSE = "种子、肥料、作物和备用工具各归其位。",
        AGRIWELL = "固定淡水源，供机器人和水壶补水。",
        SUPER_PRESERVER_KIT = "让农业仓库使用极地熊獾箱保鲜机制。",
        SCALE_THERMOSTAT_MODULE = "将机器人持有的热能工具维持在70°C。",
    }
    for key, value in pairs(names) do
        G.STRINGS.NAMES[key] = value
        G.STRINGS.RECIPE_DESC[key] = descriptions[key]
        G.STRINGS.CHARACTERS.GENERIC.DESCRIBE[key] = descriptions[key]
    end
    local function add(name, ingredients, tech, image, extra, filters)
        -- Leave atlas unset: Recipe:GetAtlas() resolves the vanilla inventory atlas
        -- lazily on clients, so dedicated servers do not probe UI atlases at load.
        local config = { image = image .. ".tex" }
        for key, value in pairs(extra or {}) do config[key] = value end
        env.AddRecipe2(name, ingredients, tech, config, filters or { "GARDENING" })
    end
    add("agribot", { I("gears", 2), I("boards", 3), I("goldnugget", 4) },
        TECH.SCIENCE_ONE, "winona_storage_robot",
        -- Only inside an existing work center's radius (client placer + server build).
        { placer = "agribot_placer", testfn = Range.RobotPlacementTest })
    -- Vanilla mini sign recipe icon is minisign_item.tex (there is no minisign.tex).
    add("agriworkcenter", { I("boards", 1) }, TECH.SCIENCE_ONE, "minisign_item",
        { placer = "agriworkcenter_placer", min_spacing = 1, testfn = Range.CenterPlacementTest })
    add("agriwarehouse", { I("boards", 8) }, TECH.SCIENCE_ONE, "treasurechest_cotl_basic",
        { placer = "agriwarehouse_placer", min_spacing = 1.5 })
    add("agriwell", { I("cutstone", 6), I("boards", 4), I("rope", 2) }, TECH.SCIENCE_ONE, "agriwell",
        { placer="agriwell_placer", min_spacing=2, atlas="images/inventoryimages/agriwell.xml" })
    add("super_preserver_kit", { I("bearger_fur", 2), I("lunarplant_husk", 2), I("purebrilliance", 2), I("moonrocknugget", 8) },
        TECH.LUNARFORGING_TWO, "bearger_fur", { nounlock = true, station_tag = "lunar_forge" })
    add("scale_thermostat_module", { I("dragon_scales", 1), I("gears", 2) },
        TECH.SCIENCE_ONE, "dragon_scales")
end
return M
