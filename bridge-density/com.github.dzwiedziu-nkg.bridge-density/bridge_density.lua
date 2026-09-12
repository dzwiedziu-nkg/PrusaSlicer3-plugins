-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Spaces bridge lines by the bead the nozzle actually lays.
--
-- A bridge line extruded into mid-air is a cylinder of roughly the nozzle diameter. It is not
-- the flattened discorectangle a line printed onto solid plastic becomes, because there is
-- nothing under it to flatten against. The slicer knows this - `Flow::mm3_per_mm()` uses the
-- area of a circle for a bridge - but it then spaces the lines by
--
--     Flow::bridge_extrusion_spacing(d) = d + BRIDGE_EXTRA_SPACING      -- 0.05 mm
--
-- so consecutive strands are laid an eighth of a bead apart at a 0.4 nozzle and never touch.
-- Measured on a stock slice: bead 0.402 mm, line spacing 0.453 mm, gap 0.051 mm. Each strand
-- spans the gap alone, and a strand alone sags.
--
-- This lays them at the bead diameter instead, or closer, so they touch along their length and
-- hold each other up. The flow is left alone, so each strand is the same strand - there is just
-- less air between them, which is what "bridge density above 100 %" means.
--
-- The direction is the slicer's own `bridge_angle`. That choice is made from the shape of the
-- opening and the anchors available, and it is not this plugin's business to second-guess it.

info = {
    id = "bridge_density",
    type = "slicing.fill_planner"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local overlap = settings.overlap == nil and 0.0 or settings.overlap
local extra_spacing = settings.extra_spacing == nil and 0.05 or settings.extra_spacing
local match_stock_material = settings.match_stock_material == true
local roles = settings.roles == nil and {BridgeInfill = true} or settings.roles
local max_lines = settings.max_lines == nil and 4000 or settings.max_lines

--- Signed area of a closed contour, in mm2.
local function contour_area(points)
    local n = #points
    if n < 3 then
        return 0.0
    end
    local a = 0.0
    local j = n
    for i = 1, n do
        a = a + (points[j].x + points[i].x) * (points[j].y - points[i].y)
        j = i
    end
    return math.abs(a) * 0.5
end

--- Area the fill has to cover: the contour less its holes.
local function surface_area(surface)
    local a = contour_area(surface.contour)
    if surface.holes ~= nil then
        for _, hole in ipairs(surface.holes) do
            a = a - contour_area(hole)
        end
    end
    return a
end

local function polyline_length(path)
    local total = 0.0
    for i = 2, #path do
        local dx = path[i].x - path[i - 1].x
        local dy = path[i].y - path[i - 1].y
        total = total + math.sqrt(dx * dx + dy * dy)
    end
    return total
end

--- Parallel lines at `step` across the surface, running along `theta`.
-- Laid out from the plate origin so neighbouring surfaces of a layer share the same lines, and
-- walked alternately so the head ends each one near the start of the next.
local function lines_at(points, theta, step)
    local dx, dy = math.cos(theta), math.sin(theta)
    local nx, ny = -dy, dx
    local alo, ahi, plo, phi = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(points) do
        local a = p.x * dx + p.y * dy
        local q = p.x * nx + p.y * ny
        if a < alo then alo = a end
        if a > ahi then ahi = a end
        if q < plo then plo = q end
        if q > phi then phi = q end
    end
    if plo > phi then
        return nil
    end

    local first = math.ceil(plo / step)
    local last = math.floor(phi / step)
    if last - first + 1 > max_lines then
        return nil
    end

    local paths = {}
    for k = first, last do
        local d = k * step
        local px, py = d * nx, d * ny
        local a, b = alo - step, ahi + step
        if ((k % 2) + 2) % 2 == 1 then a, b = b, a end
        paths[#paths + 1] = {
            {x = px + a * dx, y = py + a * dy},
            {x = px + b * dx, y = py + b * dy}
        }
    end
    if #paths == 0 then
        return nil
    end
    return paths
end

--- Lays out one surface.
-- @param surface table with role, layer_id, print_z, extruder_id, spacing, density,
--                bridge_angle, contour and holes.
-- @return a table of paths, or nil to keep the slicer's own pattern.
function plan_fill(surface)
    if not roles[surface.role] then
        return nil
    end
    -- Negative means the slicer did not treat this as a bridge, so there is no direction to
    -- follow and no cylinder to space by.
    if surface.bridge_angle == nil or surface.bridge_angle < 0.0 then
        return nil
    end
    if surface.spacing <= 0.0 then
        return nil
    end

    -- What the slicer hands over for a bridge is the bead diameter plus the gap it inserts on
    -- purpose. Take the gap back out and that is the bead.
    local bead = surface.spacing - extra_spacing
    if bead <= 0.0 then
        return nil
    end
    local step = bead * (1.0 - overlap)
    if step <= 0.0 then
        return nil
    end
    -- Nothing to do if the slicer was already going to lay them this close or closer.
    if step >= surface.spacing then
        return nil
    end

    local paths = lines_at(surface.contour, surface.bridge_angle, step)
    if paths == nil then
        return nil
    end

    if not match_stock_material then
        return paths
    end

    -- The stock pattern would have covered this area with lines `spacing` apart, so it lays
    -- area/spacing of line. Scaling by the ratio of the two lengths puts the same volume of
    -- plastic on the surface, spread over more strands.
    local laid = 0.0
    for _, path in ipairs(paths) do
        laid = laid + polyline_length(path)
    end
    local wanted = surface_area(surface) / surface.spacing
    if laid <= 1e-9 or wanted <= 0.0 then
        return paths
    end
    return {paths = paths, flow_ratio = wanted / laid}
end
