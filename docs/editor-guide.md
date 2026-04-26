# 编辑器使用指南

## 启动

```bash
# 从仓库根启动（推荐，"Load humanoid example" 才能 fetch 示例）
cd /path/to/skeleton2d
python3 -m http.server 8080
# 浏览器打开 http://localhost:8080/editor/
```

> 也可双击 `editor/index.html` 走 `file://`，但 "Load humanoid example" 会被浏览器 CORS 拒绝。其他功能（拖拽 PNG、用文件选择器加载本地 JSON、导出）均可正常使用。

## 界面

```
┌─────────────────────────────────────────────────────────────┐
│  topbar：load / export                                      │
├──────────┬──────────────────────────────────┬──────────────┤
│ Parts    │  Canvas                          │ Part / Anim  │
│ list     │  (drag handles to adjust)        │ properties   │
│          │                                  │              │
├──────────┴──────────────────────────────────┴──────────────┤
│  Timeline：anim select / play-pause / time slider           │
└─────────────────────────────────────────────────────────────┘
```

## 操作

### 加载部件 PNG

3 种方式（任选）：
1. **拖拽到部件名**（左侧 list） → 自动赋给该部件
2. **拖拽到画布任意位置** → 赋给当前选中部件
3. 选中部件 → 右侧 Part 标签页 → 点 "Load PNG"

加载后部件的 `w / h` 会自动设为图片原始尺寸。

### 调骨骼 anchor / attachAt

- 先选中部件（点左侧 list）
- 在画布上：
  - **左键拖拽** = 调 `anchor`（部件本地的旋转中心，红圆点）
  - **Alt + 左键拖拽** = 调 `attachAt`（父空间内的挂载点，蓝圆点）
  - **Shift + 左键拖拽** = 平移视图原点
- 也可在右侧直接输入数值
- 角度 `restRot` 与 `z` 用右侧数值框

### 编辑动作关键帧

1. 选中要编辑的部件
2. 顶部右侧切到 **Animation** 标签
3. 时间轴拖动到目标 `t`
4. 调右侧的 `restRot`（或在画布上观察姿态）
5. 点 **+ Add KF at current time** → 把当前部件的当前 rot 写入此动作的 track

或在 Keyframes 列表里直接改 `t / rot` / 删除。

### 新建动作

Animation 标签底部输入名字 → `+`。

### 播放预览

- ▶ 开始 / ⏸ 暂停 / ⟲ 重播
- → ↔ ← 切换朝向
- scale 滑条调画面缩放

### 导出

- **Export skeleton (JSON+Lua)** → 同时下载 `<id>.json` 和 `<id>.lua`
- **Export animations (JSON+Lua)** → 下载 `animations.json` 和 `animations.lua`

直接拖回 BaiSiYeShou 主仓库的 `scripts/data/skeletons/` 即可。

## 常见问题

**Q: PNG 加载后骨骼对不齐**
A: PNG 内的关节中心需要标到 `anchor`。比如上臂 PNG 的肩膀像素位置。MVP 用拖拽近似调即可。

**Q: 部件互相穿模 / 顺序不对**
A: 调 `z`。同父部件按 z 升序绘制，大 z 在上。例：右手在身前 → `upperArmR.z = 2`。

**Q: 动作播完不停**
A: 动作勾上 `loop = false`，调用方传 `Skeleton.Play(inst, anim, { loop = false })`。

**Q: 编辑器坐标和游戏里不一样？**
A: 编辑器视图缩放/朝向只影响显示，导出的 JSON 数据是本地坐标，与游戏一致。
