-- ============================================================================
-- skeleton2d StaticSprite2D Demo (TapTap Maker / UrhoX)
--
-- 本 demo 演示 skeleton2d 在 UrhoX 中的 **场景图渲染通路**：
--   - 每个骨骼部件 = 一个子 Node + StaticSprite2D 组件（一次性创建）
--   - 每帧 Skeleton.UpdateWorldTransforms 算出 wx/wy/wr，
--     再由 backends/taptap_sprite 同步到 node.position2D / rotation2D
--
-- 部署：scripts/ 下三个符号链接 + backends/ 子目录的一个符号链接
--   SkeletonRenderer.lua          → ../../../runtime/lua/SkeletonRenderer.lua
--   backends/taptap_sprite.lua    → ../../../../runtime/lua/backends/taptap_sprite.lua
--   humanoid/skeleton.lua         → ../../../../examples/humanoid/skeleton.lua
--   humanoid/animations.lua       → ../../../../examples/humanoid/animations.lua
--
-- 贴图：humanoid 示例数据未指定 png（仅 placeholderColor），所以默认看不见
-- 任何精灵；NanoVG 覆盖层会画关节点+连线让你确认骨骼是真的在动。
-- 接入真实贴图：在 examples/humanoid/skeleton.json 里给每个 part 加 png
-- 字段，然后用 editor 重新导出 lua；并把 PNG 放到 Textures/ 下即可。
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Skeleton = require "SkeletonRenderer"
local SpriteBE = require "backends.taptap_sprite"
local SkelDef  = require "humanoid.skeleton"
local Anims    = require "humanoid.animations"

-- ============================================================================
-- 状态
-- ============================================================================
local PIXELS_PER_METER = 100  -- skeleton2d 像素 ↔ UrhoX 米

local scene_      = nil
local cameraNode  = nil
local charNode    = nil   -- 角色根节点（位置 + 朝向）
local spriteRoot  = nil   -- 部件容器（朝向翻转作用在它身上）
local skelInst    = nil
local boneNodes   = nil   -- partName → Node
local boneCount   = 0     -- 部件数量（用于 HUD）

local vg          = nil
local fontId      = -1

local currentAnim = "idle"
local animNames   = { "idle", "walk", "swing", "shoot", "hit" }
local facing      = 1

-- 角色位置（米；2D 场景坐标，Y 向上）
local charX = 0
local charY = -1.5
local moveSpeed = 1.5  -- m/s

local showJoints = true
local showHUD    = true

-- ============================================================================
-- 初始化场景
-- 注：以下是标准 Urho3D 2D 场景搭建 API；TapTap (UrhoX) 大概率一致，
-- 若引擎对 Scene/Camera/Viewport 有定制（例如默认已存在 scene），
-- 把 setupScene() 替换成获取现有 scene 即可，下游逻辑不需要改。
-- ============================================================================
local function setupScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    -- 2D 正交相机
    cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 0, -10)
    local camera = cameraNode:CreateComponent("Camera")
    camera.orthographic = true
    -- orthoSize = 视口高度（米）；6m 高 ≈ 角色高度的 4 倍，便于观察
    camera.orthoSize = 6.0

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

local function setupCharacter()
    charNode   = scene_:CreateChild("Character")
    spriteRoot = charNode:CreateChild("SpriteRoot")

    skelInst = Skeleton.New(SkelDef)
    Skeleton.Play(skelInst, Anims.idle, { loop = true })

    boneNodes = SpriteBE.CreateNodes(spriteRoot, skelInst, {
        cache            = cache,
        texturePrefix    = "Textures/",
        pixelsPerMeter   = PIXELS_PER_METER,
        baseOrderInLayer = 0,
    })

    boneCount = 0
    for _ in pairs(boneNodes) do boneCount = boneCount + 1 end
end

-- ============================================================================
-- NanoVG 调试覆盖层（仅可视化骨骼，不参与渲染管线）
-- ============================================================================
local function setupNanoVG()
    vg = nvgCreate(1)
    if not vg then
        print("[WARN] NanoVG context unavailable; debug overlay disabled")
        return
    end
    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
end

-- 把 2D 世界坐标（米）投影成屏幕像素，用于 NanoVG 覆盖层
local function worldToScreen(wx, wy)
    local gfx = GetGraphics()
    local cam = cameraNode:GetComponent("Camera")
    -- 简化：正交相机居中、无旋转
    local viewH = cam.orthoSize
    local viewW = viewH * gfx:GetWidth() / gfx:GetHeight()
    local sx = (wx - cameraNode.position.x) / viewW * gfx:GetWidth()  + gfx:GetWidth()  * 0.5
    local sy = -(wy - cameraNode.position.y) / viewH * gfx:GetHeight() + gfx:GetHeight() * 0.5
    return sx, sy
end

