#!/usr/bin/env python3
"""Group a G-code file into extrusion runs: maximal sequences of extruding moves
not interrupted by a travel. Reports length distribution per ;TYPE: label."""
import re, sys, math
from collections import defaultdict

NUM = re.compile(r'([XYZEF])(-?\d*\.?\d+)')


def runs(path):
    x = y = z = None
    abs_e = True
    last_e = 0.0
    layer = 0
    kind = '?'
    cur_len = 0.0
    cur_start = None
    out = []          # (layer, z, kind, length, start_xy, end_xy)
    prev_xy = None

    def close(end_xy):
        nonlocal cur_len, cur_start
        if cur_start is not None and cur_len > 0:
            out.append((layer, z, kind, cur_len, cur_start, end_xy))
        cur_len = 0.0
        cur_start = None

    for raw in open(path, errors='ignore'):
        s = raw.strip()
        if s.startswith(';TYPE:'):
            close(prev_xy)
            kind = s[6:].strip()
            continue
        if s.startswith(';LAYER_CHANGE') or 'AFTER_LAYER_CHANGE' in s:
            close(prev_xy)
            layer += 1
            continue
        code = s.split(';', 1)[0].strip()
        if not code:
            continue
        if code.startswith('M83'): abs_e = False; continue
        if code.startswith('M82'): abs_e = True; continue
        if code.startswith('G92'):
            for a, v in NUM.findall(code):
                if a == 'E': last_e = float(v)
            continue
        if not (code.startswith('G0 ') or code.startswith('G1 ')):
            continue
        nx, ny, nz, e = x, y, z, None
        for a, v in NUM.findall(code):
            v = float(v)
            if a == 'X': nx = v
            elif a == 'Y': ny = v
            elif a == 'Z': nz = v
            elif a == 'E': e = v
        if abs_e and e is not None:
            de, last_e = e - last_e, e
        else:
            de = e if e is not None else 0.0
        d = 0.0
        if None not in (x, y, nx, ny):
            d = math.hypot(nx - x, ny - y)
        if de > 0 and d > 0:
            if cur_start is None:
                cur_start = (x, y)
            cur_len += d
        elif d > 0:
            close((x, y))
        x, y, z = nx, ny, nz
        prev_xy = (x, y)
    close(prev_xy)
    return out


if __name__ == '__main__':
    data = runs(sys.argv[1])
    thr = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
    by_kind = defaultdict(list)
    for layer, z, kind, ln, a, b in data:
        by_kind[kind].append(ln)
    print(f"{'type':22s} {'runs':>6s} {'total mm':>10s} {'median':>8s} "
          f"{'<%.1fmm' % thr:>8s} {'their mm':>9s}")
    for kind, lens in sorted(by_kind.items(), key=lambda kv: -len(kv[1])):
        lens_s = sorted(lens)
        short = [l for l in lens if l < thr]
        print(f"{kind:22s} {len(lens):6d} {sum(lens):10.0f} {lens_s[len(lens_s)//2]:8.2f} "
              f"{len(short):8d} {sum(short):9.1f}")
    print()
    shorts = [(l, k, ln, a) for l, z, k, ln, a, b in data if ln < thr]
    if shorts:
        layers = sorted(set(s[0] for s in shorts))
        print(f"short runs (<{thr}mm): {len(shorts)} on {len(layers)} layers, "
              f"layers {layers[0]}..{layers[-1]}")
        for l, k, ln, a in shorts[:8]:
            print(f"   layer {l:4d}  {k:18s} {ln:6.2f}mm at ({a[0]:.2f}, {a[1]:.2f})")
