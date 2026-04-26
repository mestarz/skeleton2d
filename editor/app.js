// skeleton2d editor - main application
'use strict';

// ----- State -----
const state = {
  skeleton: null,        // { id, version, root, parts: { name: {...} } }
  anims: {},             // { name: { duration, loop, tracks } }
  selectedPart: null,
  currentAnim: 'idle',
  inst: null,            // Skeleton2D instance
  playing: false,
  imageCache: {},        // path -> HTMLImageElement
  facing: 1,
  viewScale: 1.5,
  origin: { x: 0, y: 0 }, // canvas-space origin where root is drawn
  drag: null,             // { kind: 'pan'|'anchor'|'attachAt', startX, startY, baseX, baseY }
};

const EMPTY_ANIMS = { idle: { duration: 1.0, loop: true, tracks: {} } };

// ----- DOM helpers -----
const $ = (id) => document.getElementById(id);

function setStatus(msg) { $('status').textContent = msg; }

// ----- Skeleton creation / mutation -----
function newEmptySkeleton() {
  return {
    id: 'untitled',
    version: 1,
    root: 'torso',
    parts: {
      torso: { parent: null, w: 60, h: 90, anchor: [30, 90], attachAt: [0, 0], restRot: 0, z: 0, png: null, placeholderColor: [200, 100, 100, 220] },
    },
  };
}

function rebuildInstance() {
  if (!state.skeleton) { state.inst = null; return; }
  state.inst = Skeleton2D.New(state.skeleton);
  const anim = state.anims[state.currentAnim];
  if (anim) Skeleton2D.Play(state.inst, anim, { loop: anim.loop !== false });
}

// ----- Image loading -----
function imageProvider(path) {
  if (!path) return null;
  return state.imageCache[path] || null;
}

function loadImageDataURL(path, dataURL, autoSize) {
  const img = new Image();
  img.onload = () => {
    state.imageCache[path] = img;
    if (autoSize && state.skeleton.parts[path === '__last_part_image__' ? state.selectedPart : null]) {}
    if (autoSize && state.selectedPart) {
      const p = state.skeleton.parts[state.selectedPart];
      // Only resize if user explicitly assigned to this part
      if (p && p.png === path) {
        p.w = img.naturalWidth;
        p.h = img.naturalHeight;
        renderPropsPanel();
      }
    }
    redraw();
  };
  img.src = dataURL;
}

function readFileAsDataURL(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = reject;
    r.readAsDataURL(file);
  });
}

function readFileAsText(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = reject;
    r.readAsText(file);
  });
}

// ----- Rendering -----
let canvas, ctx;

function redraw() {
  if (!ctx) return;
  const w = canvas.width, h = canvas.height;
  ctx.fillStyle = '#1a1a1a';
  ctx.fillRect(0, 0, w, h);

  // grid
  ctx.strokeStyle = '#2a2a2a';
  ctx.lineWidth = 1;
  const step = 20;
  for (let x = 0; x < w; x += step) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke(); }
  for (let y = 0; y < h; y += step) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke(); }

  // axes through origin
  ctx.strokeStyle = '#3a3a3a';
  ctx.beginPath(); ctx.moveTo(state.origin.x, 0); ctx.lineTo(state.origin.x, h); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(0, state.origin.y); ctx.lineTo(w, state.origin.y); ctx.stroke();

  if (state.inst) {
    Skeleton2D.Draw(state.inst, ctx, state.origin.x, state.origin.y, state.facing, state.viewScale, imageProvider, state.selectedPart);
  }

  // Selected part overlay marker for attachAt (drawn separately as a ring at parent space)
  if (state.selectedPart) {
    const p = state.skeleton.parts[state.selectedPart];
    if (p) {
      // Compute world transform of parent and draw attachAt point
      const M = computeWorldTransform(state.selectedPart, /*upToAttach*/ true);
      if (M) {
        ctx.save();
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        const wp = applyMatrix(M, 0, 0);
        ctx.fillStyle = '#03a9f4';
        ctx.beginPath(); ctx.arc(wp.x, wp.y, 4, 0, Math.PI * 2); ctx.fill();
        ctx.restore();
      }
    }
  }
}

