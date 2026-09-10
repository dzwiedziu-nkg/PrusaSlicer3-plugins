#!/usr/bin/env python3
# Copyright (c) 2026 dzwiedziu-nkg
# SPDX-License-Identifier: AGPL-3.0-only
"""Measure travel (non-extruding) moves in a G-code file. Independent of the
slicer's own accounting: it only reads the emitted G0/G1 moves."""
import re, sys, math

def analyze(path):
    x = y = z = None
    travel = extrude = 0.0
    travel_moves = 0
    per_z = {}
    abs_e = True
    last_e = 0.0
    num = re.compile(r'([XYZEF])(-?\d*\.?\d+)')
    for line in open(path, errors="ignore"):
        line = line.split(';', 1)[0].strip()
        if not line:
            continue
        if line.startswith('M83'): abs_e = False; continue
        if line.startswith('M82'): abs_e = True;  continue
        if line.startswith('G92'):
            for a, v in num.findall(line):
                if a == 'E': last_e = float(v)
            continue
        if not (line.startswith('G0 ') or line.startswith('G1 ')):
            continue
        nx, ny, nz, e = x, y, z, None
        for a, v in num.findall(line):
            v = float(v)
            if   a == 'X': nx = v
            elif a == 'Y': ny = v
            elif a == 'Z': nz = v
            elif a == 'E': e = v
        if abs_e and e is not None:
            de, last_e = e - last_e, e
        else:
            de = e if e is not None else 0.0
        if None not in (x, y, nx, ny):
            d = math.hypot(nx - x, ny - y)
            if de > 0:
                extrude += d
            elif d > 0:
                travel += d
                travel_moves += 1
                per_z[z] = per_z.get(z, 0.0) + d
        x, y, z = nx, ny, nz
    return travel, extrude, travel_moves, per_z

if __name__ == "__main__":
    for p in sys.argv[1:]:
        t, e, n, _ = analyze(p)
        print(f"{p}\n  travel   = {t:10.1f} mm  ({n} moves)\n  extruded = {e:10.1f} mm")
