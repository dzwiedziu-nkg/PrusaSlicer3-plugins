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

The G-code contains `ISLAND_SEQUENCE_TRANSITION_BEGIN/END` comments around this move.

## Safety envelope

Version 0.1 deliberately activates only for:

- one FFF object with one instance;
- no supports or raft;
- no wipe tower;
- no infinite skirt;
- no spiral-vase or ordinary complete-objects mode;
- no height-based custom G-code, color changes, or pauses.

The existing complete-objects collision checker does **not** model branches starting
above the bed. PrusaSlicer therefore shows a high-severity warning whenever this plugin's
plan is accepted. Inspect the G-code preview and take responsibility for carriage and
tool clearance around the completed branch.

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
