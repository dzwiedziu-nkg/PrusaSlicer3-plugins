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

function plan_islands(layers, ctx)
    local split_layer, labels = find_split(layers)
    if split_layer == nil then return nil end

    local steps = {}

    -- Common base remains ordinary layer-by-layer printing.
    for layer = 1, split_layer - 1 do
        steps[#steps + 1] = {
            layer = layer,
            islands = all_positions(#layers[layer].islands)
        }
    end

    -- Each root and all of its descendants are printed to completion.
    local roots = branch_order(layers, split_layer, ctx)
    for _, branch in ipairs(roots) do
        for layer = split_layer, #layers do
            local islands = {}
            for island, label in ipairs(labels[layer]) do
                if label == branch then islands[#islands + 1] = island end
            end
            if #islands > 0 then
                steps[#steps + 1] = {layer = layer, islands = islands}
            end
        end
    end

    return {
        steps = steps,
        wipe_distance = WIPE_DISTANCE,
        z_clearance = Z_CLEARANCE,
        split_layer = split_layer,
        branch_count = #roots
    }
end
