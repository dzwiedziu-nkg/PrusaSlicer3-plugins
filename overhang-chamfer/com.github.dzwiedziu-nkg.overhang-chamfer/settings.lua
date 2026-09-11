-- Settings for the overhang-chamfer plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- The shallowest slope the chamfer will produce, in degrees.
    --
    -- PrusaSlicer's convention, the one `support_material_threshold` uses: 90 is vertical and
    -- the number is the most horizontal slope printable without support. 35 is what that
    -- setting is set to in the stock profiles, which is why it is the default here.
    --
    -- A layer's outline may then grow by `layer_height / tan(angle)` over the layer below.
    -- At 0.2 mm layers that is 1.134 mm at 10 degrees, 0.286 mm at 35 and 0.200 mm at 45.
    -- Smaller angles chamfer faster and cost less material; 90 lets the outline grow not at
    -- all, which chamfers every overhang it is allowed to touch back to vertical.
    --
    -- 35 stops the printer laying beads onto air - measured, every overhang perimeter gone -
    -- but it does NOT stop the support generator, which wants a margin on two counts: it adds
    -- a degree to the threshold to make it inclusive, and it measures perpendicular to the
    -- wall while a square corner advances by d*sqrt(2). The angle that clears it is
    --
    --     atan(tan(support_material_threshold + 1) * sqrt(2))
    --
    -- which is 45.8 degrees for a threshold of 35, and measured the support goes from 389 mm3
    -- at 45 to nothing at 46. So: 35 to stop printing onto air, 46 to also stop printing
    -- support - at the cost of more of the model.
    angle = 35,

    -- The most material the chamfer may cut away, in mm. This is the safety catch.
    --
    -- Measured as the largest disc that fits inside the piece about to be removed. An overhang
    -- too big to fit under it is left alone in one piece, and the support generator deals with
    -- it as it always did - which is right, because chamfering only the outer rim of a big
    -- ledge would reshape the part and still leave an overhang needing support.
    --
    -- It is also what stops the chamfer running away on a slope shallower than `angle`. Each
    -- layer of such a slope is measured against the outline the layer below was left with, so
    -- the shortfall accumulates; once it no longer fits under this number the layer is handed
    -- back in full. The model is therefore never more than this far from what the mesh says.
    --
    -- 0 means no limit, which lets the chamfer eat an entire table top. Do not.
    max_width = 2.0,

    -- Leave everything below this height alone, in mm. 0 acts everywhere.
    --
    -- Worth setting when the bottom of the part has to come out dimensionally right and the
    -- support down there is not a problem.
    min_z = 0.0
}
