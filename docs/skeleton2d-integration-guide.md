# 轻量级骨骼系统对接指南 — TapTap Maker (UrhoX) / NanoVG

> 本仓库**只针对 NanoVG immediate-mode 渲染**做集成。
> StaticSprite2D / Scene-graph 路径在 UrhoX WebGL 不可用，
> 历史方案已从代码与文档中移除（见 `docs/taptap-integration-pitfalls.md` §7）。

---

## 目录

1. [核心概念](#1-核心概念)
2. [NanoVG 渲染管线](#2-nanovg-渲染管线)
3. [骨骼 Runtime 使用](#3-骨骼-runtime-使用)
4. [程序化动画驱动](#4-程序化动画驱动)
5. [图集（Atlas）打包约定](#5-图集atlas打包约定)
6. [API 速查](#6-api-速查)

---

## 1. 核心概念

### 三层架构

```
┌─────────────────────────────────────┐
│  驱动层（关键帧动画 / 程序化控制）       │  ← 设置 part.currentRot 或调 Skeleton.Play
├─────────────────────────────────────┤
│  Runtime 层（变换递推）                │  ← Skeleton.Update + UpdateWorldTransforms
├─────────────────────────────────────┤
│  渲染层（NanoVG immediate-mode）      │  ← 自己遍历 inst.parts，nvgImagePattern 画图集子区域
└─────────────────────────────────────┘
```

### 数据流

```
skeleton.json / .lua (table)
      ↓ Skeleton.New(def)
inst.parts[*]  含 parent / attachAt / anchor / png / w / h / restRot / z
      ↓ Skeleton.Play(inst, anim) + Skeleton.Update(inst, dt)
inst.parts[*].currentRot
      ↓ Skeleton.UpdateWorldTransforms(inst)
inst.parts[*].wx / wy / wr     ← 像素坐标 + 度，相对骨骼根
      ↓ 主循环每帧 nvgSave/Translate/Rotate + nvgImagePattern + nvgFill
屏幕
```

> Runtime 不做绘制，也不持有 NanoVG 上下文；它只把骨骼树折算成"每个 part 的世界变换"。
> 这套抽象的好处是 runtime 可以在编辑器（JS / Canvas）和游戏（Lua / NanoVG）之间复用。

---

## 2. NanoVG 渲染管线

### 2.1 初始化

```lua
local vg
local atlasImages = {}      -- key: 图集相对路径, value: nvg image handle

function Start()
    vg = nvgCreate(0)
    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
end

local function loadAtlas(path)
    if not atlasImages[path] then
        atlasImages[path] = nvgCreateImage(vg, path, 0)
    end
    return atlasImages[path]
end
```

### 2.2 绘制图集子区域

> 这是接 atlas 的核心套路。NanoVG 没有"画 sub-rect"的直接 API，
> 我们用 `nvgImagePattern` 把整张图集"虚拟放大 + 反向偏移"，
> 让目标子区域恰好对齐到 `nvgRect` 的位置。

```lua
--- 在 (x, y, w, h) 处绘制图集 atlas 中的子区域 rect
---@param atlasHandle number nvgCreateImage 返回值
---@param rect table { x, y, w, h }   像素坐标，Y 向下
---@param x number 目标位置（屏幕/局部坐标）
---@param y number
---@param w number 目标宽度
---@param h number 目标高度
local function drawAtlasRegion(atlasHandle, rect, x, y, w, h)
    local atlasW, atlasH = nvgImageSize(vg, atlasHandle)

    local scaleX = w / rect.w
    local scaleY = h / rect.h
    local patW   = atlasW * scaleX
    local patH   = atlasH * scaleY
    local ox     = x - rect.x * scaleX
    local oy     = y - rect.y * scaleY

    local paint = nvgImagePattern(vg, ox, oy, patW, patH, 0, atlasHandle, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end
```

### 2.3 绘制整个骨骼

```lua
--- @param inst   骨骼实例（Skeleton.New 的返回值）
--- @param sx,sy  屏幕位置（像素）
--- @param facing 1 或 -1（用于水平镜像）
--- @param sc     缩放
local function drawSkeleton(inst, atlasHandle, atlasRects, sx, sy, facing, sc)
    nvgSave(vg)
    nvgTranslate(vg, sx, sy)
    if facing < 0 then nvgScale(vg, -sc, sc) else nvgScale(vg, sc, sc) end

    -- 收集所有 part 按 z 升序绘制
    local sorted = {}
    for name, p in pairs(inst.parts) do
        if p.wx ~= nil then sorted[#sorted + 1] = { name = name, p = p } end
    end
    table.sort(sorted, function(a, b) return a.p.z < b.p.z end)

    for _, item in ipairs(sorted) do
        local name, p = item.name, item.p
        local rect = atlasRects[name]
        if rect then
            nvgSave(vg)
            nvgTranslate(vg, p.wx, p.wy)
            nvgRotate(vg, math.rad(p.wr or 0))
            nvgTranslate(vg, -p.anchor[1], -p.anchor[2])
            drawAtlasRegion(atlasHandle, rect, 0, 0, p.w, p.h)
            nvgRestore(vg)
        end
    end

    nvgRestore(vg)
end
```

### 2.4 渲染回调

```lua
function HandleNanoVGRender(eventType, eventData)
    local W, H, dpr = graphics:GetWidth(), graphics:GetHeight(), graphics:GetDPR()
    nvgBeginFrame(vg, W / dpr, H / dpr, dpr)

    drawSkeleton(skelInst, currentAtlas, currentAtlasRects,
                 W / dpr / 2, H / dpr / 2, facing, 1.0)

    nvgEndFrame(vg)
end
```

完整可运行示例参考 `scripts/main.lua`。

---

## 3. 骨骼 Runtime 使用

### 3.1 加载骨骼 + 动画

```lua
local Skeleton = require "SkeletonRenderer"
local SkelDef  = require "police_m.skeleton"
local Anims    = require "police_m.animations"

local skelInst = Skeleton.New(SkelDef)
Skeleton.Play(skelInst, Anims.idle, { loop = true })
```

### 3.2 每帧驱动

```lua
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    Skeleton.Update(skelInst, dt)              -- 关键帧采样 → currentRot
    Skeleton.UpdateWorldTransforms(skelInst)   -- 写 part.wx/wy/wr
end
```

### 3.3 武器挂点

```lua
local AxeDef = {
    png = "weapons/axe.png", w = 24, h = 80,
    anchor = { 12, 70 }, attachAt = { 7, 7 }, restRot = 30, z = 5,
}

Skeleton.AttachWeapon(skelInst, AxeDef, "handR")
-- ... 切换 / 卸下：
Skeleton.DetachWeapon(skelInst)
```

挂上后 `inst.parts.weapon` 出现在 part 列表中，`drawSkeleton` 会自动按 z 序绘制。

### 3.4 公开 API

| API | 作用 |
|---|---|
| `Skeleton.New(def)` | 解析骨骼 def，返回实例 |
| `Skeleton.Play(inst, anim, opts)` | 切动画；`opts.loop` 覆盖 `anim.loop` |
| `Skeleton.Update(inst, dt)` | 推进 phase + 写 currentRot |
| `Skeleton.UpdateWorldTransforms(inst)` | 递推填充 `part.wx/wy/wr` |
| `Skeleton.AttachWeapon(inst, def, parentName)` | 动态挂武器（默认 `handR`） |
| `Skeleton.DetachWeapon(inst)` | 卸武器 |

> 这些之外的字段（`Draw / SetBackend / Preload / fillRect / drawImage / ...`）**不存在**，
> 仓库已清理；任何还引用这些 API 的代码都是过时残留，请改为自绘 + UpdateWorldTransforms。

---

## 4. 程序化动画驱动

不用关键帧，纯代码改 `inst.parts[name].currentRot`，然后照常调 `UpdateWorldTransforms`。

> ⚠️ 顺序：必须在 `Skeleton.Update(inst, dt)` **之后**改 currentRot。
> 因为 `Update` 会先用关键帧覆盖一次。如果你不要关键帧，干脆不调 `Skeleton.Play`。

### 4.1 呼吸/待机抖动

```lua
local time = 0
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    time = time + dt

    -- 不调 Skeleton.Update：纯程序化控制
    local breath = math.sin(time * 2.0) * 2.0
    skelInst.parts.torso.currentRot = breath
    skelInst.parts.head.currentRot  = breath * 0.5

    Skeleton.UpdateWorldTransforms(skelInst)
end
```

### 4.2 IK 风格手部跟随鼠标

```lua
-- 简单 2 段 IK：upperArmR + lowerArmR 让 handR 朝向鼠标
local function aimRight(inst, mouseX, mouseY)
    local shoulder = inst.parts.upperArmR
    local sx, sy = (shoulder.wx or 0), (shoulder.wy or 0)
    local angle = math.deg(math.atan(mouseY - sy, mouseX - sx))
    inst.parts.upperArmR.currentRot = angle
    inst.parts.lowerArmR.currentRot = 0
end
```

---

## 5. 图集（Atlas）打包约定

### 5.1 为什么必须用图集

TapTap Maker 单项目纹理资源数有上限（约 32 张就开始 cooking 失败）。
30+ 个 part PNG 必须打包成少数几张 atlas。详细成因见
`docs/taptap-integration-pitfalls.md` §1。

### 5.2 atlas 文件约定

- **POW2 尺寸**：`512 × 1024`、`256 × 128` 这样的 2 的幂。
  非 POW2 会导致 ASTC/ETC 压缩跳过、显存浪费。
- **网格布局**：行高 = max(part.h)，列宽 = max(part.w)，简单粗暴；
  打包脚本 `tools/split_character.py` 可参照。
- **PNG 必须带 sRGB chunk**：不带的话 cooking 会跳过 ASTC 压缩。
  详见 pitfalls §5。

### 5.3 atlasRects 元数据

```lua
local ATLAS_RECTS = {
    police_m = {  -- atlas: 512x1024
        torso = { x = 0,   y = 0,   w = 100, h = 140 },
        head  = { x = 120, y = 0,   w = 120, h = 135 },
        -- ...
    },
}
```

- 坐标是**像素，Y 向下**（atlas 左上角原点）。
- key 必须跟 `skeleton.parts` 的 key 一致。
- `drawAtlasRegion` 内部会把它换算成 NanoVG pattern 的反向偏移。

### 5.4 数据生成

`tools/split_character.py` 输入"原始大图 + bbox 配置"（见 `tools/configs/*.json`），
一次性输出：

- `assets/Textures/<character>_atlas.png`（POW2 网格）
- `<character>/skeleton.json`（含 `parent / anchor / attachAt / w / h / z`）
- `ATLAS_RECTS` 表（可粘到 main.lua）

---

## 6. API 速查

### 6.1 NanoVG 图片绘制

| 函数 | 说明 |
|---|---|
| `nvgCreateImage(vg, path, flags)` | 加载图片，返回 handle；同一 path 自己缓存复用 |
| `nvgImageSize(vg, handle)` | 返回 `atlasW, atlasH`（像素） |
| `nvgImagePattern(vg, ox, oy, patW, patH, angle, img, alpha)` | 创建图片填充 paint |
| `nvgFillPaint(vg, paint)` + `nvgFill(vg)` | 应用 paint 到当前 path |

### 6.2 NanoVG 变换栈

| 函数 | 说明 |
|---|---|
| `nvgSave(vg)` / `nvgRestore(vg)` | 保存/恢复变换 + 状态 |
| `nvgTranslate(vg, x, y)` | 平移 |
| `nvgRotate(vg, radians)` | 旋转（弧度，顺时针为正） |
| `nvgScale(vg, sx, sy)` | 缩放（`-sx` 实现水平翻转） |

### 6.3 SkeletonRenderer

参见 §3.4。除此之外字段都已不存在。

### 6.4 单位与坐标

| 量 | 单位 / 方向 |
|---|---|
| `part.w / h / anchor / attachAt` | 像素，Y 向下（编辑器画布约定） |
| `part.wx / wy` | 像素（相对骨骼根），Y 向下 |
| `part.wr / restRot / track.rot` | 度，顺时针为正（与 NanoVG 一致） |
| atlas `rect.x / y / w / h` | 图集像素坐标，Y 向下 |
| NanoVG 屏幕坐标 | 像素，Y 向下 |

> 所有"像素 vs 米"、"Y 向上 vs 向下"的换算在 NanoVG 路径下**一律不需要**——
> 不再经过 UrhoX 2D Scene-graph，全程像素 + Y 向下，省心。
