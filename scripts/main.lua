-- ============================================================================
-- skeleton2d NanoVG Demo (TapTap Maker / UrhoX)
--
-- 演示 skeleton2d 在 NanoVG immediate-mode 下绘制：
--   - 用 nvgCreateImage 加载图集纹理（每张 atlas 一次）
--   - SkeletonRenderer 只负责动画 + 世界变换递推
--   - 自己遍历 skelInst.parts，用 nvgImagePattern 在 part.wx/wy/wr 处画子区域
--
-- UrhoX WebGL 中 StaticSprite2D 不可用，所有 2D 游戏均使用 NanoVG。
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Skeleton = require "SkeletonRenderer"
local Weapons  = require "weapons"

-- 图集子区域定义（由 Python 打包脚本生成，网格布局，2的幂次方尺寸）
local ATLAS_RECTS = {
    police_m = {  -- atlas: 512x1024, cell=120x140, grid=4x4
        torso     = { x =   0, y =   0, w = 100, h = 140 },
        head      = { x = 120, y =   0, w = 120, h = 135 },
        upperArmL = { x = 240, y =   0, w =  40, h =  80 },
        upperArmR = { x = 360, y =   0, w =  45, h =  80 },
        lowerArmL = { x =   0, y = 140, w =  45, h =  70 },
        lowerArmR = { x = 120, y = 140, w =  50, h =  70 },
        handL     = { x = 240, y = 140, w =  40, h =  30 },
        handR     = { x = 360, y = 140, w =  45, h =  35 },
        thighL    = { x =   0, y = 280, w =  45, h = 110 },
        thighR    = { x = 120, y = 280, w =  45, h = 110 },
        shinL     = { x = 240, y = 280, w =  45, h =  90 },
        shinR     = { x = 360, y = 280, w =  45, h =  90 },
        footL     = { x =   0, y = 420, w =  55, h =  35 },
        footR     = { x = 120, y = 420, w =  55, h =  35 },
    },
    civilian_f = {  -- atlas: 512x1024, cell=120x138, grid=4x4
        torso     = { x =   0, y =   0, w =  98, h = 138 },
        head      = { x = 120, y =   0, w = 120, h = 138 },
        upperArmL = { x = 240, y =   0, w =  45, h =  75 },
        upperArmR = { x = 360, y =   0, w =  50, h =  75 },
        lowerArmL = { x =   0, y = 138, w =  45, h =  70 },
        lowerArmR = { x = 120, y = 138, w =  50, h =  70 },
        handL     = { x = 240, y = 138, w =  35, h =  35 },
        handR     = { x = 360, y = 138, w =  40, h =  35 },
        thighL    = { x =   0, y = 276, w =  45, h = 105 },
        thighR    = { x = 120, y = 276, w =  45, h = 105 },
        shinL     = { x = 240, y = 276, w =  45, h =  95 },
        shinR     = { x = 360, y = 276, w =  45, h =  95 },
        footL     = { x =   0, y = 414, w =  55, h =  40 },
        footR     = { x = 120, y = 414, w =  55, h =  40 },
    },
    weapons = {  -- atlas: 256x128, cell=118x111, grid=2x1
        handgun = { x =   0, y = 0, w = 118, h =  84 },
        knife   = { x = 118, y = 0, w = 106, h = 111 },
    },
}

local CHARACTERS = {
    { id = "police_m",
      skeleton   = require "police_m.skeleton",
      animations = require "police_m.animations",
      atlasPng   = "Textures/char_police.png",
      atlasRects = ATLAS_RECTS.police_m,
      atlasSize  = { w = 512, h = 1024 } },
    { id = "civilian_f",
      skeleton   = require "civilian_f.skeleton",
      animations = require "civilian_f.animations",
      atlasPng   = "Textures/char_civilian.png",
      atlasRects = ATLAS_RECTS.civilian_f,
      atlasSize  = { w = 512, h = 1024 } },
}

local WEAPON_NAMES = { "handgun", "knife" }

