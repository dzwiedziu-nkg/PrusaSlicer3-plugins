-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Chamfers small overhangs off and carries big ones on a cone.
--
-- There are two ways to stop the printer laying a bead onto air: take the overhang off, or put
-- something under it. Which one is right depends on how big the overhang is, and until now that
-- meant choosing one for the whole print, because the slicer loads one plugin of each type and
-- `overhang-chamfer` and `make-overhang-printable` are both slice planners.
--
-- They are both this hook, though, so this asks for both passes at once and lets their size
-- bounds do the choosing: the clip is told to leave alone anything wider than `cut_below`, so
-- it takes only the small ledges on the way up, and the fill then carries what is left on the
-- way down. A part with a 1 mm ledge and a 10 mm shelf gets the cheap answer on the ledge and
-- the honest one on the shelf, in one print.
--
-- Both halves are OrcaSlicer's ideas: the carry is their `make_overhang_printable`, and the
-- angle convention is the mirror of their `make_overhang_printable_angle`, so their default of
-- 55 is this plugin's 35.
--
-- Install this **instead of** overhang-chamfer and make-overhang-printable, not alongside them.

info = {
    id = "overhang_by_size",
    type = "slicing.slice_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local angle = settings.angle == nil and 35 or settings.angle
local cut_below = settings.cut_below == nil and 2.0 or settings.cut_below
local carry_max = settings.carry_max == nil and 0 or settings.carry_max
local min_z = settings.min_z == nil and 0.0 or settings.min_z

-- tan(90 degrees) is not representable, and at 90 the answer is exactly zero anyway.
local reach_per_mm = nil
if angle > 0 and angle < 90 then
    reach_per_mm = 1.0 / math.tan(math.rad(angle))
elseif angle >= 90 then
    reach_per_mm = 0.0
end

--- Decides what this layer's outline is allowed to be.
--
-- Both passes are asked for at once. The bounds are what does the choosing: the clip is told to
-- leave alone anything wider than `cut_below`, so it takes only the small ledges, and the fill
-- then carries whatever the clip left. A layer never gets both remedies applied to the same
-- piece of overhang - the clip runs first and the fill only sees what is still overhanging.
--
-- @param layer table with layer_id, print_z, slice_z, layer_height, object_height, area
--              and islands.
-- @return a list of two plans, one plan, or nil.
function plan_slice(layer)
    if reach_per_mm == nil then
        return nil
    end
    if layer.print_z < min_z then
        return nil
    end

    local reach = layer.layer_height * reach_per_mm

    -- A cut_below of 0 is "never cut", which is make-overhang-printable exactly.
    if cut_below <= 0.0 then
        return {max_overhang = reach, max_overhang_width = carry_max, remedy = "fill"}
    end

    return {
        {max_overhang = reach, max_overhang_width = cut_below, remedy = "clip"},
        {max_overhang = reach, max_overhang_width = carry_max, remedy = "fill"}
    }
end
