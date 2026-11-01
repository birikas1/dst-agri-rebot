# 田间管家 · 自动农业机器人

**Field Steward · Automated Farming Robot for Don't Starve Together**

当前版本 / Current version: **0.3.0 — 正式版 / Release**

[下载正式版安装包](https://github.com/birikas1/dst-agri-rebot/raw/refs/heads/main/releases/0.3.0/agri_robot-0.3.0.zip) · [Steam创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3827604865) · [本版更新说明](releases/0.3.0/README.md)

手动开垦农田，设置每块田的种植密度和各作物数量，再准备真实的种子、工具、水和肥料，机器人即可进行打孔、播种、浇水、照料、收获和入库。

**由 GPT/Codex 与 Claude 协作开发；近期更新按玩家要求由 GPT/Codex 直接实现与测试。玩家负责玩法需求与实机反馈。**

## 功能与使用

- 边相连的农田地皮组成一个田区；隔着草地或仅斜角接触的田独立管理，只接管工作范围内的农田。
- 每片田区上方有浮牌，点击展开箱子式作物计划格；这些格子用于设置方案，真实种子仍从机器人和农业仓库取用。
- 默认按作物比例种满田区，也支持整片田区的精确株数。密度按每格地皮计算，例如四格各八孔，共三十二孔。
- 方案当前模式的选择总数不得超过“田区格数 × 每格孔数”。旧超额方案可逐项减少，修正前不能保存；比例模式仍按配比填满。
- 建造机器人时预览工作范围；绿色中心木牌固定在工作组最初的建造点，悬停查看范围。机器人移动、接管和读档不移动中心；加入现有工作组时共用它的中心与范围。
- 悬停圆圈全亮显示，暂停时仍按客户端帧更新；实际半径较大时，滚轮拉远可查看完整边界。
- 9 孔为规整 3×3；8 孔为 3×3 去掉中心；16 孔为规整 4×4。
- 根据实际土壤水分安排浇水，附近有可用水源时补水。
- 新建筑“水井”：科学机器解锁，石砖×6、木板×4、绳子×2。放在机器人固定工作圈内，提供永久淡水，不随季节冻结；可以手动用水壶打水。
- 机器人优先使用工作圈内可用水井，缺井时仍可使用原有自然水源。空壶从仓库取出后，自动到井边装水，再返回浇田；新增或拆除水井会刷新相关停工任务。
- 每个田区按类别完成农活：清除杂物 → 清理自然坑/坏坑 → 打孔 → 播种 → 浇水 → 对话照料；田区之间独立调度。
- 已有作物临近缺水时优先补水，可中断准备和普通取货；补水会预留行走、动作与补水壶的时间，湿土不重复浇水。
- 成熟作物收获、仓库分类存取和多机器人协作。
- 种子可以放在农业仓库中，机器人会就近取用；卸货会保留待播种任务所需种子，后续批次缺货不会卡住当前已有种子的播种。
- 工具栏保留园艺锄、铲子、锤子、斧头和镐子，水壶有专用槽位。
- 农业仓库有五类工具各3格、水壶3格。机器人按工作需要走到仓库取用工具或水壶，放进自己的对应专用栏；空壶继续寻找水源补水。
- 机器人合成图标使用本体；仓库图标和客户端模型引用原生“羊群宝箱”外观。旧仓库原有49个槽位编号保留，新增工具/水壶使用50–67格。
- **不自动开垦农田。** 地面耕地机作为回收物拾取，送入仓库作物/回收区。
- 打开管理面板或机器人库存时暂停工作组，关闭后恢复。
- 编辑某个田区只暂停该田区；关闭编辑后恢复。手动暂停的田区在恢复前保持停工，包括浇水。

1. 下载仓库，复制 `agri_robot` 文件夹到饥荒联机版安装目录的 `mods` 文件夹。
2. 在测试世界启用本 Mod；主机和客户端均需要安装。
3. 科学机器科技可制作农业机器人（齿轮×2、木板×3、金块×4）和农业仓库（木板×8）。
4. 手动开垦农田，仓库放在工作范围附近；工具和水壶放专用格，种子放工作库存或仓库种子区。
5. 点击农田上方浮牌，选择作物、比例或精确数量，以及每格密度，保存并关闭编辑。
6. 机器人管理面板提供田区列表和默认配比模板；旧方案迁移为默认模板，单独配置的田区保留自己的设置。

## 已知限制

- 更新前请备份存档；已有仓库1–49槽编号保留，新增工具和水壶使用50–67槽。
- 原版普通模式最小打孔间距为 1.25：相邻完整 4×4 地块会冲突，机器人会跳过冲突孔并提示，不能保证连片每块都种满 16 株。
- 仓库满或未绑定时，回收的耕地机会保留在机器人中并提示。
- 旧季节预设、农业蓝图和自动推荐界面不作为当前简化版本的公开功能承诺。
- 不同方案的田区合并、精确数量田区分割时，会保留方案并提示确认，确认前暂停新种植。
- 本作品为非官方玩家创作，与 Klei Entertainment 无关联。原版素材由游戏提供，本仓库不分发游戏文件。
- 水井建筑贴图和图标为本项目生成的独立资源，原图及提示词见 `art_source/agriwell`；由官方Klei工具编译为游戏的2.5D建筑和图标格式。游戏内最终贴图表现由玩家实测。

源码与反馈：**https://github.com/birikas1/dst-agri-rebot**

反馈请提供版本、复现步骤、其他 Mod 列表和相关日志片段，请勿公开凭据或私人信息。

## English

An agricultural automation mod for **Don't Starve Together**. Cultivate farmland manually, select holes per plot and crop quantities, then provide real seeds, tools, water and fertilizer. Robots till regular grids, plant available seeds, water, tend, harvest and store the output.

**Developed collaboratively with GPT/Codex and Claude. GPT/Codex handles requirements analysis, planning, code review and testing; Claude implements the code; the player provides gameplay requirements and in-game feedback.**

- 9 holes: 3×3. 8 holes: 3×3 without the centre. 16 holes: 4×4.
- Current-soil watering, replenishment from available water sources, warehouse logistics and shared robot groups.
- Edge-connected farm tiles form one zone with its own floating crop-plan editor; ground gaps and diagonal contact separate zones.
- Ratio mode fills each zone's capacity; exact mode sets whole-zone totals. Density remains holes per native tile. Zone plans persist with the world.
- Work stages apply per zone: debris, stray/broken holes, tilling, planting, watering, then tending. Time-critical watering can interrupt preparation and supply trips.
- Seeds can stay in the warehouse until needed. Deposits retain seeds for live planting work; missing future batch inputs do not block an already supplied action.
- Five tool slots: hoe, shovel, hammer, axe and pickaxe; separate watering-can slots.
- Automatic plowing is disabled. Ground plows are collected and stored in the warehouse.
- Native spacing prevents adjacent complete 4×4 grids in normal mode; conflicting positions are withheld and reported.

Copy `agri_robot` into the game's `mods` directory and enable it in a test world. Craft the robot and warehouse using Science Machine technology, cultivate land manually, supply resources, configure density and crop counts, then close the management UI to resume work.

This is a **testing release**. Back up saves and test compatibility with other mods. This unofficial project is not affiliated with or endorsed by Klei Entertainment. Vanilla assets are referenced from the installed game; game files are not redistributed here.

## Tests / 测试

```text
python -m pip install --target .test-deps lupa
python tests/run_tests.py
```

Windows native acceptance tests require an installed copy of DST at the path configured in `tests/native/stage.py`. They stage an isolated game copy under ignored `tests/native/runtime` and use isolated test saves:

```text
python tests/native/run_grid_tests.py
python tests/native/run_watering_tests.py
python tests/native/run_plow_storage_tests.py
python tests/native/run_farm_phases_tests.py
python tests/native/run_warehouse_seed_tests.py
python tests/native/run_mixed_seed_tests.py
python tests/native/run_zone_tests.py
```

These native tests exercise real engine actions under controlled fixtures; they do not certify every multiplayer or third-party-mod configuration.
