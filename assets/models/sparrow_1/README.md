# Sparrow–1 lightweight engine

Original procedural exterior model based on the supplied LR-1 reference: graphite bell, copper liner and lip, dark chamber, machined silver clamps, blue oxidizer pipe, copper fuel return, braided hose, valve cans, and a small geometric Sparrow marking. A shallow adapter retains Kestrel's mounting interface.

- `sparrow_1.glb`: self-contained glTF 2.0, seven inspectable components, 42,783 triangles.
- `preview.png`: actual Godot render. `comparison.png` shows Sparrow beside Kestrel at their installed scales. Available in the in-game Asset laboratory as **Sparrow–1 / lightweight engine**.
- Rebuild: `python3 tools/build_sparrow_1.py`.
- Preview: `./tools/run.sh res://scenes/sparrow_1_preview.tscn`.

Asset coordinates are metres, Y up, nozzle exit at Y=0 and attachment plane at Y=2.0. The mounting ring has the same 0.96 m radius and 0.85 m bolt circle as Kestrel. The bell has a 0.486 m outer lip radius; the exhaust fits inside a 0.454 m radius.

The game uses Kestrel's horizontal and vertical scale factors for both models. Installed mounting diameter is 1.88 m; Sparrow is approximately 1.34 m tall compared with Kestrel's 1.80 m. Its shorter body raises the nozzle while keeping the top attachment at the existing engine slot's Y=2.0 plane. Workshop, free and snapped drag previews, core and radial installations use the same asset. The plume begins at the actual nozzle exit.

Static exterior mesh with material-based details and planar UVs. The reference's cutaway, labels, and performance figures are visual reference material; Sparrow's existing gameplay statistics remain in `scripts/parts.gd`.
