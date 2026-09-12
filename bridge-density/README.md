# Bridge density — a PrusaSlicer slicing plugin

A `slicing.fill_planner` plugin for PrusaSlicer 3.x. It **spaces bridge lines by the bead the
nozzle actually lays**, so adjacent strands touch and hold each other up instead of each hanging
alone.

## The problem, and it is one constant

A bridge line extruded into mid-air is a **cylinder** of roughly the nozzle diameter. It is not
the flattened discorectangle a line becomes when it is printed onto solid plastic, because there
is nothing under it to flatten against.

PrusaSlicer knows this — `Flow::mm3_per_mm()` uses the area of a circle for a bridge. But it then
spaces the lines with:

```c
#define BRIDGE_EXTRA_SPACING 0.05
float Flow::bridge_extrusion_spacing(float dmr) { return dmr + BRIDGE_EXTRA_SPACING; }
```

so every pair of neighbours is laid **0.05 mm apart on purpose**. Measured on a stock slice at a
0.4 nozzle:

| | |
|---|---|
| bead the nozzle lays | 0.406 mm |
| line spacing the slicer uses | 0.453 mm |
| **daylight between strands** | **0.047 mm — an eighth of a bead** |

The whole gap is that one constant. Each strand spans the opening alone, and a strand alone
sags.

## What it does

It lays the lines at the bead diameter instead — recovered as `spacing − extra_spacing`, since
that is exactly how the slicer built the number — or closer if you ask for overlap. The flow is
left alone, so each strand is the same strand; there is just less air between them.

| | bead | line spacing | result | line laid |
|---|---|---|---|---|
| stock | 0.406 mm | 0.453 mm | gap 0.047 mm | 4023 mm |
| `overlap = 0` | 0.402 mm | 0.400 mm | **touching** (1 % overlap) | 4636 mm (+15 %) |
| `overlap = 0.10` | 0.402 mm | 0.360 mm | **11 % overlap** | 5152 mm (+28 %) |

Bridge material goes 449.3 → 510.9 mm³ at `overlap = 0`, which is +13.7 % and matches the line
spacing exactly. **Nothing else in the print changes** — internal infill, solid infill, both
perimeter roles and top solid infill all come out identical to the thousandth.

The direction is the slicer's own `bridge_angle`. That choice is made from the shape of the
opening and the anchors available, and second-guessing it is not this plugin's business.

## What it is not

It is **not** [`radial-bridge`](../radial-bridge/), which turns the lines to run across the
short way over an annular gap. That one changes line *direction*; this one changes line
*spacing*, and they are answers to different problems. `radial-bridge` does end up denser than
nominal — but only at the inner edge of its fan, as a side effect of the geometry rather than as
a controlled setting, and it is *sparser* than stock at the outer edge:

| radial-bridge, measured | line spacing | vs a 0.374 mm bead |
|---|---|---|
| r = 11 mm | 0.346 mm | touching |
| r = 12.5 mm | 0.393 mm | gap 0.019 mm |
| r = 15.5 mm | 0.487 mm | gap 0.113 mm |

The spacing there is strictly proportional to radius, because the spoke count is matched to the
middle radius; `density` scales the whole profile rather than levelling it.

## Settings

`settings.lua` next to the Lua source. Edit and slice again; no restart, no rescan. It is read
inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and the
defaults apply.

| setting | default | what it does |
|---|---|---|
| `overlap` | `0.0` | How much of the bead adjacent strands share, 0 to 0.5. `0` puts them edge to edge, which is already the whole of the fix. `0.1` is what "bridge density above 100 %" means in practice. Past about 0.25 the strands lift off their neighbours. |
| `extra_spacing` | `0.05` | What the slicer adds between bridge lines on purpose — `BRIDGE_EXTRA_SPACING` in `Flow.hpp`. This is how the bead diameter is recovered. Setting it to `0` turns the plugin off, since then it would ask for exactly the stock spacing. |
| `match_stock_material` | `false` | Scale the flow so the surface gets the material it would have, spread over more strands. Off is the point — packing the lines closer *without* touching the flow is what makes the strands meet. Turn it on for a bridge already sagging from too much plastic. |
| `roles` | `BridgeInfill` | Bridges only: a bead laid on solid plastic is a flattened rectangle, not a cylinder. |
| `max_lines` | `4000` | Refuse a surface needing more lines than this. |

## Only one fill planner at a time

`bridge-density`, `radial-bridge`, `cross-hatch` and `gradient-infill` are all
`slicing.fill_planner`, and the slicer loads one plugin of each type. This one and
`radial-bridge` both want bridges and cannot be combined, which is a real loss — the fan would
benefit from level spacing more than a straight bridge does.

## The hook it needs

`slicing.fill_planner`. Requires the fork:
<https://github.com/dzwiedziu-nkg/PrusaSlicer> at `529aba88b2` or later, with the hook at API
1.2.0.

## Running it

```bash
ln -sfn "$PWD/com.github.dzwiedziu-nkg.bridge-density" \
    ~/.config/PrusaSlicer3-dev/lua/
```

## License

AGPL-3.0-only. See `LICENSE`.
