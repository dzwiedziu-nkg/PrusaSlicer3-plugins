-- Settings for the cross-hatch plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- Direction of the lines in the first run, in degrees. 45 is what OrcaSlicer uses and
    -- what its output was measured at.
    angle = 45,

    -- How far the pattern climbs before it has turned a full 90 degrees, in mm.
    --
    -- Measured off OrcaSlicer's own output: the lines hold 45 degrees from Z 1.0 to 2.2, turn
    -- between 2.4 and 3.4, hold 135 degrees from 3.6 to 5.0, and turn back - a full cycle of
    -- 5.4 mm, so half of it is 2.7 mm. Set it to 0 to turn the plugin off.
    --
    -- Shorter means the infill changes direction more often: less like a wall, more like a
    -- lattice. Longer means stiffer runs and taller continuous faces.
    half_period = 2.7,

    -- How much of each half period is the zigzag rather than the straight run, 0 to 1.
    --
    -- The pattern is a stack of truncated octahedra, the same tessellation PrusaSlicer ships as
    -- `3dhoneycomb`. Where the zigzag amplitude falls to zero the lines come out straight, and
    -- straight layers stacked on each other fuse into a wall that carries load. Stock 3D
    -- Honeycomb passes through that state in one layer out of nineteen; this holds it.
    --
    -- 0 leaves no zigzag at all, which is plain `rectilinear`. 1 leaves no straight run, which
    -- is close to stock 3D Honeycomb - the thing this exists to improve on. OrcaSlicer spends
    -- about six layers of the thirteen in a half period on the zigzag, which is the 0.4444.
    transition = 0.4444,

    -- Shifts the whole pattern up, in mm. Which height the first run starts at makes no
    -- difference to what the infill does; this exists so the output can be checked against
    -- OrcaSlicer's, and 4.6 is the value that lines the two up. Wraps at twice `half_period`.
    z_offset = 4.6,

    -- Which surfaces to take over. Sparse infill only by default - solid, top and bridge
    -- surfaces have their own reasons for the pattern they use, and this is not one of them.
    roles = {InternalInfill = true},

    -- Leave the first layers alone, counted from the bed.
    skip_first_layers = 0
}
