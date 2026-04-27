-- ============================================================
-- skeleton2d / SkeletonRenderer.lua
-- ------------------------------------------------------------
-- 极简 2D 纸娃娃骨骼渲染器（无 NanoVG/Renderer 强依赖）。
--
-- 用法：
--   local Skeleton = require "skeleton2d.runtime.lua.SkeletonRenderer"
--   Skeleton.SetBackend({
--       drawImage = function(handle, x, y, w, h) end,
--       fillRect  = function(x, y, w, h, rgba) end,
--       getImage  = function(path) return handle end,   -- 同步返回，缺失返回 nil/0
--       enqueueImage = function(path) end,              -- 异步加载（可选，缺失则跳过）
--       pushTransform = function() end,
--       popTransform  = function() end,
--       translate = function(x, y) end,
--       rotate    = function(rad) end,
--       scale     = function(sx, sy) end,
--   })
--
--   local inst = Skeleton.New(skeletonDef)   -- skeletonDef 来自 JSON 或等价 Lua 表
--   Skeleton.Play(inst, anims.swing, { loop = false })
--   -- per frame:
--   Skeleton.Update(inst, dt)
--   Skeleton.Draw(inst, x, y, facing, scale)
-- ============================================================

local Skeleton = {}

-- ---------- 后端接口 ----------
local backend = nil

local function noop() end
local function noop_get() return nil end

function Skeleton.SetBackend(be)
    backend = {
        drawImage     = be.drawImage     or noop,
        fillRect      = be.fillRect      or noop,
        getImage      = be.getImage      or noop_get,
        enqueueImage  = be.enqueueImage  or noop,
        pushTransform = be.pushTransform or noop,
        popTransform  = be.popTransform  or noop,
        translate     = be.translate     or noop,
        rotate        = be.rotate        or noop,
        scale         = be.scale         or noop,
    }
end

-- ---------- 关键帧线性插值 ----------
local function sampleTrack(track, phase)
    local n = #track
    if n == 0 then return 0 end
    if n == 1 then return track[1].rot or 0 end
    if phase <= track[1].t then return track[1].rot or 0 end
    if phase >= track[n].t then return track[n].rot or 0 end
    for i = 1, n - 1 do
        local a, b = track[i], track[i + 1]
        if phase >= a.t and phase <= b.t then
            local span = b.t - a.t
            if span <= 0 then return a.rot or 0 end
            local k = (phase - a.t) / span
            return (a.rot or 0) + ((b.rot or 0) - (a.rot or 0)) * k
        end
    end
    return track[n].rot or 0
end

local function applyAnimation(inst, anim, phase)
    for _, p in pairs(inst.parts) do
        p.currentRot = p.restRot or 0
    end
    if not anim then return end
    for boneName, track in pairs(anim.tracks or {}) do
        local p = inst.parts[boneName]
        if p then
            p.currentRot = sampleTrack(track, phase)
        end
    end
end

-- ---------- 数据归一化 ----------
-- 兼容 JSON 解析后的 anchor=[x,y] / Lua 表 anchor={x=,y=}
local function pt(v, default)
    if not v then return { default[1], default[2] } end
    if v.x ~= nil then return { v.x, v.y } end
    return { v[1] or default[1], v[2] or default[2] } 
end

-- ---------- 公共 API ----------

function Skeleton.New(skeletonDef)
    assert(skeletonDef and skeletonDef.parts, "skeleton def must have .parts")
    local parts = {}
    for name, src in pairs(skeletonDef.parts) do
        parts[name] = {
            png        = src.png,
            w          = src.w or 32,
            h          = src.h or 32,
            anchor     = pt(src.anchor,   {0, 0}),
            parent     = src.parent,
            attachAt   = pt(src.attachAt, {0, 0}),
            restRot    = src.restRot or 0,
            z          = src.z or 0,
            placeholderColor = src.placeholderColor or { 200, 100, 100, 220 },
            currentRot = src.restRot or 0,
        }
    end
    -- 找 root
    local rootName = skeletonDef.root
    if not rootName then
        for name, p in pairs(parts) do
            if not p.parent then rootName = name; break end
        end
    end
    -- 缓存子节点列表（按 z 升序，z 大的后画 = 在上层）
    local children = {}
    for name, p in pairs(parts) do
        if p.parent then
            children[p.parent] = children[p.parent] or {}
            table.insert(children[p.parent], name)
        end
    end
    for _, list in pairs(children) do
        table.sort(list, function(a, b) return parts[a].z < parts[b].z end)
    end

    return {
        def       = skeletonDef,
        parts     = parts,
        rootName  = rootName,
        children  = children,
        animation = nil,
        phase     = 0,
        playLoop  = true,
        finished  = false,
    }
