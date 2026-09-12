-- Settings for the gradient-infill plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- How far in from the wall the dense band reaches, in mm.
    --
    -- Inside this band the lines are packed `edge` times closer than the setting asks for;
    -- past `taper` beyond it they are back to `core`. 0 turns the plugin off.
    band = 0,

    -- How much closer the lines run inside the band, as a multiple of the density.
    --
    -- 2.0 is twice the density you asked for. This is the half that buys stiffness: a beam
    -- carries its load in the material furthest from its neutral axis, and in a printed part
    -- that is the infill just behind the wall.
    edge = 2.0,

    -- How much of the density is kept in the middle, as a multiple.
    --
    -- 0.5 is half of what you asked for. Together with an `edge` of 2.0 and a wide enough
    -- part, the two roughly cancel and the part comes out near the material you budgeted -
    -- but with it in the useful place. Set both to 1.0 and the plugin lays the stock pattern.
    core = 0.5,

    -- How far the change from `edge` to `core` is spread over, in mm. 0 is a hard step.
    taper = 4.0,

    -- Direction of the lines, in degrees, and how much it turns each layer.
    --
    -- The stock rectilinear pattern alternates 45 and 135. Keeping that means the gradient is
    -- the only thing this plugin changes.
    angle = 45,
    angle_step = 90,

    -- Which surfaces to take over. Sparse infill only: a solid or top surface has to stay
    -- solid, and a bridge has to keep the direction the slicer chose for it.
    roles = {InternalInfill = true},

    -- Leave the first layers alone, counted from the bed.
    skip_first_layers = 0
}
