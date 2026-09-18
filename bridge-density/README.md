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
| bead the nozzle lays | 0.323 mm |
| line spacing the slicer uses | 0.409 mm |
| **daylight between strands** | **0.086 mm — a quarter of a bead** |

Each strand spans the opening alone, and a strand alone sags.

How much daylight depends on the opening: the slicer fits a whole number of lines across a
region, so the nominal `bead + 0.05` comes back adjusted, and the gap runs from a few hundredths
up to the full 0.05 mm. It is never zero.

## What it does

It lays the lines at the bead diameter instead — taken from the flow the slicer reports, so it
is exact — or closer if you ask for it. Two knobs, **the same two OrcaSlicer has**:

| | what it changes |
|---|---|
| `density` | how far apart the strands go, as a fraction of their own width |
| `flow_ratio` | how fat the strands are |

Measured on the test part at a 0.4 nozzle:

| | line spacing | bead | coverage |
|---|---|---|---|
| stock | 0.409 mm | 0.323 mm | 0.789 |
| `density = 1.00` | 0.322 mm | 0.323 mm | **1.002** — touching |
| `density = 1.14` | 0.282 mm | 0.323 mm | 1.145 |
| `density = 0.40` | 0.805 mm | 0.323 mm | 0.401 |
| `flow_ratio = 1.5` | 0.394 mm | 0.395 mm | 1.003 |

Coverage is bead ÷ spacing; 1.0 is exactly touching. `density` sets it directly.

### Converting from OrcaSlicer

Measured on four OrcaSlicer exports of this same part, its two settings are cleanly separable:
`bridge_density` changes **only** the spacing and `bridge_flow` **only** the strand.

| Orca | spacing | bead | coverage |
|---|---|---|---|
| `bd 100 %`, `bf 1.0` | 0.357 | 0.302 | 0.845 |
| `bd 114 %`, `bf 1.0` | 0.313 | 0.302 | 0.963 |
| `bd 40 %`, `bf 1.0` | 0.893 | 0.302 | 0.338 |
| `bd 100 %`, `bf 1.5` | 0.357 | 0.369 | 1.035 |

`spacing = 0.357 / bd` and `bead = 0.302 × √bf`, to three decimals in all four. So:

```
density    = 0.846 × orca_bridge_density × √(orca_bridge_flow)
flow_ratio = orca_bridge_flow × (orca_bead / our_bead)²
```

where 0.846 is `0.302 / 0.357`, Orca's coverage at 100 %. Note that Orca's **100 % does not mean
touching** — it is 15 % short of it, which is the whole reason this plugin exists.

Checked by slicing the same part both ways, with `flow_ratio = 0.874` to match Orca's thinner
strand (0.302 against this profile's 0.323):

| Orca | this plugin | our spacing | Orca's | our coverage | Orca's |
|---|---|---|---|---|---|
| `bd 40 %` | `density = 0.338` | 0.891 mm | 0.893 | 0.339 | 0.338 |
| `bd 100 %` | `density = 0.845` | 0.356 mm | 0.357 | 0.848 | 0.845 |
| `bd 114 %` | `density = 0.963` | 0.313 mm | 0.313 | 0.964 | 0.963 |

Spacing, bead and coverage all agree to the thousandth. Leave `flow_ratio` at 1.0 and you keep
this profile's own strand, which is fatter — same coverage, more plastic.

**The 0.846 is specific to that profile**, because Orca's "100 %" is a fraction of its own
nominal line spacing. `density` here is a fraction of the strand, which is absolute: the strand
either reaches its neighbour or it does not.

### Its own speed

PrusaSlicer has **one** `bridge_speed` and gives both kinds of bridge the same extrusion role,
so raising it because internal bridges crawl speeds up the external ones too. There is no
setting that separates them.

`speed` here does. Measured with `speed = 10`:

| | stock | with the plugin |
|---|---|---|
| external bridge, Z 6.2 | 50 mm/s | **10 mm/s** |
| internal bridge, Z 7.2 | 50 mm/s | 50 mm/s — untouched |

Set `bridge_speed` for the internal ones and put the external speed here.

### It walks them, it does not drop them

The lines are turned round at the ends into one continuous path, the way the stock filler does
and the way OrcaSlicer does — a line, a short link, a line back. On the test part that is **4
continuous paths and 95 mm of travel**, against 4 and 105 mm for stock. An earlier version
handed back separate lines and left the slicer to clip them: 528 paths and 540 mm of travel.

The turn has to start a hair inside the boundary. A chord that starts exactly on it is a coin
toss for the clipper that runs afterwards, and half the turns were being dropped.

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

## A part to try it on

`doc/bridge_test.scad.py` writes an 80 × 40 × 8 mm block with three tunnels running right
through it — **10, 20 and 30 mm wide**, 5 mm walls between them, and a 2 mm roof. Print it,
turn it over, and look into the tunnels: the underside of the bridge is the first layer of the
roof and nothing hides it.

```bash
python3 doc/bridge_test.scad.py bridge_test.stl
```

Slice it three times — without the plugin, with `density = 1.0`, with `density = 1.14` — and
compare the three undersides. What to look for, in order of how obvious it is:

1. **Daylight between the strands.** Hold it up to a light. Stock leaves a slot beside every
   strand; at `density = 1.0` they meet.
2. **Sag.** A strand touching its neighbours is held by them. The 30 mm tunnel shows it first.
3. **Whether it went too far.** Past `density ≈ 1.3` there is more plastic than room and the
   strands lift into the path of the nozzle. The 10 mm tunnel shows that first, because the
   strands there are stiff enough not to sag out of the way.

## Settings

`settings.lua` next to the Lua source. Edit and slice again; no restart, no rescan. It is read
inside a `pcall`, so **a syntax error in it is reported nowhere** — the file is ignored and the
defaults apply.

| setting | default | what it does |
|---|---|---|
| `density` | `0.963` | How far apart the strands go, as a fraction of their own width. `1.0` is edge to edge; the default is what OrcaSlicer's 114 % works out to, which is what came out best on a real print. Past about 1.3 they lift off their neighbours into the path of the nozzle. |
| `flow_ratio` | `1.0` | Multiplies the extrusion, 1:1 with OrcaSlicer's `bridge_flow`. Strand width goes as its square root. |
| `speed` | `0` | Print speed for these bridges in mm/s; `0` keeps `bridge_speed`. The only way to give external bridges a speed of their own. |
| `external_only` | `true` | Only bridges cast over open air. A bridge over sparse infill rests on a lattice and is not sagging for want of lateral contact. |
| `match_stock_material` | `false` | Scale the flow so the surface gets the material it would have, spread over more strands. Off is the point — packing closer *without* touching the flow is what makes them meet. |
| `extra_spacing` | `0.05` | Fallback only, against a fork too old to report the flow (API below 1.3.0). |
| `roles` | `BridgeInfill` | Bridges only. An empty table turns the plugin off. |
| `max_lines` | `4000` | Refuse a surface needing more lines than this. |

Nothing here is measured against the slicer's own line spacing, which differs between slicers
and between regions of one layer. Everything is measured against the strand.

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
