# skeleton2d × TapTap Maker (UrhoX) 集成踩坑集

本文沉淀把 `skeleton2d` 这套轻量骨骼 runtime 接入 TapTap Maker（底层引擎为 UrhoX，
WebGL 跑 Lua 脚本）过程中遇到的全部环境性问题。每条按 **现象 → 根因 → 修复 → 经验** 组织，
用于：

- 后续接入新角色/新武器/新动画时少走弯路
- 给迁移到其它"Lua + 受限引擎"环境的同学提供参照

> 版本基线：仓库 commit `66f1968` (master)，时间线见末尾 [提交时间线](#提交时间线)。

---

## 目录

1. [纹理打包：32 张贴图的 cooking 上限](#1-纹理打包32-张贴图的-cooking-上限)
2. [Lua LSP 误报引擎全局符号](#2-lua-lsp-误报引擎全局符号)
3. [图集加载失败时的"二次错误风暴"](#3-图集加载失败时的二次错误风暴)
4. [仓库结构：git root 与符号链接的兼容性](#4-仓库结构git-root-与符号链接的兼容性)
5. [PNG 缺 sRGB chunk 导致 ASTC 压缩被跳过](#5-png-缺-srgb-chunk-导致-astc-压缩被跳过)
6. [textureRect 的 UV Y 轴方向](#6-texturerect-的-uv-y-轴方向)
7. [StaticSprite2D 在 UrhoX WebGL 不可用 → 切 NanoVG](#7-staticsprite2d-在-urhox-webgl-不可用--切-nanovg)
8. [提交时间线](#提交时间线)

---

## 1. 纹理打包：32 张贴图的 cooking 上限

**现象**
原始 demo 把每个骨骼部件做成独立 PNG（`police_m/parts/torso.png` 等）。
14 部件 × 2 角色 + 武器 + …合计 **30+ 张** 贴图。
TapTap AssetsCooking 直接拒绝：单项目纹理资源数有上限（实测 32 张左右就开始失败）。

**根因**
TapTap Maker 平台限制单包内纹理数量上限，目的是控制下发体积和移动端 GPU 内存。
跟资源总字节数无关，纯按资源条目数算。

**修复（commit `8a19f34`）**
做纹理图集（atlas）：

- Python 脚本把每个角色的 14 个 part PNG 打包成 1 张 atlas，按"网格 + 2 的幂尺寸"布局：
  - `police_m_atlas.png`：512 × 1024（4×4 grid，cell 120×140）
  - `civilian_f_atlas.png`：512 × 1024
  - `weapons_atlas.png`：256 × 128（2×1 grid）
- 30+ → **3 张**。
- runtime 后端（`taptap_sprite.lua`）支持 `atlasPath + atlasRects + atlasSize`，
  通过 `useTextureRect = true` + `textureRect = Rect(uvRect)` 切子区域。
- main.lua 暴露 `ATLAS_RECTS` 表，每个 part 一行 `{x, y, w, h}`（**像素坐标**，
  Y 轴向下，由打包脚本自动生成）。

**经验**

- POW2 尺寸是为了 ASTC/ETC 压缩友好；不要省力用 `420×980` 这种数字。
- 不要把所有角色塞一张 atlas，分角色更利于按需加载、不影响热更新粒度。
- 武器图集独立的好处：后续武器扩展（不动角色 atlas）。
- **不要做"只做了一半"的图集化**：留一部分单 PNG 会把贴图数又顶到上限。
  彻底切换 atlas 后，单 part PNG 就该从 cooked 项目里清掉。

---

## 2. Lua LSP 误报引擎全局符号

**现象**
本地 IDE 给 `Vector2`、`Rect`、`nvgRect` 等"引擎注入的全局变量"标红：
`undefined-global`。

**根因**
UrhoX 的 `.emmylua/` 类型定义文件常常挂载在 read-only 路径下，
本地 LSP 索引不到，把所有引擎全局都判为未定义。

**修复（commit `2e500ec`）**
受影响的 Lua 文件顶部加一行：

```lua
---@diagnostic disable: undefined-global
```

只在**真的依赖引擎全局**的边界文件上打（如 `runtime/lua/backends/taptap_sprite.lua`），
不要全仓库扫一遍打开。

`*.meta` 同时入了 `.gitignore`（UrhoX 本地构建产物）。

**经验**
不要为了让 IDE 不红就 `local Vector2 = Vector2` 这种"假声明"——
那会在 LSP 里掩盖真正的 typo。`---@diagnostic disable` 是最小破坏的方案。

---

## 3. 图集加载失败时的"二次错误风暴"

**现象**
TapTap Maker 启动后，控制台报 14 行类似：

```
Could not find resource Textures/police_m/parts/torso.png
Could not find resource Textures/police_m/parts/head.png
...（14 行 part PNG 都找不到）
```

但还有一行**真正的错误**淹没在最上面：

```
GET https://...tapapps.cn/assets/CQCu....png 404 (atlas)
```

**根因**
旧版本 `taptap_sprite.lua` 的逻辑是：

```lua
if atlasSprite and o.atlasRects[name] then
    -- 图集模式
elseif p.png and cache then
    -- 单 PNG fallback
end
```

当 atlas 没在 ResourceCache 里命中（CDN 404、未 import、路径写错）时，
`atlasSprite == nil`，**静默** 走 fallback，去找单 part PNG。
但 atlas 模式下那些单 PNG 早就没打进项目了，于是 14 个 part 各报一遍 not found，
把唯一有用的"atlas 没加载到"那行盖掉。

**修复（commit `4a9fef8`，源自本地 commit `f6d9c00`）**

```lua
local atlasMode = (o.atlasPath ~= nil)
local atlasSprite = nil

if atlasMode then
    if not (o.atlasRects and o.atlasSize) then
        print("[taptap_sprite] ERROR: atlasPath given but atlasRects/atlasSize missing")
    elseif not cache then
        print("[taptap_sprite] ERROR: no ResourceCache available; cannot load atlas " .. o.atlasPath)
    else
        atlasSprite = cache:GetResource("Sprite2D", o.atlasPath)
        if not atlasSprite then
            print("[taptap_sprite] ERROR: atlas Sprite2D not found in ResourceCache: '" .. o.atlasPath .. "'")
            print("  - Check the file exists under your TapTap project's Resources/Data/")
            print("  - Re-cook / reimport assets if you just added the atlas PNG")
            print("  - The path is resolved relative to ResourceCache roots, not to scripts/")
        end
    end
end

-- 部件创建处：
if atlasSprite and o.atlasRects[name] then
    -- 图集模式
elseif atlasMode then
    -- 处于图集模式但 atlas 没加载到 / 部件没注册：不再 fallback 到单 PNG
    -- 留空 sprite + 警告，让真正的 ERROR 行可见
elseif p.png and cache then
    -- 仅当 atlasMode == false 时才走单 PNG（保留向后兼容）
end
```

**经验**

- "fallback to legacy path"在调试期是噪音放大器。**模式切换要刚性**：声明使用图集模式
  的调用方，加载失败就要看到那条 ERROR，不要被 "好心" 的兜底掩盖。
- 出错要 self-explanatory：路径 + 几条排查 hint 一起打，不要只甩一个 `nil`。

---

## 4. 仓库结构：git root 与符号链接的兼容性

**现象**
旧布局：`workspace/skeleton2d/{runtime, examples, ...}`，git root 在子目录。
TapTap Maker 把项目根挂载进引擎沙箱时：

- 沙箱的 mount 点容易跟 `examples/` 命名冲突（引擎自己有 `examples/` 概念）
- `scripts/police_m/animations.lua` 是 symlink 指向 `examples/humanoid/animations.lua`，
  在 read-only mount 下 symlink 不一定被解析

**修复（commit `44063bc`）**
仓库结构整体上抬：

```
workspace/                ← git root（原 skeleton2d/ 内容上移）
├── runtime/              核心 runtime
├── editor/               HTML 编辑器
├── demo/                 示例数据（原 examples/，重命名规避冲突）
│   ├── humanoid/
│   └── urhox-demo/
├── scripts/              UrhoX demo 入口（main.lua + 模块）
├── assets/               图集贴图（移出 demo/ 直接挂在工程根）
├── docs/  schema/  tools/
└── AGENTS.md  README.md  LICENSE
```

同时把 `scripts/{char}/animations.lua` 的 symlink **拷贝成真实文件**——TapTap 沙箱
对 symlink 的支持参差，宁可冗余也不要赌它能解析。

**经验**

- 受限引擎沙箱里，**避免 symlink、避免目录名跟引擎约定冲突**（如 `examples/`、`Data/`）。
- git root 应当跟引擎眼中的"项目根"对齐，避免 `cd skeleton2d/` 这种额外约定。
- `assets/` 单独提到顶层，便于平台资产 import 时一次性扫到。

---

## 5. PNG 缺 sRGB chunk 导致 ASTC 压缩被跳过

**现象**
`AssetsCooking` 日志里，部分 PNG 显示"skipped ASTC compression"，
导致包体里依然是 RGBA 原图大小，移动端加载慢、显存占用高。

**根因**
TapTap 的 cooking pipeline 判断"是否进 ASTC"的依据之一是 PNG 的 **sRGB chunk**：

- 有 sRGB chunk → 走 ASTC（移动端 GPU 友好）
- 没有 → 保留 RGBA8（保险但笨重）

部分历史工具链（早年的 PIL、ImageMagick 默认设置等）输出 PNG 不带 sRGB chunk，
也没有 filter type 显式声明，于是命中"skip ASTC"分支。

**修复（commit `9829a65`）**
重导出有问题的 PNG，确保：

- 写入 `sRGB` chunk（PIL: `Image.save(..., icc_profile=ImageCms.createProfile("sRGB").tobytes())`）
- 显式 `filter_type=0`

**经验**

- 移动平台资产管线对 PNG 元数据敏感，不只是像素数据。
- 工具脚本（`tools/split_character.py` 等）在生成最终交付资产时，要校验输出 PNG 的元数据。
  可以加个 `pngcheck` 或 PIL 端的 sanity 检查。
- 调试这个问题最快的办法是看 cooking log 里 "ASTC" 相关行而不是看图。

---

## 6. textureRect 的 UV Y 轴方向

**现象**
切到图集模式后，所有部件 sprite 都"采样到了透明像素"——画面全空白，
但 atlas 加载日志正常、`atlasRects` 也对得上 atlas 实际像素位置。

**根因**
UrhoX 的 `StaticSprite2D.textureRect` 是 **OpenGL UV 坐标**（Y=0 在底）。
而打包脚本生成的 `atlasRects` 是 **像素坐标**，Y=0 在顶（这是绝大多数图像处理库的约定）。

我们之前老老实实算 `r.y / atlasH` 得到 UV Y——这正好对应 atlas **底部** 的某行，
但底部一般是空白填充区，于是采到全透明。

**修复（commit `3fe05c8`）**
后端转 UV 时翻转 Y：

```lua
local u0 = r.x / atlasW
local v0 = 1 - (r.y + r.h) / atlasH      -- 翻转
local u1 = (r.x + r.w) / atlasW
local v1 = 1 - r.y / atlasH              -- 翻转
sprite.textureRect = Rect(u0, v0, u1, v1)
```

**经验**

- 图像/纹理坐标系的"上下"问题在跨工具链时是高频陷阱：
  - PNG / 像素艺术 / Photoshop / Pillow / 多数图集工具：Y 向下
  - OpenGL UV：Y 向上
  - DirectX UV：Y 向下
- 在 backend 层一次性翻转，**不要让上层（main.lua / 打包工具）感知 UV**——
  它们应该只跟"像素矩形"打交道。
- 调试 UV 翻转最快的办法：在 atlas 里画一行红色到顶部 / 底部，看采到的是哪一边。

---

## 7. StaticSprite2D 在 UrhoX WebGL 不可用 → 切 NanoVG

**现象**
所有 atlas / textureRect / cooking 问题都修完后，**WebGL 端依然不渲染**。
Native 桌面版 UrhoX 跑通了，但是浏览器里整个角色不可见，
没报错——`StaticSprite2D` 组件创建成功、纹理加载成功、但 SpriteBatch 没把它画上屏。

**根因**
UrhoX 的 WebGL 后端中 `StaticSprite2D` / 整套 2D scene-graph 渲染路径**残缺/未完工**。
TapTap Maker 的所有 2D 游戏实际上都是用 **NanoVG** 在 immediate-mode 模式下绘制的，
不走 Scene/Viewport/Camera/Sprite 组件链。

这个事实在引擎文档里没有显式说明，是一条"踩进去才知道"的隐性约束。

**修复（commit `66f1968`）**
整个渲染管线重写：

| 旧（StaticSprite2D） | 新（NanoVG） |
|---|---|
| 每 part 一个 child Node + StaticSprite2D 组件 | 每帧 immediate-mode 调一次 `nvgImagePattern` + `nvgRect` |
| `node.position2D / rotation2D` 同步 | `nvgSave/Translate/Rotate/Restore` 栈 |
| `cache:GetResource("Sprite2D", path)` | `nvgCreateImage(vg, path, 0)` |
| `useTextureRect + textureRect` | `nvgImagePattern(vg, ox, oy, patW, patH, ...)` 用偏移裁切 |
| 米单位 + camera orthoSize 控制视口 | 像素坐标，角色直接在屏幕中心绘制 |
| Scene + Viewport + Camera | 全部移除，纯 NanoVG |

关键技巧：用 `nvgImagePattern` 实现"图集子区域绘制"。
NanoVG 没有"画图集 sub-rect"的直接 API，要靠 pattern 的 offset/scale 把图集
"虚拟移动"到只有目标子区域露在 `nvgRect` 之内：

```lua
local atlasW, atlasH = nvgImageSize(vg, imgHandle)
local scaleX = w / rect.w     -- 把子区域缩放到目标宽
local scaleY = h / rect.h
local patW, patH = atlasW * scaleX, atlasH * scaleY
local ox = x - rect.x * scaleX  -- 反向偏移，让子区域起点对齐 (x, y)
local oy = y - rect.y * scaleY
local paint = nvgImagePattern(vg, ox, oy, patW, patH, 0, imgHandle, 1.0)
nvgBeginPath(vg)
nvgRect(vg, x, y, w, h)
nvgFillPaint(vg, paint)
nvgFill(vg)
```

后端契约也变了：渲染**不再走 SkeletonRenderer**——它现在的产出是
"每个 part 的 `wx/wy/wr` + atlas 元数据"，调用方在主循环里自己用 NanoVG 遍历绘制
（`scripts/main.lua` 的 `drawSkeletonNanoVG()` 是参考实现）。
之前那一套 `Skeleton.SetBackend(...)` + 9 个绘制原语的 backend 抽象层在切到 NanoVG
后已无用，已从仓库移除（见本次清理）。

**经验**

- 接入受限引擎前先确认目标平台的"实际推荐渲染路径"——文档可能不全，
  最快的办法是看引擎自带 demo 用的是什么。
- 即使 Scene-graph 在 native 跑得好，到 WebGL 也要**实证**而非默认能跑。
  整套 2D Sprite 流水线在很多 web 移植中都是"看起来 API 都在，但实际不渲染"。
- runtime 与渲染要解耦：本仓库的 `SkeletonRenderer` 现在**只产出 `part.wx/wy/wr`**，
  调用方拿到这套世界变换后想用 NanoVG / Canvas / 别的什么都行。
  上游切渲染管线时只动绘制循环，不动骨骼/动画/混合逻辑——
  本次重写没改 `SkeletonRenderer.lua` 的核心 transform 计算就是这个解耦的红利。
  > 注：早期版本曾有一套 `Skeleton.SetBackend` + 9 个绘制原语的 backend 抽象。
  > 切到 NanoVG 后那层抽象已无用，反而让一帧多一层间接调用，已删除。
- NanoVG 的 `nvgImagePattern` 是实现 atlas 子区域绘制的唯一直接路径，
  套路就是"扩张 + 反向偏移"，记下来下次照抄。

---

## 提交时间线

| Commit | 主题 | 解决的问题 |
|---|---|---|
| `8a19f34` | feat: use texture atlas with power-of-2 grid layout | §1 32 张贴图上限 |
| `2e500ec` | fix(lsp): add diagnostic suppression for engine globals | §2 LSP 误报 |
| `f6d9c00` → `4a9fef8` | fix: fail loudly when atlas load fails | §3 二次错误风暴 |
| `44063bc` | refactor: restructure as workspace-root repo | §4 仓库结构与 symlink |
| `baa1a4a` | chore: remove redundant demo/ directory | §4 收尾 |
| `9829a65` | fix: add sRGB chunk to char_police.png for ASTC | §5 ASTC 跳过 |
| `3fe05c8` | fix: flip textureRect UV Y-axis for OpenGL convention | §6 UV Y 翻转 |
| `66f1968` | refactor: replace StaticSprite2D with NanoVG rendering | §7 WebGL 路径切换 |

---

## 附：接入新角色/新平台时的检查清单

当你想把 skeleton2d 接到一个新的角色资产或新的"Lua + 受限引擎"平台时，
按下面这条清单跑一遍可以避开本文 90% 的坑：

1. **打包**：把每个角色的 part PNG 打成单张 POW2 atlas，连同 `atlasRects` 元数据一起出。
2. **PNG 元数据**：导出时显式带 sRGB chunk + filter_type 0。
3. **路径与目录**：避免 symlink；avoid 目录名与引擎约定冲突；git root = 项目根。
4. **后端选择**：先确认目标平台真正可用的渲染路径（Scene-graph vs immediate-mode）。
5. **UV 方向**：在 backend 内部统一处理 Y 翻转，对外只暴露像素坐标。
6. **错误显式化**：模式切换严格，加载失败立刻 ERROR 不静默兜底。
7. **LSP**：受影响文件顶部 `---@diagnostic disable: undefined-global`。
