# Cloud class isolation — 2026-10-14

Both foreground subjects are **stratocumulus (weather G)**. They remain with
only G enabled and disappear with G disabled. The overhead anvil in the
chunky view is **storm (weather A)**. Cumulus contributes distant clouds;
stratus does not produce either subject.

Replayed both supplied HUD poses at time 3150 with weather frozen at 167.4
(chunky) and 154.9 (natural). Each variant masks channels of an in-memory copy
of the saved weather image, resets temporal history, and settles for 60 frames.
Saved weather and production rendering are unchanged. Captures: 1280 × 720.
This identifies the formation, not the cause of the surface-detail difference.

Run: `tools/run.sh --resolution 1280x720 --script res://tests/_probe/cloud_classes.gd`

| Toggle | Chunky view | Natural view |
| --- | --- | --- |
| all | [Image](chunky-all.png) | [Image](natural-all.png) |
| none | [Image](chunky-none.png) | [Image](natural-none.png) |
| only cumulus | [Image](chunky-only_cumulus.png) | [Image](natural-only_cumulus.png) |
| without cumulus | [Image](chunky-without_cumulus.png) | [Image](natural-without_cumulus.png) |
| only stratocumulus | [Image](chunky-only_stratocumulus.png) | [Image](natural-only_stratocumulus.png) |
| without stratocumulus | [Image](chunky-without_stratocumulus.png) | [Image](natural-without_stratocumulus.png) |
| only stratus | [Image](chunky-only_stratus.png) | [Image](natural-only_stratus.png) |
| without stratus | [Image](chunky-without_stratus.png) | [Image](natural-without_stratus.png) |
| only storm | [Image](chunky-only_storm.png) | [Image](natural-only_storm.png) |
| without storm | [Image](chunky-without_storm.png) | [Image](natural-without_storm.png) |
