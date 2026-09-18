-- Settings for the bridge-counterbore-hole plugin.
--
-- Edit and slice again; there is no restart and no rescan. This file is loaded inside a
-- `pcall`, so a syntax error in it is reported nowhere: the file is ignored and the defaults
-- below apply. That is the first thing to suspect when a setting appears to do nothing.

return {
    -- Set to false to turn the plugin off without removing it.
    enabled = true,

    -- Which of OrcaSlicer's two modes to use.
    --
    -- "sacrificial"  Close the hole for the one layer where the opening narrows. The whole
    --                opening is bridged in a single span, nothing is left suspended in it, and
    --                **the disc has to be drilled or pushed out afterwards**. OrcaSlicer's
    --                `sacrificiallayer`.
    --
    -- "partial"      Leave the hole open and stop the wall being drawn round it in mid-air.
    --                The unsupported ring is cut out of the perimeter stage, with a band of
    --                held-up material beside it to anchor the bridge on, and handed to the
    --                fill. Nothing has to be drilled out; the hole's wall is missing on that
    --                one layer. OrcaSlicer's `partiallybridge`.
    --
    -- "off"          Neither, which is the stock slicer: the ring is bridged and its wall is
    --                printed in mid-air.
    --
    -- The two modes are alternatives and cannot be combined: closing the hole leaves no wall
    -- for the other mode to remove.
    --
    -- "partial" is the default because it needs nothing done to the part afterwards.
    mode = "partial",

    -- The largest opening that may be closed, in mm, measured as the largest disc that fits
    -- inside it.
    --
    -- **This is the whole of the safety and 0 does not mean "no limit" here**, unlike the other
    -- plugins on this extension point - it means the same as everywhere else, no limit, and
    -- that is the wrong thing to ask for. A sacrificial layer across a 30 mm bore is a disc
    -- somebody has to cut out of the middle of a part.
    --
    -- 10 mm covers a screw counterbore, which is what this is for. A hole wider than this is
    -- left to the slicer, which bridges the ring round it and prints its wall in mid-air, as it
    -- always did.
    max_hole = 10.0,

    -- How far a hole's rim has to hang over air before the hole is closed, as an angle.
    --
    -- PrusaSlicer's convention, the one `support_material_threshold` uses: 90 is vertical and
    -- the number is the most horizontal slope printable without support. The rim is measured
    -- `layer_height / tan(angle)` wide - 0.286 mm at 35 degrees and 0.2 mm layers - and most of
    -- that band has to be over air for the hole to count.
    --
    -- This is what keeps an ordinary hole alone: a hole going straight down has a rim resting
    -- on the layer below, and so does a bore that tapers gently. Lower the angle to catch
    -- gentler steps, raise it to catch only the sharp ones.
    angle = 35,

    -- Only for `mode = "partial"`.
    --
    -- The largest piece that may be taken off the layer's outline, in mm, as the largest disc
    -- that fits inside it.
    --
    -- A ring cannot be bridged all the way round: the two lobes beside the hole are crossed by
    -- no straight line that is held at both ends, so nothing is laid there. They are taken off
    -- the outline as well, because the layer above reads the outline to know what it has to
    -- rest on, and left in place it lays solid infill over the gap believing it solid.
    --
    -- 6 mm suits a screw counterbore, where the lobes are a few millimetres across. A piece
    -- bigger than this is left alone, because this removes material from the part.
    max_trimmed = 6.0,

    -- Leave everything below this height alone, in mm. 0 acts everywhere.
    min_z = 0.0,

    -- Only for `mode = "partial"`.
    --
    -- How far the fill may reach into held-up material for the bridge to be anchored on, in mm.
    --
    -- 1.0 by default, which is what it takes to anchor the bridge the way the slicer anchors an
    -- ordinary one. Measured on the Ø12 counterbore: the bridge reaches 0.22 mm past the
    -- unsupported ring at 0.45, and 0.65 mm at 1.0 - against the 0.63 mm a stock bridge gets.
    -- **Above 1.0 nothing more happens**, because from there it is the slicer's own bridge
    -- expansion that sets the overlap, not the room this leaves it; all a bigger number buys is
    -- a wider band of wall moved out of the way for nothing.
    --
    -- 0 asks the slicer for one perimeter spacing, which is 0.45 on a 0.4 nozzle and is
    -- OrcaSlicer's answer. It is thinner than an ordinary bridge's anchor, which is why it is
    -- not the default here.
    anchor = 1.0,

    -- Only for `mode = "partial"`.
    --
    -- Ignore unsupported pieces narrower than this, in mm. 0 asks the slicer for its own
    -- answer, which is one perimeter spacing. Without it every sliver along a sloping face
    -- would be cut out of the wall stage.
    min_unsupported = 0.0
}
