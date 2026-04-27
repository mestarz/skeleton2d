-- ============================================================================
-- skeleton2d StaticSprite2D Demo (TapTap Maker / UrhoX)
--
-- 演示 skeleton2d 跑在 UrhoX 场景图渲染通路上：
--   - 每个骨骼部件 = 一个子 Node + StaticSprite2D 组件（一次性创建）
--   - 每帧 Skeleton.UpdateWorldTransforms 算出 wx/wy/wr，
--     再由 backends/taptap_sprite 同步到 node.position2D / rotation2D
--
-- 贴图使用图集模式（SpriteSheet2D）：每个角色 14 张部件图合为 1 张图集。
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Skeleton = require "SkeletonRenderer"
local SpriteBE = require "backends.taptap_sprite"
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

local PIXELS_PER_METER = 100

local scene_      = nil
local cameraNode  = nil
local charNode    = nil
local spriteRoot  = nil
local skelInst    = nil
local boneNodes   = nil
local boneCount   = 0

local vg          = nil
local fontId      = -1

local charIndex   = 1
local currentAnim = "idle"
local animNames   = { "idle", "walk", "swing", "shoot", "hit" }
local facing      = 1
local weaponIdx   = 0

local charX, charY = 0, -1.5
local moveSpeed = 1.5

local showJoints = true
local showHUD    = true

local function setupScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    cameraNode = scene_:CreateChild("Camera")
    cameraNode.position = Vector3(0, 0, -10)
    local camera = cameraNode:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = 6.0

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
end

local function destroyCharacter()
    if boneNodes then SpriteBE.Destroy(boneNodes); boneNodes = nil end
    if spriteRoot and spriteRoot.Remove then spriteRoot:Remove(); spriteRoot = nil end
    if charNode   and charNode.Remove   then charNode:Remove();   charNode = nil end
    skelInst, boneCount = nil, 0
end

local WEAPONS_ATLAS_SIZE = { w = 256, h = 128 }

local function attachCurrentWeapon()
    if weaponIdx == 0 then return end
    local w = Weapons[WEAPON_NAMES[weaponIdx]]
    if not (w and skelInst and boneNodes and spriteRoot) then return end

    Skeleton.AttachWeapon(skelInst, w, "handR")

    -- 武器图集：把当前武器的子区域以 "weapon" 为键传入，后端按 partName 查找
    local weaponRects = { weapon = ATLAS_RECTS.weapons[WEAPON_NAMES[weaponIdx]] }

    SpriteBE.AttachPart(boneNodes, spriteRoot, skelInst, "weapon", {
        atlasPath        = "Textures/items_weapons.png",
        atlasRects       = weaponRects,
        atlasSize        = WEAPONS_ATLAS_SIZE,
        pixelsPerMeter   = PIXELS_PER_METER,
        baseOrderInLayer = 0,
    })
end

local function buildCharacter(idx)
    destroyCharacter()
    local def = CHARACTERS[idx]

    charNode   = scene_:CreateChild("Character_" .. def.id)
    spriteRoot = charNode:CreateChild("SpriteRoot")

    skelInst = Skeleton.New(def.skeleton)
    local first = def.animations[currentAnim] or def.animations.idle
    if first then Skeleton.Play(skelInst, first, { loop = first.loop ~= false }) end

    -- 图集模式：传图集路径 + 子区域坐标，后端用 textureRect 选择子区域
    boneNodes = SpriteBE.CreateNodes(spriteRoot, skelInst, {
        atlasPath        = def.atlasPng,
        atlasRects       = def.atlasRects,
        atlasSize        = def.atlasSize,
        pixelsPerMeter   = PIXELS_PER_METER,
        baseOrderInLayer = 0,
    })

    boneCount = 0
    for _ in pairs(boneNodes) do boneCount = boneCount + 1 end

    attachCurrentWeapon()
end

local function cycleCharacter()
    charIndex = charIndex % #CHARACTERS + 1
    buildCharacter(charIndex)
    print("[CHAR] -> " .. CHARACTERS[charIndex].id)
end

