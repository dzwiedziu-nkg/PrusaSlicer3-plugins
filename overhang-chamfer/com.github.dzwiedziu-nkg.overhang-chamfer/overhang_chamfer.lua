-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Chamfers small 90 degree overhangs away.
--
-- Where a model juts sideways, the layer above is printed onto air. The bead curls, the nozzle
-- drags through it on the next pass, and the usual answer is support - which has to be printed,
-- has to be removed, and leaves a mark on the face it touched.
--
-- For a small ledge there is a better answer: do not print the overhang at all. Let each layer
-- reach only so far past the layer below and the ledge comes out as a chamfer, built up over
-- several layers, every one of them resting on the one under it. A little material is missing
-- from the underside of the part and nothing has to be removed afterwards.
--
-- How far "so far" is comes from an angle, in the convention `support_material_threshold`
-- uses: 90 degrees is vertical and the number is the most horizontal slope printable without
-- support. A layer may then grow by `layer_height / tan(angle)`.
--
-- Setting the angle to the threshold stops the printer laying beads onto air, but it does not
-- stop the support generator - that wants a margin, for the reason worked out in settings.lua.
--
-- This removes material from the model. That is the point, and it is also the risk: `max_width`
-- is what keeps it to the edges. See settings.lua.

info = {
    id = "overhang_chamfer",
    type = "slicing.slice_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local angle = settings.angle == nil and 35 or settings.angle
local max_width = settings.max_width == nil and 2.0 or settings.max_width
local min_z = settings.min_z == nil and 0.0 or settings.min_z

-- tan(90 degrees) is not representable, and at 90 the answer is exactly zero anyway: the
-- outline may not widen at all. Worked out once rather than per layer.
local reach_per_mm = nil
if angle > 0 and angle < 90 then
    reach_per_mm = 1.0 / math.tan(math.rad(angle))
elseif angle >= 90 then
    reach_per_mm = 0.0
end

--- Decides how far this layer's outline may reach past the layer below.
-- @param layer table with layer_id, print_z, slice_z, layer_height, object_height, area
--              and islands.
-- @return a table naming max_overhang and max_overhang_width in mm, or nil to print the
--         outline the mesh gives.
function plan_slice(layer)
    -- At or below zero degrees every slope is printable by definition, so there is nothing to
    -- chamfer and the plugin has been turned off.
    if reach_per_mm == nil then
        return nil
    end

    if layer.print_z < min_z then
        return nil
    end

    return {
        max_overhang = layer.layer_height * reach_per_mm,
        max_overhang_width = max_width
    }
end
