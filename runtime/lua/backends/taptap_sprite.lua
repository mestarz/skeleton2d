---@diagnostic disable: undefined-global
-- ============================================================
-- skeleton2d / backends/taptap_sprite.lua
-- ------------------------------------------------------------
-- TapTap Maker (UrhoX) Sprite 节点适配器。
--
-- 把 skeleton2d 的部件挂成 TapTap 场景图里的 StaticSprite2D 节点，
-- 每帧只需把 Skeleton.UpdateWorldTransforms() 算出的 wx/wy/wr
-- 同步到 node.position2D / rotation2D，引擎自动绘制 + 支持物理碰撞。
--
-- ------------------------------------------------------------
-- 用法：
--   local Skeleton = require "external.skeleton2d.runtime.lua.SkeletonRenderer"
--   local SpriteBE = require "external.skeleton2d.runtime.lua.backends.taptap_sprite"
--
--   -- 一次性建节点（角色 Enter 时）
--   self.skeleton  = Skeleton.New(SkelDef)
--   self.spriteRoot = charNode:CreateChild("SpriteRoot")
--   self.boneNodes  = SpriteBE.CreateNodes(self.spriteRoot, self.skeleton, {
--       cache            = cache,            -- ResourceCache 子系统
--       texturePrefix    = "Textures/",      -- 资源前缀（可选）
--       pixelsPerMeter   = 100,              -- 像素 → UrhoX 单位
--       baseOrderInLayer = 0,                -- 整体图层基线
--   })
--
--   -- 每帧
--   Skeleton.Update(self.skeleton, dt)
--   Skeleton.UpdateWorldTransforms(self.skeleton)
--   SpriteBE.Sync(self.boneNodes, self.skeleton)
--
--   -- 切朝向：直接缩放 spriteRoot
--   self.spriteRoot:SetScale2D(Vector2(facing < 0 and -1 or 1, 1))
--
--   -- 角色销毁
--   SpriteBE.Destroy(self.boneNodes)
-- ============================================================

local M = {}

local DEFAULT_OPTS = {
    pixelsPerMeter   = 100,
    texturePrefix    = "",
    baseOrderInLayer = 0,
    blendMode        = nil,   -- 默认 BLEND_ALPHA（若全局可用）
    -- 图集模式（3 个字段需同时提供）：
    atlasPath        = nil,   -- string: 图集 PNG 资源路径
    atlasRects       = nil,   -- table: { partName = { x, y, w, h }, ... } 像素坐标
    atlasSize        = nil,   -- table: { w, h } 图集整体尺寸（用于归一化）
}

local function mergeOpts(opts)
    local o = {}
    for k, v in pairs(DEFAULT_OPTS) do o[k] = v end
    if opts then
        for k, v in pairs(opts) do o[k] = v end
    end
    return o
end