// Manual transform composition for hit-testing & overlay markers.
// Returns 2x3 matrix [a,b,c,d,e,f] s.t. (x,y) -> (a*x+c*y+e, b*x+d*y+f)
function identity() { return [1, 0, 0, 1, 0, 0]; }
function multiply(m1, m2) {
  const [a1,b1,c1,d1,e1,f1] = m1;
  const [a2,b2,c2,d2,e2,f2] = m2;
  return [
    a1*a2 + c1*b2,
    b1*a2 + d1*b2,
    a1*c2 + c1*d2,
    b1*c2 + d1*d2,
    a1*e2 + c1*f2 + e1,
    b1*e2 + d1*f2 + f1,
  ];
}
function translateM(m, tx, ty) { return multiply(m, [1,0,0,1,tx,ty]); }
function rotateM(m, rad) { const c=Math.cos(rad), s=Math.sin(rad); return multiply(m, [c,s,-s,c,0,0]); }
function scaleM(m, sx, sy) { return multiply(m, [sx,0,0,sy,0,0]); }
function applyMatrix(m, x, y) { return { x: m[0]*x + m[2]*y + m[4], y: m[1]*x + m[3]*y + m[5] }; }

// Build transform stack from canvas-origin into the local coordinate space *just
// before drawing the part itself* (i.e., after attachAt + rotate, before -anchor).
// If upToAttach=true, stops after parent chain attachAt+rot but before this part's
// own attachAt — used to mark attachAt point.
function computeWorldTransform(name, upToAttach) {
  if (!state.inst) return null;
  // Build chain root -> ... -> name
  const chain = [];
  let cur = name;
  while (cur) {
    chain.unshift(cur);
    cur = state.inst.parts[cur].parent;
  }

  let M = identity();
  M = translateM(M, state.origin.x, state.origin.y);
  if (state.facing < 0) M = scaleM(M, -state.viewScale, state.viewScale);
  else M = scaleM(M, state.viewScale, state.viewScale);

  for (let i = 0; i < chain.length; i++) {
    const p = state.inst.parts[chain[i]];
    if (i === chain.length - 1 && upToAttach) {
      // We want the parent-space frame at which this part's attachAt is plotted,
      // i.e. the parent's local-space origin (before applying this part's attachAt).
      M = translateM(M, p.attachAt[0], p.attachAt[1]);
      return M;
    }
    M = translateM(M, p.attachAt[0], p.attachAt[1]);
    M = rotateM(M, (p.currentRot || 0) * Math.PI / 180);
  }
  return M;
}

// ----- Parts list rendering -----
function renderPartsList() {
  const ul = $('parts-list');
  ul.innerHTML = '';
  if (!state.skeleton) return;
  // Build tree from root
  const visited = new Set();
  const order = [];
  function visit(name, depth) {
    if (visited.has(name) || !state.skeleton.parts[name]) return;
    visited.add(name);
    order.push({ name, depth });
    for (const childName in state.skeleton.parts) {
      if (state.skeleton.parts[childName].parent === name) visit(childName, depth + 1);
    }
  }
  const root = state.skeleton.root;
  if (root && state.skeleton.parts[root]) visit(root, 0);
  // append orphans
  for (const name in state.skeleton.parts) if (!visited.has(name)) order.push({ name, depth: 0 });

  for (const { name, depth } of order) {
    const p = state.skeleton.parts[name];
    const li = document.createElement('li');
    li.dataset.name = name;
    if (state.selectedPart === name) li.classList.add('selected');
    if (p.png && state.imageCache[p.png]) li.classList.add('has-png');
    const indent = '·'.repeat(depth * 2);
    li.innerHTML = `<span><span class="indent">${indent}</span> ${name}</span><span class="png-dot"></span>`;
    li.addEventListener('click', () => selectPart(name));
    li.addEventListener('dragover', (e) => { e.preventDefault(); li.style.background = '#3a4a5a'; });
    li.addEventListener('dragleave', () => { li.style.background = ''; });
    li.addEventListener('drop', async (e) => {
      e.preventDefault();
      li.style.background = '';
      const file = e.dataTransfer.files[0];
      if (!file || !file.type.startsWith('image/')) return;
      const dataURL = await readFileAsDataURL(file);
      const path = file.name;
      state.skeleton.parts[name].png = path;
      loadImageDataURL(path, dataURL, true);
      selectPart(name);
      renderPartsList();
      setStatus(`assigned ${path} to ${name}`);
    });
    ul.appendChild(li);
  }
}

