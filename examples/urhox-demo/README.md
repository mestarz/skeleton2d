# UrhoX NanoVG 技术验证 Demo

在 UrhoX 引擎中使用 NanoVG 作为渲染后端运行 skeleton2d 骨骼系统。

## 验证内容

| 功能 | 说明 |
|------|------|
| 骨骼层级渲染 | 14 部件人形骨骼，按 z 序递归绘制 |
| 关键帧插值 | rot 通道线性插值 |
| 动画切换 | idle / walk / swing / shoot / hit |
| 朝向翻转 | facing=1 朝右, facing=-1 朝左 (水平镜像) |
| 缩放控制 | 0.5x ~ 6.0x |
| 骨骼调试 | 可视化关节点和连接线 |

## 操作

| 按键 | 功能 |
|------|------|
| 1-5 | 切换动画 (idle/walk/swing/shoot/hit) |
| A / D | 左右移动（自动切换 walk/idle） |
| F | 翻转朝向 |
| +/- | 缩放 |
| B | 显示/隐藏骨骼关节点 |
| H | 显示/隐藏 HUD 面板 |

## 后端适配

核心集成代码在 `scripts/main.lua` 的 `setupNanoVGBackend()` 函数，映射关系：

```
Skeleton.SetBackend    →  NanoVG C API
  fillRect             →  nvgBeginPath + nvgRect + nvgFillColor + nvgFill
  pushTransform        →  nvgSave
  popTransform         →  nvgRestore
  translate            →  nvgTranslate
  rotate               →  nvgRotate
  scale                →  nvgScale
  drawImage            →  (预留，当前用 placeholderColor)
  getImage             →  (预留，返回 nil 触发占位色)
```

## 文件结构

```
examples/urhox-demo/
└── scripts/
    ├── main.lua                              # Demo 主程序 + NanoVG 后端适配
    └── skeleton2d/
        ├── data/
        │   ├── humanoid_skeleton.lua         # 骨骼定义 (Lua 表)
        │   └── humanoid_animations.lua       # 动画定义 (Lua 表)
        └── runtime/
            └── lua/
                └── SkeletonRenderer.lua      # 骨骼运行时（仓库副本）
```