-- ============================================================================
-- 全局状态
-- ============================================================================
local vg       = nil
local fontId   = -1

-- NanoVG 图集句柄
local atlasImages = {}  -- { "Textures/xxx.png" = nvgImageHandle }

local skelInst  = nil
local boneCount = 0

local charIndex   = 1
local currentAnim = "idle"
local animNames   = { "idle", "walk", "swing", "shoot", "hit" }
local facing      = 1
local weaponIdx   = 0

-- 角色屏幕中心位置（像素）和缩放
local charScreenX, charScreenY = 0, 0
local charScale = 1.0

local moveSpeed = 150  -- 像素/秒

local showJoints = true
local showHUD    = true

-- ============================================================================
-- NanoVG 图集绘制
-- ============================================================================

-- 当前角色使用的图集信息
local currentAtlasImage = 0  -- nvg image handle
local currentAtlasRects = nil
local currentWeaponAtlasImage = 0
local currentWeaponAtlasRects = nil

--- 用 nvgImagePattern 绘制图集子区域
--- partName -> 从 atlasRects 查子区域 -> 用 pattern offset 裁切
local function drawAtlasRegion(partName, x, y, w, h)
    if not vg then return end

    -- 查找子区域信息
    local rect = nil
    local imgHandle = 0

    if currentAtlasRects and currentAtlasRects[partName] then
        rect = currentAtlasRects[partName]
        imgHandle = currentAtlasImage
    elseif partName == "weapon" and currentWeaponAtlasRects then
        -- 武器用独立图集
        local wname = WEAPON_NAMES[weaponIdx]
        if wname and currentWeaponAtlasRects[wname] then
            rect = currentWeaponAtlasRects[wname]
            imgHandle = currentWeaponAtlasImage
        end
    end

    if not rect or imgHandle == 0 then
        -- 没有图集信息，画占位色块
        nvgBeginPath(vg)
        nvgRect(vg, x, y, w, h)
        nvgFillColor(vg, nvgRGBA(200, 100, 100, 180))
        nvgFill(vg)
        return
    end

    -- 获取图集纹理实际尺寸
    local atlasW, atlasH = nvgImageSize(vg, imgHandle)

    -- nvgImagePattern 的原理：
    -- 创建一个以 (ox, oy) 为图案起点、宽 ex 高 ey 的贴图映射
    -- 我们需要把子区域 (rect.x, rect.y, rect.w, rect.h) 映射到绘制区域 (x, y, w, h)
    --
    -- 缩放因子：绘制尺寸 / 子区域尺寸 * 图集尺寸
    -- 偏移：-rect.x * scale + x, -rect.y * scale + y
    local scaleX = w / rect.w
    local scaleY = h / rect.h
    local patW = atlasW * scaleX
    local patH = atlasH * scaleY
    local ox = x - rect.x * scaleX
    local oy = y - rect.y * scaleY

    local paint = nvgImagePattern(vg, ox, oy, patW, patH, 0, imgHandle, 1.0)

    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- ============================================================================
-- 骨骼管理
-- ============================================================================

