name = "田间管家 · 自动农业机器人"
description = "田间管家0.3.3。先在制作栏放置小木牌式“农业工作中心”（木板×1），机器人只能放在中心范围内；放置时和鼠标悬停中心时像雪球发射器一样显示范围圈；同一中心内可协作多台机器人，中心范围互不重叠。种植方案在农田浮标上设置。机器人会自动捡起工作范围内地上的工具使用，多余的工具放入农业仓库。机器人使用真实种子、工具和水；仓库67槽；水井自动打水。农田需手动开垦。\n\nAI 协作开发：GPT/Codex 与 Claude。\nAI-assisted development: GPT/Codex & Claude.\nGitHub: https://github.com/birikas1/dst-agri-rebot"
author = "birikas1 · GPT/Codex & Claude"
version = "0.3.3"
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