local function drawJointsOverlay()
    if not vg or not boneNodes then return end
    local invPPM = 1 / PIXELS_PER_METER

    nvgBeginPath(vg)
    for name, node in pairs(boneNodes) do
        local p = skelInst.parts[name]
        if p and p.wx then
            -- 部件锚点在世界中的位置（米）
            local cx = charNode.position2D.x + facing * (p.wx * invPPM)
            local cy = charNode.position2D.y - (p.wy * invPPM)  -- skeleton2d Y 向下
            local sx, sy = worldToScreen(cx, cy)
            nvgCircle(vg, sx, sy, 3)
        end
    end
    nvgFillColor(vg, nvgRGBA(255, 80, 80, 220))
    nvgFill(vg)
end

local function drawHUD()
    if not vg then return end
    local gfx = GetGraphics()

    nvgBeginPath(vg)
    nvgRoundedRect(vg, 10, 10, 300, 180, 8)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgFill(vg)

    if fontId >= 0 then nvgFontFaceId(vg, fontId) end
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, 20, 18, "skeleton2d / StaticSprite2D Demo", nil)

    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(220, 230, 255, 255))
    local y = 46
    local lh = 20
    nvgText(vg, 20, y, "Anim:    " .. currentAnim, nil); y = y + lh
    nvgText(vg, 20, y, "Facing:  " .. (facing == 1 and "Right" or "Left"), nil); y = y + lh
    nvgText(vg, 20, y, string.format("Pos:     (%.2f, %.2f) m", charX, charY), nil); y = y + lh
    nvgText(vg, 20, y, "Bones:   " .. tostring(boneCount) .. " StaticSprite2D nodes", nil); y = y + lh
    nvgText(vg, 20, y, "Joints:  " .. (showJoints and "ON" or "OFF"), nil); y = y + lh

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(160, 160, 180, 200))
    nvgText(vg, 20, y + 6, "[1-5] Anim  [A/D] Move  [F] Flip  [J] Joints  [H] HUD", nil)
end

-- ============================================================================
-- 生命周期
-- ============================================================================
function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    setupScene()
    setupCharacter()
    setupNanoVG()

    SubscribeToEvent("Update", "HandleUpdate")
    if vg then
        SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    end

    print("=== skeleton2d StaticSprite2D Demo ===")
    print("[1-5] Switch animation  [A/D] Move  [F] Flip facing")
    print("[J] Toggle joint overlay  [H] Toggle HUD")
end

function Stop()
    if vg then nvgDelete(vg); vg = nil end
    if boneNodes then SpriteBE.Destroy(boneNodes); boneNodes = nil end
end

-- ============================================================================
-- 每帧
-- ============================================================================
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 动画切换 (1-5)
    for i = 1, #animNames do
        if input:GetKeyPress(KEY_1 + (i - 1)) then
            currentAnim = animNames[i]
            local a = Anims[currentAnim]
            if a then
                Skeleton.Play(skelInst, a, { loop = a.loop, restart = true })
                print("[ANIM] → " .. currentAnim)
            end
        end
    end

    -- 朝向翻转
    if input:GetKeyPress(KEY_F) then facing = -facing end

    -- 移动
    local moving = false
    if input:GetKeyDown(KEY_A) then charX = charX - moveSpeed * dt; facing = -1; moving = true end
    if input:GetKeyDown(KEY_D) then charX = charX + moveSpeed * dt; facing =  1; moving = true end

    -- 行走/待机自动切换
    if moving and currentAnim == "idle" then
        currentAnim = "walk"; Skeleton.Play(skelInst, Anims.walk, { loop = true })
    elseif not moving and currentAnim == "walk" then
        currentAnim = "idle"; Skeleton.Play(skelInst, Anims.idle, { loop = true })
    end

    -- 一次性动画播完回 idle
    if skelInst.finished and Anims[currentAnim] and not Anims[currentAnim].loop then
        currentAnim = "idle"
        Skeleton.Play(skelInst, Anims.idle, { loop = true })
    end

    -- 调试开关
    if input:GetKeyPress(KEY_J) then showJoints = not showJoints end
    if input:GetKeyPress(KEY_H) then showHUD    = not showHUD end

    -- 1) 推动画
    Skeleton.Update(skelInst, dt)
    -- 2) 算世界变换
    Skeleton.UpdateWorldTransforms(skelInst)
    -- 3) 同步到节点
    SpriteBE.Sync(boneNodes, skelInst, { pixelsPerMeter = PIXELS_PER_METER })

    -- 角色位置 + 朝向（作用在 charNode / spriteRoot）
    charNode.position2D = Vector2(charX, charY)
    spriteRoot:SetScale2D(Vector2(facing, 1))
end

-- ============================================================================
-- NanoVG 覆盖层（仅调试可视化）
-- ============================================================================
function HandleNanoVGRender(eventType, eventData)
    if not vg then return end
    local gfx = GetGraphics()
    nvgBeginFrame(vg, gfx:GetWidth(), gfx:GetHeight(), 1.0)

    if showJoints then drawJointsOverlay() end
    if showHUD    then drawHUD() end

    nvgEndFrame(vg)
end
