-- Copyright (c) 2026 dzwiedziu-nkg
-- SPDX-License-Identifier: AGPL-3.0-only

-- Edit and slice again; no restart needed.
return {
    -- Which parts of the print that are not model objects become cancellable. The wipe
    -- tower is the only kind the slicer offers so far.
    labelled_regions = {wipe_tower = true},

    -- What to call them on the printer. Left unset, the slicer's own name is used, which
    -- is what you want unless the printer's display is too narrow for it.
    names = {
        -- wipe_tower = "Tower",
    },
}
