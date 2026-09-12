-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Cross Hatch sparse infill.
--
-- This is 3D Honeycomb - the same truncated-octahedron tessellation PrusaSlicer already ships
-- as `3dhoneycomb` - with one thing changed: the moment where the zigzag flattens into straight
-- lines is stretched over several layers instead of passing through in one.
--
-- Why that matters. In 3D Honeycomb the zigzag amplitude follows a sawtooth in Z, so the lines
-- are straight for an instant and swinging the rest of the time, and the direction flips every
-- layer. Nothing gets a chance to fuse into anything. Hold the straight phase for a few
-- millimetres instead and those layers stack into a stiff wall, and then the zigzag carries the
-- pattern round to the other direction so the wall never runs the height of the part.
--
-- The direction flips at the **peak** of the zigzag, not in the straight phase, which is what
-- makes the change invisible: at full amplitude the pattern about 45 degrees and the pattern
-- about 135 degrees are the same lattice.
--
-- The algorithm is OrcaSlicer's, not ours; this is a reimplementation of their Cross Hatch for
-- PrusaSlicer. The octahedron geometry follows PrusaSlicer's own Fill3DHoneycomb, credited
-- there to David Eccles (gringer).
--
-- Use it with `fill_pattern = rectilinear` or `line`, which lay one family of lines per layer
-- as this does, so the density you ask for is the density you get.

info = {
    id = "cross_hatch",
    type = "slicing.fill_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local angle = settings.angle == nil and 45 or settings.angle
local half_period = settings.half_period == nil and 2.7 or settings.half_period
local transition = settings.transition == nil and 0.4444 or settings.transition
local z_offset = settings.z_offset == nil and 4.6 or settings.z_offset
local roles = settings.roles == nil and {InternalInfill = true} or settings.roles
local skip_first_layers = settings.skip_first_layers == nil and 0 or settings.skip_first_layers

-- Half a grid cell, which is the amplitude at which the octahedron closes up. Straight from
-- Fill3DHoneycomb's `octagramGap`.
local OCTAGRAM_GAP = 0.5

--- Direction and zigzag amplitude at this height.
-- Amplitude is 0 for the held part of each half period and swings 0 -> peak -> 0 through the
-- transition; the direction turns a quarter turn at the peak, where the two are the same shape.
-- @return angle in radians, amplitude as a fraction of the grid cell
local function shape_at(z)
    local cycles = (z + z_offset) / half_period
    local whole = math.floor(cycles)
    local t = cycles - whole
    local theta = math.rad(angle) + whole * math.pi / 2.0
    if transition <= 0.0 or t <= 1.0 - transition then
        return theta, 0.0
    end
    local u = (t - (1.0 - transition)) / transition     -- 0..1 across the turn
    if u > 0.5 then
        theta = theta + math.pi / 2.0
    end
    return theta, math.sin(u * math.pi) * OCTAGRAM_GAP
end

--- Bounding box of a contour in the rotated frame, in grid cells.
local function extent(points, dx, dy, nx, ny, cell)
    local alo, ahi, plo, phi = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(points) do
        local a = (p.x * dx + p.y * dy) / cell
        local q = (p.x * nx + p.y * ny) / cell
        if a < alo then alo = a end
        if a > ahi then ahi = a end
        if q < plo then plo = q end
        if q > phi then phi = q end
    end
    return alo, ahi, plo, phi
end

--- One line of the pattern, as a list of points in the plate frame.
--
-- Follows Fill3DHoneycomb: along the line the points step a cell at a time, pulled in by
-- `off/2` at each end of the step; across it they alternate between +off/2 and -off/2, flipping
-- every cell. At off = 0 both collapse and the line comes out straight, which is the whole
-- point of the pattern.
local function line_points(k, alo, ahi, off, dx, dy, nx, ny, cell)
    local o2 = off / 2.0
    local pts = {}
    local function put(a, q)
        local ax, ay = a * cell, q * cell
        pts[#pts + 1] = {x = ax * dx + ay * nx, y = ax * dy + ay * ny}
    end
    local i0, i1 = math.floor(alo) - 1, math.ceil(ahi) + 1
    local side = (((k + i0) % 2) == 0) and 1.0 or -1.0
    put(i0 - math.abs(o2), k - o2 * side)
    for i = i0, i1 - 1 do
        side = ((((i + k) % 2) + 2) % 2 == 0) and 1.0 or -1.0
        put(i + math.abs(o2), k + o2 * side)
        put(i + 1 - math.abs(o2), k + o2 * side)
    end
    put(i1 + math.abs(o2), k - o2 * side)
    return pts
end

--- Lays out one surface.
-- @param surface table with role, layer_id, print_z, extruder_id, spacing, density,
--                bridge_angle, contour and holes.
-- @return a table of paths, or nil to keep the slicer's own pattern.
function plan_fill(surface)
    if half_period <= 0.0 then
        return nil
    end
    if not roles[surface.role] then
        return nil
    end
    if surface.layer_id < skip_first_layers then
        return nil
    end
    if surface.spacing <= 0.0 then
        return nil
    end

    -- `spacing` is the width of the bead, not the gap between the pattern's lines; the gap is
    -- that divided by the density, and that gap is the octahedron's cell.
    local density = surface.density
    if density == nil or density <= 0.0 or density > 1.0 then
        density = 1.0
    end
    local cell = surface.spacing / density

    local theta, off = shape_at(surface.print_z)
    local dx, dy = math.cos(theta), math.sin(theta)
    local nx, ny = -dy, dx
    local alo, ahi, plo, phi = extent(surface.contour, dx, dy, nx, ny, cell)
    if alo > ahi then
        return nil
    end

    local paths = {}
    for k = math.floor(plo) - 1, math.ceil(phi) + 1 do
        local pts = line_points(k, alo, ahi, off, dx, dy, nx, ny, cell)
        -- Alternate the direction so the head ends each line near the start of the next.
        if ((k % 2) + 2) % 2 == 1 then
            local rev = {}
            for i = #pts, 1, -1 do rev[#rev + 1] = pts[i] end
            pts = rev
        end
        paths[#paths + 1] = pts
    end
    if #paths == 0 then
        return nil
    end
    return paths
end
