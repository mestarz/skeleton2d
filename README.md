# skeleton2d

> 极简 2D 纸娃娃骨骼系统，专为 **TapTap Maker (UrhoX) + NanoVG immediate-mode** 渲染设计。
> 1 套数据，编辑器（HTML）和游戏（Lua/NanoVG）共用。

## 是什么

- **数据规范**：JSON 描述骨骼层级 + 动作关键帧（rot 通道线性插值）
- **运行时**：纯 Lua（约 200 行，零依赖）。**不做绘制**——只产出 `part.wx/wy/wr`，
  渲染由调用方用 NanoVG 完成
- **图集打包工具**：`tools/split_character.py` 把整张角色图按 bbox 切成 14 部件 +
  POW2 网格 atlas
- **编辑器**：单文件 HTML，拖拽 PNG 调骨骼/做动作/导出 JSON+Lua

> ⚠️ **只支持 NanoVG 渲染路径。** UrhoX WebGL 中 `StaticSprite2D` 不可用，
> Scene-graph 后端已从仓库移除。背景见 `docs/taptap-integration-pitfalls.md` §7。

## 快速上手

### 启动编辑器

```bash
# 仓库根启 server，浏览器访问 http://localhost:8080/editor/
python3 -m http.server 8080
```

### 在 Lua / NanoVG 项目里使用

```lua
local Skeleton = require "SkeletonRenderer"
local SkelDef  = require "police_m.skeleton"
local Anims    = require "police_m.animations"

local inst = Skeleton.New(SkelDef)
Skeleton.Play(inst, Anims.idle)

-- 每帧
Skeleton.Update(inst, dt)
Skeleton.UpdateWorldTransforms(inst)
-- 然后自己用 nvgImagePattern 遍历 inst.parts 画图集子区域
-- 完整实现见 scripts/main.lua 的 drawSkeletonNanoVG()
```

详见 [`docs/integration.md`](docs/integration.md) 与
[`docs/skeleton2d-integration-guide.md`](docs/skeleton2d-integration-guide.md)。

## 目录

```
runtime/lua/      纯 Lua 运行时（SkeletonRenderer.lua）
scripts/          UrhoX/TapTap demo（main.lua + 角色数据 + 沙箱副本）
assets/Textures/  3 张图集（police_m / civilian_f / weapons）
editor/           单文件 HTML 编辑器
tools/            数据管线（split_character.py / preview_skeleton.py / json2lua.js）
schema/           JSON Schema
docs/             规范、集成指南、踩坑集
```

## 文档

- [`docs/spec.md`](docs/spec.md) — JSON 数据规范
- [`docs/integration.md`](docs/integration.md) — 接入步骤
- [`docs/skeleton2d-integration-guide.md`](docs/skeleton2d-integration-guide.md) — NanoVG 渲染管线详解
- [`docs/taptap-integration-pitfalls.md`](docs/taptap-integration-pitfalls.md) — TapTap Maker 踩坑集
- [`docs/editor-guide.md`](docs/editor-guide.md) — 编辑器使用

## License

MIT
