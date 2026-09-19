-- Settings for the hull-line plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- How much of the flow the solid infill keeps. 1.0 turns the plugin off.
    --
    -- Prusa's own words for what they tried by hand are "slightly lower the flow of solid
    -- infill, except for the very top layer", and 0.95 is the smallest change worth measuring.
    -- Below about 0.9 the solid infill stops being solid and the top surface above it shows it.
    --
    -- **They were not sure this is what helped**, and neither are we until it is printed. It is
    -- the half of their experiment a fill planner can do; the other half is the order the layer
    -- is printed in, which needs an extension point that does not exist yet.
    flow_ratio = 0.95,

    -- Print speed for that solid infill, in mm/s. 0 keeps the one the role asks for.
    --
    -- The hull line is attributed to the step in layer *time* at the transition, so this is the
    -- knob that addresses the cause rather than the symptom - and the one that cannot be aimed
    -- properly from here, because a fill planner is asked about every layer at once and cannot
    -- tell which of them is the transition. Raising it shortens the deck layers and makes the
    -- step smaller; it also shortens every other solid layer in the part.
    speed = 0,

    -- Ignore solid surfaces smaller than this, in mm^2.
    --
    -- The shell over a hole, the floor of a recess and the first layers of a slope are all
    -- solid infill and none of them is a deck. 15 mm^2 is a 4 mm square.
    --
    -- Measured on Prusa's own hull line test block, the solid infill of the three layers over
    -- the deck is 19.2, 27.9 and 29.1 mm^2, and the patches this is meant to skip are 0.7 to
    -- 5.1. There is a wide gap between them and the default sits in it.
    min_area = 15.0,

    -- Which surfaces to claim.
    --
    -- `SolidInfill` covers the internal solid layers. **`TopSolidInfill` is deliberately not
    -- here**: it is the surface you look at, and it is the one Prusa excluded by name. Adding
    -- it would thin the skin of the part.
    roles = {SolidInfill = true},

    -- Leave the first layers alone, counted from the bed.
    skip_first_layers = 0,

    -- The second half of the plugin, and the half Prusa thought did the work: **print the deck
    -- before the wall that runs past it**. Set to false to turn it off and leave only the flow.
    --
    -- On a transition layer the order becomes solid fill, then the rest of the fill, then the
    -- walls, so the hull's wall is not laid straight after the mass of solid beside it. With a
    -- modifier mesh splitting the deck from the hull - which is how Prusa did it - the deck's
    -- own walls are a group of their own and come first, which is their order exactly.
    order = true,

    -- How much solid infill, in mm^3, makes a layer a deck rather than a patch.
    min_solid = 1.0,

    -- How many layers back the "almost none below" comparison looks.
    --
    -- It is also how many layers have to go by before anything can fire at all: a part that
    -- starts solid on the bed is not a transition, because there is no wall below it to carry
    -- the mark.
    window = 5,

    -- The shortest run, in layers, counting the transition itself.
    --
    -- It is a minimum rather than the whole run: the reordering keeps going while the layer is
    -- still carrying the deck - at least `min_solid` of solid infill - and ends on the first
    -- layer after that. A deck is as many layers thick as the part makes it, and a fixed count
    -- would hand the wall back to its old place in the middle of one.
    depth = 3,

    -- Only treat a layer as a transition when a wall runs through it. The hull line is a mark
    -- on a wall, so a layer with none cannot have one.
    require_wall = true,

    -- Diagnostic, not a feature: reorder **every** layer, so the wall is laid last from the
    -- first layer to the last and the run has no boundaries in the middle of the part.
    --
    -- Why it exists. Reordering a run of layers changes nothing about speed, flow, direction or
    -- seam - but it does change *when* in the layer the wall is laid, and so how long that wall
    -- waits before the next one lands on it. Measured on the test block at the seam: the
    -- ordinary run makes that wait 10.9 s on the first reordered layer and 5.0 s on the first
    -- layer after it, where every other layer of the print sits at 7.0 to 7.8 s. Two steps in
    -- the wall's rhythm, at the transition, which is where a hull line forms.
    --
    -- Print the block once with this false and once with it true. If the wall is clean all the
    -- way up with it true, the marks come from *switching* the order part way up the part, not
    -- from the order. If the wall looks the same either way, it is the order itself - the layer
    -- ending on the outside wall, where the layer-change travel then starts.
    always = false
}
