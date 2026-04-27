-- ============================================================================
-- skeleton2d StaticSprite2D Demo (TapTap Maker / UrhoX)
--
-- 演示 skeleton2d 跑在 UrhoX 场景图渲染通路上：
--   - 每个骨骼部件 = 一个子 Node + StaticSprite2D 组件（一次性创建）
--   - 每帧 Skeleton.UpdateWorldTransforms 算出 wx/wy/wr，
--     再由 backends/taptap_sprite 同步到 node.position2D / rotation2D
--
-- 数据：
--   police_m   男警察（14 骨）  Textures/police_m/parts/*.png
--   civilian_f 女平民（14 骨）  Textures/civilian_f/parts/*.png
--   weapons    handgun / knife  Textures/weapons/*.png
--
-- 部署：scripts/ 下符号链接（git 提交，引擎运行时按文件读取）：
--   SkeletonRenderer.lua          → ../../../runtime/lua/SkeletonRenderer.lua
--   backends/taptap_sprite.lua    → ../../../../runtime/lua/backends/taptap_sprite.lua
--   police_m/skeleton.lua         (本地生成)
--   police_m/animations.lua       → ../../../humanoid/animations.lua
--   civilian_f/skeleton.lua       (本地生成)
--   civilian_f/animations.lua     → ../../../humanoid/animations.lua
-- ============================================================================

require "LuaScripts/Utilities/Sample"

local Skeleton = require "SkeletonRenderer"
local SpriteBE = require "backends.taptap_sprite"
local Weapons  = require "weapons"

local CHARACTERS = {
    { id = "police_m",
      skeleton   = require "police_m.skeleton",
      animations = require "police_m.animations" },
    { id = "civilian_f",
      skeleton   = require "civilian_f.skeleton",
      animations = require "civilian_f.animations" },
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

local function attachCurrentWeapon()
    if weaponIdx == 0 then return end
    local w = Weapons[WEAPON_NAMES[weaponIdx]]
    if not (w and skelInst and boneNodes and spriteRoot) then return end
    Skeleton.AttachWeapon(skelInst, w, "handR")
    SpriteBE.AttachPart(boneNodes, spriteRoot, skelInst, "weapon", {
        cache            = cache,
        texturePrefix    = "Textures/",
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

    boneNodes = SpriteBE.CreateNodes(spriteRoot, skelInst, {
        cache            = cache,
        texturePrefix    = "Textures/",
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
