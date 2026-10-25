# CHANGELOG — 田间管家 · 自动农业机器人

## 0.2.0-simple.5（2026-10-25，测试版 / testing release）
- 简化管理：密度和作物数量控制规整网格与种植；8 孔去掉中心，9 孔为 3×3，16 孔为 4×4。
- 清理天然孔，缺种子仍准备完整网格，修复密度切换时重复任务编号。
- 自动浇水依据当前土壤水分，修复旧生长预测导致的漏浇。
- 移除耕地机工具栏位并关闭自动开垦；地面耕地机回收入库。
- 保持其他工具、水壶槽位编号，兼容旧耕地机槽位转存。
- 增加独立网格、自动浇水、回收入库测试与真实引擎验收脚本。
- Simplified density/count planning, regular grids, current-soil watering and collection-only plow warehousing, with native spacing checks.
- Credits: GPT/Codex (planning, review and tests), Claude (implementation), player (requirements and in-game feedback).

## 0.1.0-rc.5（2026-10-25）
- Fixed：P0 Boss 检测按 SRC-024 要求 `epic + hostile`（果蝇王始终计入），友方/已死亡 epic 实体不再误停农场。
- Fixed：配方不再在加载时探测 UI 图集，消除专用服务器日志中的 `Invalid resource handle for atlas` 警告（图集由客户端按需解析）。
- Added：`tests/emergency_regression.lua`（P0 检测 4 个场景）。
- Added：`tests/native/run_native_test.bat` 一键原生冒烟测试（隔离的 DST 副本，两次启动覆盖保存/重载）。

## 0.1.0-rc.4
- 原生移动状态改用 Winona 储物机器人 run_pre/run_loop/run_pst；耕地机异步完成追踪；保存/重载、主机器人接管、锁与 RPC 限流等加固（详见 SOURCE_VERIFICATION.md）。

## 首个正式版建议
- 发布闸门（09_TEST_ACCEPTANCE.md）在真实游戏中全部通过后，将 version 改为 `1.0.0` 再上传创意工坊。
