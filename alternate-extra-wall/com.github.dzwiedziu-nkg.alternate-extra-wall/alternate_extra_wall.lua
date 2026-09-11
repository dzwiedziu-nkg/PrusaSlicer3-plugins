-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Adds one wall on every other layer.
--
-- A wall count is one number for the whole object, so every layer's innermost wall sits at the
-- same radius and the infill meets it along the same line all the way up. That line is a seam
-- running the height of the part, and it is where the part comes apart.
--
-- Give every other layer one more wall and the innermost wall alternates between two radii.
-- The infill now ends up wedged vertically between walls rather than butting against a
-- continuous face, which is what OrcaSlicer's `alternate_extra_wall` does and what it is for.
--
-- Measured on OrcaSlicer's own output for the test part: the layers that get the extra wall
-- carry about twice the inner-wall material, a little less sparse infill because the wall eats
-- into the area, and about 11 % more material overall. Averaged over the whole print that is
-- roughly 6 %.
--
-- This costs material and print time and buys strength. It buys nothing at all on a part that
-- is not loaded, and on a thin-walled part it may find no room for the extra wall to go.

info = {
    id = "alternate_extra_wall",
    type = "slicing.perimeter_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local extra = settings.extra == nil and 1 or settings.extra
local every = settings.every == nil and 2 or settings.every
local phase = settings.phase == nil and 1 or settings.phase
local skip_first_layers = settings.skip_first_layers == nil and 1 or settings.skip_first_layers

--- Decides how many walls this layer gets.
-- @param region table with layer_id, print_z, layer_height, extruder_id, perimeters,
--               perimeter_width, perimeter_spacing and nozzle_diameter.
-- @return the wall count to use, or nil to leave the settings' count alone.
function plan_perimeters(region)
    if extra == 0 or every < 2 then
        return nil
    end

    -- A region the settings gave no wall at all is one the slicer is treating specially -
    -- spiral vase, or a surface that is all infill. Adding a wall there is not this plugin's
    -- business.
    if region.perimeters <= 0 then
        return nil
    end

    -- The first layers are about adhesion, not strength, and changing the wall count there
    -- moves the seam around on the face everyone looks at.
    if region.layer_id < skip_first_layers then
        return nil
    end

    if region.layer_id % every ~= phase then
        return nil
    end

    return region.perimeters + extra
end
