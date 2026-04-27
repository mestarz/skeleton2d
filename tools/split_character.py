#!/usr/bin/env python3
"""
split_character.py — 按 bbox 配置把整张角色立绘拆成 skeleton2d 部件

用法:
    python3 tools/split_character.py <config.json>

config.json 形式 (相对路径基于 config 文件所在目录):
    {
      "id": "police_m",
      "source": "../assets/.../frame_01.png",   # 整张立绘
      "out_dir": "../examples/.../police_m",     # 输出根
      "out_textures_subdir": "parts",            # PNG 输出子目录
      "root": "torso",
      "parts": {
        "torso": {
          "bbox": [x, y, w, h],         # 在源图上的裁剪框（像素，左上原点）
          "anchor": [ax, ay],           # 部件局部坐标里关节 hinge 位置
          "attachAt": [cx, cy],         # 在父部件局部坐标里，本部件应该 hinge 的位置
          "z": 0,
          "parent": null
        },
        ...
      }
    }
"""
import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.stderr.write("This tool requires Pillow:  pip install Pillow\n")
    sys.exit(2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config")
    ap.add_argument("--source")
    ap.add_argument("--out")
    args = ap.parse_args()

    cfg_path = Path(args.config).resolve()
    cfg_dir = cfg_path.parent
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))

    src_path = Path(args.source) if args.source else (cfg_dir / cfg["source"]).resolve()
    out_dir = Path(args.out) if args.out else (cfg_dir / cfg["out_dir"]).resolve()
    tex_subdir = cfg.get("out_textures_subdir", "parts")

    if not src_path.exists():
        sys.exit(f"source PNG not found: {src_path}")

    src = Image.open(src_path).convert("RGBA")
    sw, sh = src.size
    print(f"[src ] {src_path}  ({sw}x{sh})")

    out_tex = out_dir / tex_subdir
    out_tex.mkdir(parents=True, exist_ok=True)

    skel_parts = {}
    for name, p in cfg["parts"].items():
        x, y, w, h = p["bbox"]
        if x < 0 or y < 0 or x + w > sw or y + h > sh:
            sys.exit(f"part '{name}' bbox out of source bounds: {p['bbox']}")

        crop = src.crop((x, y, x + w, y + h))
        out_png = out_tex / f"{name}.png"
        crop.save(out_png, "PNG")
        alpha = crop.split()[-1]
        nz = sum(1 for px in alpha.getdata() if px > 0)
        print(f"[part] {name:<10} bbox={p['bbox']}  size={w}x{h}  opaque_px={nz}")

        skel_parts[name] = {
            "parent":   p.get("parent"),
            "w":        w,
            "h":        h,
            "anchor":   p["anchor"],
            "attachAt": p["attachAt"],
            "restRot":  p.get("restRot", 0),
            "z":        p.get("z", 0),
            "png":      f"{cfg['id']}/{tex_subdir}/{name}.png",
        }

    skeleton = {
        "id":      cfg["id"],
        "version": 1,
        "root":    cfg["root"],
        "parts":   skel_parts,
    }
    skel_json = out_dir / "skeleton.json"
    skel_json.write_text(
        json.dumps(skeleton, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"[out ] {skel_json}")
    print(f"[out ] {out_tex}/  ({len(skel_parts)} files)")


if __name__ == "__main__":
    main()
