// skeleton2d JS runtime (mirrors runtime/lua/SkeletonRenderer.lua).
// Renders to an HTML5 Canvas 2D context.

(function (global) {
  'use strict';

  function pt(v, dx, dy) {
    if (!v) return [dx, dy];
    if (Array.isArray(v)) return [Number(v[0]) || dx, Number(v[1]) || dy];
    if (typeof v === 'object') return [Number(v.x) || dx, Number(v.y) || dy];
    return [dx, dy];
  }

  function sampleTrack(track, phase) {
    const n = track.length;
    if (n === 0) return 0;
    if (n === 1) return track[0].rot || 0;
    if (phase <= track[0].t) return track[0].rot || 0;
    if (phase >= track[n - 1].t) return track[n - 1].rot || 0;
    for (let i = 0; i < n - 1; i++) {
      const a = track[i], b = track[i + 1];
      if (phase >= a.t && phase <= b.t) {
        const span = b.t - a.t;
        if (span <= 0) return a.rot || 0;
        const k = (phase - a.t) / span;
        return (a.rot || 0) + ((b.rot || 0) - (a.rot || 0)) * k;
      }
    }
    return track[n - 1].rot || 0;
  }

  function applyAnimation(inst, anim, phase) {
    for (const name in inst.parts) {
      const p = inst.parts[name];
      p.currentRot = p.restRot || 0;
    }
    if (!anim || !anim.tracks) return;
    for (const boneName in anim.tracks) {
      const p = inst.parts[boneName];
      if (p) p.currentRot = sampleTrack(anim.tracks[boneName], phase);
    }
  }

  function newInstance(skeletonDef) {
    if (!skeletonDef || !skeletonDef.parts) throw new Error('skeleton def must have .parts');
    const parts = {};
    for (const name in skeletonDef.parts) {
      const src = skeletonDef.parts[name];
      parts[name] = {
        png:        src.png || null,
        w:          src.w || 32,
        h:          src.h || 32,
        anchor:     pt(src.anchor,   0, 0),
        parent:     src.parent || null,
        attachAt:   pt(src.attachAt, 0, 0),
        restRot:    src.restRot || 0,
        z:          src.z || 0,
        placeholderColor: src.placeholderColor || [200, 100, 100, 220],
        currentRot: src.restRot || 0,
      };
    }
    let rootName = skeletonDef.root || null;
    if (!rootName) {
      for (const name in parts) if (!parts[name].parent) { rootName = name; break; }
    }
    const children = {};
    for (const name in parts) {
      const p = parts[name];
      if (p.parent) {
        (children[p.parent] = children[p.parent] || []).push(name);
      }
    }
    for (const k in children) children[k].sort((a, b) => parts[a].z - parts[b].z);

    return {
      def: skeletonDef,
      parts,
      rootName,
      children,
      animation: null,
      phase: 0,
      playLoop: true,
      finished: false,
    };
  }

  function play(inst, anim, opts) {
    opts = opts || {};
    if (inst.animation === anim && !opts.restart) return;
    inst.animation = anim;
    inst.phase = 0;
    inst.finished = false;
    if (opts.loop !== undefined) inst.playLoop = opts.loop;
    else if (anim && anim.loop !== undefined) inst.playLoop = anim.loop;
    else inst.playLoop = true;
  }

  function update(inst, dt) {
    const anim = inst.animation;
    if (!anim) return;
    const dur = anim.duration || 1.0;
    inst.phase += dt;
    if (inst.phase >= dur) {
      if (inst.playLoop) inst.phase = inst.phase % dur;
      else { inst.phase = dur; inst.finished = true; }
    }
    applyAnimation(inst, anim, inst.phase);
  }

  // imageProvider(path) -> HTMLImageElement | null (loaded) | 'pending' | null
  function drawTree(inst, name, ctx, imageProvider, highlightName) {
    const p = inst.parts[name];
    if (!p) return;
    ctx.save();
    ctx.translate(p.attachAt[0], p.attachAt[1]);
    ctx.rotate((p.currentRot || 0) * Math.PI / 180);

    ctx.save();
    ctx.translate(-p.anchor[0], -p.anchor[1]);
    let drewImage = false;
    if (p.png && imageProvider) {
      const img = imageProvider(p.png);
      if (img && img.complete && img.naturalWidth > 0) {
        ctx.drawImage(img, 0, 0, p.w, p.h);
        drewImage = true;
      }
    }
    if (!drewImage) {
      const c = p.placeholderColor;
      ctx.fillStyle = `rgba(${c[0]},${c[1]},${c[2]},${(c[3]||255)/255})`;
      ctx.fillRect(0, 0, p.w, p.h);
      ctx.strokeStyle = 'rgba(30,30,30,0.6)';
      ctx.lineWidth = 1;
      ctx.strokeRect(0, 0, p.w, p.h);
    }
    if (highlightName === name) {
      ctx.strokeStyle = '#ffeb3b';
      ctx.lineWidth = 2;
      ctx.strokeRect(0, 0, p.w, p.h);
      // anchor cross
      ctx.fillStyle = '#ff5722';
      ctx.beginPath();
      ctx.arc(p.anchor[0], p.anchor[1], 3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    const kids = inst.children[name];
    if (kids) for (let i = 0; i < kids.length; i++) drawTree(inst, kids[i], ctx, imageProvider, highlightName);

    ctx.restore();
  }

  function draw(inst, ctx, x, y, facing, scale, imageProvider, highlightName) {
    facing = facing || 1;
    scale = scale || 1.0;
    ctx.save();
    ctx.translate(x, y);
    if (facing < 0) ctx.scale(-scale, scale);
    else if (scale !== 1) ctx.scale(scale, scale);
    if (inst.rootName) drawTree(inst, inst.rootName, ctx, imageProvider, highlightName);
    ctx.restore();
  }

  global.Skeleton2D = {
    New: newInstance,
    Play: play,
    Update: update,
    Draw: draw,
  };
})(window);
