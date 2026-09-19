-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Prints the deck before the wall that runs past it.
--
-- The other half of this bundle thins the solid infill at the transition, which is the half of
-- Prusa's experiment a fill planner can do. This is the half they thought did the work:
-- **printing the deck before the rest of the layer**, so the hull's wall is not laid straight
-- after the mass of solid beside it.
--
-- It is also the half that needs to know *which* layer the deck starts on, and that is why it
-- is a layer planner rather than a fill planner. This extension point is reached from the
-- serialized G-code stage, one layer at a time and in order, so the plugin can carry a running
-- picture of the part from one layer to the next and notice where it changes. A fill planner is
-- asked about every layer at once and can never know.
--
-- The rule is the signature Prusa describe and this repository measured: a layer that carries
-- real solid infill where the layers below it carried almost none, with the wall running
-- through unchanged.

info = {
    id = "hull_line_order",
    type = "slicing.layer_planner",
    title = "Hull line, the order"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local enabled = settings.order ~= false
local min_solid = settings.min_solid == nil and 1.0 or settings.min_solid
local window = settings.window == nil and 5 or settings.window
local depth = settings.depth == nil and 3 or settings.depth
local require_wall = settings.require_wall ~= false

-- What counts as the deck: the roles a solid layer is laid with. Ironing and gap fill are not
-- here, and neither is TopSolidInfill - a top surface is solid because it is the outside of the
-- part, which is not the change this is looking for.
local SOLID_ROLES = {"SolidInfill", "BridgeInfill"}

-- What the layers below carried, one entry per layer, newest last. The plugin is called in
-- layer order, which is the whole reason this can be kept at all.
local history = {}
-- Inside a transition: this layer and the ones after it are reordered until the deck ends.
local running = false
-- Layers of the minimum run still owed, this one included.
local layers_left = 0
local last_layer = -1
-- Solid volume of the layer being described, summed over the pieces it falls into.
local carried = 0.0

--- Median of the last `window` layers, or nil while fewer than that have gone by.
local function baseline()
    -- Nothing to compare against yet, and that is an answer rather than a zero: a part that
    -- starts solid on the bed is not a transition. A hull line is a mark on a wall that runs
    -- past the change, and at the bottom of a part there is no wall below it to be marked.
    if #history < window then
        return nil
    end

    local recent = {}
    for i = #history - window + 1, #history do
        recent[#recent + 1] = history[i]
    end
    table.sort(recent)
    return recent[math.ceil(#recent / 2)]
end

--- Decides the order this layer's groups are printed in.
-- @param layer table with layer_id, print_z, extruder_id and groups, each carrying island,
--              kind, role, length, volume, bbox and roles - the last being what every role in
--              the group contributes, keyed by name, which is what the deck is detected from.
-- @return a list of positions into layer.groups, or nil to keep the slicer's order.
function plan_layer(layer)
    if not enabled then
        return nil
    end

    -- Per role, not per group. Where a deck starts inside a part its solid infill and the
    -- sparse infill round it are one region's worth of fill and therefore one group, and the
    -- sparse is the longer of the two - so a rule reading the group's dominant role sees no
    -- solid at all on the very layer it is looking for.
    local solid, wall = 0.0, 0.0
    for _, group in ipairs(layer.groups) do
        if group.kind == "perimeters" then
            wall = wall + group.length
        else
            for _, name in ipairs(SOLID_ROLES) do
                local share = group.roles[name]
                if share ~= nil then
                    solid = solid + share.volume
                end
            end
        end
    end

    -- A layer is planned once per piece it falls into - two islands, or two objects of the
    -- same height - so a new layer_id, not a new call, is what banks a layer and spends one of
    -- the layers a transition asked for. Counting calls would give a two-island part half the
    -- depth it asked for and twice the history.
    if layer.layer_id ~= last_layer then
        if last_layer >= 0 then
            history[#history + 1] = carried
            -- The run follows the deck, not a counter. It ends on the first layer after the
            -- one that stopped carrying `min_solid` of solid infill, once the minimum run is
            -- spent - a deck is as many layers thick as the part makes it, and stopping in the
            -- middle of one leaves the wall laid after the mass on exactly the layers the
            -- reordering was meant for.
            if running and layers_left <= 0 and carried < min_solid then
                running = false
            end
        end
        carried = 0.0
        if layers_left > 0 then
            layers_left = layers_left - 1
        end
        last_layer = layer.layer_id
    end
    carried = carried + solid

    if not running then
        local before = baseline()
        -- The deck: real solid infill where the layers below carried almost none. A ratio
        -- rather than a difference, because "almost none" is what the layers below have and a
        -- difference would need a scale nobody can name for every part.
        if before ~= nil and solid >= min_solid and before < solid * 0.5
            and (wall > 0.0 or not require_wall) then
            running = true
            layers_left = depth
        end
    end

    if not running then
        return nil
    end

    -- The deck first, then whatever else fills the layer, then the walls. With a modifier mesh
    -- splitting the deck from the hull - which is how Prusa did it - the deck's own walls are a
    -- group of their own and come first of all, which is their order exactly.
    local solid_fill, other_fill, walls = {}, {}, {}
    for i, group in ipairs(layer.groups) do
        if group.kind == "perimeters" then
            walls[#walls + 1] = i
        elseif group.role == "SolidInfill" or group.role == "BridgeInfill" then
            -- By the dominant role here, deliberately: a group is moved whole, so what decides
            -- where it goes is what most of it is. A run that is mostly sparse with a patch of
            -- solid inside it is sparse for this purpose, and stays where the slicer put it.
            solid_fill[#solid_fill + 1] = i
        else
            other_fill[#other_fill + 1] = i
        end
    end

    local order = {}
    for _, list in ipairs({solid_fill, other_fill, walls}) do
        for _, i in ipairs(list) do
            order[#order + 1] = i
        end
    end
    return order
end
