# skeleton2d

> 极简 2D 纸娃娃骨骼系统：1 套数据，多端运行。
> 为受限沙盒环境（无 Spine/DragonBones C 扩展）设计的轻量骨骼方案。

## 是什么

- **数据规范**：JSON 格式描述骨骼层级 + 动作关键帧（rot 通道线性插值）
- **运行时**：纯 Lua 实现（约 250 行，零依赖）+ JS 实现（编辑器内置）
- **后端适配器**：开箱即用的 TapTap Maker / UrhoX `StaticSprite2D` 集成（`runtime/lua/backends/taptap_sprite.lua`）
- **编辑器/浏览器**：单文件 HTML，双击打开，拖拽 PNG → 调骨骼 → 预览动作 → 导出 JSON+Lua

## 快速上手

### 启动编辑器

```bash
# 从仓库根启动 server，浏览器访问 http://localhost:8080/editor/
python3 -m http.server 8080

# 或直接双击 editor/index.html（部分功能受 file:// CORS 限制）
```

### 集成到 Lua 项目

```lua
local Skeleton = require "external.skeleton2d.runtime.lua.SkeletonRenderer"
local def      = require "data.skeletons.humanoid"   -- 编辑器导出的 .lua
local anims    = require "data.animations.humanoid"

Skeleton.SetBackend({
    drawImage = function(handle, x, y, w, h) ... end,
    fillRect  = function(x, y, w, h, rgba) ... end,
    getImage  = function(path) return handle end,
    pushTransform = function() end,
    popTransform  = function() end,
    translate = function(x, y) end,
    rotate    = function(rad) end,
    scale     = function(sx, sy) end,
})

local inst = Skeleton.New(def)
Skeleton.Play(inst, anims.swing, { loop = false })

-- 每帧
Skeleton.Update(inst, dt)
Skeleton.Draw(inst, x, y, facing, scale)
```

详见 [`docs/integration.md`](docs/integration.md)。

## 目录

```
editor/      单文件 HTML 编辑器（含 JS runtime）
runtime/     纯 Lua 运行时
schema/      JSON Schema 定义
examples/    示例 humanoid 骨骼 + 动作
docs/        规范、编辑器使用指南、集成指南
```

## License

MIT
