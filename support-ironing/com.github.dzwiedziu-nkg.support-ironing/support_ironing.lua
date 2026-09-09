-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Irons the top of a support interface flat before the object is printed against it.
--
-- The underside of an overhang is an imprint of whatever it was printed on. A support
-- interface is a row of parallel extrusions with a ridge between every pair of them, and
-- the object's first layer copies those ridges - which is why a supported underside comes
-- out corrugated even when everything else about the print is right.
--
-- This runs the nozzle back over the interface at the same height, across the direction
-- the interface lines run in, extruding a fraction of a layer. The ridges melt down and
-- the object is cast against a flat surface instead.
--
-- Bambu Studio added this in 2.5.0 as Support Interface Ironing; OrcaSlicer has it as
-- `support_ironing`. PrusaSlicer irons top surfaces only, so the pass itself is new here.
--
-- It costs print time and nothing else: the pass is at `ironing_speed`, over the interface
-- area only, and only where something is going to be printed on top.

info = {
    id = "support_ironing",
    type = "slicing.pass_planner",
    title = "Support interface ironing"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local spacing = settings.spacing or 0.1
local flow_ratio = settings.flow_ratio == nil and 0.15 or settings.flow_ratio
local angle_offset = settings.angle_offset == nil and 45.0 or settings.angle_offset
local angle_absolute = settings.angle
local object_facing_only = settings.object_facing_only == nil and true
    or settings.object_facing_only
local min_area = settings.min_area == nil and 1.0 or settings.min_area
local min_length = settings.min_length == nil and 0.5 or settings.min_length
local inset = settings.inset or 0.0

local DEG = math.pi / 180.0

-- The roles a support surface is filled with. With `support_material_interface_layers`
-- set to 0 the contact layer is filled as plain support, and the object still rests on it.
local IRONABLE_ROLES = {
    SupportMaterialInterface = true,
    SupportMaterial = true
}

--- Area of a closed contour, signed by winding direction.
local function contour_area(contour)
    local area = 0.0
    local n = #contour
    for i = 1, n do
        local a = contour[i]
        local b = contour[i % n + 1]
        area = area + (a.x * b.y - b.x * a.y)
    end
    return area * 0.5
end

--- Area enclosed by a contour with its holes taken out.
local function net_area(surface)
    local area = math.abs(contour_area(surface.contour))
    for _, hole in ipairs(surface.holes) do
        area = area - math.abs(contour_area(hole))
    end
    return area
end

--- Every edge of the region, contour and holes alike, in the frame the scan runs in.
--
-- Rotating the region so the ironing lines are horizontal turns clipping into sorting
-- numbers on a line, which is the whole reason for doing it this way round.
local function rotated_edges(surface, cos_a, sin_a)
    local edges = {}
    local min_y, max_y = math.huge, -math.huge

    local function add(contour)
        local n = #contour
        if n < 3 then return end
        local previous = nil
        for i = 1, n + 1 do
            local p = contour[i > n and 1 or i]
            local q = {x = p.x * cos_a + p.y * sin_a, y = -p.x * sin_a + p.y * cos_a}
            if q.y < min_y then min_y = q.y end
            if q.y > max_y then max_y = q.y end
            if previous ~= nil then
                edges[#edges + 1] = {a = previous, b = q}
            end
            previous = q
        end
    end

    add(surface.contour)
    for _, hole in ipairs(surface.holes) do
        add(hole)
    end
    return edges, min_y, max_y
end

--- The spans of one scan line that fall inside the region, as {from, to} pairs of x.
local function spans_at(edges, y)
    local crossings = {}
    for _, edge in ipairs(edges) do
        local a, b = edge.a, edge.b
        -- Half open in y, so a vertex shared by two edges is counted once.
        if (a.y <= y and b.y > y) or (b.y <= y and a.y > y) then
            crossings[#crossings + 1] = a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)
        end
    end
    table.sort(crossings)

    local spans = {}
    for i = 1, #crossings - 1, 2 do
        local from, to = crossings[i] + inset, crossings[i + 1] - inset
        if to - from >= min_length then
            spans[#spans + 1] = {from = from, to = to}
        end
    end
    return spans
end

function plan_pass(surface)
    if object_facing_only and not surface.object_above then
        -- Nothing will be printed onto this one, so there is no mould to smooth.
        return nil
    end
    if not IRONABLE_ROLES[surface.role] then
        return nil
    end
    if spacing <= 0.0 or #surface.contour < 3 then
        return nil
    end
    if min_area > 0.0 and net_area(surface) < min_area then
        -- Too small to be worth the extra pass and the travel to reach it.
        return nil
    end

    -- Cross the interface lines rather than retrace them: a pass along the ridges rides in
    -- the valley between two of them and flattens neither.
    local angle = angle_absolute ~= nil and angle_absolute * DEG
        or surface.angle + angle_offset * DEG
    local cos_a, sin_a = math.cos(angle), math.sin(angle)

    local edges, min_y, max_y = rotated_edges(surface, cos_a, sin_a)
    if #edges == 0 then
        return nil
    end

    local paths = {}
    -- Half a spacing in from the first edge, so the outermost line is not exactly on it.
    local y = min_y + spacing * 0.5
    local flip = false
    while y < max_y do
        for _, span in ipairs(spans_at(edges, y)) do
            local from, to = span.from, span.to
            if flip then
                from, to = to, from
            end
            -- Back into the object frame.
            paths[#paths + 1] = {
                {x = from * cos_a - y * sin_a, y = from * sin_a + y * cos_a},
                {x = to * cos_a - y * sin_a, y = to * sin_a + y * cos_a}
            }
        end
        -- Alternate direction so the nozzle walks up the surface instead of flying back to
        -- the same side for every line.
        flip = not flip
        y = y + spacing
    end

    if #paths == 0 then
        return nil
    end
    return {paths = paths, spacing = spacing, flow_ratio = flow_ratio}
end