function selectPart(name) {
  state.selectedPart = name;
  renderPartsList();
  renderPropsPanel();
  renderKeyframes();
  redraw();
}

// ----- Props panel -----
function renderPropsPanel() {
  if (!state.selectedPart || !state.skeleton.parts[state.selectedPart]) {
    $('part-name-display').textContent = '(none)';
    return;
  }
  const p = state.skeleton.parts[state.selectedPart];
  $('part-name-display').textContent = state.selectedPart;

  // parent select
  const sel = $('prop-parent');
  sel.innerHTML = '<option value="">(root)</option>';
  for (const n in state.skeleton.parts) {
    if (n === state.selectedPart) continue;
    const o = document.createElement('option');
    o.value = n; o.textContent = n;
    if (p.parent === n) o.selected = true;
    sel.appendChild(o);
  }

  $('prop-png').value = p.png || '';
  $('prop-w').value = p.w;
  $('prop-h').value = p.h;
  $('prop-anchor-x').value = p.anchor[0];
  $('prop-anchor-y').value = p.anchor[1];
  $('prop-attach-x').value = p.attachAt[0];
  $('prop-attach-y').value = p.attachAt[1];
  $('prop-restrot').value = p.restRot || 0;
  $('prop-z').value = p.z || 0;
}

function bindPropFields() {
  function onChange(id, fn) {
    $(id).addEventListener('change', () => {
      if (!state.selectedPart) return;
      fn(state.skeleton.parts[state.selectedPart]);
      rebuildInstance(); redraw(); renderPartsList();
    });
  }
  onChange('prop-parent', (p) => { p.parent = $('prop-parent').value || null; });
  onChange('prop-png',    (p) => { p.png = $('prop-png').value || null; });
  onChange('prop-w',      (p) => { p.w = +$('prop-w').value || 1; });
  onChange('prop-h',      (p) => { p.h = +$('prop-h').value || 1; });
  onChange('prop-anchor-x', (p) => { p.anchor[0] = +$('prop-anchor-x').value || 0; });
  onChange('prop-anchor-y', (p) => { p.anchor[1] = +$('prop-anchor-y').value || 0; });
  onChange('prop-attach-x', (p) => { p.attachAt[0] = +$('prop-attach-x').value || 0; });
  onChange('prop-attach-y', (p) => { p.attachAt[1] = +$('prop-attach-y').value || 0; });
  onChange('prop-restrot', (p) => { p.restRot = +$('prop-restrot').value || 0; });
  onChange('prop-z',       (p) => { p.z = +$('prop-z').value || 0; });

  $('prop-png-clear').addEventListener('click', () => {
    if (!state.selectedPart) return;
    state.skeleton.parts[state.selectedPart].png = null;
    rebuildInstance(); renderPropsPanel(); renderPartsList(); redraw();
  });

  $('prop-png-file').addEventListener('change', async (e) => {
    if (!state.selectedPart) return;
    const file = e.target.files[0]; if (!file) return;
    const dataURL = await readFileAsDataURL(file);
    const path = file.name;
    state.skeleton.parts[state.selectedPart].png = path;
    loadImageDataURL(path, dataURL, true);
    renderPropsPanel(); renderPartsList(); redraw();
    e.target.value = '';
  });
}