local function cycleWeapon()
    weaponIdx = (weaponIdx + 1) % (#WEAPON_NAMES + 1)
    if skelInst then Skeleton.DetachWeapon(skelInst) end
    if boneNodes then SpriteBE.DetachPart(boneNodes, "weapon") end
    if weaponIdx > 0 then
        attachCurrentWeapon()
        print("[WEAPON] -> " .. WEAPON_NAMES[weaponIdx])
    else
        print("[WEAPON] -> none")
    end
end

local function setupNanoVG()
    vg = nvgCreate(1)
    if not vg then
        print("[WARN] NanoVG context unavailable; debug overlay disabled")
        return
    end
    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
end

local function worldToScreen(wx, wy)
    local gfx = GetGraphics()
    local cam = cameraNode:GetComponent("Camera")
    local viewH = cam.orthoSize
    local viewW = viewH * gfx:GetWidth() / gfx:GetHeight()
    local sx = (wx - cameraNode.position.x) / viewW * gfx:GetWidth()  + gfx:GetWidth()  * 0.5
    local sy = -(wy - cameraNode.position.y) / viewH * gfx:GetHeight() + gfx:GetHeight() * 0.5
    return sx, sy
end

local function drawJointsOverlay()
    if not vg or not skelInst or not boneNodes then return end
    local invPPM = 1 / PIXELS_PER_METER
    nvgBeginPath(vg)
    for name, _ in pairs(boneNodes) do
        local p = skelInst.parts[name]
        if p and p.wx then
            local cx = charNode.position2D.x + facing * (p.wx * invPPM)
            local cy = charNode.position2D.y - (p.wy * invPPM)
            local sx, sy = worldToScreen(cx, cy)
            nvgCircle(vg, sx, sy, 3)
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
    nvgText(vg, 20, 18, "skeleton2d / StaticSprite2D Demo", nil)

    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(220, 230, 255, 255))
    local y, lh = 46, 20
    nvgText(vg, 20, y, "Char:    " .. CHARACTERS[charIndex].id,  nil); y = y + lh
    nvgText(vg, 20, y, "Anim:    " .. currentAnim,               nil); y = y + lh
    local wname = (weaponIdx == 0) and "(none)" or WEAPON_NAMES[weaponIdx]
    nvgText(vg, 20, y, "Weapon:  " .. wname,                     nil); y = y + lh
    nvgText(vg, 20, y, "Facing:  " .. (facing == 1 and "Right" or "Left"), nil); y = y + lh
    nvgText(vg, 20, y, string.format("Pos:     (%.2f, %.2f) m", charX, charY), nil); y = y + lh
    nvgText(vg, 20, y, "Bones:   " .. tostring(boneCount),       nil); y = y + lh

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(160, 160, 180, 200))
    nvgText(vg, 20, y + 6, "[1-5] Anim [A/D] Move [F] Flip [C] Char [W] Weapon [J/H] Overlay", nil)
end

function Start()
    SampleStart()
    SampleInitMouseMode(MM_FREE)

    setupScene()

    buildCharacter(charIndex)
    setupNanoVG()

    SubscribeToEvent("Update", "HandleUpdate")
    if vg then
        SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    end

    print("=== skeleton2d StaticSprite2D Demo ===")
    print("[1-5] Anim  [A/D] Move  [F] Flip  [C] Char  [W] Weapon  [J/H] Overlay")
end

function Stop()
    if vg then nvgDelete(vg); vg = nil end
    destroyCharacter()
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    local Anims = CHARACTERS[charIndex].animations

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

    local moving = false
    if input:GetKeyDown(KEY_A) then charX = charX - moveSpeed * dt; facing = -1; moving = true end
    if input:GetKeyDown(KEY_D) then charX = charX + moveSpeed * dt; facing =  1; moving = true end

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

    Skeleton.Update(skelInst, dt)
    Skeleton.UpdateWorldTransforms(skelInst)
    SpriteBE.Sync(boneNodes, skelInst, { pixelsPerMeter = PIXELS_PER_METER })

    charNode.position2D = Vector2(charX, charY)
    spriteRoot:SetScale2D(Vector2(facing, 1))
end

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end
    local gfx = GetGraphics()
    nvgBeginFrame(vg, gfx:GetWidth(), gfx:GetHeight(), 1.0)
    if showJoints then drawJointsOverlay() end
    if showHUD    then drawHUD() end
    nvgEndFrame(vg)
end