end

function Skeleton.Play(inst, anim, opts)
    opts = opts or {}
    if inst.animation == anim and not opts.restart then return end
    inst.animation = anim
    inst.phase     = 0
    inst.finished  = false
    if opts.loop ~= nil then
        inst.playLoop = opts.loop
    elseif anim and anim.loop ~= nil then
        inst.playLoop = anim.loop
    else
        inst.playLoop = true
    end
end

function Skeleton.Update(inst, dt)
    local anim = inst.animation
    if not anim then return end
    local dur = anim.duration or 1.0
    inst.phase = inst.phase + dt
    if inst.phase >= dur then
        if inst.playLoop then
            inst.phase = inst.phase % dur
        else
            inst.phase = dur
            inst.finished = true
        end
    end
    applyAnimation(inst, anim, inst.phase)
end

local function drawTree(inst, name, be)
    local p = inst.parts[name]
    if not p then return end
    be.pushTransform()
    be.translate(p.attachAt[1], p.attachAt[2])
    be.rotate(math.rad(p.currentRot or 0))

    -- 画自己
    be.pushTransform()
    be.translate(-p.anchor[1], -p.anchor[2])
    if p.png then
        local handle = be.getImage(p.png)
        if handle and handle ~= 0 then
            be.drawImage(handle, 0, 0, p.w, p.h)
        else
            be.enqueueImage(p.png)
            be.fillRect(0, 0, p.w, p.h, p.placeholderColor)
        end
    else
        be.fillRect(0, 0, p.w, p.h, p.placeholderColor)
    end
    be.popTransform()

    -- 递归画子节点
    local kids = inst.children[name]
    if kids then
        for i = 1, #kids do
            drawTree(inst, kids[i], be)
        end
    end

    be.popTransform()
end

function Skeleton.Draw(inst, x, y, facing, scale)
    local be = backend
    if not be then error("Skeleton.SetBackend(...) must be called first") end
    facing = facing or 1
    scale  = scale or 1.0

    be.pushTransform()
    be.translate(x, y)
    if facing < 0 then
        be.scale(-scale, scale)
    elseif scale ~= 1 then
        be.scale(scale, scale)
    end

    if inst.rootName then
        drawTree(inst, inst.rootName, be)
    end

    be.popTransform()
end

function Skeleton.Preload(inst)
    if not backend then return end
    for _, p in pairs(inst.parts) do
        if p.png then backend.enqueueImage(p.png) end
    end
end

-- 动态挂武器到 handR（或任何已有部件）
function Skeleton.AttachWeapon(inst, weaponDef, parentName)
    parentName = parentName or "handR"
    local p = {
        png        = weaponDef.png,
        w          = weaponDef.w or 16,
        h          = weaponDef.h or 64,
        anchor     = pt(weaponDef.anchor,   {0, 0}),
        parent     = parentName,
        attachAt   = pt(weaponDef.attachAt, {0, 0}),
        restRot    = weaponDef.restRot or 0,
        z          = weaponDef.z or 5,
        placeholderColor = weaponDef.placeholderColor or { 180, 180, 180, 220 },
        currentRot = weaponDef.restRot or 0,
    }
    inst.parts.weapon = p
    inst.children[parentName] = inst.children[parentName] or {}
    table.insert(inst.children[parentName], "weapon")
end

function Skeleton.DetachWeapon(inst)
    inst.parts.weapon = nil
    for parent, kids in pairs(inst.children) do
        for i = #kids, 1, -1 do
            if kids[i] == "weapon" then table.remove(kids, i) end
        end
    end
end

return Skeleton
