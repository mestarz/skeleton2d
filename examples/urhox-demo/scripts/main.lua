-- ============================================================================
-- skeleton2d 技术验证 Demo
-- 验证: SkeletonRenderer + NanoVG 后端 在 UrhoX 中的完整运行
--
-- 本文件直接 require 仓库根的 runtime 和 examples 数据，
-- 不复制任何 SkeletonRenderer / skeleton / animations 副本。
-- ============================================================================

require "LuaScripts/Utilities/Sample"

-- 把仓库根的 runtime/lua/ 和 examples/ 加入搜索路径
-- SCRIPT_ROOT = 当前脚本所在目录 (examples/urhox-demo/scripts/)
-- 向上三级即为仓库根
local ROOT = SCRIPT_ROOT .. "/../../.."
package.path = package.path
    .. ";" .. ROOT .. "/runtime/lua/?.lua"
    .. ";" .. ROOT .. "/examples/?.lua"

-- skeleton2d 运行时（仓库唯一源: runtime/lua/SkeletonRenderer.lua）
local Skeleton = require "SkeletonRenderer"
-- 编辑器导出数据（仓库唯一源: examples/humanoid/{skeleton,animations}.lua）
local SkelDef  = require "humanoid.skeleton"
local Anims    = require "humanoid.animations"

-- ============================================================================
-- 全局状态
-- ============================================================================
local vg = nil           -- NanoVG 上下文
local fontId = -1        -- 字体句柄

---@type table
local skelInst = nil     -- 骨骼实例
local currentAnim = "idle"
local facing = 1         -- 1=朝右, -1=朝左
local drawScale = 2.5    -- 绘制缩放
local showDebug = true   -- 显示调试信息
local showBones = false  -- 显示骨骼关节点

-- 动画列表（用于循环切换）
local animNames = { "idle", "walk", "swing", "shoot", "hit" }
local animIndex = 1

-- 角色位置（屏幕坐标）
local charX = 0
local charY = 0
local moveSpeed = 150   -- 像素/秒

-- ============================================================================
-- NanoVG 后端适配层
-- ============================================================================
local function setupNanoVGBackend()
    Skeleton.SetBackend({
        drawImage = function(handle, x, y, w, h)
            -- 暂无贴图，后续扩展
        end,

        fillRect = function(x, y, w, h, rgba)
            nvgBeginPath(vg)
            nvgRect(vg, x, y, w, h)
            local r = rgba[1] or 200
            local g = rgba[2] or 100
            local b = rgba[3] or 100
            local a = rgba[4] or 220
            nvgFillColor(vg, nvgRGBA(r, g, b, a))
            nvgFill(vg)
        end,

        getImage = function(path)
            return nil  -- 占位模式，全部使用 placeholderColor
        end,

        enqueueImage = function(path)
            -- 占位模式，无需加载
        end,

        pushTransform = function()
            nvgSave(vg)
        end,

        popTransform = function()
            nvgRestore(vg)
        end,

        translate = function(x, y)
            nvgTranslate(vg, x, y)
        end,

        rotate = function(rad)
            nvgRotate(vg, rad)
        end,

        scale = function(sx, sy)
            nvgScale(vg, sx, sy)
        end,
    })
end

-- ============================================================================
-- 绘制辅助
-- ============================================================================

--- 绘制背景网格
local function drawGrid(ctx, w, h)
    local gridSize = 40
    nvgBeginPath(ctx)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 15))
    nvgStrokeWidth(ctx, 1)
    for x = 0, w, gridSize do
        nvgMoveTo(ctx, x, 0)
        nvgLineTo(ctx, x, h)
    end
    for y = 0, h, gridSize do
        nvgMoveTo(ctx, 0, y)
        nvgLineTo(ctx, w, y)
    end
    nvgStroke(ctx)
end

--- 绘制地面参考线
local function drawGroundLine(ctx, w, groundY)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 0, groundY)
    nvgLineTo(ctx, w, groundY)
    nvgStrokeColor(ctx, nvgRGBA(100, 200, 100, 80))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    -- 地面标注
    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(100, 200, 100, 120))
    nvgText(ctx, 8, groundY - 4, "Ground", nil)
end

