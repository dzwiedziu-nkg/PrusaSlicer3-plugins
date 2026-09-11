-- Settings for the alternate-extra-wall plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- How many walls to add on the layers that get them. 0 turns the plugin off.
    --
    -- One is what OrcaSlicer does and what the effect is named after. More than one is
    -- possible and rapidly stops being worth the material: the point is that the innermost
    -- wall alternates between two radii, and it does that at one.
    extra = 1,

    -- Add them on every Nth layer. 2 is every other layer, which is the whole idea; 3 would
    -- give one extra wall in every three layers. Below 2 the plugin does nothing, since
    -- "every layer" is just a higher wall count and belongs in the print settings.
    every = 2,

    -- Which layer of each cycle gets the extra wall, as `layer_id % every`.
    --
    -- Only matters for where the alternation starts, and with `every = 2` the two choices are
    -- indistinguishable a few layers up. OrcaSlicer starts on the second layer, which is 1.
    phase = 1,

    -- Leave this many layers at the bottom alone.
    --
    -- The first layers are about adhesion rather than strength, and changing the wall count
    -- there moves the seam around on the face that sits on the bed.
    skip_first_layers = 1
}
