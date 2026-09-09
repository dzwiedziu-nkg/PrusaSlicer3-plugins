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

--- Groups the scan lines into runs the nozzle can walk without leaving the surface.
--
-- A notch or a hole splits a scan line into several spans, and a pass that simply emitted
-- them line by line would fly across the hole twice per line. Two spans on neighbouring
-- lines belong to the same run when they overlap in x; where they stop overlapping the
-- surface has divided and a new run starts. Measured on the notched test model this is the
-- difference between 11.5 m of travel with 481 retractions and 0.1 m with none.
local function build_runs(lines)
    local runs = {}
    local open = {}
    for _, line in ipairs(lines) do
        local next_open = {}
        for _, span in ipairs(line.spans) do
            local index = nil
            for _, previous in ipairs(open) do
                if not previous.taken
                    and previous.span.to > span.from and span.to > previous.span.from then
                    index = previous.run
                    previous.taken = true
                    break
                end
            end
            if index == nil then
                runs[#runs + 1] = {}
                index = #runs
            end
            local run = runs[index]
            run[#run + 1] = {y = line.y, from = span.from, to = span.to}
            next_open[#next_open + 1] = {span = span, run = index}
        end
        open = next_open
    end
    return runs
end

--- The four points a run can be entered at: either end, walked either way.
local function entries(run)
    local last = #run
    return {
        {up = true,  at_from = true,  x = run[1].from,    y = run[1].y},
        {up = true,  at_from = false, x = run[1].to,      y = run[1].y},
        {up = false, at_from = true,  x = run[last].from, y = run[last].y},
        {up = false, at_from = false, x = run[last].to,   y = run[last].y}
    }
end

--- Walks one run from the given entry, alternating direction line by line.
local function walk(run, entry, cos_a, sin_a, paths)
    local n = #run
    local flip = not entry.at_from
    for i = 1, n do
        local seg = run[entry.up and i or (n - i + 1)]
        local from, to = seg.from, seg.to
        if flip then
            from, to = to, from
        end
        -- Back into the object frame.
        paths[#paths + 1] = {
            {x = from * cos_a - seg.y * sin_a, y = from * sin_a + seg.y * cos_a},
            {x = to * cos_a - seg.y * sin_a,   y = to * sin_a + seg.y * cos_a}
        }
        flip = not flip
    end
    local last = run[entry.up and n or 1]
    return flip and last.from or last.to, last.y
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

    -- Half a spacing in from the first edge, so the outermost line is not exactly on it.
    local lines = {}
    local y = min_y + spacing * 0.5
    while y < max_y do
        local spans = spans_at(edges, y)
        if #spans > 0 then
            lines[#lines + 1] = {y = y, spans = spans}
        end
        y = y + spacing
    end

    local runs = build_runs(lines)
    if #runs == 0 then
        return nil
    end

    -- Take the runs nearest first, entering each at whichever of its four ends is closest.
    -- The engine keeps the order a pass comes back in, so this is the only chance to get it
    -- right: nothing downstream will chain these for us.
    local paths = {}
    local at_x, at_y = lines[1].spans[1].from, lines[1].y
    local remaining = #runs
    local done = {}
    while remaining > 0 do
        local best, best_run, best_distance = nil, nil, math.huge
        for index, run in ipairs(runs) do
            if not done[index] then
                for _, entry in ipairs(entries(run)) do
                    local dx, dy = entry.x - at_x, entry.y - at_y
                    local distance = dx * dx + dy * dy
                    if distance < best_distance then
                        best_distance, best, best_run = distance, entry, index
                    end
                end
            end
        end
        at_x, at_y = walk(runs[best_run], best, cos_a, sin_a, paths)
        done[best_run] = true
        remaining = remaining - 1
    end

    if #paths == 0 then
        return nil
    end
    return {paths = paths, spacing = spacing, flow_ratio = flow_ratio}
end
