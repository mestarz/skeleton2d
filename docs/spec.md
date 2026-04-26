# 数据规范

## 设计目标

- **JSON 为单一真相源**，编辑器读写 JSON。Lua 表是从 JSON 一键导出的便利产物。
- **关键帧只用 `rot` 单通道**，线性插值。MVP 不支持曲线/缓动/`tx/ty/scale`。
- **所有坐标为本地坐标**，原点是父骨骼的 anchor 点；rotation 顺时针为正（与 Canvas/NanoVG 一致）。

## skeleton.json

```jsonc
{
  "id": "humanoid",       // 唯一标识，导出 Lua 文件用作模块名
  "version": 1,           // 始终 1
  "root": "torso",        // 可选，未指定时取首个 parent=null 的部件
  "parts": {
    "<partName>": {
      "parent":   "torso",        // null 或省略 = 根
      "png":      "head.png",     // 相对资源路径；null 时用 placeholderColor 填充
      "w": 50, "h": 50,           // 部件原始像素尺寸
      "anchor":   [25, 50],       // 部件本地坐标系内的旋转中心（关节点）
      "attachAt": [30, 0],        // 父骨骼本地坐标系内的挂载点
      "restRot":  0,              // 静止角度（度）；动画 track 会覆写
      "z":        1,              // 同父绘制顺序，大者后画（在上层）
      "placeholderColor": [230, 200, 160, 230]  // 缺图时的占位色 RGBA
    }
  }
}
```

### 命名约定

- 部件名用驼峰：`torso / head / upperArmL / lowerArmR / handL`
- `L`/`R` 后缀 = 玩家视角（角色面朝右时）的左右；即角色自身右手 = `handR`
- 推荐挂点：`weapon` / `hat` / `backpack`（动态挂在 `handR` / `head` / `torso`）

### 推荐 14 部件人型骨骼

```
torso (root)
├─ head
├─ upperArmL → lowerArmL → handL
├─ upperArmR → lowerArmR → handR     ← 武器挂点
├─ thighL    → shinL     → footL
└─ thighR    → shinR     → footR
```

参考 `examples/humanoid/skeleton.json`。

## animations.json

```jsonc
{
  "<animName>": {
    "duration": 0.4,            // 秒
    "loop": false,              // true = 循环；false = 播完停止
    "tracks": {
      "<partName>": [
        { "t": 0.0,  "rot": 0   },
        { "t": 0.1,  "rot": -90 },
        { "t": 0.2,  "rot": 60  },
        { "t": 0.4,  "rot": 0   }
      ]
    }
  }
}
```

- `t` 必须在 `[0, duration]` 内
- 关键帧无需排序，runtime/编辑器都会自动排
- 缺失 keyframe 的部件保持 `restRot`

### 全角色共用动作集

骨骼方案的杠杆：N 个角色共用同一套动作 JSON。建议至少包含 `idle / walk / swing / shoot / hit`。详见 `examples/humanoid/animations.json`。

## 武器（动态挂载）

武器不写在 skeleton.json 里。装备时由代码动态挂到 `handR`：

```lua
Skeleton.AttachWeapon(inst, {
    png = "weapons/axe.png",
    w = 24, h = 80,
    anchor   = { 12, 70 },   -- 握把
    attachAt = { 7,  7 },    -- handR 内的握紧点
    restRot  = 30,
    z        = 5,
})
```

`swing` 等动画作用于 `upperArmR/lowerArmR`，武器自动跟随。

## 坐标系总结

- 屏幕坐标：Y 向下、X 向右（与 Canvas / NanoVG 一致）
- 旋转：顺时针为正
- 部件绘制顺序：先递归画父，再画子
  - 同父之间按 `z` 升序，`z` 大的后画 = 在视觉上层
- `Draw(x, y, facing, scale)`：(x, y) 是 root 的世界落地点；`facing=-1` 时整张图水平镜像
