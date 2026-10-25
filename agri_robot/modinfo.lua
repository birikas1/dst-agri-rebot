name = "田间管家 · 自动农业机器人"
description = "使用真实种子、工具、水和肥料的自动农业机器人。按“密度 + 种植方案”在已有农田上自动打孔、播种、照料和收获；农田需手动开垦，地上的耕地机会被回收进仓库。测试版：请先在测试世界验证。\n\nAI 协作开发：GPT/Codex 与 Claude。\nAI-assisted development: GPT/Codex & Claude.\nGitHub: https://github.com/birikas1/dst-agri-rebot"
author = "birikas1 · GPT/Codex & Claude"
version = "0.2.0-simple.5"
api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
hamlet_compatible = false
all_clients_require_mod = true
client_only_mod = false
server_only_mod = false
server_filter_tags = { "agriculture", "automation", "agribot" }
priority = 0
configuration_options = {
    {
        name = "debug_log",
        label = "调试日志",
        hover = "排查问题时开启；正常游戏保持关闭。",
        options = { { description = "关闭", data = false }, { description = "开启", data = true } },
        default = false,
    },
}
