# Gyro–1 reaction wheel

An original 3D part based on the supplied white, dark-metal and orange concept.
Matches the Atlas–1 decoupler's mounting diameter and nominal 20 cm stack height.
The model has segmented white panels, orange concentric rotor rings, eight metal
spokes on each face, and four controller housings with orange direction markers.

In the workshop, drag **Gyro–1 reaction wheel** below the capsule decoupler
(or below the capsule when no decoupler is fitted). Additional rings stack above
the fuel tanks. Each ring adds **50 kg**, **650 credits** and **12 kN·m** of torque
on each axis. Pitch, yaw and roll use the existing controls; no stage activation
or propellant is required. The simulation adds torque before dividing by craft
inertia, so the effect depends on vehicle mass and geometry. The angular-speed
limit increases by 0.5 rad/s per wheel above the existing 1 rad/s limit.
Place a stack decoupler beneath a gyro to release the lower stack while keeping
the gyro and its torque with the capsule. A decoupler above the gyro discards it.
The gyro and Atlas ring retain full mesh detail at all zoom levels; automatic
simplification of their tightly layered faces caused dark surface artifacts.

Available in the in-game Asset Viewer and standalone turntable:

```sh
./tools/run.sh res://scenes/gyro_1_preview.tscn
```

Rebuild the GLB, import it, and bake its large-craft mesh:

```sh
python3 tools/build_gyro_1.py
./tools/run.sh --headless --editor --quit
./tools/run.sh --headless --script res://tools/bake_vehicle_visuals.gd -- gyro_1
```

Run `tests/test_reaction_wheel.gd` for assembly, save/load, mass, controls,
separation, asset-envelope and workshop checks.
