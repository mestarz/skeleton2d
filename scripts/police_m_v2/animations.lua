-- police_m_v2: 18-part skeleton animations
-- 实证三个新通道：scaleY（呼吸）、rootOffset（bob）、ease（缓动）
-- 这些扩展字段由 main.lua 的临时 hack 消费，不在 SkeletonRenderer.lua 里
return {
    idle = {
        duration = 2.4,
        loop = true,
        rootOffset = {
            { t = 0,   y = 0,    ease = "easeInOut" },
            { t = 1.2, y = -1.5, ease = "easeInOut" },
            { t = 2.4, y = 0,    ease = "easeInOut" },
        },
        tracks = {
            chest = {
                { t = 0,   rot = 0, scaleY = 1.00, ease = "easeInOut" },
                { t = 1.2, rot = 0, scaleY = 1.04, ease = "easeInOut" },
                { t = 2.4, rot = 0, scaleY = 1.00, ease = "easeInOut" },
            },
            neck = {
                { t = 0,   rot =  0,   ease = "easeInOut" },
                { t = 1.2, rot = -2.5, ease = "easeInOut" },
                { t = 2.4, rot =  0,   ease = "easeInOut" },
            },
            head = {
                { t = 0,   rot = 0,    ease = "easeInOut" },
                { t = 1.2, rot = 1.5,  ease = "easeInOut" },
                { t = 2.4, rot = 0,    ease = "easeInOut" },
            },
            shoulderL = {
                { t = 0,   rot =  0,   ease = "easeInOut" },
                { t = 1.2, rot = -1,   ease = "easeInOut" },
                { t = 2.4, rot =  0,   ease = "easeInOut" },
            },
            shoulderR = {
                { t = 0,   rot =  0,   ease = "easeInOut" },
                { t = 1.2, rot =  1,   ease = "easeInOut" },
                { t = 2.4, rot =  0,   ease = "easeInOut" },
            },
        },
    },

    walk = {
        duration = 0.6,
        loop = true,
        rootOffset = {
            { t = 0,    y =  0, ease = "easeInOut" },
            { t = 0.15, y = -3, ease = "easeInOut" },
            { t = 0.3,  y =  0, ease = "easeInOut" },
            { t = 0.45, y = -3, ease = "easeInOut" },
            { t = 0.6,  y =  0, ease = "easeInOut" },
        },
        tracks = {
            pelvis = {
                { t = 0,   rot =  3, ease = "easeInOut" },
                { t = 0.3, rot = -3, ease = "easeInOut" },
                { t = 0.6, rot =  3, ease = "easeInOut" },
            },
            chest = {
                { t = 0,   rot = -2, scaleY = 1.0,  ease = "easeInOut" },
                { t = 0.3, rot =  2, scaleY = 1.02, ease = "easeInOut" },
                { t = 0.6, rot = -2, scaleY = 1.0,  ease = "easeInOut" },
            },
            thighL = {
                { t = 0,   rot =  25, ease = "easeInOut" },
                { t = 0.3, rot = -25, ease = "easeInOut" },
                { t = 0.6, rot =  25, ease = "easeInOut" },
            },
            thighR = {
                { t = 0,   rot = -25, ease = "easeInOut" },
                { t = 0.3, rot =  25, ease = "easeInOut" },
                { t = 0.6, rot = -25, ease = "easeInOut" },
            },
            shinL = {
                { t = 0,   rot = -10, ease = "easeInOut" },
                { t = 0.3, rot =  20, ease = "easeInOut" },
                { t = 0.6, rot = -10, ease = "easeInOut" },
            },
            shinR = {
                { t = 0,   rot =  20, ease = "easeInOut" },
                { t = 0.3, rot = -10, ease = "easeInOut" },
                { t = 0.6, rot =  20, ease = "easeInOut" },
            },
            shoulderL = {
                { t = 0,   rot = -8, ease = "easeInOut" },
                { t = 0.3, rot =  8, ease = "easeInOut" },
                { t = 0.6, rot = -8, ease = "easeInOut" },
            },
            shoulderR = {
                { t = 0,   rot =  8, ease = "easeInOut" },
                { t = 0.3, rot = -8, ease = "easeInOut" },
                { t = 0.6, rot =  8, ease = "easeInOut" },
            },
            upperArmL = {
                { t = 0,   rot = -25, ease = "easeInOut" },
                { t = 0.3, rot =  25, ease = "easeInOut" },
                { t = 0.6, rot = -25, ease = "easeInOut" },
            },
            upperArmR = {
                { t = 0,   rot =  25, ease = "easeInOut" },
                { t = 0.3, rot = -25, ease = "easeInOut" },
                { t = 0.6, rot =  25, ease = "easeInOut" },
            },
        },
    },
}
