-- Weapon defs for the NanoVG demo.
-- 配合 Skeleton.AttachWeapon 使用，绘制由 main.lua 的 NanoVG 主循环完成。
--
-- 字段:
--   png       贴图相对 Textures/ 路径
--   w, h      贴图像素尺寸（用于 placeholder 占位框，可选）
--   anchor    贴图内的 grip 像素 [px, py]
--   attachAt  父部件 (handR) 图像局部坐标里的挂点 [px, py]
--   restRot   静态相对父的角度（度），未做动画时使用
--   z         层级（hand 是 2，武器一般 >2 显示在手前面）
return {
    handgun = {
        png      = "weapons/handgun.png",
        w        = 118, h = 84,
        anchor   = { 102, 67 },   -- grip mid pixel
        attachAt = { 15, 20 },    -- 挂在 handR 中心
        restRot  = 0,
        z        = 3,
    },
    knife = {
        png      = "weapons/knife.png",
        w        = 106, h = 111,
        anchor   = { 78, 33 },    -- grip just above guard
        attachAt = { 15, 20 },
        restRot  = 30,            -- 顺手向前下方
        z        = 3,
    },
}