--- 在 parentNode 下为骨骼每个部件创建一个子节点 + StaticSprite2D。
--- 节点名 = 部件名。返回 { partName -> Node } 映射。
---
---@param parentNode userdata UrhoX Node（建议是 spriteRoot 子节点）
---@param skeletonInst table  Skeleton.New(...) 的返回值
---@param opts table|nil
---@return table boneNodes  partName → Node
function M.CreateNodes(parentNode, skeletonInst, opts)
    assert(parentNode, "taptap_sprite.CreateNodes: parentNode required")
    assert(skeletonInst and skeletonInst.parts, "taptap_sprite.CreateNodes: skeletonInst invalid")
    local o = mergeOpts(opts)
    local cache = o.cache or _G.cache  -- TapTap 通常注册了全局 `cache`
    local ppm   = o.pixelsPerMeter
    local invPPM = 1 / ppm

    -- 图集模式：预加载图集 Sprite2D（所有部件共享同一张贴图）
    -- 注意：如果用户传了 atlasPath 但加载失败，应当显式报错，而不是悄悄回退到
    -- 单 PNG 路径（那条路径会触发一堆"找不到 part PNG"的二次错误，反而掩盖
    -- 真正的"图集没加载"原因）。
    local atlasMode  = (o.atlasPath ~= nil)
    local atlasSprite = nil
    local atlasW, atlasH = 1, 1
    if atlasMode then
        if not (o.atlasRects and o.atlasSize) then
            print("[taptap_sprite] ERROR: atlasPath given but atlasRects/atlasSize missing -> " .. tostring(o.atlasPath))
        elseif not cache then
            print("[taptap_sprite] ERROR: no ResourceCache available; cannot load atlas " .. tostring(o.atlasPath))
        else
            atlasSprite = cache:GetResource("Sprite2D", o.atlasPath)
            if not atlasSprite then
                print("[taptap_sprite] ERROR: atlas Sprite2D not found in ResourceCache: '" .. tostring(o.atlasPath) .. "'")
                print("[taptap_sprite]   - Check the file exists under your TapTap project's Resources/Data/")
                print("[taptap_sprite]   - Re-cook / reimport assets if you just added the atlas PNG")
                print("[taptap_sprite]   - The path is resolved relative to ResourceCache roots, not to scripts/")
            else
                atlasW = o.atlasSize.w
                atlasH = o.atlasSize.h
            end
        end
    end

    local boneNodes = {}
    for name, p in pairs(skeletonInst.parts) do
        local node = parentNode:CreateChild(name)

        local sprite = node:CreateComponent("StaticSprite2D")
        if atlasSprite and o.atlasRects[name] then
            -- 图集模式：共用同一张 Sprite2D，用 textureRect 选择子区域
            sprite.sprite = atlasSprite
            local r = o.atlasRects[name]
            sprite.useTextureRect = true
            sprite.textureRect = Rect(
                r.x / atlasW, r.y / atlasH,
                (r.x + r.w) / atlasW, (r.y + r.h) / atlasH
            )
        elseif atlasMode then
            -- 处于图集模式但 atlas 没加载到 / 或者 part 不在 atlasRects 里：
            -- 不要回退到单 PNG 路径（那些 PNG 通常已经被打包流程移除），
            -- 否则会污染日志、掩盖真正的图集错误。直接留空 sprite，警告一行。
            if atlasSprite and not o.atlasRects[name] then
                print("[taptap_sprite] WARN: part '" .. name .. "' not in atlasRects; skipped")
            end
        elseif p.png and cache then
            local res = cache:GetResource("Sprite2D", o.texturePrefix .. p.png)
            if res then sprite.sprite = res end
        end

        -- 透明 PNG 通用混合
        local blend = o.blendMode or _G.BLEND_ALPHA
        if blend then sprite.blendMode = blend end

        -- 锚点：skeleton2d 用像素坐标（左上原点），UrhoX 用 0~1 归一化（左下原点）
        sprite.useHotSpot = true
        local hsX = (p.w and p.w > 0) and (p.anchor[1] / p.w) or 0.5
        local hsY = (p.h and p.h > 0) and (1 - p.anchor[2] / p.h) or 0.5
        sprite.hotSpot = Vector2(hsX, hsY)

        -- 自定义绘制尺寸（按像素 → 米换算），保证与编辑器视觉一致
        if p.w and p.h then
            local halfW = (p.w * invPPM) * 0.5
            local halfH = (p.h * invPPM) * 0.5
            sprite.useDrawRect = true
            sprite.drawRect = Rect(-halfW, -halfH, halfW, halfH)
        end

        sprite.orderInLayer = o.baseOrderInLayer + (p.z or 0)

        boneNodes[name] = node
    end

    return boneNodes
end

--- 每帧把 runtime 算好的世界变换写到节点。
--- 调用前请先 Skeleton.UpdateWorldTransforms(skeletonInst)。
---@param boneNodes table  CreateNodes 的返回值
---@param skeletonInst table
---@param opts table|nil  { pixelsPerMeter = 100 }（应与 CreateNodes 一致）
function M.Sync(boneNodes, skeletonInst, opts)
    local ppm = (opts and opts.pixelsPerMeter) or DEFAULT_OPTS.pixelsPerMeter
    local inv = 1 / ppm
    for name, node in pairs(boneNodes) do
        local p = skeletonInst.parts[name]
        if p and p.wx ~= nil then
            -- skeleton2d 屏幕坐标系 Y 向下；UrhoX 2D Y 向上 → 翻转 y
            node.position2D = Vector2(p.wx * inv, -p.wy * inv)
            node.rotation2D = -(p.wr or 0)
        end
    end
end

--- 销毁所有部件节点。
---@param boneNodes table
function M.Destroy(boneNodes)
    if not boneNodes then return end
    for name, node in pairs(boneNodes) do
        if node and node.Remove then node:Remove() end
        boneNodes[name] = nil
    end
end

--- 动态挂武器：在已有 boneNodes 中追加一个挂在 parentName 下的部件。
--- 配合 Skeleton.AttachWeapon 使用。
---@param boneNodes table
---@param parentNode userdata SpriteRoot（与 CreateNodes 同级）
---@param skeletonInst table
---@param weaponName string  默认 "weapon"
---@param opts table|nil
function M.AttachPart(boneNodes, parentNode, skeletonInst, weaponName, opts)
    weaponName = weaponName or "weapon"
    local p = skeletonInst.parts[weaponName]
    if not p then return end
    local subInst = { parts = { [weaponName] = p } }
    local sub = M.CreateNodes(parentNode, subInst, opts)
    boneNodes[weaponName] = sub[weaponName]
end

--- 移除一个部件节点（配合 Skeleton.DetachWeapon）
function M.DetachPart(boneNodes, partName)
    partName = partName or "weapon"
    local node = boneNodes[partName]
    if node and node.Remove then node:Remove() end
    boneNodes[partName] = nil
end

return M
