# 2026-11-01 三步更新验收

版本0.3.0-zones.3。按玩家要求由Codex直接实现，不使用Claude或DeepSeek。遵循先圆圈、再仓库工具、最后图标/外观的顺序。

1. 圆圈：全亮/加色/发光的原生圆环；悬停采用updatelooper的客户端wall update，暂停时也处理，兼容世界目标和原生高亮目标，移开或移除时清理。范围实际半径不缩小，完整边界可能需要拉远镜头。17组阶段回归与原生预览集成通过。
2. 仓库工具：67槽布局；49升级槽及其前方旧槽编号保留，50–64五类工具各3格，65–67水壶。十个新增场景覆盖分类、远距离不得转移、正确专用栏、满格保留物品、空壶补水、无复制和转移回滚。原生测试实际走到仓库取锄/取壶、9株播种、真实浇水、67格存读档通过。
3. 外观：游戏原生inventoryimages4含winona_storage_robot.tex，inventoryimages3含treasurechest_cotl_basic.tex；原生中文翻译确认后者是“羊群宝箱”。使用相同原生SetSkin资源对，渲染客户端初始复制后重新应用。客户端回调/放置外观契约测试通过；原生配方图像ID、容器67槽、动画与放置实体冒烟通过。

离线专服对动态皮肤会保留普通箱体的动画构建，不能用GetBuild或离线SpawnPrefab的皮肤参数来证明最终皮肤像素。为避免误报，最终实际外观留待玩家图形客户端重启后查看；玩家明确选择继续后台开发，没有使用共享键鼠或截图验收。

日志：dist/round3-final-regressions.log（42文件、19组），dist/round3-step1-native.log，dist/round3-step2-native.log，dist/round3-step3-native.log。
