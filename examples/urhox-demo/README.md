# UrhoX NanoVG 技术验证 Demo

在 UrhoX 引擎中使用 **NanoVG 变换栈**作为渲染后端运行 skeleton2d 骨骼系统。

> **渲染通路说明**
>
> skeleton2d 提供两种 UrhoX 集成通路，本 demo 走 **NanoVG**（变换栈 push/pop/translate/rotate，由 `Skeleton.Draw` 驱动）。
> 如需物理碰撞或场景图管理，应改用 **StaticSprite2D 后端** `runtime/lua/backends/taptap_sprite.lua`（每部件对应一个 UrhoX 节点，由 `Skeleton.UpdateWorldTransforms` + `SpriteBE.Sync` 驱动）。
> 详见 `docs/integration.md` → "TapTap Maker (UrhoX) Sprite 集成"。

## 验证内容

| 功能 | 说明 |
|------|------|
| 骨骼层级渲染 | 14 部件人形骨骼，按 z 序递归绘制 |
| 关键帧插值 | rot 通道线性插值 |
| 动画切换 | idle / walk / swing / shoot / hit |
| 朝向翻转 | `facing=-1` 时通过变换栈 `nvgScale(-scale, scale)` 水平镜像，非 sprite.flipX |
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

## 后端适配表

`setupNanoVGBackend()` 将 `Skeleton.SetBackend` 的 9 个接口映射到 NanoVG C API：

| 接口 | NanoVG 实现 | 状态 |
|------|------------|------|
| `drawImage(handle, x, y, w, h)` | `nvgImagePattern` + `nvgRect` + `nvgFill` | **未启用** — 当前 demo 仅展示几何渲染，所有部件使用 `placeholderColor` 色块 |
| `fillRect(x, y, w, h, rgba)` | `nvgBeginPath` + `nvgRect` + `nvgFillColor` + `nvgFill` | 已实现 |
| `getImage(path)` | `nvgCreateImage` 句柄缓存 | **未启用** — 始终返回 `nil`，触发占位色 |
| `enqueueImage(path)` | 异步加载队列 | **未启用** — noop |
| `pushTransform()` | `nvgSave` | 已实现 |
| `popTransform()` | `nvgRestore` | 已实现 |
| `translate(x, y)` | `nvgTranslate` | 已实现 |
| `rotate(rad)` | `nvgRotate` | 已实现 |
| `scale(sx, sy)` | `nvgScale` | 已实现 |

> `drawImage` / `getImage` / `enqueueImage` 已预留，接入 PNG 贴图需实现 `nvgCreateImage` 缓存 + `nvgImagePattern` 绘制。

## 文件结构

```
examples/urhox-demo/
├── README.md
└── scripts/
    └── main.lua          ← 唯一文件，require 仓库主 runtime
```

`main.lua` 通过 `package.path` 直接引用仓库根文件，不维护副本：

```
runtime/lua/SkeletonRenderer.lua     ← require "SkeletonRenderer"
examples/humanoid/skeleton.lua       ← require "humanoid.skeleton"
examples/humanoid/animations.lua     ← require "humanoid.animations"
```