--- 绘制骨骼关节调试点（递归遍历骨骼树）
local function drawBoneJoints(ctx, inst, name, worldX, worldY, worldRot, scale)
    local p = inst.parts[name]
    if not p then return end

    local ax = p.attachAt[1] * scale
    local ay = p.attachAt[2] * scale
    local rad = math.rad(worldRot + (p.currentRot or 0))
    local cosR = math.cos(rad)
    local sinR = math.sin(rad)

    -- 当前关节在世界坐标中的位置
    local jx = worldX + ax * cosR - ay * sinR
    local jy = worldY + ax * sinR + ay * cosR

    -- 画关节点（红色）
    nvgBeginPath(ctx)
    nvgCircle(ctx, jx, jy, 3)
    nvgFillColor(ctx, nvgRGBA(255, 60, 60, 200))
    nvgFill(ctx)

    -- 画连线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, worldX, worldY)
    nvgLineTo(ctx, jx, jy)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 0, 100))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 递归子节点
    local kids = inst.children[name]
    if kids then
        for i = 1, #kids do
            drawBoneJoints(ctx, inst, kids[i], jx, jy, worldRot + (p.currentRot or 0), scale)
        end
    end
end

--- 绘制 HUD 信息面板
local function drawHUD(ctx, w, h)
    -- 半透明背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, 10, 10, 280, 210, 8)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180))
    nvgFill(ctx)

    nvgFontFaceId(ctx, fontId)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 标题
    nvgFontSize(ctx, 18)
    nvgFillColor(ctx, nvgRGBA(255, 220, 100, 255))
    nvgText(ctx, 20, 18, "skeleton2d Tech Demo", nil)

    -- 分隔线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 20, 42)
    nvgLineTo(ctx, 280, 42)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 40))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    nvgFontSize(ctx, 14)
    local y = 52
    local lineH = 22

    -- 当前动画
    nvgFillColor(ctx, nvgRGBA(180, 220, 255, 255))
    nvgText(ctx, 20, y, "Animation: " .. currentAnim, nil)
    y = y + lineH

    -- 朝向
    local facingStr = facing == 1 and "Right →" or "← Left"
    nvgText(ctx, 20, y, "Facing: " .. facingStr, nil)
    y = y + lineH

    -- 缩放
    nvgText(ctx, 20, y, string.format("Scale: %.1fx", drawScale), nil)
    y = y + lineH

    -- 调试开关
    nvgText(ctx, 20, y, "Bones: " .. (showBones and "ON" or "OFF"), nil)
    y = y + lineH

    -- 分隔线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 20, y + 2)
    nvgLineTo(ctx, 280, y + 2)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 40))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)
    y = y + 10

    -- 操作提示
    nvgFontSize(ctx, 12)
    nvgFillColor(ctx, nvgRGBA(160, 160, 180, 200))
    nvgText(ctx, 20, y, "[1-5] Switch Anim  [A/D] Move  [F] Flip", nil)
    y = y + 18
    nvgText(ctx, 20, y, "[+/-] Scale  [B] Bones  [H] HUD", nil)
end

--- 绘制动画按钮栏
local function drawAnimBar(ctx, w, h)
    local barH = 40
    local barY = h - barH - 10
    local btnW = 80
    local totalW = #animNames * (btnW + 8) - 8
    local startX = (w - totalW) / 2

    for i, name in ipairs(animNames) do
        local bx = startX + (i - 1) * (btnW + 8)
        local isActive = (name == currentAnim)

        -- 按钮背景
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, bx, barY, btnW, barH, 6)
        if isActive then
            nvgFillColor(ctx, nvgRGBA(60, 120, 220, 220))
        else
            nvgFillColor(ctx, nvgRGBA(50, 55, 70, 180))
        end
        nvgFill(ctx)

        -- 边框
        nvgStrokeColor(ctx, nvgRGBA(120, 140, 180, isActive and 200 or 80))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)

        -- 文字
        nvgFontFaceId(ctx, fontId)
        nvgFontSize(ctx, 14)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, isActive and 255 or 160))
        nvgText(ctx, bx + btnW / 2, barY + barH / 2, name, nil)

        -- 快捷键提示
        nvgFontSize(ctx, 10)
        nvgFillColor(ctx, nvgRGBA(200, 200, 200, 100))
        nvgText(ctx, bx + btnW / 2, barY - 8, tostring(i), nil)
    end
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

    -- 加载字体（只调用一次）
    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    if fontId == -1 then
        print("[ERROR] Failed to load font")
    end

    -- 初始化 NanoVG 后端
    setupNanoVGBackend()

    -- 创建骨骼实例并播放 idle 动画
    skelInst = Skeleton.New(SkelDef)
    Skeleton.Play(skelInst, Anims.idle, { loop = true })

    -- 初始位置（屏幕中央）
    local gfx = GetGraphics()
    charX = gfx:GetWidth() / 2
    charY = gfx:GetHeight() * 0.7

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")

    print("=== skeleton2d Tech Demo Started ===")
    print("[1-5] Switch animation  [A/D] Move  [F] Flip facing")
    print("[+/-] Scale  [B] Toggle bones  [H] Toggle HUD")
