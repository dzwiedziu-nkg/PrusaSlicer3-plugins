#!/usr/bin/env python3
# Copyright (c) 2026 dzwiedziu-nkg
# SPDX-License-Identifier: AGPL-3.0-only
"""Per-island cooling time and travel-hop metrics, read straight from the G-code.

The test model is a row of 15 pillars 20 mm apart, so an extrusion can be
assigned to an island by its X coordinate. For every island we measure the gap
between finishing it on one layer and starting it again on the next -- the time
it actually has to cool -- plus the length of the individual travel hops.
"""
import re, sys, math
from collections import defaultdict

NUM = re.compile(r'([XYZEF])(-?\d*\.?\d+)')
PILLAR_X0 = 40.0        # centre of the first pillar, model centred at 180,180
PILLAR_STEP = 20.0
PILLAR_COUNT = 15
PILLAR_HALF = 7.0       # 10 mm wide plus perimeter margin


def island_of(x):
    if x is None:
        return None
    i = round((x - PILLAR_X0) / PILLAR_STEP)
    if 0 <= i < PILLAR_COUNT and abs(x - (PILLAR_X0 + i * PILLAR_STEP)) <= PILLAR_HALF:
        return i
    return None


def analyze(path, z_min=10.2):
    x = y = z = None
    f = 1200.0
    t = 0.0
    abs_e = True
    last_e = 0.0
    # island -> list of (first_touch_time, last_touch_time) per layer
    spans = defaultdict(list)
    cur = {}
    layer_z = 0.0
    hops = []           # travel move lengths between islands
    prev_island = None

    def flush():
        for isl, (t0, t1) in cur.items():
            spans[isl].append((t0, t1))
        cur.clear()

    for raw in open(path, errors='ignore'):
        if 'AFTER_LAYER_CHANGE' in raw:
            flush()
            continue
        if raw.startswith(';Z:'):
            layer_z = float(raw[3:])
            continue
        s = raw.split(';', 1)[0].strip()
        if not s:
            continue
        if s.startswith('M83'):
            abs_e = False; continue
        if s.startswith('M82'):
            abs_e = True; continue
        if s.startswith('G92'):
            for a, v in NUM.findall(s):
                if a == 'E':
                    last_e = float(v)
            continue
        if not (s.startswith('G0 ') or s.startswith('G1 ')):
            continue
        nx, ny, nz, e = x, y, z, None
        for a, v in NUM.findall(s):
            v = float(v)
            if a == 'X': nx = v
            elif a == 'Y': ny = v
            elif a == 'Z': nz = v
            elif a == 'E': e = v
            elif a == 'F': f = v
        if abs_e and e is not None:
            de, last_e = e - last_e, e
        else:
            de = e if e is not None else 0.0
        d = 0.0
        if None not in (x, y, nx, ny):
            d = math.hypot(nx - x, ny - y)
        if d == 0 and nz is not None and z is not None:
            d = abs(nz - z)
        if d > 0 and f > 0:
            t += d / (f / 60.0)
        if de > 0 and layer_z >= z_min:
            isl = island_of(nx)
            if isl is not None:
                if isl not in cur:
                    cur[isl] = (t, t)
                else:
                    cur[isl] = (cur[isl][0], t)
                if prev_island is not None and prev_island != isl:
                    hops.append(abs(nx - (PILLAR_X0 + prev_island * PILLAR_STEP)))
                prev_island = isl
        x, y, z = nx, ny, nz
    flush()
    return spans, hops


def report(path):
    spans, hops = analyze(path)
    gaps = []
    per_island_min = {}
    for isl, visits in spans.items():
        if len(visits) < 2:
            continue
        g = [visits[i + 1][0] - visits[i][1] for i in range(len(visits) - 1)]
        gaps += g
        per_island_min[isl] = min(g)
    print(f"{path}")
    if not gaps:
        print("  no island revisits found")
        return
    gaps.sort()
    print(f"  cooling gap between revisits of the same island:")
    print(f"    min={min(gaps):6.2f}s  p05={gaps[len(gaps)//20]:6.2f}s  "
          f"median={gaps[len(gaps)//2]:6.2f}s  max={max(gaps):6.2f}s   (n={len(gaps)})")
    worst = sorted(per_island_min.items(), key=lambda kv: kv[1])[:3]
    print(f"    worst islands (index: min gap): " +
          ", ".join(f"{i}: {v:.2f}s" for i, v in worst))
    if hops:
        hops.sort()
        print(f"  inter-island travel hops: max={max(hops):7.1f}mm  "
              f"p95={hops[int(len(hops)*0.95)]:7.1f}mm  median={hops[len(hops)//2]:6.1f}mm  (n={len(hops)})")


if __name__ == '__main__':
    for p in sys.argv[1:]:
        report(p)
