# Gradient infill — a PrusaSlicer slicing plugin

A `slicing.fill_planner` plugin for PrusaSlicer 3.x. It **packs the sparse infill lines closer
together near the walls and lets them open out towards the middle**, so the material goes where
the part is stiffest.

## The problem

`fill_density` is one number for the whole object, so the slicer spreads the same lattice
through the middle of a part as it does just behind the wall.

That is not where the material earns its keep. A part in bending carries the load in the
material furthest from its neutral axis — in a printed part, the wall and the infill right
behind it. The lattice in the middle is mostly holding the two halves apart, and it costs the
same per millimetre as the lattice that is doing the work.

## What it does

Inside a band along the edge the lines are packed `edge` times closer than `fill_density` asks
for; past `taper` beyond it they are at `core` times. Set the two so they roughly cancel and the
part costs about what it did, with the material somewhere more useful. Set only `edge` and it
costs more and is stiffer.

### Measured

A 20 × 20 × 16 mm block at 15 %, defaults otherwise. Line spacing across the region, edge to
edge:

| | spacings across the layer |
|---|---|
| stock `rectilinear` | 2.71 2.71 2.71 2.71 2.71 2.71 2.71 2.71 |
| gradient | **1.36 1.36 1.37** 1.86 3.57 **5.43 5.43** 1.36 1.36 |

1.36 mm is 2.714/2, the `edge` of 2.0. 5.43 mm is 2.714/0.5, the `core` of 0.5. The 1.86 and
3.57 in between are the taper. It does what it says.

### What it measures, and the setting that follows from it

The distance it uses is **to the edge along the line normal** — how far a line is from the first
and last line of that layer — not the true distance to the wall, which would mean a distance
transform of the contour on every surface of every layer.

**So point the lines at the walls you care about.** On that same block:

| | material | where the dense band lands |
|---|---|---|
| stock | 893 mm³ | — |
| gradient, `angle = 45` | 617 mm³ (−31 %) | the **corners** |
| gradient, `angle = 0` | 1082 mm³ (+21 %) | the **sides** |

At 45° to a square the "first and last line of the layer" are at opposite corners, so that is
where the material goes — and because the corner lines are short, the part ends up *cheaper*
rather than stiffer. At 0° the lines run parallel to two of the walls and the dense band lands
on them, which is what you want and what the +21 % is buying.

Since the pattern turns 90° each layer, whatever `angle` you choose gets both of its pairs of
edges over any two layers. On a long thin region — a beam, the case this is for — the measure is
exactly right whichever way you point it.

## Settings

`settings.lua` next to the Lua source. Edit and slice again; no restart, no rescan. It is read
inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and the
defaults apply.

| setting | default | what it does |
|---|---|---|
| `band` | `4.0` | How far in from the edge the dense band reaches, in mm. `0` turns the plugin off. |
| `edge` | `2.0` | How much closer the lines run inside the band, as a multiple of the density. |
| `core` | `0.5` | How much of the density is kept in the middle, as a multiple. |
| `taper` | `4.0` | How far the change from `edge` to `core` is spread over, in mm. `0` is a hard step. |
| `angle` / `angle_step` | `45` / `90` | Direction of the lines and how much it turns each layer — the stock rectilinear alternation, so the gradient is the only thing that changes. |
| `roles` | `InternalInfill` | Sparse infill only: a solid or top surface has to stay solid, and a bridge has to keep the direction the slicer chose. |
| `skip_first_layers` | `0` | Leave this many layers at the bed alone. |

Lines are never packed closer than one bead apart whatever the settings say — closer than that
is not infill any more, it is solid, and the flow was not computed for it.

## Use it with `rectilinear`, not `grid`

Same reason as [`cross-hatch`](../cross-hatch/): this lays one family of lines per layer, and
`grid`'s spacing is worked out for two families crossing on every layer.

## The hook it needs

`slicing.fill_planner`. Requires the fork:
<https://github.com/dzwiedziu-nkg/PrusaSlicer> at `529aba88b2` or later, with the hook at API
1.2.0 — that is the version which tells a planner the **density**, without which it cannot know
how far apart a sparse pattern's lines belong.

## Running it

```bash
ln -sfn "$PWD/com.github.dzwiedziu-nkg.gradient-infill" \
    ~/.config/PrusaSlicer3-dev/lua/
```

## License

AGPL-3.0-only. See `LICENSE`.
