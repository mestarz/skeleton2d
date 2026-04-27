# 轻量级骨骼系统对接指南 — TapTap Maker (UrhoX)

> 本文档提供在 UrhoX 引擎中实现和对接轻量级 2D 骨骼动画系统的完整示例。
> 包含两种渲染方案（Sprite 节点 / NanoVG）以及碰撞解耦、部件管理等最佳实践。

---

## 目录

1. [核心概念](#1-核心概念)
2. [方案一：StaticSprite2D 节点渲染（推荐）](#2-方案一staticsprite2d-节点渲染推荐)
3. [方案二：NanoVG 渲染](#3-方案二nanovg-渲染)
4. [骨骼 Runtime 核心实现](#4-骨骼-runtime-核心实现)
5. [碰撞与动画解耦](#5-碰撞与动画解耦)
6. [程序化动画驱动](#6-程序化动画驱动)
7. [帧动画 vs 骨骼动画混用](#7-帧动画-vs-骨骼动画混用)
8. [API 速查](#8-api-速查)

---

## 1. 核心概念

### 骨骼系统的三层架构

```
┌─────────────────────────────────┐
│  驱动层（动画数据 / 程序化控制）    │  ← 输入：旋转角度、位移
├─────────────────────────────────┤
│  Runtime 层（变换递推）            │  ← 核心：local → world transform
├─────────────────────────────────┤
│  渲染层（Sprite 节点 / NanoVG）   │  ← 输出：把图画在正确位置
└─────────────────────────────────┘
```

### 数据流

```
骨骼定义 (table)
    ↓
每帧更新 bone.rotation / bone.x / bone.y（驱动层）
    ↓
递推计算 bone.wx, bone.wy, bone.wr（runtime 层）
    ↓
写到渲染目标（渲染层）
    ├── node.position2D = Vector2(wx, wy)     ← Sprite 方案
    └── nvgTranslate(vg, wx, wy)              ← NanoVG 方案
```

---

## 2. 方案一：StaticSprite2D 节点渲染（推荐）

适用于需要物理碰撞、场景交互的游戏。

### 2.1 加载单张部件图

```lua
-- 创建一个骨骼部件节点
local armNode = parentNode:CreateChild("arm_left")

-- 添加 StaticSprite2D 组件
local sprite = armNode:CreateComponent("StaticSprite2D")

-- 加载贴图（路径相对于 assets/）
sprite.sprite = cache:GetResource("Sprite2D", "Textures/arm_left.png")

-- 设置混合模式（带透明通道的 PNG）
sprite.blendMode = BLEND_ALPHA

-- 设置锚点（关节旋转中心）
-- (0.5, 0.5) = 图片中心
-- (0.5, 0.0) = 图片顶部中心（手臂上端为肩关节）
-- (0.5, 1.0) = 图片底部中心
sprite.useHotSpot = true
sprite.hotSpot = Vector2(0.5, 0.0)  -- 肩部为旋转中心

-- 设置绘制层级（数字越大越靠前）
sprite.orderInLayer = 5
```

### 2.2 设置节点变换

```lua
-- 2D 位置（单位：米）
armNode.position2D = Vector2(0.3, 1.2)

-- 2D 旋转（单位：度，逆时针为正）
armNode.rotation2D = -15.0

-- 2D 缩放
armNode:SetScale2D(Vector2(1.0, 1.0))

-- 翻转（角色转向）
sprite.flipX = true   -- 水平翻转
sprite.flipY = false  -- 垂直翻转
```

### 2.3 自定义绘制尺寸

```lua
-- 默认按贴图原始尺寸（像素 → 引擎单位，100px = 1米）
-- 如果需要自定义大小：
sprite.useDrawRect = true
sprite.drawRect = Rect(-0.3, -0.8, 0.3, 0.0)  -- left, bottom, right, top（米）
-- 这会将图片绘制在 0.6m 宽、0.8m 高的矩形内
```

### 2.4 局部纹理区域（图集切割）

```lua
-- 只显示贴图的一部分（UV 坐标，0~1 范围）
sprite.useTextureRect = true
sprite.textureRect = Rect(0.0, 0.0, 0.5, 1.0)  -- 只显示左半部分
```

### 2.5 颜色和透明度

```lua
-- 整体着色
sprite.color = Color(1.0, 0.8, 0.8, 1.0)  -- 略偏红

-- 单独设置透明度
sprite.alpha = 0.7
```

### 2.6 完整部件角色组装示例

```lua
--- 创建一个由多个 Sprite 部件组成的骨骼角色
---@param scene Scene
---@param position Vector2 角色位置
---@return Node characterNode 角色根节点
function CreateSkeletonCharacter(scene, position)
    -- 角色根节点
    local charNode = scene:CreateChild("Character")
    charNode.position2D = position

    -- 骨骼视觉根节点（和碰撞体解耦）
    local spriteRoot = charNode:CreateChild("SpriteRoot")

    -- 部件定义：name, 贴图路径, 锚点, 偏移, 层级
    local parts = {
        { name = "leg_l",  tex = "Parts/leg.png",   hotSpot = Vector2(0.5, 0.0), offset = Vector2(-0.15, 0.0),  order = 1 },
        { name = "leg_r",  tex = "Parts/leg.png",   hotSpot = Vector2(0.5, 0.0), offset = Vector2(0.15, 0.0),   order = 1 },
        { name = "torso",  tex = "Parts/torso.png", hotSpot = Vector2(0.5, 0.0), offset = Vector2(0.0, 0.4),    order = 2 },
        { name = "arm_l",  tex = "Parts/arm.png",   hotSpot = Vector2(0.5, 0.0), offset = Vector2(-0.25, 0.9),  order = 1 },
        { name = "arm_r",  tex = "Parts/arm.png",   hotSpot = Vector2(0.5, 0.0), offset = Vector2(0.25, 0.9),   order = 3 },
        { name = "head",   tex = "Parts/head.png",  hotSpot = Vector2(0.5, 0.2), offset = Vector2(0.0, 1.2),    order = 4 },
    }

    ---@type table<string, Node>
    local boneNodes = {}

    for _, part in ipairs(parts) do
        local node = spriteRoot:CreateChild(part.name)
        node.position2D = part.offset

        local spr = node:CreateComponent("StaticSprite2D")
        spr.sprite = cache:GetResource("Sprite2D", part.tex)
        spr.blendMode = BLEND_ALPHA
        spr.useHotSpot = true
        spr.hotSpot = part.hotSpot
        spr.orderInLayer = part.order

        boneNodes[part.name] = node
    end

    return charNode, boneNodes
end
```

---

## 3. 方案二：NanoVG 渲染

适用于纯 2D 渲染、不需要物理碰撞的场景。

### 3.1 加载图片

```lua
local vg = nil
local images = {}

function Start()
    vg = nvgCreate(0)

    -- 加载部件图片（返回 image handle）
    images.head  = nvgCreateImage(vg, "Parts/head.png", 0)
    images.torso = nvgCreateImage(vg, "Parts/torso.png", 0)
    images.arm   = nvgCreateImage(vg, "Parts/arm.png", 0)
    images.leg   = nvgCreateImage(vg, "Parts/leg.png", 0)

    SubscribeToEvent("NanoVGRender", "HandleNanoVGRender")
end
```

### 3.2 绘制单个部件

```lua
--- 在指定位置和旋转下绘制一个部件图
---@param vg userdata NanoVG context
---@param img number image handle
---@param x number 世界坐标 X
---@param y number 世界坐标 Y
---@param rotation number 旋转角度（度）
---@param pivotX number 锚点 X（像素，相对于图片左上角）
---@param pivotY number 锚点 Y（像素，相对于图片左上角）
---@param w number 图片宽度（像素）
---@param h number 图片高度（像素）
function DrawPart(vg, img, x, y, rotation, pivotX, pivotY, w, h)
    nvgSave(vg)

    -- 移动到世界位置
    nvgTranslate(vg, x, y)
    -- 旋转（NanoVG 用弧度）
    nvgRotate(vg, math.rad(rotation))
    -- 偏移锚点（让旋转中心在关节位置）
    nvgTranslate(vg, -pivotX, -pivotY)

    -- 绘制图片
    local paint = nvgImagePattern(vg, 0, 0, w, h, 0, img, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    nvgRestore(vg)
end
```

### 3.3 完整渲染回调

```lua
function HandleNanoVGRender(eventType, eventData)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()

    nvgBeginFrame(vg, w / dpr, h / dpr, dpr)

    -- 按层级顺序绘制（先画的在后面）
    -- 假设 bones 是 runtime 算好的世界变换
    DrawPart(vg, images.leg,   bones.leg_l.wx, bones.leg_l.wy, bones.leg_l.wr, 16, 0, 32, 64)
    DrawPart(vg, images.leg,   bones.leg_r.wx, bones.leg_r.wy, bones.leg_r.wr, 16, 0, 32, 64)
    DrawPart(vg, images.torso, bones.torso.wx, bones.torso.wy, bones.torso.wr, 32, 0, 64, 80)
    DrawPart(vg, images.arm,   bones.arm_l.wx, bones.arm_l.wy, bones.arm_l.wr, 8,  0, 16, 48)
    DrawPart(vg, images.arm,   bones.arm_r.wx, bones.arm_r.wy, bones.arm_r.wr, 8,  0, 16, 48)
    DrawPart(vg, images.head,  bones.head.wx,  bones.head.wy,  bones.head.wr,  32, 48, 64, 64)

    nvgEndFrame(vg)
end
```

---

## 4. 骨骼 Runtime 核心实现

这是与渲染方案无关的通用 runtime，计算骨骼树的世界变换。

### 4.1 骨骼定义

```lua
-- 骨骼树数据结构
-- x, y: 相对于父骨骼的本地偏移
-- rotation: 本地旋转（度）
-- length: 骨骼长度（可选，用于调试绘制）
local skeleton = {
    name = "root", x = 0, y = 0, rotation = 0,
    children = {
        {
            name = "torso", x = 0, y = 0.4, rotation = 0,
            children = {
                { name = "head",  x = 0,     y = 0.5, rotation = 0 },
                { name = "arm_l", x = -0.25, y = 0.45, rotation = 0 },
                { name = "arm_r", x = 0.25,  y = 0.45, rotation = 0 },
            }
        },
        { name = "leg_l", x = -0.12, y = 0, rotation = 0 },
        { name = "leg_r", x = 0.12,  y = 0, rotation = 0 },
    }
}
```

### 4.2 世界变换递推

```lua
--- 递推计算骨骼树的世界变换
---@param bone table 骨骼节点
---@param parentWX number 父骨骼世界 X
---@param parentWY number 父骨骼世界 Y
---@param parentWR number 父骨骼世界旋转（度）
function UpdateBoneTransforms(bone, parentWX, parentWY, parentWR)
    local rad = math.rad(parentWR)
    local cosR = math.cos(rad)
    local sinR = math.sin(rad)

    -- 本地坐标旋转到世界坐标
    bone.wx = parentWX + cosR * bone.x - sinR * bone.y
    bone.wy = parentWY + sinR * bone.x + cosR * bone.y
    bone.wr = parentWR + bone.rotation

    -- 递推子骨骼
    if bone.children then
        for _, child in ipairs(bone.children) do
            UpdateBoneTransforms(child, bone.wx, bone.wy, bone.wr)
        end
    end
end

-- 每帧调用
function UpdateSkeleton(skeleton, rootX, rootY, rootRotation)
    skeleton.x = rootX
    skeleton.y = rootY
    skeleton.rotation = rootRotation
    UpdateBoneTransforms(skeleton, 0, 0, 0)
end
```

### 4.3 骨骼查找辅助

```lua
--- 按名称在骨骼树中查找节点
---@param bone table
---@param name string
---@return table|nil
function FindBone(bone, name)
    if bone.name == name then return bone end
    if bone.children then
        for _, child in ipairs(bone.children) do
            local found = FindBone(child, name)
            if found then return found end
        end
    end
    return nil
end

-- 也可以在初始化时建一个 name → bone 的 lookup table
---@param bone table
---@param lookup table<string, table>
function BuildBoneLookup(bone, lookup)
    lookup[bone.name] = bone
    if bone.children then
        for _, child in ipairs(bone.children) do
            BuildBoneLookup(child, lookup)
        end
    end
end

-- 用法
local boneLookup = {}
BuildBoneLookup(skeleton, boneLookup)
local arm = boneLookup["arm_l"]
arm.rotation = 30  -- 直接修改
```

### 4.4 输出到 Sprite 节点

```lua
--- 将 runtime 计算的世界变换同步到引擎节点
---@param boneLookup table<string, table> 骨骼 name → bone 映射
---@param boneNodes table<string, Node> 骨骼 name → Node 映射
function SyncToNodes(boneLookup, boneNodes)
    for name, bone in pairs(boneLookup) do
        local node = boneNodes[name]
        if node then
            node.position2D = Vector2(bone.wx, bone.wy)
            node.rotation2D = bone.wr
        end
    end
end
```

---

## 5. 碰撞与动画解耦

### 5.1 标准结构

```lua
--[[
    CharacterNode              ← 物理碰撞体（简单形状）
    ├── RigidBody2D            ← 物理刚体
    ├── CollisionCircle2D      ← 碰撞形状
    │
    └── SpriteRoot             ← 视觉骨骼根（runtime 驱动）
        ├── torso (StaticSprite2D)
        ├── head  (StaticSprite2D)
        ├── arm_l (StaticSprite2D)
        ├── arm_r (StaticSprite2D)
        ├── leg_l (StaticSprite2D)
        └── leg_r (StaticSprite2D)
]]
```

### 5.2 实现

```lua
function CreateCharacterWithPhysics(scene, position)
    -- 根节点
    local charNode = scene:CreateChild("Character")
    charNode.position2D = position

    -- === 碰撞体（简单胶囊） ===
    local body = charNode:CreateComponent("RigidBody2D")
    body.bodyType = BT_DYNAMIC
    body.fixedRotation = true  -- 防止角色旋转

    -- 身体碰撞（椭圆用一个 Box 近似）
    local bodyShape = charNode:CreateComponent("CollisionBox2D")
    bodyShape.size = Vector2(0.5, 1.4)    -- 宽 0.5m，高 1.4m
    bodyShape.center = Vector2(0, 0.7)    -- 中心在脚上方 0.7m
    bodyShape.density = 1.0
    bodyShape.friction = 0.3

    -- 脚底传感器（地面检测）
    local footSensor = charNode:CreateComponent("CollisionCircle2D")
    footSensor.radius = 0.2
    footSensor.center = Vector2(0, 0.05)
    footSensor.isTrigger = true

    -- === 视觉骨骼（独立子树） ===
    local spriteRoot = charNode:CreateChild("SpriteRoot")
    -- ... 在 spriteRoot 下创建骨骼部件节点 ...

    return charNode, spriteRoot
end
```

### 5.3 受击判定（可选精细碰撞）

```lua
-- 如果需要部位精确受击判定，在关键骨骼上加 trigger 碰撞体
function AddHitboxToBone(boneNode, size)
    -- 注意：碰撞体需要 RigidBody2D（设为 Kinematic）
    local body = boneNode:CreateComponent("RigidBody2D")
    body.bodyType = BT_KINEMATIC

    local shape = boneNode:CreateComponent("CollisionBox2D")
    shape.size = size
    shape.isTrigger = true  -- 只检测，不产生物理反应

    return shape
end

-- 给头部加受击框
AddHitboxToBone(boneNodes["head"], Vector2(0.3, 0.3))
```

---

## 6. 程序化动画驱动

不使用关键帧数据，纯代码驱动骨骼旋转。

### 6.1 呼吸/待机动画

```lua
function AnimateIdle(boneLookup, time)
    local breath = math.sin(time * 2.0) * 2.0  -- ±2 度，2Hz

    boneLookup["torso"].rotation = breath * 0.5
    boneLookup["head"].rotation  = breath * 0.3
    boneLookup["arm_l"].rotation = breath * 1.0 + 5.0   -- 略微下垂
    boneLookup["arm_r"].rotation = breath * -1.0 - 5.0
end
```

### 6.2 走路/跑步动画

```lua
function AnimateRun(boneLookup, time, speed)
    local freq = speed * 3.0  -- 步频和速度挂钩
    local t = time * freq

    -- 腿交替摆动
    boneLookup["leg_l"].rotation = math.sin(t) * 30.0
    boneLookup["leg_r"].rotation = math.sin(t + math.pi) * 30.0  -- 反相

    -- 手臂反向摆动
    boneLookup["arm_l"].rotation = math.sin(t + math.pi) * 20.0
    boneLookup["arm_r"].rotation = math.sin(t) * 20.0

    -- 身体轻微前倾
    boneLookup["torso"].rotation = -5.0

    -- 头部稳定
    boneLookup["head"].rotation = 5.0  -- 补偿身体前倾
end
```

### 6.3 角色朝向翻转

```lua
--- 翻转角色（Sprite 方案）
---@param boneNodes table<string, Node>
---@param faceLeft boolean
function FlipCharacter(boneNodes, faceLeft)
    for _, node in pairs(boneNodes) do
        local sprite = node:GetComponent("StaticSprite2D")
        if sprite then
            sprite.flipX = faceLeft
        end
    end
end

-- 或者直接缩放 SpriteRoot
spriteRoot:SetScale2D(Vector2(faceLeft and -1.0 or 1.0, 1.0))
```

---

## 7. 帧动画 vs 骨骼动画混用

项目中已有完整帧图素材（`assets/Sprites/`），可以和骨骼系统混用。

### 7.1 帧动画播放器（StaticSprite2D 方式）

```lua
---@class FrameAnimPlayer
---@field frames Sprite2D[]
---@field sprite StaticSprite2D
---@field frameTime number
---@field elapsed number
---@field currentFrame number
local FrameAnimPlayer = {}
FrameAnimPlayer.__index = FrameAnimPlayer

--- 创建帧动画播放器
---@param node Node
---@param framePaths string[] 帧图片路径列表
---@param fps number 帧率
---@return FrameAnimPlayer
function FrameAnimPlayer.New(node, framePaths, fps)
    local self = setmetatable({}, FrameAnimPlayer)

    self.sprite = node:GetComponent("StaticSprite2D")
    if not self.sprite then
        self.sprite = node:CreateComponent("StaticSprite2D")
        self.sprite.blendMode = BLEND_ALPHA
    end

    -- 预加载所有帧
    self.frames = {}
    for i, path in ipairs(framePaths) do
        self.frames[i] = cache:GetResource("Sprite2D", path)
    end

    self.frameTime = 1.0 / fps
    self.elapsed = 0
    self.currentFrame = 1

    -- 显示第一帧
    self.sprite.sprite = self.frames[1]

    return self
end

--- 每帧更新
---@param dt number deltaTime
function FrameAnimPlayer:Update(dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed >= self.frameTime then
        self.elapsed = self.elapsed - self.frameTime
        self.currentFrame = self.currentFrame % #self.frames + 1
        self.sprite.sprite = self.frames[self.currentFrame]
    end
end

-- 用法：
local idleFrames = {}
for i = 1, 8 do
    idleFrames[i] = string.format("Sprites/female/civilian_f_1_idle/frame_%02d.png", i)
end
local animPlayer = FrameAnimPlayer.New(characterNode, idleFrames, 10)

-- 在 HandleUpdate 中：
animPlayer:Update(dt)
```

### 7.2 策略选择

```
角色有部件拆分图 → 骨骼 runtime + StaticSprite2D
角色只有完整帧图 → FrameAnimPlayer
同一项目可以混用：
  - 主角用骨骼（动作丰富、需要程序化控制）
  - NPC 用帧动画（动作固定、美术已画好）
```

---

## 8. API 速查

### StaticSprite2D 常用属性

| 属性              | 类型      | 说明                           |
| ----------------- | --------- | ------------------------------ |
| `sprite`          | Sprite2D  | 贴图资源                       |
| `blendMode`       | BlendMode | 混合模式（`BLEND_ALPHA` 常用） |
| `flipX` / `flipY` | bool      | 水平/垂直翻转                  |
| `color`           | Color     | 着色                           |
| `alpha`           | float     | 透明度 0~1                     |
| `useHotSpot`      | bool      | 是否使用自定义锚点             |
| `hotSpot`         | Vector2   | 锚点位置（0~1 归一化）         |
| `orderInLayer`    | int       | 绘制层级（越大越靠前）         |
| `useDrawRect`     | bool      | 是否自定义绘制尺寸             |
| `drawRect`        | Rect      | 自定义绘制矩形（米）           |
| `useTextureRect`  | bool      | 是否使用局部纹理               |
| `textureRect`     | Rect      | 纹理 UV 区域（0~1）            |

### Sprite2D 资源属性

| 属性        | 类型       | 说明               |
| ----------- | ---------- | ------------------ |
| `texture`   | Texture2D  | 底层纹理           |
| `rectangle` | IntRect    | 在纹理中的像素区域 |
| `hotSpot`   | Vector2    | 默认锚点           |
| `offset`    | IntVector2 | 像素偏移           |

### SpriteSheet2D（图集）

```lua
-- 创建图集并手动定义切割区域
local sheet = SpriteSheet2D:new()
sheet.texture = cache:GetResource("Texture2D", "Parts/atlas.png")

-- 定义子精灵：name, 像素区域, 锚点
sheet:DefineSprite("head",  IntRect(0, 0, 64, 64),   Vector2(0.5, 0.5))
sheet:DefineSprite("torso", IntRect(64, 0, 128, 96),  Vector2(0.5, 0.0))
sheet:DefineSprite("arm",   IntRect(128, 0, 160, 64), Vector2(0.5, 0.0))

-- 获取子精灵
local headSprite = sheet:GetSprite("head")
sprite.sprite = headSprite
```

### Node 2D 变换

| 方法/属性                  | 说明               |
| -------------------------- | ------------------ |
| `node.position2D`          | Vector2 位置（米） |
| `node.rotation2D`          | float 旋转（度）   |
| `node:SetScale2D(Vector2)` | 2D 缩放            |

### NanoVG 图片绘制

| 函数                                              | 说明                  |
| ------------------------------------------------- | --------------------- |
| `nvgCreateImage(vg, path, flags)`                 | 加载图片，返回 handle |
| `nvgImagePattern(vg, x,y,w,h, angle, img, alpha)` | 创建图片填充 paint    |
| `nvgSave(vg)` / `nvgRestore(vg)`                  | 保存/恢复变换状态     |
| `nvgTranslate(vg, x, y)`                          | 平移                  |
| `nvgRotate(vg, radians)`                          | 旋转（弧度）          |
| `nvgScale(vg, sx, sy)`                            | 缩放                  |
