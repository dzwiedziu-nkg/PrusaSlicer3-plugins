-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Sequentially prints independent branches which split from a common object.
--
-- The slicer supplies its exact inter-layer overlap graph. This plugin labels every
-- descendant of each island at the split, then schedules one complete branch before
-- the next. It returns nil whenever that graph merges again, floats, or is too short
-- to be intentional. Returning nil preserves ordinary layer-by-layer printing.

info = {
    id = "sequential_islands",
    type = "slicing.island_sequence",
    title = "Sequential islands"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local MIN_BRANCH_LAYERS = settings.min_branch_layers or 3
local WIPE_DISTANCE = settings.wipe_distance or 2.0
local Z_CLEARANCE = settings.z_clearance or 0.6

local function printer_dock_edge(printer_model)
    local configured = settings.dock_edge or "auto"
    if configured == "front" or configured == "rear" then
        return configured
    end

    local model = string.upper(printer_model or "")
    if string.find(model, "XL", 1, true) then
        return "rear"
    end
    return "front"
end

local function all_positions(count)
    local result = {}
    for i = 1, count do result[i] = i end
    return result
end

local function reversed(values)
    local result = {}
    for i = #values, 1, -1 do result[#result + 1] = values[i] end
    return result
end

local function ranges_within(a_min, a_max, b_min, b_max, clearance)
    return a_max + clearance >= b_min and b_max + clearance >= a_min
end

-- Match the engine's implementation of PrusaSlicer's three-slice fallback
-- geometry for Original Prusa CORE One:
--   Z=0 mm: 10 x 10 mm nozzle footprint
--   Z=1 mm: clearance-radius square around the nozzle
--   Z=clearance height: X gantry, unlimited conservatively along X
local function head_intersects(target, target_z, obstacle, obstacle_z, ctx)
    local dz = obstacle_z - target_z
    if dz <= 0.000001 then return false end

    local clearance = dz < 1.0 and 5.0 or ctx.extruder_clearance_radius
    local a, b = target.bbox, obstacle.bbox
    if not ranges_within(a.min_y, a.max_y, b.min_y, b.max_y, clearance) then
        return false
    end
    if dz >= ctx.extruder_clearance_height then
        return true
    end
    return ranges_within(a.min_x, a.max_x, b.min_x, b.max_x, clearance)
end

local function schedule_is_safe(steps, layers, ctx)
    if ctx.collision_model ~= "coreone_fallback_v1" then return true end

    local emitted = {}
    for _, step in ipairs(steps) do
        local layer = layers[step.layer]
        for _, island_index in ipairs(step.islands) do
            local target = layer.islands[island_index]
            for _, previous in ipairs(emitted) do
                if head_intersects(
                    target, layer.print_z,
                    previous.island, previous.print_z,
                    ctx
                ) then
                    return false
                end
            end
            emitted[#emitted + 1] = {
                island = target,
                print_z = layer.print_z
            }
        end
    end
    return true
end

-- Labels all islands from split_layer upwards with the root branch they descend
-- from. A merge across two roots or a floating island is unsafe and rejects this
-- candidate split.
local function label_branches(layers, split_layer)
    local branch_count = #layers[split_layer].islands
    local labels = {}
    local seen_layers = {}

    labels[split_layer] = {}
    for island = 1, branch_count do
        labels[split_layer][island] = island
        seen_layers[island] = 1
    end

    for layer = split_layer + 1, #layers do
        labels[layer] = {}
        local present = {}

        for island, info in ipairs(layers[layer].islands) do
            local inherited = nil
            for _, below in ipairs(info.overlaps_below) do
                local branch = labels[layer - 1][below]
                if branch == nil then return nil end
                if inherited ~= nil and inherited ~= branch then
                    -- Two completed branches would have to meet again.
                    return nil
                end
                inherited = branch
            end
            if inherited == nil then
                -- An island appearing in mid-air is not a supported branch.
                return nil
            end
            labels[layer][island] = inherited
            present[inherited] = true
        end

        for branch in pairs(present) do
            seen_layers[branch] = seen_layers[branch] + 1
        end
    end

    for branch = 1, branch_count do
        if seen_layers[branch] < MIN_BRANCH_LAYERS then return nil end
    end
    return labels
end

local function find_split(layers)
    for layer = 2, #layers do
        if #layers[layer - 1].islands == 1 and #layers[layer].islands >= 2 then
            local labels = label_branches(layers, layer)
            if labels ~= nil then return layer, labels end
        end
    end
    return nil, nil
end

local function branch_order(layers, split_layer, ctx)
    local roots = layers[split_layer].islands
    local order = all_positions(#roots)
    local dock_edge = printer_dock_edge(ctx.printer_model)

    table.sort(order, function(a, b)
        local ay, by = roots[a].centroid.y, roots[b].centroid.y
        if ay ~= by then
            -- Far side first: high Y for a front dock, low Y for a rear dock.
            return dock_edge == "front" and ay > by or dock_edge == "rear" and ay < by
        end
        local ax, bx = roots[a].centroid.x, roots[b].centroid.x
        if ax ~= bx then return ax < bx end
        return a < b
    end)
    return order
end

local function append_common_layers(steps, layers, split_layer)
    for layer = 1, split_layer - 1 do
        steps[#steps + 1] = {
            layer = layer,
            islands = all_positions(#layers[layer].islands)
        }
    end
end

local function append_branch_range(steps, labels, order, first_layer, last_layer)
    for _, branch in ipairs(order) do
        for layer = first_layer, last_layer do
            local islands = {}
            for island, label in ipairs(labels[layer]) do
                if label == branch then islands[#islands + 1] = island end
            end
            if #islands > 0 then
                steps[#steps + 1] = {layer = layer, islands = islands}
            end
        end
    end
end

local function full_schedule(layers, labels, split_layer, order)
    local steps = {}
    append_common_layers(steps, layers, split_layer)
    append_branch_range(steps, labels, order, split_layer, #layers)
    return steps
end

local function range_schedule(labels, order, first_layer, last_layer)
    local steps = {}
    append_branch_range(steps, labels, order, first_layer, last_layer)
    return steps
end

local function result(steps, split_layer, branch_count, mode, party_count)
    return {
        steps = steps,
        wipe_distance = WIPE_DISTANCE,
        z_clearance = Z_CLEARANCE,
        split_layer = split_layer,
        branch_count = branch_count,
        collision_strategy = mode,
        party_count = party_count
    }
end

function plan_islands(layers, ctx)
    local split_layer, labels = find_split(layers)
    if split_layer == nil then return nil end

    local roots = branch_order(layers, split_layer, ctx)
    local default_steps = full_schedule(layers, labels, split_layer, roots)
    if schedule_is_safe(default_steps, layers, ctx) then
        return result(default_steps, split_layer, #roots, "default", 1)
    end

    -- A completed branch is an obstacle only for branches printed after it. Before
    -- giving up on full-height sequencing, try the opposite side first.
    local reverse_roots = reversed(roots)
    local reverse_steps = full_schedule(layers, labels, split_layer, reverse_roots)
    if schedule_is_safe(reverse_steps, layers, ctx) then
        return result(reverse_steps, split_layer, #roots, "reversed", 1)
    end

    -- Neither complete ordering is possible. Greedily grow the tallest safe
    -- horizontal band ("party"), trying the preferred and reversed order for every
    -- candidate height. Previous parties end below the next party's first layer, so
    -- only the geometry emitted inside the candidate band can obstruct it.
    local steps = {}
    append_common_layers(steps, layers, split_layer)
    local first_layer = split_layer
    local party_count = 0

    while first_layer <= #layers do
        local best_last = nil
        local best_order = nil

        for last_layer = first_layer, #layers do
            local preferred = range_schedule(labels, roots, first_layer, last_layer)
            if schedule_is_safe(preferred, layers, ctx) then
                best_last, best_order = last_layer, roots
            else
                local alternate = range_schedule(
                    labels, reverse_roots, first_layer, last_layer
                )
                if schedule_is_safe(alternate, layers, ctx) then
                    best_last, best_order = last_layer, reverse_roots
                else
                    -- The unsafe schedule remains a prefix of every taller band.
                    break
                end
            end
        end

        if best_last == nil then return nil end
        append_branch_range(steps, labels, best_order, first_layer, best_last)
        party_count = party_count + 1
        first_layer = best_last + 1
    end

    return result(steps, split_layer, #roots, "partitioned", party_count)
end
