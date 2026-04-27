# 集成 skeleton2d 到 Lua / NanoVG 项目

> 本仓库**只支持 NanoVG immediate-mode 渲染路径**。
> 详细教程见 [`docs/skeleton2d-integration-guide.md`](skeleton2d-integration-guide.md)，
> 本文只覆盖"接入"层面的最小步骤。

---

## 步骤 1：作为 git submodule 加入

```bash
cd /path/to/your-game
git submodule add git@github.com:mestarz/skeleton2d.git external/skeleton2d
git commit -m "chore: add skeleton2d submodule"
```

之后克隆时：

```bash
git submodule update --init --recursive
```

---

## 步骤 2：require runtime + 数据

```lua
local Skeleton = require "external.skeleton2d.runtime.lua.SkeletonRenderer"
local SkelDef  = require "data.skeletons.humanoid"
local Anims    = require "data.animations.humanoid"
```

> TapTap Maker 沙箱不识别 `external/`，需要把 `runtime/lua/SkeletonRenderer.lua` 拷到
> 项目可见的 `scripts/` 路径下，并把 require 路径相应改写。
> 本仓库的 `scripts/SkeletonRenderer.lua` 即为这种"沙箱副本"。

---

## 步骤 3：每帧驱动 + 渲染

`SkeletonRenderer` 不做绘制，只产出 `part.wx / wy / wr`。
渲染由你自己用 NanoVG 完成（`scripts/main.lua` 的 `drawSkeletonNanoVG()`
是一份完整可抄的实现）。

```lua
-- 初始化
local skel = Skeleton.New(SkelDef)
Skeleton.Play(skel, Anims.idle)

-- 每帧
function HandleUpdate(et, ed)
    local dt = ed["TimeStep"]:GetFloat()

    -- 切动作
    Skeleton.Play(skel,
        attacking and Anims.swing
        or moving  and Anims.walk
        or            Anims.idle)

    Skeleton.Update(skel, dt)              -- 关键帧 → currentRot
    Skeleton.UpdateWorldTransforms(skel)   -- 写 part.wx/wy/wr
end

-- NanoVG 渲染回调
function HandleNanoVGRender(et, ed)
    nvgBeginFrame(vg, w, h, dpr)
    drawSkeleton(skel, atlasHandle, atlasRects, screenX, screenY, facing, scale)
    nvgEndFrame(vg)
end
```

`drawSkeleton` 的实现见
[`docs/skeleton2d-integration-guide.md`](skeleton2d-integration-guide.md#23-绘制整个骨骼)。

---

## 步骤 4：装备武器

```lua
local AxeDef = {
    png = "weapons/axe.png", w = 24, h = 80,
    anchor = { 12, 70 }, attachAt = { 7, 7 }, restRot = 30, z = 5,
}

Skeleton.AttachWeapon(skel, AxeDef, "handR")
-- ... 后续切换：
Skeleton.DetachWeapon(skel)
```

挂上后 `inst.parts.weapon` 自动出现在 part 列表中，`drawSkeleton` 会按 z 序绘制。
注意 `weapon` 这个 key 也得在你的 `atlasRects` 表里有条目（武器一般用单独的图集）。

---

## 步骤 5（可选）：直接消费 JSON

`require` 加载 Lua 表是首选；如果你的环境必须读 JSON：

```lua
local cjson = require "cjson"
local SkelDef = cjson.decode(io.open("data/skeletons/humanoid.json", "rb"):read("*a"))
```

runtime 已兼容 `anchor = [x, y]`（数组）与 `anchor = { x = , y = }`（命名）两种格式。

---

## 升级 submodule

```bash
cd external/skeleton2d
git pull origin master
cd ../..
git add external/skeleton2d
git commit -m "chore: bump skeleton2d"
```

---

## 不再支持

下面这些是**历史方案**，已从仓库移除，不要写新代码再用：

- `Skeleton.SetBackend(...)` / `Skeleton.Draw(...)` / `Skeleton.Preload(...)` —— backend 抽象层
- `runtime/lua/backends/taptap_sprite.lua` —— UrhoX `StaticSprite2D` 后端（WebGL 不可用）
- 单 part PNG 直接挂 `cache:GetResource("Sprite2D", ...)` 的路径

如果你正在维护一个还在用上述 API 的旧项目，参考
`docs/taptap-integration-pitfalls.md` §3 / §7 做迁移。