--- 自己遍历 inst.parts 绘制：每个 part 用 nvgImagePattern 画图集子区域
local function drawSkeletonNanoVG(inst, sx, sy, fac, sc)
    if not vg or not inst then return end

    nvgSave(vg)
    nvgTranslate(vg, sx, sy)
    if fac < 0 then
        nvgScale(vg, -sc, sc)
    elseif sc ~= 1 then
        nvgScale(vg, sc, sc)
    end

    -- 收集所有 part，按 z 排序绘制
    local sorted = {}
    for name, p in pairs(inst.parts) do
        if p.wx ~= nil then
            sorted[#sorted + 1] = { name = name, p = p }
        end
    end
    table.sort(sorted, function(a, b) return a.p.z < b.p.z end)

    for _, item in ipairs(sorted) do
        local name = item.name
        local p = item.p

        nvgSave(vg)
        -- skeleton2d 的 wx/wy 是像素坐标，Y 向下
        nvgTranslate(vg, p.wx, p.wy)
        nvgRotate(vg, math.rad(p.wr or 0))
        nvgTranslate(vg, -p.anchor[1], -p.anchor[2])

        -- 绘制图集子区域
        drawAtlasRegion(name, 0, 0, p.w, p.h)

        nvgRestore(vg)
    end

    nvgRestore(vg)
end

local function buildCharacter(idx)
    local def = CHARACTERS[idx]

    skelInst = Skeleton.New(def.skeleton)
    local first = def.animations[currentAnim] or def.animations.idle
    if first then Skeleton.Play(skelInst, first, { loop = first.loop ~= false }) end

    -- 加载图集 NanoVG 纹理（只加载一次）
    if not atlasImages[def.atlasPng] then
        atlasImages[def.atlasPng] = nvgCreateImage(vg, def.atlasPng, 0)
        print("[NVG] Created atlas image: " .. def.atlasPng .. " -> " .. tostring(atlasImages[def.atlasPng]))
    end
    currentAtlasImage = atlasImages[def.atlasPng]
    currentAtlasRects = def.atlasRects

    boneCount = 0
    for _ in pairs(skelInst.parts) do boneCount = boneCount + 1 end

    -- 初始化武器
    currentWeaponAtlasImage = 0
    currentWeaponAtlasRects = nil
    weaponIdx = 0

    print("[CHAR] Built: " .. def.id .. " (" .. boneCount .. " bones)")
end

local function attachCurrentWeapon()
    if weaponIdx == 0 then return end
    local wname = WEAPON_NAMES[weaponIdx]
    local w = Weapons[wname]
    if not (w and skelInst) then return end

    Skeleton.AttachWeapon(skelInst, w, "handR")

    -- 加载武器图集
    local weaponPath = "Textures/items_weapons.png"
    if not atlasImages[weaponPath] then
        atlasImages[weaponPath] = nvgCreateImage(vg, weaponPath, 0)
        print("[NVG] Created weapon atlas: " .. weaponPath .. " -> " .. tostring(atlasImages[weaponPath]))
    end
    currentWeaponAtlasImage = atlasImages[weaponPath]
    currentWeaponAtlasRects = ATLAS_RECTS.weapons
end

local function cycleCharacter()
    charIndex = charIndex % #CHARACTERS + 1
    buildCharacter(charIndex)
end

local function cycleWeapon()
    weaponIdx = (weaponIdx + 1) % (#WEAPON_NAMES + 1)
    if skelInst then Skeleton.DetachWeapon(skelInst) end
    if weaponIdx > 0 then
        attachCurrentWeapon()
        print("[WEAPON] -> " .. WEAPON_NAMES[weaponIdx])
    else
        currentWeaponAtlasImage = 0
        currentWeaponAtlasRects = nil
        print("[WEAPON] -> none")
    end
end

-- ============================================================================
-- HUD 绘制
-- ============================================================================

local function drawJointsOverlay()
    if not vg or not skelInst then return end
    local gfx = GetGraphics()
    local cx = gfx:GetWidth() * 0.5 + charScreenX
    local cy = gfx:GetHeight() * 0.6 + charScreenY

    nvgBeginPath(vg)
    for name, p in pairs(skelInst.parts) do
        if p.wx ~= nil then
            local jx = cx + facing * p.wx * charScale
            local jy = cy + p.wy * charScale
            nvgCircle(vg, jx, jy, 3)
        end
    end
    nvgFillColor(vg, nvgRGBA(255, 80, 80, 220))
    nvgFill(vg)
end

local function drawHUD()
    if not vg then return end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 10, 10, 320, 200, 8)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    if fontId >= 0 then nvgFontFaceId(vg, fontId) end
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, 20, 18, "skeleton2d / NanoVG Demo", nil)

    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(220, 230, 255, 255))
    local y, lh = 46, 20
    nvgText(vg, 20, y, "Char:    " .. CHARACTERS[charIndex].id,  nil); y = y + lh
    nvgText(vg, 20, y, "Anim:    " .. currentAnim,               nil); y = y + lh
    local wname = (weaponIdx == 0) and "(none)" or WEAPON_NAMES[weaponIdx]
    nvgText(vg, 20, y, "Weapon:  " .. wname,                     nil); y = y + lh
    nvgText(vg, 20, y, "Facing:  " .. (facing == 1 and "Right" or "Left"), nil); y = y + lh
    nvgText(vg, 20, y, "Bones:   " .. tostring(boneCount),       nil); y = y + lh

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(160, 160, 180, 200))
    nvgText(vg, 20, y + 6, "[1-5] Anim [A/D] Move [F] Flip [C] Char [W] Weapon [J/H] Overlay", nil)
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    -- 创建 NanoVG 上下文
    vg = nvgCreate(1)
    if not vg then
        print("[ERROR] Failed to create NanoVG context")
        return
    end
    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    -- 构建角色
    buildCharacter(charIndex)

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")

    print("=== skeleton2d NanoVG Demo ===")
    print("[1-5] Anim  [A/D] Move  [F] Flip  [C] Char  [W] Weapon  [J/H] Overlay")
