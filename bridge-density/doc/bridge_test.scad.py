#!/usr/bin/env python3
"""Writes the bridge test part: three through-tunnels of 10, 20 and 30 mm under a 2 mm roof.

    python3 bridge_test.scad.py bridge_test.stl

Print it, turn it over and look into the tunnels. The underside of the bridge is the first
layer of the roof, and nothing is in the way of seeing it.
"""
import sys

SPANS = [10, 20, 30]   # tunnel widths, mm
DEPTH = 40.0           # how far the tunnels run, mm
WALL = 5.0             # wall between tunnels, mm
HEIGHT = 6.0           # tunnel height, mm
ROOF = 2.0             # roof over the tunnels, mm


def box(x0, y0, z0, x1, y1, z1):
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    quads = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
             (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    out = []
    for a, b, c, d in quads:
        out.append((v[a], v[b], v[c]))
        out.append((v[a], v[c], v[d]))
    return out


def main(path):
    tris = []
    x = 0.0
    for span in SPANS:
        # The walls overlap the roof by a layer so the two fuse into one solid.
        tris += box(x, 0, 0, x + WALL, DEPTH, HEIGHT + 0.2)
        x += WALL + span
    tris += box(x, 0, 0, x + WALL, DEPTH, HEIGHT + 0.2)
    width = x + WALL
    tris += box(0, 0, HEIGHT, width, DEPTH, HEIGHT + ROOF)

    with open(path, "w") as f:
        f.write("solid bridge_test\n")
        for tri in tris:
            f.write("facet normal 0 0 0\n outer loop\n")
            for p in tri:
                f.write("  vertex %.6f %.6f %.6f\n" % p)
            f.write(" endloop\nendfacet\n")
        f.write("endsolid bridge_test\n")
    print("%s: %.0f x %.0f x %.1f mm, tunnels %s mm, roof %.1f mm"
          % (path, width, DEPTH, HEIGHT + ROOF, "/".join(map(str, SPANS)), ROOF))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "bridge_test.stl")
