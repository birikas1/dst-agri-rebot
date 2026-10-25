# 田间管家 · 自动农业机器人

**Field Steward · Automated Farming Robot for Don't Starve Together**

当前版本 / Current version: **0.2.0-simple.5 — 测试版 / Testing release**

手动开垦农田，设置每块田的种植密度和各作物数量，再准备真实的种子、工具、水和肥料，机器人即可进行打孔、播种、浇水、照料、收获和入库。

**由 GPT/Codex 与 Claude 协作开发：GPT/Codex 负责需求分析、规划、代码审查与测试；Claude 负责代码实现；玩家负责玩法需求与实机反馈。**

## 功能与使用

- 按“密度 + 作物数量”管理种植，种子不足时先种已有的部分。
- 9 孔为规整 3×3；8 孔为 3×3 去掉中心；16 孔为规整 4×4。
- 根据实际土壤水分安排浇水，附近有可用水源时补水。
- 成熟作物收获、仓库分类存取和多机器人协作。
- 工具栏保留园艺锄、铲子、锤子、斧头和镐子，水壶有专用槽位。
- **不自动开垦农田。** 地面耕地机作为回收物拾取，送入仓库作物/回收区。
- 打开管理面板或机器人库存时暂停工作组，关闭后恢复。

1. 下载仓库，复制 `agri_robot` 文件夹到饥荒联机版安装目录的 `mods` 文件夹。
2. 在测试世界启用本 Mod；主机和客户端均需要安装。
3. 科学机器科技可制作农业机器人（齿轮×2、木板×3、金块×4）和农业仓库（木板×8）。
4. 手动开垦农田，仓库放在工作范围附近；工具和水壶放专用格，种子放工作库存或仓库种子区。
5. 设置密度与种植数量，关闭管理面板后观察工作。

## 已知限制

- 当前为测试版，请备份存档并先在测试世界验证。
- 原版普通模式最小打孔间距为 1.25：相邻完整 4×4 地块会冲突，机器人会跳过冲突孔并提示，不能保证连片每块都种满 16 株。
- 仓库满或未绑定时，回收的耕地机会保留在机器人中并提示。
- 旧季节预设、农业蓝图和自动推荐界面不作为当前简化版本的公开功能承诺。
- 本作品为非官方玩家创作，与 Klei Entertainment 无关联。原版素材由游戏提供，本仓库不分发游戏文件。

源码与反馈：**https://github.com/birikas1/dst-agri-rebot**

反馈请提供版本、复现步骤、其他 Mod 列表和相关日志片段，请勿公开凭据或私人信息。

## English

An agricultural automation mod for **Don't Starve Together**. Cultivate farmland manually, select holes per plot and crop quantities, then provide real seeds, tools, water and fertilizer. Robots till regular grids, plant available seeds, water, tend, harvest and store the output.

**Developed collaboratively with GPT/Codex and Claude. GPT/Codex handles requirements analysis, planning, code review and testing; Claude implements the code; the player provides gameplay requirements and in-game feedback.**

- 9 holes: 3×3. 8 holes: 3×3 without the centre. 16 holes: 4×4.
- Current-soil watering, replenishment from available water sources, warehouse logistics and shared robot groups.
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
```

These native tests exercise real engine actions under controlled fixtures; they do not certify every multiplayer or third-party-mod configuration.
