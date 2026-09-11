-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Carries an overhang on a cone of new material built up from underneath.
--
-- Where a model juts sideways the layer above starts in mid-air. There are two ways to stop
-- that: take the overhang off, or put something under it. This plugin puts something under it.
-- Each layer is made to cover at least the layer above shrunk by `layer_height / tan(angle)`,
-- and walking downward that grows a cone at exactly that slope, from the overhang down to
-- whatever holds it up - the part, or the bed.
--
-- Nothing of the model is lost. The part comes out larger instead, with a skirt of material
-- that was not in the mesh, and that material has to be cut off afterwards if it is in the way.
-- Where the overhang is small, taking it off instead is usually the better trade, and that is
-- the `overhang-chamfer` plugin.
--
-- This is OrcaSlicer's `make_overhang_printable`. Its `make_overhang_printable_angle` is the
-- same quantity measured from the other side: its default of 55 is this plugin's 35.

info = {
    id = "make_overhang_printable",
    type = "slicing.slice_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local angle = settings.angle == nil and 35 or settings.angle
local max_width = settings.max_width == nil and 0 or settings.max_width
local min_z = settings.min_z == nil and 0.0 or settings.min_z

-- tan(90 degrees) is not representable, and at 90 the answer is exactly zero anyway: the layer
-- below must cover the whole of the layer above. Worked out once rather than per layer.
local reach_per_mm = nil
if angle > 0 and angle < 90 then
    reach_per_mm = 1.0 / math.tan(math.rad(angle))
elseif angle >= 90 then
    reach_per_mm = 0.0
end

--- Decides how far this layer's outline may fall short of the one above it.
-- @param layer table with layer_id, print_z, slice_z, layer_height, object_height, area
--              and islands.
-- @return a table naming max_overhang, max_overhang_width and the remedy, or nil to print the
--         outline the mesh gives.
function plan_slice(layer)
    -- At or below zero degrees every slope is printable by definition, so there is nothing to
    -- carry and the plugin has been turned off.
    if reach_per_mm == nil then
        return nil
    end

    if layer.print_z < min_z then
        return nil
    end

    return {
        max_overhang = layer.layer_height * reach_per_mm,
        max_overhang_width = max_width,
        remedy = "fill"
    }
end
