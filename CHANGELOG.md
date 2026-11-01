# CHANGELOG — 田间管家 · 自动农业机器人

## 0.3.0（2026-11-01，正式版 / Release）

- 汇总并发布zones.1–zones.4更新：四向相连田区、每田独立的比例/精确种植方案、箱子式浮窗、孔数上限、固定工作中心及范围显示。
- 修复农活阶段穿插、仓库种子只存不取及部分缺货阻塞；按田区执行清杂→清坑→打孔→播种→浇水→照料，紧急补水可优先处理。
- 仓库扩充至67槽：五类工具各3格、水壶3格，保留旧1–49槽编号；机器人按需实际取用工具/水壶。
- 新增生成贴图和图标的水井，复用原生FILL补水；支持无水源停工后建井恢复、井存档恢复及拆除。
- 机器人图标使用本体，仓库图标及客户端外观引用原生羊群宝箱资源。
- 验证：44个Lua文件与20组回归通过；原生引擎完成真实仓库取工具/取空壶、井边补水、播种浇水、存档恢复等验收。最终皮肤像素和本轮游戏截图未做独立验收，不把它们记为通过。
- 主机和客户端均需安装；农田仍需手动开垦。原生最小孔距仍生效，连片16孔不能保证每格都种满。旧全局方案保留为默认配比模板。

## 0.3.0-zones.4（2026-11-01，水井与自动打水）

- 新增“水井”：科学机器配方为石砖×6、木板×4、绳子×2，永久淡水源，可用水壶补水。井体及合成图标分别生成透明原图，并编译为独立游戏资源。
- 复用已有原生FILL自动补水流程，优先选工作范围内的井，其次可用自然水源。仓库里的空水壶也可自动取出、到井边补满再浇田。
- 建井/拆井会唤醒相关资源任务；井及水源能力可随存档恢复，不绕过真实水壶和原生浇水动作。
- 44个Lua文件、20组回归通过；原生引擎验证无水源停工→建井恢复→实际从井补水→真实播种/浇田，以及井存档恢复、拆除、模型与放置预览加载。最终游戏内贴图效果按玩家要求留待其测试。

## 0.3.0-zones.3（2026-11-01，范围显示、仓库工具与外观）

- 工作中心悬停圆环改为全亮、高对比显示；使用客户端逐帧更新，避免暂停时不更新，并允许原生高亮目标触发圆环。
- 仓库追加18格：园艺锄、铲子、锤子、斧头、镐子各3格，水壶3格。原有1–49槽编号不变。
- 机器人缺少工具/水壶时认领可从仓库补给的任务，实际走到仓库取出同一件物品，放入自己的专用栏。空水壶会进入已有补水流程；工具格已满时保留双方物品并提示。
- 机器人配方图标改为本体；仓库配方图标及渲染客户端模型引用“羊群宝箱”原生资源，放置预览使用同一外观。
- 42个Lua文件语法、19组回归通过；原生仓库67格存读档、实际园艺锄/水壶提取、9株播种和真实浇水通过。外观资源及开关箱冒烟通过，最终皮肤像素按玩家要求留待重启客户端查看，未宣称完成截图验收。

## 0.3.0-zones.2（2026-10-30，孔数限制与固定工作中心测试版）

- 田区方案新增总数上限：1 格 × 8 孔最多选择 8，4 格 × 8 孔最多选择 32。比例与精确两种模式均限制输入总数，比例填满的分配规则保持一致。
- 添加作物、加号、默认模板及服务端保存统一校验。降低密度、切换模式、旧方案或田区缩小时，超额草稿提示调整并阻止保存，不删除已有作物。
- 建造预览显示工作范围；新增绿色中心木牌，悬停显示范围，移开隐藏。附近机器人加入同一工作组时，预览对应已有组的固定中心与半径。
- 工作组原点随存档保留，移动机器人或移除主机器人不会移动原点；半径变更会同步范围，最后一台机器人移除后清理标记。
- 验证：42 个生产 Lua 文件语法通过，17 组回归通过；隔离原生服务器通过 8/32 上限、中心标记、建造预览回调、36 株真实播种与仓库种子消耗检查。真实界面验收另见 `tests/CAPACITY_ORIGIN_ACCEPTANCE.md`。
- 2026-10-31 补充：建造预览的配方连接、原生圆环加载、移动和取消已通过引擎集成测试；实际鼠标制作菜单预览尚未完成。
- 本次按玩家明确要求由 GPT/Codex 直接开发；暂缓 GitHub 和 Steam 发布，先本地测试。