end

function Stop()
    -- 删除 NanoVG 图片
    if vg then
        for path, handle in pairs(atlasImages) do
            nvgDeleteImage(vg, handle)
        end
        atlasImages = {}
        nvgDelete(vg)
        vg = nil
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    local Anims = CHARACTERS[charIndex].animations

    -- 动画切换
    for i = 1, #animNames do
        if input:GetKeyPress(KEY_1 + (i - 1)) then
            local a = Anims[animNames[i]]
            if a then
                currentAnim = animNames[i]
                Skeleton.Play(skelInst, a, { loop = a.loop ~= false, restart = true })
                print("[ANIM] -> " .. currentAnim)
            end
        end
    end

    if input:GetKeyPress(KEY_F) then facing = -facing end
    if input:GetKeyPress(KEY_C) then cycleCharacter() end
    if input:GetKeyPress(KEY_W) then cycleWeapon() end

    -- 移动
    local moving = false
    if input:GetKeyDown(KEY_A) then charScreenX = charScreenX - moveSpeed * dt; facing = -1; moving = true end
    if input:GetKeyDown(KEY_D) then charScreenX = charScreenX + moveSpeed * dt; facing =  1; moving = true end

    if moving and currentAnim == "idle" and Anims.walk then
        currentAnim = "walk"; Skeleton.Play(skelInst, Anims.walk, { loop = true })
    elseif not moving and currentAnim == "walk" and Anims.idle then
        currentAnim = "idle"; Skeleton.Play(skelInst, Anims.idle, { loop = true })
    end

    if skelInst.finished and Anims[currentAnim] and not Anims[currentAnim].loop then
        currentAnim = "idle"
        if Anims.idle then Skeleton.Play(skelInst, Anims.idle, { loop = true }) end
    end

    if input:GetKeyPress(KEY_J) then showJoints = not showJoints end
    if input:GetKeyPress(KEY_H) then showHUD    = not showHUD end

    -- 更新骨骼动画
    Skeleton.Update(skelInst, dt)
    Skeleton.UpdateWorldTransforms(skelInst)
end

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end
    local gfx = GetGraphics()
    local screenW, screenH = gfx:GetWidth(), gfx:GetHeight()

    nvgBeginFrame(vg, screenW, screenH, 1.0)

    -- 绘制角色：屏幕中心偏下
    local cx = screenW * 0.5 + charScreenX
    local cy = screenH * 0.6 + charScreenY
    drawSkeletonNanoVG(skelInst, cx, cy, facing, charScale)

    -- 叠加层
    if showJoints then drawJointsOverlay() end
    if showHUD    then drawHUD() end

    nvgEndFrame(vg)
end
