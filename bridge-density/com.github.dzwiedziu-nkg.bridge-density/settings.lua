-- Settings for the bridge-density plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- How far apart the strands go, as a fraction of their own width.
    --
    -- 1.0 puts them exactly edge to edge, which is the whole of the fix: PrusaSlicer leaves a
    -- deliberate gap beside every bridge line and the strands never touch. 1.14 gives them 14 %
    -- of overlap. 0.4 leaves a gap of one and a half strands.
    --
    -- This is OrcaSlicer's `bridge_density` in spirit but not in units. Theirs is a fraction of
    -- *its own* nominal line spacing, which differs between slicers and between regions of one
    -- layer; this is a fraction of the strand, which either touches its neighbour or does not.
    -- Measured on OrcaSlicer's output at a 0.4 nozzle, its 100 % lands at 0.846 here and the
    -- conversion is `density = 0.846 * orca_bridge_density * sqrt(orca_bridge_flow)`.
    --
    -- Past about 1.3 the strands stop being strands: too much plastic in too little space lifts
    -- them off their neighbours and into the path of the nozzle.
    density = 1.0,

    -- Multiplies the extrusion, the way OrcaSlicer's `bridge_flow` does. 1:1 with it.
    --
    -- A fatter strand reaches its neighbour sooner, so this and `density` pull in the same
    -- direction; the strand width goes as the square root of the flow. Raise this when the
    -- strands are touching but thin, raise `density` when they are fat but apart.
    flow_ratio = 1.0,

    -- Fallback only, in mm: `BRIDGE_EXTRA_SPACING` from Flow.hpp.
    --
    -- The bead diameter is normally taken from the flow the slicer reports, which is exact.
    -- This is only used against a fork too old to report it (API below 1.3.0), where the bead
    -- has to be guessed as `spacing` less the gap the slicer inserts - and that guess is wrong
    -- wherever the slicer adjusted the spacing to fit a whole number of lines across.
    extra_spacing = 0.05,

    -- Scale the flow so the surface receives the material it would have, rather than more.
    --
    -- Off by default, and off is the point: packing the lines closer without touching the flow
    -- is what puts more plastic on the bridge and makes the strands touch. Turning it on keeps
    -- the material and thins every strand, which is the opposite of what this is for - but it
    -- is the honest way to close the gaps on a bridge that is already sagging from too much.
    match_stock_material = false,

    -- Print speed for these bridges, in mm/s. 0 keeps the one `bridge_speed` gives.
    --
    -- PrusaSlicer has **one** `bridge_speed` for both kinds of bridge, because both are the
    -- same extrusion role to it. That is a real problem and not one you can settle in the print
    -- settings: a bridge over sparse infill is resting on a lattice and printing it slowly just
    -- wastes time, while a bridge cast over open air wants to go slowly enough for the strand
    -- to cool before it is asked to hold the next one. Raise `bridge_speed` for the first and
    -- the second suffers; lower it for the second and every internal bridge crawls.
    --
    -- Set `bridge_speed` for the internal ones and put the external speed here. With
    -- `external_only` left on, this only ever touches bridges over open air.
    speed = 10,

    -- Roles to take over. Bridges only: this is about beads laid in mid-air, and a bead laid
    -- on solid plastic below it is a flattened rectangle, not a cylinder.
    roles = {BridgeInfill = true},

    -- Only bridges cast over open air, not the ones laid over sparse infill.
    --
    -- PrusaSlicer gives both the same extrusion role and the same `bridge_speed`, so the role
    -- alone cannot separate them - OrcaSlicer, which can, keeps `bridge_density` and
    -- `internal_bridge_density` apart and defaults the internal one to 100 %. A bridge over
    -- infill rests on a lattice every few millimetres; it is not sagging for want of lateral
    -- contact, and packing its lines together only adds plastic inside the part.
    --
    -- Set to false to treat both alike.
    external_only = true,

    -- Refuse a surface that would need more lines than this.
    max_lines = 4000
}
