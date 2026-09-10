-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Edit and re-slice. The slicing plugin is loaded into a fresh Lua state per export.

return {
    -- "auto": Prusa XL docks are treated as rear-mounted; all other printers,
    -- including COREONE_INDX*, are treated as front-mounted.
    -- Explicit alternatives: "front" or "rear".
    dock_edge = "auto",

    -- Ignore accidental, short-lived splits. Each resulting branch must occur on at
    -- least this many layers before sequential printing is enabled.
    min_branch_layers = 3,

    -- Retraction wipe performed on the final extrusion path before changing branch.
    -- After the descent, the slicer additionally prints infill before perimeters.
    wipe_distance = 2.0,

    -- The nozzle rises by this amount before the high XY move over the next branch.
    z_clearance = 0.6,
}
