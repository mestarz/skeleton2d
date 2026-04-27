# 集成到 Lua 项目（以 BaiSiYeShou 为例）

## 步骤 1：作为 git submodule 加入

```bash
cd /path/to/your-game
git submodule add git@github.com:mestarz/skeleton2d.git external/skeleton2d
git commit -m "chore: add skeleton2d submodule"
```

之后克隆时：

```bash
git clone --recurse-submodules <your-game-repo>
# 或已 clone：
git submodule update --init --recursive
```

## 步骤 2：在 Lua 入口注入后端

skeleton2d 的 runtime 不依赖任何特定渲染库，需要你提供 4 组接口：

```lua
local Skeleton = require "external.skeleton2d.runtime.lua.SkeletonRenderer"
local R  = require "Renderer"
local AL = require "AssetLoader"

Skeleton.SetBackend({
    -- 绘制
    drawImage = function(handle, x, y, w, h)
        R.DrawImage(handle, x, y, w, h, 1.0)
    end,
    fillRect  = function(x, y, w, h, rgba)
        R.FillRect(x, y, w, h, rgba)
    end,

    -- 资源
    getImage = function(path)
        local h = AL.GetHandle(path)
        return (h and h > 0) and h or nil
    end,
    enqueueImage = function(path)
        AL.EnqueueImage(path)
    end,

    -- 变换栈（NanoVG 直接转）
    pushTransform = function() nvgSave(R.GetVG()) end,
    popTransform  = function() nvgRestore(R.GetVG()) end,
    translate = function(x, y) nvgTranslate(R.GetVG(), x, y) end,
    rotate    = function(rad)  nvgRotate(R.GetVG(), rad) end,
    scale     = function(sx, sy) nvgScale(R.GetVG(), sx, sy) end,
})
```

> `Skeleton.SetBackend` 全局生效，**只需在游戏启动时调一次**。

## 步骤 3：require 编辑器导出的数据

把编辑器导出的 `humanoid.lua` / `animations.lua` 拷到主仓库：

```
scripts/
  data/
    skeletons/
      humanoid.lua          ← 来自编辑器
    animations/
      humanoid.lua          ← 来自编辑器
```

```lua
local SkelDef = require "data.skeletons.humanoid"
local Anims   = require "data.animations.humanoid"
```

## 步骤 4：使用

```lua
-- 在角色实体里
function Player.Init(self)
    self.skeleton = Skeleton.New(SkelDef)
    Skeleton.Preload(self.skeleton)
    Skeleton.Play(self.skeleton, Anims.idle)
end

function Player.Update(self, dt)
    -- 决定动作
    local anim = self.attacking and Anims.swing
              or self.moving    and Anims.walk
              or                   Anims.idle
    Skeleton.Play(self.skeleton, anim, { loop = anim ~= Anims.swing })
    Skeleton.Update(self.skeleton, dt)
end

function Player.Draw(self)
    Skeleton.Draw(self.skeleton, self.x, self.y, self.facing or 1, 1.0)
end
```

## 步骤 5：装备武器

```lua
function Player.EquipWeapon(self, weaponId)
    local def = WeaponSkelDB.Get(weaponId)  -- 由你定义的小表
    Skeleton.AttachWeapon(self.skeleton, def, "handR")
end

function Player.UnequipWeapon(self)
    Skeleton.DetachWeapon(self.skeleton)
end
```

`def` 示例：

```lua
return {
    png = "weapons/axe.png",
    w = 24, h = 80,
    anchor   = { 12, 70 },
    attachAt = { 7,  7 },
    restRot  = 30,
    z        = 5,
}
```

## 直接消费 JSON（不导出 Lua）

如果你的环境有 JSON 解码器，可以跳过 Lua 导出，直接：

```lua
local cjson = require "cjson"
local function loadJSON(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a"); f:close()
    return cjson.decode(data)
end

local SkelDef = loadJSON("data/skeletons/humanoid.json")
local Anims   = loadJSON("data/animations/humanoid.json")
```

runtime 已兼容 `anchor = [x, y]`（数组）与 `anchor = { x = , y = }`（命名）两种格式。

---

## TapTap Maker (UrhoX) Sprite 集成

