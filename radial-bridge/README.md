# Radial bridges — a PrusaSlicer slicing plugin

A `slicing.fill_planner` plugin for PrusaSlicer 3.x. It lays a bridge over an annular gap
out as spokes running from the inner island to the surrounding wall, instead of parallel
lines running across the whole opening.

## The problem

The stock fill patterns run straight lines in a single direction chosen per surface. Over
a ring-shaped gap — a boss inside a wall, a hub inside a rim — that direction is wrong for
most of the area. The lines that pass closest to the inner island become long chords
spanning the entire opening, while the gap they actually have to cross is only as wide as
the ring.

On the test model, a 20 mm boss inside a 32 mm bore, the widest gap to cross is 6 mm but
the longest bridge line is **27.7 mm**.

![Stock bridge over an annular gap](doc/normal_bridge.png)

Every line runs the same way regardless of where the anchors are. The ones passing closest
to the hub are the longest in the layer, and they are unsupported over most of their
length; the ones out at the sides are short only by accident of the geometry.

## What this does

Spokes. Every line runs outwards from the inner island to the outer wall, so no line is
longer than the gap it crosses, whatever the diameters are.

Two things make it practical rather than merely geometric:

- **The spoke count is matched to the middle radius.** Spokes fan out as they go, so
  matching the line spacing at the inner edge leaves the outer edge sparse, and matching
  it at the outer edge crowds the inner one. Matching it half way puts the average where
  it belongs, and the material laid down comes out within a few percent of the pattern it
  replaces.
- **The spokes are walked as one continuous path**, out along one and back along the next.
  Emitted as separate lines they cost 2.6 m of extra travel on one layer; joined up they
  cost none.

![Radial bridge over the same gap](doc/radial_bridge.png)

The hairpin turns at both edges are the continuous path: the head runs out along one spoke,
turns on the anchor, and comes back along the next. The spokes are visibly tighter at the
inner edge than the outer one, which is the fan spreading as it goes; the count is chosen so
that the average lands on the line spacing.

The plugin claims only a surface it can improve: a bridge whose region has a hole in it.
Everything else is declined and the slicer fills it exactly as before.

## Measurements

`radial_bridge.stl`, Prusa CORE One 0.4 HF, 0.20 mm SPEED, layer 31 — the layer that
closes the ring.

| | stock | radial |
|---|---|---|
| longest bridge line | 27.69 mm | **7.69 mm** |
| bridge extrusion | 1 519.4 mm | 1 613.7 mm |
| travel on that layer | 137.6 mm | **130.4 mm** |
| travel moves on that layer | 17 | 17 |

The longest unsupported run drops by 3.6×, for 6 % more material and slightly *less*
travel than the stock pattern.

Two intermediate designs are worth recording as the reasons for the final one: separate
spokes matched to the inner radius gave the same 7.7 mm lines but 2 593 mm of travel and
29 % less material, and adding spokes by doubling the count where they spread too far
gave 5 137 mm of travel and 42 % *more* material than stock.

On a model with no annular bridge — a garage with ordinary walls — travel and extrusion
come out identical to a slice with the plugin removed.

## Settings

`settings.lua` sits next to the plugin. Edit it and re-slice — no restart, no rescan.

| key | default | meaning |
|---|---|---|
| `filtered_roles` | `BridgeInfill` | Roles the planner may take over. |
| `min_hole_radius` | `1.0` | Skip surfaces whose hole is smaller than this, in mm. |
| `density` | `1.0` | Multiplies the spoke spacing. Above 1.0 uses less material. |
| `max_spokes` | `2000` | Refuse a surface needing more spokes than this. |

## Requirements

A PrusaSlicer build providing the `slicing.fill_planner` plugin API. See
`doc/Plugin_API.md` in the slicer sources for the contract.

## Installing

```bash
ln -s "$PWD/com.github.dzwiedziu-nkg.radial-bridge" ~/.config/PrusaSlicer/lua/
```

The directory name has to match the `id` in `manifest.json`. The plugin has no menu entry.
The log names it at the start of every slice and reports what it took over at the end:

```
[info] Fill planner plugin in use: com.github.dzwiedziu-nkg.radial-bridge.radial_bridge
[info] Fill planner plugin ... laid out 1 of 77 surfaces
```

## Limitations

- The spokes radiate from the centroid of the largest hole. A surface whose hole is far
  from round, or which has several holes of similar size, will not come out as a tidy fan.
- Spacing is uniform in angle, not in area: it is tighter than nominal at the inner edge
  and looser at the outer one, by the ratio of the two radii. On a very wide ring that
  difference becomes visible.
- It does not consider where the anchors actually are; it assumes the ring is anchored on
  both edges, which is what makes a bridge over an annular gap a good case for it and a
  bridge over a slot a poor one.
- The slicer calls this hook from its parallel infill stage, and the Lua state behind it
  is single threaded, so a plugin claiming every surface of a large print would serialize
  that stage. This one claims very few.

## License

AGPL-3.0-only, the same licence as PrusaSlicer itself. The full text is in `LICENSE`.