// ----- Animation editor -----
function renderAnimSelect() {
  const sel = $('anim-select');
  sel.innerHTML = '';
  for (const name in state.anims) {
    const o = document.createElement('option');
    o.value = name; o.textContent = name;
    if (name === state.currentAnim) o.selected = true;
    sel.appendChild(o);
  }
  const a = state.anims[state.currentAnim];
  if (a) {
    $('anim-duration').value = a.duration;
    $('anim-loop').checked = a.loop !== false;
    $('time-slider').max = a.duration;
    $('time-slider').step = 0.01;
  }
}

function renderKeyframes() {
  const ul = $('keyframes'); ul.innerHTML = '';
  const a = state.anims[state.currentAnim]; if (!a) return;
  if (!state.selectedPart) return;
  const track = (a.tracks[state.selectedPart] = a.tracks[state.selectedPart] || []);
  track.sort((x, y) => x.t - y.t);
  for (let i = 0; i < track.length; i++) {
    const kf = track[i];
    const li = document.createElement('li');
    li.innerHTML = `t <input type="number" data-i="${i}" data-k="t" step="0.01" value="${kf.t}"> rot <input type="number" data-i="${i}" data-k="rot" step="1" value="${kf.rot || 0}"> <button data-del="${i}">×</button>`;
    ul.appendChild(li);
  }
  ul.querySelectorAll('input').forEach(inp => {
    inp.addEventListener('change', () => {
      const i = +inp.dataset.i, k = inp.dataset.k;
      track[i][k] = +inp.value;
      track.sort((x, y) => x.t - y.t);
      rebuildInstance(); redraw(); renderKeyframes();
    });
  });
  ul.querySelectorAll('button[data-del]').forEach(btn => {
    btn.addEventListener('click', () => {
      track.splice(+btn.dataset.del, 1);
      rebuildInstance(); redraw(); renderKeyframes();
    });
  });
}

function bindAnimUI() {
  $('anim-select').addEventListener('change', () => {
    state.currentAnim = $('anim-select').value;
    rebuildInstance();
    renderAnimSelect();
    renderKeyframes();
    redraw();
  });
  $('anim-duration').addEventListener('change', () => {
    const a = state.anims[state.currentAnim]; if (!a) return;
    a.duration = +$('anim-duration').value || 1;
    rebuildInstance(); renderAnimSelect();
  });
  $('anim-loop').addEventListener('change', () => {
    const a = state.anims[state.currentAnim]; if (!a) return;
    a.loop = $('anim-loop').checked;
    rebuildInstance();
  });
  $('btn-add-anim').addEventListener('click', () => {
    const name = $('new-anim-name').value.trim(); if (!name) return;
    if (state.anims[name]) { setStatus('animation already exists'); return; }
    state.anims[name] = { duration: 1.0, loop: true, tracks: {} };
    state.currentAnim = name;
    $('new-anim-name').value = '';
    renderAnimSelect(); renderKeyframes(); rebuildInstance();
  });
  $('btn-add-kf').addEventListener('click', () => {
    if (!state.selectedPart) { setStatus('select a part first'); return; }
    const a = state.anims[state.currentAnim]; if (!a) return;
    const t = +$('time-slider').value;
    const p = state.skeleton.parts[state.selectedPart];
    const track = (a.tracks[state.selectedPart] = a.tracks[state.selectedPart] || []);
    track.push({ t, rot: p.currentRot != null ? p.currentRot : (p.restRot || 0) });
    track.sort((x, y) => x.t - y.t);
    renderKeyframes();
  });
}

