# Sequential islands — a PrusaSlicer slicing plugin

This experimental `slicing.island_sequence` plugin prints independent upper parts of
one object sequentially after they split from a common base. In `house.3mf`, the common
house body is printed normally; after it separates into two gable peaks, one peak is
finished to the top before the nozzle returns down to print the other.

## Ordering and the branch transition

The plugin follows PrusaSlicer's own `overlaps_above` / `overlaps_below` graph. It does
not infer structural continuity from bounding boxes. A split is accepted only when all
descendants stay assigned to exactly one root branch and every branch lasts for at least
`min_branch_layers`.

Branches farthest from the tool dock print first:

- `COREONE_INDX*` and other front-dock machines: larger Y first;
- Prusa XL rear dock: smaller Y first.

Before Z moves down to the next branch, the slicer:

1. wipes backwards on the last extrusion path while retracting (normally top infill),
   capped by `wipe_distance`;
2. raises Z by `z_clearance`;
3. moves XY at that high Z until it is above the first extrusion of the next branch;
4. only then descends to the branch's first layer.

Immediately after a downward move, that island exceptionally prints infill before its
perimeters. The hidden infill becomes a long, model-contained purge/wipe and the visible
walls are laid down only after the nozzle flow has stabilised. If a particular layer has
no infill, the slicer simply starts with the first available perimeter.

The G-code contains `ISLAND_SEQUENCE_TRANSITION_BEGIN/END` comments around this move.

## Safety envelope

Version 0.1 deliberately activates only for:

- one FFF object with one instance;
- no supports or raft;
- no wipe tower;
- no infinite skirt;
- no spiral-vase or ordinary complete-objects mode;
- no height-based custom G-code, color changes, or pauses.

For Original Prusa CORE One (`printer_model = COREONE`), the plugin and the engine both
use PrusaSlicer's fallback sequential-print geometry: a 10 x 10 mm nozzle footprint, a
square with the profile's 75 mm clearance radius from 1 mm above the nozzle, and the X
gantry from the profile's 33 mm clearance height. The preferred full branch order is
checked first, then the reversed full order. If both collide, the upper branches are split
into the tallest collision-free horizontal parties and each party tries both orders.

The engine independently validates the final schedule and rejects it if it collides. The
ordinary high-severity unchecked-collision warning is therefore suppressed for CORE One.
Other printer models, including COREONE INDX and XL for now, retain the warning and remain
the user's responsibility.

If no persistent split is found, the overlap graph is ambiguous, or the returned plan
fails the engine's dependency/coverage validation, slicing falls back to normal layer
order.

Strict branch completion may increase the number of tool changes on a multi-tool print:
each branch needs its own tool-change cycle on a physical layer. This can increase the
time and filament consumed by tool-change priming even though the model extrusion paths
are emitted exactly once.

## Validation on `house.3mf`

The Core One INDX project has 281 physical layers. The plugin detects the split at
Z = 17.6 mm and produces 475 scheduling steps. It prints the larger-Y (rear) peak first
through Z = 56.2 mm, wipes over top solid infill, rises to Z = 56.8 mm, moves above the
smaller-Y (front) peak, and only then descends to Z = 17.6 mm.

A control export and the sequential export contain identical positive model-extrusion
totals in every G-code role. The sequential export does contain more INDX tool changes,
as described above.

## Validation on `niaczek_garaz.3mf`

The two narrow door islands separate at Z = 4.2 mm and end at Z = 9.0 mm. Completing one
whole island would collide with the CORE One head, so version 0.2 divides the sequence into
five collision-free parties, each no taller than 0.8 mm. Every party transition raises Z,
moves above the other island, descends, prints internal/solid infill first, and only then
prints its perimeters.

## Settings

Edit `settings.lua` and slice again:

| key | default | meaning |
|---|---:|---|
| `dock_edge` | `"auto"` | `"front"`, `"rear"`, or detect XL as rear and everything else as front |
| `min_branch_layers` | `3` | minimum lifetime of every root branch |
| `wipe_distance` | `2.0` mm | cap on the transition wipe |
| `z_clearance` | `0.6` mm | rise before the high XY move |

## Requirements and installation

Use the accompanying PrusaSlicer fork with `slicing.island_sequence` API 1.0.0.

```bash
ln -s "$PWD/com.github.dzwiedziu-nkg.sequential-islands" ~/.config/PrusaSlicer/lua/
```

The bundle directory name must match the manifest `id`. The plugin is automatic and has
no menu item. The log confirms `Island sequencing plugin in use` and whether a plan was
accepted.
