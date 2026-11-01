# 水井图像来源

2026-11-01，使用内置 image_gen 工具生成，透明背景。模型原图 building.png，独立配方图标 icon.png；均已复制到项目，不依赖生成缓存。未替换为CLI或其他模型。

## 井体提示词

Use case: stylized-concept. Asset type: production game building sprite for a Don't Starve Together mod. Create ONE complete rustic water well, isolated on genuinely transparent background. A short chunky oval stone well rim with visible deep blue fresh water, two crooked wooden uprights and a wooden crossbeam, rope and a small hanging bucket. Hand-drawn gothic survival-game style, bold scratchy dark outlines, muted gray stone and brown wood, readable blue water. Three-quarter orthographic front view from slightly above, as a 2.5D ground building sprite; the entire object fits, centered, with clear silhouette and generous transparent margin. No roof, no ground scenery, no people, no grass, no text, no UI border, no cast shadow outside the object. Flat painted game illustration, not photorealistic, not a 3D render. One well only, no sprite sheet or labels. Intended to remain readable at about200 pixels in-game.

## 图标提示词

Use case: stylized-concept. Asset type: crafting inventory icon for a Don't Starve Together mod. The attached image is a DESIGN REFERENCE, not a picture to preserve: generate a new simplified matching water-well icon, ONE short oval gray stone water well with two crooked brown wooden posts, one crossbeam, rope and hanging bucket, readable bright blue water. Match the same well design, slightly elevated three-quarter front game view, bold scratchy ink outline, muted painted survival-game palette. Compact silhouette with fewer small details so it reads at64 pixels. Center it on a square canvas with transparent margin, whole well visible. Genuinely transparent background. No ground, shadow patch, landscape, labels, lettering, borders, UI, extra objects, or watermark. New original item icon matching the reference building.

图标以已生成的井体图片为设计参考。tools/build_well_assets.py 调用已安装的官方 Klei 编译器生成运行资源，保留原始PNG及透明通道；井体为游戏使用的2.5D单帧建筑动画，而非外部3D网格。