// ----- Transport / time -----
let lastTs = 0;
function tick(ts) {
  if (!lastTs) lastTs = ts;
  const dt = Math.min(0.05, (ts - lastTs) / 1000);
  lastTs = ts;
  if (state.playing && state.inst) {
    Skeleton2D.Update(state.inst, dt);
    const a = state.anims[state.currentAnim];
    if (a) {
      $('time-slider').value = state.inst.phase;
      $('time-display').textContent = state.inst.phase.toFixed(2) + ' / ' + a.duration.toFixed(2) + ' s';
    }
    redraw();
  }
  requestAnimationFrame(tick);
}

function bindTransport() {
  $('btn-play').addEventListener('click', () => { state.playing = true; setStatus('playing'); });
  $('btn-pause').addEventListener('click', () => { state.playing = false; setStatus('paused'); });
  $('btn-restart').addEventListener('click', () => {
    if (!state.inst) return;
    const a = state.anims[state.currentAnim];
    if (a) Skeleton2D.Play(state.inst, a, { restart: true, loop: a.loop !== false });
    redraw();
  });
  $('btn-facing').addEventListener('click', () => {
    state.facing = -state.facing;
    $('btn-facing').textContent = state.facing > 0 ? '→' : '←';
    redraw();
  });
  $('view-scale').addEventListener('input', () => {
    state.viewScale = +$('view-scale').value;
    redraw();
  });
  $('time-slider').addEventListener('input', () => {
    if (!state.inst) return;
    state.playing = false;
    state.inst.phase = +$('time-slider').value;
    const a = state.anims[state.currentAnim];
    if (a) {
      // Re-apply by stepping update with dt=0 (applyAnimation hidden, use Update with 0 won't refresh)
      // Easiest: directly call internal apply by Play->set phase->fake tick:
      state.inst.animation = a;
      // call Update with 0 to invoke applyAnimation
      Skeleton2D.Update(state.inst, 0);
      $('time-display').textContent = state.inst.phase.toFixed(2) + ' / ' + a.duration.toFixed(2) + ' s';
      redraw();
      renderKeyframes(); // (in case user is mid-edit)
    }
  });
}

// ----- Canvas interaction (drag anchor / attachAt) -----
function bindCanvasDrag() {
  canvas.addEventListener('mousedown', (e) => {
    const rect = canvas.getBoundingClientRect();
    const cx = e.clientX - rect.left, cy = e.clientY - rect.top;
    if (e.shiftKey) {
      state.drag = { kind: 'pan', startX: cx, startY: cy, baseX: state.origin.x, baseY: state.origin.y };
      return;
    }
    if (!state.selectedPart) return;
    if (e.altKey) {
      // attachAt: drag in parent space
      state.drag = { kind: 'attachAt', startX: cx, startY: cy };
      const p = state.skeleton.parts[state.selectedPart];
      state.drag.baseX = p.attachAt[0]; state.drag.baseY = p.attachAt[1];
    } else {
      state.drag = { kind: 'anchor', startX: cx, startY: cy };
      const p = state.skeleton.parts[state.selectedPart];
      state.drag.baseX = p.anchor[0]; state.drag.baseY = p.anchor[1];
    }
  });
  canvas.addEventListener('mousemove', (e) => {
    if (!state.drag) return;
    const rect = canvas.getBoundingClientRect();
    const cx = e.clientX - rect.left, cy = e.clientY - rect.top;
    const dx = (cx - state.drag.startX) / state.viewScale * (state.facing > 0 ? 1 : -1);
    const dy = (cy - state.drag.startY) / state.viewScale;
    if (state.drag.kind === 'pan') {
      state.origin.x = state.drag.baseX + (cx - state.drag.startX);
      state.origin.y = state.drag.baseY + (cy - state.drag.startY);
    } else if (state.drag.kind === 'anchor') {
      const p = state.skeleton.parts[state.selectedPart];
      p.anchor[0] = Math.round((state.drag.baseX - dx) * 10) / 10;
      p.anchor[1] = Math.round((state.drag.baseY - dy) * 10) / 10;
      renderPropsPanel();
    } else if (state.drag.kind === 'attachAt') {
      const p = state.skeleton.parts[state.selectedPart];
      p.attachAt[0] = Math.round((state.drag.baseX + dx) * 10) / 10;
      p.attachAt[1] = Math.round((state.drag.baseY + dy) * 10) / 10;
      renderPropsPanel();
    }
    rebuildInstance();
    if (state.anims[state.currentAnim]) Skeleton2D.Update(state.inst, 0);
    redraw();
  });
  window.addEventListener('mouseup', () => { state.drag = null; });
}