end

function Stop()
    if vg then
        nvgDelete(vg)
        vg = nil
    end
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 动画切换 (1-5)
    for i = 1, #animNames do
        local key = KEY_1 + (i - 1)
        if input:GetKeyPress(key) then
            animIndex = i
            currentAnim = animNames[i]
            local anim = Anims[currentAnim]
            if anim then
                Skeleton.Play(skelInst, anim, { loop = anim.loop, restart = true })
                print("[ANIM] → " .. currentAnim)
            end
        end
    end

    -- 朝向翻转 (F)
    if input:GetKeyPress(KEY_F) then
        facing = facing * -1
        print("[FACING] → " .. (facing == 1 and "Right" or "Left"))
    end

    -- 移动 (A/D)
    local moving = false
    if input:GetKeyDown(KEY_A) then
        charX = charX - moveSpeed * dt
        facing = -1
        moving = true
    end
    if input:GetKeyDown(KEY_D) then
        charX = charX + moveSpeed * dt
        facing = 1
        moving = true
    end

    -- 自动切换行走/待机动画
    if moving and currentAnim == "idle" then
        currentAnim = "walk"
        animIndex = 2
        Skeleton.Play(skelInst, Anims.walk, { loop = true })
    elseif not moving and currentAnim == "walk" then
        currentAnim = "idle"
        animIndex = 1
        Skeleton.Play(skelInst, Anims.idle, { loop = true })
    end

    -- 非循环动画播完后回到 idle
    if skelInst.finished and not Anims[currentAnim].loop then
        currentAnim = "idle"
        animIndex = 1
        Skeleton.Play(skelInst, Anims.idle, { loop = true })
    end

    -- 缩放 (+/-)
    if input:GetKeyPress(KEY_KP_PLUS) or input:GetKeyPress(KEY_EQUALS) then
        drawScale = math.min(drawScale + 0.5, 6.0)
        print("[SCALE] → " .. string.format("%.1f", drawScale))
    end
    if input:GetKeyPress(KEY_KP_MINUS) or input:GetKeyPress(KEY_MINUS) then
        drawScale = math.max(drawScale - 0.5, 0.5)
        print("[SCALE] → " .. string.format("%.1f", drawScale))
    end

    -- 调试开关
    if input:GetKeyPress(KEY_B) then
        showBones = not showBones
    end
    if input:GetKeyPress(KEY_H) then
        showDebug = not showDebug
    end

    -- 更新骨骼动画
    Skeleton.Update(skelInst, dt)
end

-- ============================================================================
-- 渲染
-- ============================================================================

function HandleNanoVGRender(eventType, eventData)
    if not vg or not skelInst then return end

    local gfx = GetGraphics()
    local w = gfx:GetWidth()
    local h = gfx:GetHeight()

    nvgBeginFrame(vg, w, h, 1.0)

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    local bg = nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(25, 30, 45, 255),
        nvgRGBA(15, 18, 28, 255))
    nvgFillPaint(vg, bg)
    nvgFill(vg)

    -- 网格
    drawGrid(vg, w, h)

    -- 地面线
    drawGroundLine(vg, w, charY)

    -- 绘制骨骼角色
    Skeleton.Draw(skelInst, charX, charY, facing, drawScale)

    -- 骨骼关节调试
    if showBones then
        drawBoneJoints(vg, skelInst, skelInst.rootName, charX, charY, 0, drawScale)
    end

    -- HUD
    if showDebug then
        drawHUD(vg, w, h)
    end

    -- 底部动画按钮栏
    drawAnimBar(vg, w, h)

    nvgEndFrame(vg)
end
