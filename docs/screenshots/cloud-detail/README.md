# Stratocumulus detail diagnosis

Replayed the two reported poses with only stratocumulus enabled. Compared
normal 40 km detail range, forced full detail (10,000 km range), and no detail
(0.001 km range), settling each variant for 60 frames.

A CPU trace into each foreground subject at screen UV (0.5, 0.42), using
20 m steps and density threshold 0.02, found cloud at approximately 2.50 km
(chunky) and 2.90 km (natural). Both are well inside the 20 km start of detail
fading. Weather G at those samples was 0.5826 and 0.5812 respectively.

Full detail leaves the chunky foreground smooth; removing detail makes both
views dramatically smoother and thicker. Distance fading is therefore not
the cause of the difference between these foreground subjects.

The remaining explanation from the field implementation is coarse shape and
optical thickness, emphasized by viewing direction and lighting. Stratocumulus
uses a smooth, vertically stretched cell field with a height profile. Erosion
subtracts detail but renormalizes the remaining density: (density - erosion) /
(1 - erosion). At density 1 this stays 1 regardless of erosion. Thick interiors
therefore retain solid cores, and sun shadows sample the coarse field rather
than the eroded detail. These mechanisms favour smooth slab-like sides even
where thinner margins or top-facing views reveal irregular erosion. Their
individual contributions have not been separately ablated in this probe.

| Detail | Chunky | Natural |
| --- | --- | --- |
| Normal | [Image](chunky-normal.png) | [Image](natural-normal.png) |
| Full | [Image](chunky-full_detail.png) | [Image](natural-full_detail.png) |
| None | [Image](chunky-no_detail.png) | [Image](natural-no_detail.png) |

Reproduce: `tools/run.sh --resolution 1280x720 --script res://tests/_probe/cloud_detail.gd`.
Only in-memory weather copies and diagnostic settings change; nothing is saved.
