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
| 1–5 | 切换动画（idle / walk / swing / shoot / hit） |
| A / D | 左右移动（自动切 walk/idle） |
| F | 翻转朝向 |
| C | 切换角色（police_m / civilian_f） |
| W | 切换武器（无 / handgun / knife） |
| J | 显示/隐藏关节调试点 |
| H | 显示/隐藏 HUD |

## 文件结构

```
examples/urhox-demo/
├── README.md
├── Textures/                              ← 拷贝到 TapTap 项目 Resources/Data/Textures/
│   ├── police_m/parts/*.png               14 张部件
│   ├── civilian_f/parts/*.png             14 张部件
│   └── weapons/{handgun,knife}.png
└── scripts/
    ├── main.lua                           ← demo 入口
    ├── weapons.lua                        ← 武器定义（grip 锚点）
    ├── SkeletonRenderer.lua               ─symlink─→ ../../../runtime/lua/SkeletonRenderer.lua
    ├── backends/
    │   └── taptap_sprite.lua              ─symlink─→ ../../../../runtime/lua/backends/taptap_sprite.lua
    ├── police_m/
    │   ├── skeleton.lua                   (本地生成)
    │   └── animations.lua                 ─symlink─→ ../../../humanoid/animations.lua
    └── civilian_f/
        ├── skeleton.lua                   (本地生成)
        └── animations.lua                 ─symlink─→ ../../../humanoid/animations.lua
```

> UrhoX 沙箱不允许 `package.path` 指向 `scripts/` 之外的目录；symlink 让模块在
> 文件系统层完成跳转，沙箱 stat 出来仍然落在 `scripts/` 内部。
>
> `animations.lua` 用符号链接共享 `examples/humanoid/animations.lua` ——
> 两个角色都是 14 骨人形，骨骼名字完全一致，可以共用动画轨道。

## 数据生成管线

`Textures/<id>/parts/*.png` 与 `Textures/<id>/skeleton.json` 由仓库根的工具生成：

```bash
# 1) 拆分原图（按 bbox 配置裁剪 14 个部件 + 写 skeleton.json）
python3 tools/split_character.py tools/configs/police_m.json
python3 tools/split_character.py tools/configs/civilian_f.json

# 2) （可选）重组预览，目视校验 anchor / attachAt 是否合理
python3 tools/preview_skeleton.py examples/urhox-demo/Textures/police_m/skeleton.json
python3 tools/preview_skeleton.py examples/urhox-demo/Textures/civilian_f/skeleton.json

# 3) 转成运行期 Lua
node tools/json2lua.js examples/urhox-demo/Textures/police_m/skeleton.json   examples/urhox-demo/scripts/police_m/skeleton.lua
node tools/json2lua.js examples/urhox-demo/Textures/civilian_f/skeleton.json examples/urhox-demo/scripts/civilian_f/skeleton.lua
```

要换原图，编辑 `tools/configs/<id>.json`（bbox / anchor / attachAt / parent / z）后
重跑步骤 1–3 即可。

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