如果目标平台是 **TapTap Maker / UrhoX**，骨骼部件应直接挂成 `StaticSprite2D` 节点，
让引擎场景图来绘制（自动支持物理、批处理、混合层级）。skeleton2d 自带适配器：
`runtime/lua/backends/taptap_sprite.lua`。

### 一次性建节点

```lua
local Skeleton = require "external.skeleton2d.runtime.lua.SkeletonRenderer"
local SpriteBE = require "external.skeleton2d.runtime.lua.backends.taptap_sprite"

local SkelDef = require "data.skeletons.humanoid"
local Anims   = require "data.animations.humanoid"

function Player.Init(self, scene, spawnPos)
    self.charNode = scene:CreateChild("Player")
    self.charNode.position2D = spawnPos

    -- 物理碰撞 / TouchControls 等其他组件挂在 charNode
    -- ...

    -- 骨骼视觉根（与碰撞解耦，方便整体翻转 / 缩放）
    self.spriteRoot = self.charNode:CreateChild("SpriteRoot")

    self.skeleton  = Skeleton.New(SkelDef)
    self.boneNodes = SpriteBE.CreateNodes(self.spriteRoot, self.skeleton, {
        cache            = cache,         -- ResourceCache（全局即可省略）
        texturePrefix    = "Textures/",
        pixelsPerMeter   = 100,
        baseOrderInLayer = 0,
    })

    Skeleton.Play(self.skeleton, Anims.idle)
end
```

> **重要**：`SkelDef.parts[*].png` 应是相对 `texturePrefix` 的路径。例如 `parts.head.png = "head.png"`，
> 加上前缀 `"Textures/"` 解析为 `cache:GetResource("Sprite2D", "Textures/head.png")`。

### 每帧

```lua
function Player.Update(self, dt)
    -- 切动作（可任意时刻调）
    Skeleton.Play(self.skeleton,
        self.attacking and Anims.swing
        or self.moving and Anims.walk
        or Anims.idle)

    Skeleton.Update(self.skeleton, dt)              -- 算 currentRot
    Skeleton.UpdateWorldTransforms(self.skeleton)   -- 算 wx / wy / wr
    SpriteBE.Sync(self.boneNodes, self.skeleton)    -- 写到 node.position2D / rotation2D
end

function Player.SetFacing(self, facing)
    self.spriteRoot:SetScale2D(Vector2(facing < 0 and -1 or 1, 1))
end

function Player.Destroy(self)
    SpriteBE.Destroy(self.boneNodes)
    self.charNode:Remove()
end
```

> **不要** 在 `Player.Update` 里画图；StaticSprite2D 由引擎自动渲染。

### 装备武器

```lua
local AxeDef = {
    png = "weapons/axe.png", w = 24, h = 80,
    anchor = { 12, 70 }, attachAt = { 7, 7 }, restRot = 30, z = 5,
}

function Player.EquipWeapon(self)
    Skeleton.AttachWeapon(self.skeleton, AxeDef, "handR")
    SpriteBE.AttachPart(self.boneNodes, self.spriteRoot, self.skeleton, "weapon", {
        cache = cache, texturePrefix = "Textures/", pixelsPerMeter = 100,
    })
end

function Player.UnequipWeapon(self)
    SpriteBE.DetachPart(self.boneNodes, "weapon")
    Skeleton.DetachWeapon(self.skeleton)
end
```

### 坐标系约定

- skeleton2d 内部坐标系：**像素，Y 向下**（编辑器画布约定）。
- UrhoX 2D 坐标系：**米（默认 100px=1m），Y 向上**。
- 适配器自动按 `pixelsPerMeter` 换算并翻转 Y / 旋转方向，使最终视觉与编辑器一致。
- 如果你的素材方向跟编辑器相反，可以在 `spriteRoot:SetScale2D(Vector2(1, -1))` 上手动翻转。

### 性能小贴士

- `CreateNodes` 只在角色 Init 时调一次；`Sync` 是每帧热路径，没有 GC 分配。
- 同一动作切换到 `Skeleton.Play` 是 no-op（除非 `restart=true`），不会重置 phase。
- 角色不可见时可以 `self.spriteRoot.enabled = false` 暂停整子树渲染（runtime 不需要停）。

---

## 升级 submodule

```bash
cd external/skeleton2d
git pull origin master
cd ../..
git add external/skeleton2d
git commit -m "chore: bump skeleton2d"
```
