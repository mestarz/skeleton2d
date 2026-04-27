# UrhoX StaticSprite2D Demo

在 TapTap Maker (UrhoX) 中以 **场景图通路** 运行 skeleton2d。

每个骨骼部件 = 一个 `Node` + 一个 `StaticSprite2D` 组件，节点一次性创建，
之后每帧只把 runtime 算好的 `wx/wy/wr` 写到 `node.position2D / rotation2D`。
引擎自动绘制、参与排序与批合，可与物理/碰撞共存。

> **关于 NanoVG 通路**：skeleton2d 的 runtime 也支持把每帧绘制委托给变换栈
> 后端（NanoVG / Canvas），由 `Skeleton.Draw` 驱动。本 demo 主体走 sprite 通路；
> NanoVG 仅用于一个**调试覆盖层**（画关节点 + HUD），不参与角色渲染。
> 详见仓库根 `docs/integration.md` 与 `docs/skeleton2d-integration-guide.md`。

## 演示内容

| 功能 | 说明 |
|---|---|
| 一次性场景图建立 | `SpriteBE.CreateNodes(spriteRoot, skelInst, …)` 为 14 个部件建 Node + StaticSprite2D |
| 每帧三步驱动 | `Skeleton.Update` → `Skeleton.UpdateWorldTransforms` → `SpriteBE.Sync` |
| 朝向翻转 | `spriteRoot:SetScale2D(Vector2(facing, 1))`，sprite 节点本身不改 flipX |
| 角色位移 | `charNode.position2D = Vector2(x, y)`（米） |
| 动画切换 | idle / walk / swing / shoot / hit |
| 关节调试 | NanoVG 覆盖层画红点标记每个部件锚点 |

## 操作

| 按键 | 功能 |
|---|---|
| 1–5 | 切换动画 |
| A / D | 左右移动（自动切 walk/idle） |
| F | 翻转朝向 |
| J | 显示/隐藏关节调试点 |
| H | 显示/隐藏 HUD |

## 文件结构

```
examples/urhox-demo/
├── README.md
└── scripts/
    ├── main.lua                      ← demo 入口
    ├── SkeletonRenderer.lua          ─symlink─→ ../../../runtime/lua/SkeletonRenderer.lua
    ├── backends/
    │   └── taptap_sprite.lua         ─symlink─→ ../../../../runtime/lua/backends/taptap_sprite.lua
    └── humanoid/
        ├── skeleton.lua              ─symlink─→ ../../../../examples/humanoid/skeleton.lua
        └── animations.lua            ─symlink─→ ../../../../examples/humanoid/animations.lua
```

`main.lua` 通过符号链接引用仓库唯一源文件，不维护副本、不修改 `package.path`：

```lua
local Skeleton = require "SkeletonRenderer"        -- → runtime/lua/SkeletonRenderer.lua
local SpriteBE = require "backends.taptap_sprite"  -- → runtime/lua/backends/taptap_sprite.lua
local SkelDef  = require "humanoid.skeleton"       -- → examples/humanoid/skeleton.lua
local Anims    = require "humanoid.animations"     -- → examples/humanoid/animations.lua
```

> UrhoX 沙箱不允许 `package.path` 指向 `scripts/` 之外的目录；symlink 让模块在
> 文件系统层完成跳转，沙箱 stat 出来仍然落在 `scripts/` 内部。

## 关于贴图

`examples/humanoid/` 是只带几何信息的占位骨骼，**没有指定 PNG**，所以默认运行
看到的是空场景 + 红色关节点 + HUD。用法演示和坐标管线都是真实的，只是没有可见
的精灵。接入真实贴图：

1. 在 `examples/humanoid/skeleton.json` 里给每个 part 加 `"png": "torso.png"` 等字段
2. 用 `editor/` 重新导出 lua（或直接编辑生成的 lua）
3. 把对应 PNG 放到 TapTap 项目的 `Textures/` 下（可在 demo 中改 `texturePrefix` 选项）

`backends/taptap_sprite.lua` 在 part 没有 `png` 字段或资源加载失败时不会报错，
只是该部件的 sprite 为空，节点和变换照常工作。

## 与 NanoVG 通路的对比

| 维度 | 场景图（本 demo） | NanoVG（变换栈） |
|---|---|---|
| 创建时机 | 节点一次创建 | 每帧重画 |
| 排序 | `orderInLayer` 自然支持 | 依赖绘制顺序 |
| 物理共存 | 直接与 RigidBody2D / Collider2D 同节点 | 不参与场景图 |
| 资源 | `cache:GetResource("Sprite2D", …)` | 自行管理纹理句柄 |
| 适用场景 | 正经游戏 | UI / 调试覆盖 / 自绘特效 |

后端接口对应：

| skeleton2d API | StaticSprite2D 实现 |
|---|---|
| `Skeleton.UpdateWorldTransforms(inst)` | runtime 算 `wx/wy/wr`（不含角色级 facing/scale） |
| `SpriteBE.CreateNodes(parent, inst, opts)` | 为每 part 建 Node + 设置 `sprite` / `hotSpot` / `drawRect` / `orderInLayer` |
| `SpriteBE.Sync(boneNodes, inst, opts)` | 写 `node.position2D` / `node.rotation2D`，px→m + Y 翻转 |
| `SpriteBE.AttachPart` / `DetachPart` | 配合 `Skeleton.AttachWeapon` / `DetachWeapon` 动态挂卸部件 |

## 坐标约定

- skeleton2d 内部：像素，Y 向下，左上原点（编辑器画布约定）
- UrhoX 2D：米，Y 向上，相机居中
- 转换在 `SpriteBE.Sync` 内完成：`Vector2(p.wx * inv, -p.wy * inv)`，`rotation2D = -p.wr`
- `pixelsPerMeter` 默认 100，与 UrhoX 2D 默认一致；可通过 opts 覆盖
