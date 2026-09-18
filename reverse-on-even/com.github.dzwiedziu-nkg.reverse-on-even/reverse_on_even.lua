-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Walks the wall loops of every other layer the other way round.
--
-- A perimeter is a closed loop, and the nozzle has to go round it one way or the other. The
-- slicer always picks the same way, so on a wall that leans out over air every layer is dragged
-- in the same direction as it cools, and the pull adds up: the overhang curls and the part
-- warps. Alternate the direction layer by layer and consecutive layers pull against each other
-- instead, which is what makes steep overhangs come out and what takes some of the stress out
-- of a tall wall in a material that shrinks.
--
-- Nothing is added, nothing is removed and nothing moves: the same loops are printed with the
-- same material, in the opposite order of points. It is the cheapest thing in this repository.
--
-- The idea is OrcaSlicer's, not ours: this is a reimplementation of their `overhang_reverse`
-- for PrusaSlicer, which has no equivalent. Their `overhang_reverse_threshold` is a *depth* -
-- how far the wall reaches past the layer below - and this hook can only see a *length* of wall
-- laid over air, so the two agree at their default (any overhang at all) and diverge for
-- anything else. See the README.

info = {
    id = "reverse_on_even",
    type = "slicing.loop_direction"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local enabled = settings.enabled ~= false
local phase = settings.phase == nil and 1 or settings.phase
local require_overhang = settings.require_overhang ~= false
local min_overhang_length = settings.min_overhang_length or 0.0
local internal_only = settings.internal_only == true
local skip_first_layers = settings.skip_first_layers == nil and 1 or settings.skip_first_layers

--- Decides which way round this wall loop is walked.
-- @param loop table with layer_id, print_z, extruder_id, role, perimeter_index, is_hole,
--             length, overhang_length, island_overhang and default_direction.
-- @return "cw", "ccw", or nil to walk it the way the slicer chose.
function plan_direction(loop)
    if not enabled then
        return nil
    end
    if loop.layer_id < skip_first_layers then
        return nil
    end
    -- Every other layer, counted from the bed. The layers in between keep the slicer's
    -- direction, which is what makes the two alternate.
    if loop.layer_id % 2 ~= phase then
        return nil
    end
    -- The wall that shows is the one a reversal is most likely to mark, so it can be left out.
    if internal_only and loop.role == "ExternalPerimeter" then
        return nil
    end
    -- Judge the island rather than the loop: a wall stack whose outer loop hangs over air wants
    -- all of its loops turned together, and turning only the loop that overhangs would leave
    -- the seam of one wall running against its neighbour's.
    if require_overhang and loop.island_overhang <= min_overhang_length then
        return nil
    end

    return loop.default_direction == "ccw" and "cw" or "ccw"
end
