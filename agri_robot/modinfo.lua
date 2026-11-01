name = "田间管家 · 自动农业机器人"
description = "田间管家0.3.0正式版。相连农田独立配置比例或精确种植方案，支持孔数上限、固定工作中心与范围预览。机器人使用真实种子、工具和水，自动打孔、播种、浇水、照料、收获和入库；仓库提供67个分类槽位，工具及水壶可自动取用。新增水井，支持自动打水。农田需手动开垦。\n\nAI 协作开发：GPT/Codex 与 Claude。\nAI-assisted development: GPT/Codex & Claude.\nGitHub: https://github.com/birikas1/dst-agri-rebot"
author = "birikas1 · GPT/Codex & Claude"
version = "0.3.0"
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