// ----- Drag-drop PNG anywhere -----
function bindGlobalDrop() {
  const overlay = $('drop-overlay');
  ['dragenter','dragover'].forEach(t => window.addEventListener(t, (e) => { e.preventDefault(); overlay.classList.add('active'); }));
  ['dragleave','drop'].forEach(t => window.addEventListener(t, (e) => { if (e.type === 'drop' || e.target === document) overlay.classList.remove('active'); }));
  window.addEventListener('drop', async (e) => {
    e.preventDefault();
    overlay.classList.remove('active');
    const files = Array.from(e.dataTransfer.files || []);
    for (const file of files) {
      if (file.type === 'application/json' || file.name.endsWith('.json')) {
        const text = await readFileAsText(file);
        try {
          const j = JSON.parse(text);
          if (j.parts) loadSkeleton(j);
          else loadAnims(j);
        } catch (err) { setStatus('invalid JSON: ' + err.message); }
      } else if (file.type.startsWith('image/')) {
        if (!state.selectedPart) { setStatus('select a part first to assign image'); continue; }
        const dataURL = await readFileAsDataURL(file);
        state.skeleton.parts[state.selectedPart].png = file.name;
        loadImageDataURL(file.name, dataURL, true);
        renderPropsPanel(); renderPartsList();
      }
    }
  });
}

// ----- File I/O -----
function loadSkeleton(json) {
  state.skeleton = json;
  // ensure all parts have arrays for anchor/attachAt
  for (const n in json.parts) {
    const p = json.parts[n];
    if (!Array.isArray(p.anchor))   p.anchor   = [p.anchor && p.anchor.x || 0, p.anchor && p.anchor.y || 0];
    if (!Array.isArray(p.attachAt)) p.attachAt = [p.attachAt && p.attachAt.x || 0, p.attachAt && p.attachAt.y || 0];
  }
  state.selectedPart = state.skeleton.root || Object.keys(json.parts)[0] || null;
  rebuildInstance();
  renderPartsList(); renderPropsPanel(); renderKeyframes(); redraw();
  setStatus('loaded skeleton: ' + (json.id || '(no id)'));
}

function loadAnims(json) {
  state.anims = json;
  if (!state.anims[state.currentAnim]) state.currentAnim = Object.keys(json)[0] || 'idle';
  rebuildInstance();
  renderAnimSelect(); renderKeyframes(); redraw();
  setStatus('loaded animations: ' + Object.keys(json).join(', '));
}

