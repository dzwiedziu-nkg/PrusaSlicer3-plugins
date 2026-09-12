-- Settings for the bridge-density plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- How much of the bead's diameter adjacent strands should share, 0 to 0.5.
    --
    -- 0 puts them exactly edge to edge, which is already the whole of the fix: the slicer
    -- leaves a deliberate 0.05 mm gap between bridge lines and at a 0.4 nozzle that is an
    -- eighth of a bead of daylight. 0.1 gives them a tenth of a bead of overlap, which is
    -- what "bridge density above 100 %" means in practice.
    --
    -- Past about 0.25 the strands stop being strands: too much plastic in too little space
    -- lifts them off their neighbours and into the path of the nozzle.
    overlap = 0.0,

    -- What the slicer adds between bridge lines on purpose, in mm.
    --
    -- This is `BRIDGE_EXTRA_SPACING` in Flow.hpp, and it is how the plugin recovers the bead
    -- diameter: the slicer hands a planner `spacing`, which for a bridge is the diameter plus
    -- this. Only change it if the fork changes the constant.
    extra_spacing = 0.05,

    -- Scale the flow so the surface receives the material it would have, rather than more.
    --
    -- Off by default, and off is the point: packing the lines closer without touching the flow
    -- is what puts more plastic on the bridge and makes the strands touch. Turning it on keeps
    -- the material and thins every strand, which is the opposite of what this is for - but it
    -- is the honest way to close the gaps on a bridge that is already sagging from too much.
    match_stock_material = false,

    -- Roles to take over. Bridges only: this is about beads laid in mid-air, and a bead laid
    -- on solid plastic below it is a flattened rectangle, not a cylinder.
    roles = {BridgeInfill = true},

    -- Refuse a surface that would need more lines than this.
    max_lines = 4000
}