## 0.3.0-zones.1（2026-10-30，田区管理测试版 / connected-zone testing release）

### 新增
- 按原生农田地皮识别田区：上下左右相连的地皮归为一片；中间有空地或仅斜角接触时独立管理。
- 每片田区上方新增可点击浮牌和箱子式种植方案面板，支持作物选择、数量调整、分页、库存和缺种提示。
- 支持“比例填满”和“精确数量”：密度仍按每格地皮计算，四格各八孔为三十二孔；精确株数为整片田区合计。
- 田区方案和孔位分配随世界保存，支持独立编辑、暂停与恢复；边界扩展保留方案，不同方案合并或精确数量田区分割时提示确认。
- 独立田区编辑锁、服务端距离/版本/参数校验和只读限频轮询；未保存草稿保留原版本，防止后台刷新导致覆盖其他玩家的修改。

### 修复
- 农活按田区完成清杂、清理自然坑/坏坑、打孔、播种、浇水和照料阶段，修复跨孔位穿插作业；重扫、暂停恢复、旧存档任务及双机器人认领遵守阶段约束。
- 根据实测湿度、耗水和行走/动作耗时预留补水时间；紧急浇水可抢占准备和普通物流，补水子任务继承紧急度。
- 修复卸货将仍需播种的种子反复存回仓库，以及取到当前种子后仍因后续批次缺货而卡住的问题；补货后能继续。
- 修复空手机器人抢占有种子队友的任务、失效取料子任务重复执行、暂停田区占用其他田区的种子，以及同次合并/分割的记录丢失。
- 修复旧方案作物显示不全和选择器分页；浮牌进度按实际方案目标计算，精确计划不再误用孔位容量作分母。

### 兼容与使用
- 旧的工作组作物选择迁移为新田区的默认比例模板；已经单独配置的田区保留自己的方案。健康作物继续保留，空出的孔位按新方案补种。
- 方案格不是实物仓库；种子仍从机器人或农业仓库取用。编辑或暂停某田区时，该区的浇水也会暂停。
- 保留原版打孔间距、真实种子/工具/水消耗和手动开垦规则；相邻十六孔地皮的冲突会显示可用容量与暂缓原因。

### 验证
- 40 个 Lua 5.1 文件语法检查和 16 组回归测试通过，新增田区相关测试 61 个场景。
- 隔离原生服务器验证三片田区、三十二孔配比、独立精确总量、36 颗真实种子消耗和方案保存。
- 图形客户端 760944 验证浮牌、镜头跟随、点击编辑、普通种子选择、保存重开、暂停恢复和实际世界读档；实测精确计划进度正确显示 31/31。
- 当前仍为测试版；尚未覆盖完整双客户端联机和所有第三方 Mod 组合。

### English
- Added persistent edge-connected farm zones, floating chest-style crop-plan editors, ratio-fill/exact-total modes and independent pause/edit controls. Density remains per native tile.
- Fixed work-stage interleaving, delayed watering, warehouse seed deposit/fetch loops, partial-stock deadlocks, worker claim conflicts and stale supply tasks.
- Preserved legacy crop selections as default ratio templates; healthy plants and native resource/spacing rules remain intact. Added plan-slot pagination and revision-safe draft editing.
- Passed all 16 regression suites, native planting/seed-consumption acceptance and real client UI/save/reload checks. This remains a testing release; full two-client and third-party-mod combinations are not certified.
- Development: GPT/Codex planning, review and tests; Claude implementation; player requirements and in-game feedback.

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
