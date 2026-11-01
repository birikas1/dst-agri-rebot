# 田间管家 · 自动农业机器人 / Field Steward

**0.3.0 正式版 / Release**

使用真实资源的自动农业管理。手动开垦农田，设置方案，准备工具、种子和水，机器人即可完成农活。

## 田区管理

- 上下左右相连的农田归为一个田区；空地或仅斜角接触的田区独立设置。
- 点击浮牌展开箱子式作物方案面板，支持比例填满、精确数量、独立暂停与恢复。
- 输入上限为田区格数×每格孔数：1格8孔最多选8，4格8孔最多选32；降低密度后需修正超额方案。
- 按田区完成清杂、清坑、打孔、播种、浇水、照料；临近缺水的作物优先补水。
- 工作中心固定在建造点，移动机器人、主机器人接管和读档不移动中心。悬停木牌或建造时显示范围，半径大时可拉远查看边界。

## 仓库、工具与水井

- 67槽仓库：种子12、肥料12、作物/回收物24、升级槽1、五类工具各3、水壶3。
- 机器人按需实际走到仓库取种子、工具和水壶；部分缺货不阻塞当前可完成的播种。
- 新建筑水井：科学机器解锁，石砖×6、木板×4、绳子×2。工作圈内提供永久淡水。
- 优先使用可用水井：取空壶、井边打水、返回浇田；保留自然水源支持。建井可恢复缺水源停工。
- 机器人配方图标使用本体，仓库引用原生羊群宝箱外观。水井使用本项目生成的独立贴图和图标。

## 使用与兼容

主机和客户端均需安装。机器人、仓库、水井在农业分类制作。农田需手动开垦；地面耕地机作为回收物送入仓库。

9孔为3×3，8孔去掉中心，16孔为4×4。原生孔距仍生效，连片16孔不能保证每格种满。旧仓库1–49槽编号保留，新增工具/水壶使用50–67槽；旧全局方案保留为默认配比模板。

更新前备份存档。20组回归和原生功能链路通过；最终动态外观像素、本轮图形截图及所有第三方Mod组合不记为已验收，欢迎反馈具体复现步骤。

源码、下载、反馈：https://github.com/birikas1/dst-agri-rebot

AI协作开发：GPT/Codex与Claude；后续功能按玩家要求由GPT/Codex直接实现和测试。非官方玩家创作，与Klei Entertainment无关联。原版资源由游戏提供，未随Mod分发。

---

**Field Steward 0.3.0 Release** automates existing farmland using real seeds, tools and water. Connected farm tiles form independent zones with floating plan editors, ratio/exact planting, capacity limits and separate pause controls. Work follows clearing, soil preparation, tilling, planting, watering and tending; urgent watering has priority.

The67-slot warehouse adds three slots for each of five tool types and three for watering cans. Robots fetch actual equipment and supplies. The new crafted well supplies permanent fresh water: collect an empty can, refill it at a well in the fixed work area, and return to water crops. Wells cost6 cut stone,4 boards and2 rope at Science Machine technology.

Both host and clients require the mod. Cultivate farmland manually. Native spacing limits still apply to adjacent16-hole tiles. Existing warehouse slots1–49 remain unchanged. Back up saves before upgrading. Functional regressions and native engine tests passed; final cosmetic pixels and all third-party mod combinations are not claimed as verified.

Source/downloads/feedback: https://github.com/birikas1/dst-agri-rebot

AI-assisted development: GPT/Codex & Claude. Unofficial player creation, not affiliated with Klei Entertainment.
