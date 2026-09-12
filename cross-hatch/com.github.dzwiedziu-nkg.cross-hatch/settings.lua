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
    half_period = 0,

    -- How much of each half period is spent turning rather than holding, 0 to 1.
    --
    -- 0 turns the direction over in one layer, which is what `rectilinear` does and is the
    -- thing Cross Hatch exists to avoid: consecutive layers crossing at 90 degrees touch each
    -- other at points rather than along lines. OrcaSlicer spends about six layers of the
    -- thirteen in a half period turning, which is the 0.45 here.
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
