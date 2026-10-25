local M = {}
function M.Register(env)
    local G = env.GLOBAL or env
    local I, TECH = G.Ingredient, G.TECH
    local names = {
        AGRIBOT = "农业机器人", AGRIWAREHOUSE = "农业仓库",
        SUPER_PRESERVER_KIT = "超级保鲜套件", SCALE_THERMOSTAT_MODULE = "龙鳞恒温模块",
    }
    local descriptions = {
        AGRIBOT = "用真实工具照顾一片农田。",
        AGRIWAREHOUSE = "种子、肥料与作物各归其位。",
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
        TECH.SCIENCE_ONE, "gears", { placer = "agribot_placer" })
    add("agriwarehouse", { I("boards", 8) }, TECH.SCIENCE_ONE, "treasurechest",
        { placer = "agriwarehouse_placer", min_spacing = 1.5 })
    add("super_preserver_kit", { I("bearger_fur", 2), I("lunarplant_husk", 2), I("purebrilliance", 2), I("moonrocknugget", 8) },
        TECH.LUNARFORGING_TWO, "bearger_fur", { nounlock = true, station_tag = "lunar_forge" })
    add("scale_thermostat_module", { I("dragon_scales", 1), I("gears", 2) },
        TECH.SCIENCE_ONE, "dragon_scales")
end
return M
