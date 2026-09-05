-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Puts the wipe tower on the list of objects the printer can cancel during a print.
--
-- The slicer writes that list out of the model objects only, so the tower belongs to no
-- object and the firmware has nothing to offer when you want it gone. Cancel the last
-- object that needed two filaments and the tower carries on being built, by itself, for
-- whatever was left of the print.
--
-- Naming it is all this plugin does. The slicer owns the syntax: the tower is defined in
-- the same header, in the same dialect, and its label is opened and closed around its
-- extrusions with the tool changes deliberately left outside, so cancelling it can never
-- swallow a T command.

info = {
    id = "wipe_tower_cancel",
    type = "slicing.object_labels",
    title = "Cancellable wipe tower"
}

local ok, user_settings = pcall(require, "settings")
local settings = (ok and type(user_settings) == "table") and user_settings or {}

local labelled = settings.labelled_regions or {wipe_tower = true}
local names = settings.names or {}

--- Entry point, called once per export for each part of the print that is not an object.
-- @param region {kind, default_name, outline = {{x, y}, ...}}  -- mm
-- @return the name to make it cancellable under, or nil to leave it as the slicer had it
function label_region(region)
    if not labelled[region.kind] then
        return nil
    end
    return names[region.kind] or region.default_name
end
