# Adjacent smooth and wispy clouds: class isolation

Replayed screenshot 2026-10-14 20-55-39: time 0, position
(66306.9, -1067.5, -23038.8), yaw -3.929, pitch -0.562, weather time 77.4.

The smooth pointed wedge is **cumulus (R)**. The two larger wispy foreground
clouds are **stratocumulus (G)**. Isolating R leaves only the wedge in the
foreground; isolating G removes the wedge and preserves the wispy clouds.
Stratus and storm contribute neither foreground subject. An independent
cloud-reflection toggle leaves the wedge unchanged, ruling out the ocean.

This is a different class combination from the earlier pair of screenshots,
whose two foreground subjects both survived G-only isolation. The earlier
shape/shading explanation was not a demonstrated cause for this new example.

- [All classes](adjacent-all.png)
- [Cumulus only: smooth wedge](adjacent-only_cumulus.png)
- [Stratocumulus only: wispy clouds](adjacent-only_stratocumulus.png)
- [Cumulus disabled](adjacent-without_cumulus.png)

Reproduce: `tools/run.sh --resolution 1280x720 --script res://tests/_probe/cloud_adjacent.gd`.
The probe changes only in-memory weather copies and does not save the planet.