function downloadFile(name, content, type) {
  const blob = new Blob([content], { type: type || 'text/plain' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = name;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { document.body.removeChild(a); URL.revokeObjectURL(url); }, 100);
}

function bindFileButtons() {
  $('btn-load-example').addEventListener('click', async () => {
    try {
      // Try sibling path first (when served from repo root), then fall back to
      // parent path (when served from inside editor/).
      const tryFetch = async (paths) => {
        for (const p of paths) {
          try { const r = await fetch(p); if (r.ok) return r; } catch (e) {}
        }
        throw new Error('all candidate paths failed');
      };
      const [skelR, animR] = await Promise.all([
        tryFetch(['/examples/humanoid/skeleton.json',  'examples/humanoid/skeleton.json',  '../examples/humanoid/skeleton.json']),
        tryFetch(['/examples/humanoid/animations.json','examples/humanoid/animations.json','../examples/humanoid/animations.json']),
      ]);
      loadSkeleton(await skelR.json());
      loadAnims(await animR.json());
    } catch (err) {
      setStatus('cannot fetch examples (use http server, not file://): ' + err.message);
      // fallback: empty skel + empty anims
      loadSkeleton(newEmptySkeleton());
      loadAnims(EMPTY_ANIMS);
    }
  });
  $('file-skeleton').addEventListener('change', async (e) => {
    const f = e.target.files[0]; if (!f) return;
    loadSkeleton(JSON.parse(await readFileAsText(f)));
    e.target.value = '';
  });
  $('file-anims').addEventListener('change', async (e) => {
    const f = e.target.files[0]; if (!f) return;
    loadAnims(JSON.parse(await readFileAsText(f)));
    e.target.value = '';
  });
  $('btn-export-skel-json').addEventListener('click', () => {
    if (!state.skeleton) return;
    downloadFile((state.skeleton.id || 'skeleton') + '.json', JSON.stringify(state.skeleton, null, 2), 'application/json');
    downloadFile((state.skeleton.id || 'skeleton') + '.lua', LuaExport.skeleton(state.skeleton), 'text/x-lua');
  });
  $('btn-export-anims-json').addEventListener('click', () => {
    downloadFile('animations.json', JSON.stringify(state.anims, null, 2), 'application/json');
    downloadFile('animations.lua',  LuaExport.animations(state.anims), 'text/x-lua');
  });
}

// ----- Tab UI -----
function bindTabs() {
  document.querySelectorAll('.tab-bar button').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-bar button').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      document.querySelector(`.tab-panel[data-tab="${btn.dataset.tab}"]`).classList.add('active');
    });
  });
}

// ----- Add/del part -----
function bindPartActions() {
  $('btn-add-part').addEventListener('click', () => {
    const name = $('new-part-name').value.trim(); if (!name) return;
    if (state.skeleton.parts[name]) { setStatus('part already exists'); return; }
    state.skeleton.parts[name] = {
      parent: state.selectedPart,
      w: 30, h: 30,
      anchor: [15, 15], attachAt: [0, 0],
      restRot: 0, z: 0, png: null,
      placeholderColor: [180, 180, 180, 220],
    };
    $('new-part-name').value = '';
    selectPart(name);
    rebuildInstance();
  });
  $('btn-del-part').addEventListener('click', () => {
    if (!state.selectedPart) return;
    const name = state.selectedPart;
    if (state.skeleton.root === name) { setStatus('cannot delete root'); return; }
    delete state.skeleton.parts[name];
    // re-parent children to grandparent
    for (const n in state.skeleton.parts) if (state.skeleton.parts[n].parent === name) state.skeleton.parts[n].parent = null;
    state.selectedPart = state.skeleton.root || Object.keys(state.skeleton.parts)[0] || null;
    rebuildInstance(); renderPartsList(); renderPropsPanel(); redraw();
  });
}

// ----- Init -----
function resizeCanvas() {
  const host = canvas.parentElement;
  canvas.width = host.clientWidth;
  canvas.height = host.clientHeight;
  state.origin.x = canvas.width / 2;
  state.origin.y = canvas.height * 0.7;
  redraw();
}

function init() {
  canvas = $('canvas');
  ctx = canvas.getContext('2d');
  window.addEventListener('resize', resizeCanvas);
  state.skeleton = newEmptySkeleton();
  state.anims = JSON.parse(JSON.stringify(EMPTY_ANIMS));
  state.currentAnim = 'idle';
  state.selectedPart = 'torso';

  bindFileButtons();
  bindPropFields();
  bindAnimUI();
  bindTransport();
  bindCanvasDrag();
  bindGlobalDrop();
  bindTabs();
  bindPartActions();

  rebuildInstance();
  renderPartsList(); renderPropsPanel(); renderAnimSelect(); renderKeyframes();
  resizeCanvas();
  requestAnimationFrame(tick);
  setStatus('ready — click "Load humanoid example" to start');
}

document.addEventListener('DOMContentLoaded', init);
