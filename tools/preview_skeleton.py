#!/usr/bin/env python3
"""
preview_skeleton.py — 用 anchor/attachAt 把拆好的部件重组成一张预览图

用法:
    python3 tools/preview_skeleton.py <skeleton.json> [--out preview.png] [--scale 1.0]

输出一张和源图同区域大小的 PNG，按部件 z 序合成。
没有施加任何动画，只是 rest pose 重组。如果重组后看着像原图，说明:
  - 每个 part 的 anchor 选对了关节点
  - 每个 part 的 attachAt 在父部件局部坐标里定位正确
  - 父子关系没接错

通常先运行 split_character.py 拆图，再运行本工具校验。
"""
import argparse
import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.stderr.write("This tool requires Pillow:  pip install Pillow\n")
    sys.exit(2)


def world_pos(parts, name, cache):
    """递归算出 part 的世界 hinge 位置 (px, py)，不做旋转。"""
    if name in cache:
        return cache[name]
    p = parts[name]
    if p.get("parent"):
        ppx, ppy = world_pos(parts, p["parent"], cache)
        pa = parts[p["parent"]]["anchor"]
        # attachAt 是在父图像局部坐标里的位置；减去父 anchor 得到相对父 hinge 的偏移
        x = ppx + p["attachAt"][0] - pa[0]
        y = ppy + p["attachAt"][1] - pa[1]
    else:
        x, y = p["attachAt"][0], p["attachAt"][1]
    cache[name] = (x, y)
    return x, y


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("skeleton", help="path to skeleton.json")
    ap.add_argument("--out", default=None)
    ap.add_argument("--canvas", type=int, nargs=2, default=[300, 600],
                    help="canvas size (w, h) in pixels")
    ap.add_argument("--origin", type=int, nargs=2, default=None,
                    help="root hinge position on canvas (defaults to center-bottom)")
    args = ap.parse_args()

    skel_path = Path(args.skeleton).resolve()
    skel_dir = skel_path.parent
    skel = json.loads(skel_path.read_text(encoding="utf-8"))
    parts = skel["parts"]

    cw, ch = args.canvas
    if args.origin:
        ox, oy = args.origin
    else:
        ox, oy = cw // 2, ch - 80   # near bottom-center

    canvas = Image.new("RGBA", (cw, ch), (40, 50, 70, 255))

    # sort by z (low → high); equal z keeps insertion order
    ordered = sorted(parts.items(), key=lambda kv: kv[1].get("z", 0))

    cache = {}
    for name, p in ordered:
        png_rel = p.get("png")
        if not png_rel:
            print(f"[skip] {name}: no png field")
            continue
        # png path is relative to the skeleton.json dir's parent (one up: <id>/...)
        # but split_character.py wrote `<id>/parts/<name>.png` and skeleton.json
        # lives at <out_dir>/skeleton.json where out_dir basename == id; so resolve
        # png as <skel_dir.parent>/<png_rel>
        img_path = (skel_dir.parent / png_rel).resolve()
        if not img_path.exists():
            # fallback: maybe png is just relative to skel_dir
            img_path = (skel_dir / Path(png_rel).name).resolve()
            if not img_path.exists():
                print(f"[warn] image not found for {name}: {png_rel}")
                continue
        img = Image.open(img_path).convert("RGBA")

        wx, wy = world_pos(parts, name, cache)
        # paste so that part's anchor sits at (ox+wx, oy+wy)
        ax, ay = p["anchor"]
        paste_x = int(ox + wx - ax)
        paste_y = int(oy + wy - ay)
        canvas.alpha_composite(img, (paste_x, paste_y))
        print(f"[draw] {name:<10} world=({wx:>4},{wy:>4})  anchor=({ax},{ay})  paste=({paste_x},{paste_y})  z={p.get('z',0)}")

    out_path = Path(args.out) if args.out else (skel_dir / "preview.png")
    canvas.save(out_path, "PNG")
    print(f"[out ] {out_path}")


if __name__ == "__main__":
    main()
