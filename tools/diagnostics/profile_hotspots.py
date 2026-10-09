"""Build an instrumented copy; run sequential diagnostic trials, never production edits."""
import json, os, re, shutil, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'build/hotspot-profile-source'
OUT=ROOT/'build/performance/hotspots-20261007'

def prepare():
    if DEST.exists(): raise RuntimeError('Diagnostic copy already exists')
    shutil.copytree(ROOT/'build/performance-baseline-20261007-source',DEST)
    probe='''extends RefCounted
static var rows: Dictionary = {}
static func record(label: String, duration: int) -> void:
	var row: Array = rows.get(label, [0, 0, 0])
	row[0] += duration
	row[1] += 1
	row[2] = maxi(row[2], duration)
	rows[label] = row
static func take() -> Dictionary:
	var result := rows
	rows = {}
	return result
'''
    (DEST/'tests/performance/hotspot_probe.gd').write_text(probe)
    scopes={
      'main':['_physics_process','_update_flight_ui','_enforce_warp_limit'],
      'flight_model':['warp_limit','step','_refresh_telemetry','_integrate_detached','_resolve_body_collisions'],
      'world_view':['sync_flight','_update_planet_lod','_sync_detached','_update_atmosphere','_update_moons'],
      'planet_terrain':['build','contact','segment_hit','render_mesh_for_lod'],
      'parachute_1':['advance'],
      'parachute_cloth':['advance','_step','redraw'],
      'cloud_layer':['update_weather','sun_transmittance','cloud_glow'],
    }
    for script,names in scopes.items():
      path=DEST/f'scripts/{script}.gd'; text=path.read_text()
      for name in names:
        pattern=rf'^func {re.escape(name)}\((.*)\) -> ([^:]+):$'
        match=re.search(pattern,text,re.M)
        if not match: raise RuntimeError(f'Unsupported signature {script}.{name}')
        args,ret=match.groups()
        # Selected signatures have no comma-containing default expressions.
        params=', '.join(a.split(':')[0].split('=')[0].strip() for a in args.split(',') if a.strip())
        call=f'_probe_original_{name}({params})'
        wrapper=f'func {name}({args}) -> {ret}:\n\tvar probe_started := Time.get_ticks_usec()\n'
        wrapper+=f'\t{call}\n' if ret=='void' else f'\tvar probe_result = {call}\n'
        wrapper+=f'\tpreload("res://tests/performance/hotspot_probe.gd").record("{script}.{name}", Time.get_ticks_usec() - probe_started)\n'
        if ret!='void': wrapper+='\treturn probe_result\n'
        wrapper+=f'\nfunc _probe_original_{name}({args}) -> {ret}:'
        text=text[:match.start()]+wrapper+text[match.end():]
      path.write_text(text)
    p=DEST/'scripts/cloud_layer.gd';s=p.read_text();s=s.replace('func _probe_original_update_weather(definition: Resource, observer: Vector3, sunlight: Vector3, enabled: bool) -> void:', 'func _probe_original_update_weather(definition: Resource, observer: Vector3, sunlight: Vector3, enabled: bool) -> void:\n\tif OS.get_environment("APHELION_PROBE_VARIANT") == "no_clouds":\n\t\tvisible = false\n\t\t_sync_lowres()\n\t\treturn');p.write_text(s)
    p=DEST/'tests/performance/run_scenario.gd';s=p.read_text()
    s=s.replace('\tgame.paused = true\n\t_collect_viewports(root)', '''	game.paused = true
	var variant := OS.get_environment("APHELION_PROBE_VARIANT")
	if variant == "simple_planet":
		var simple := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(0.3, 0.4, 0.3); }"
		simple.shader = shader
		game.world._planet.material_override = simple
	if variant == "no_sky":
		game.world._environment.background_mode = Environment.BG_COLOR
		game.world._environment.background_color = Color.BLACK
	_collect_viewports(root)''')
    s=s.replace('\tsamples.append(sample)', '\tsample["scopes_us_count_max"] = preload("res://tests/performance/hotspot_probe.gd").take()\n\tsamples.append(sample)')
    s=s.replace('"fixture_version": FIXTURE_VERSION', '"diagnostic_variant": OS.get_environment("APHELION_PROBE_VARIANT"), "fixture_version": FIXTURE_VERSION')
    p.write_text(s)

def run(batch):
    sys.path.insert(0,str(DEST/'tools'))
    import perf_lab as lab
    OUT.mkdir(parents=True,exist_ok=True)
    cases=[('landing','normal')] if batch.startswith('cpu') else [('orbit',v) for v in ('normal','no_clouds','simple_planet','no_sky')]
    hashes=lab.source_snapshot();lab.write_json(OUT/f'{batch}-source-before.json',hashes)
    for repeat in range(2):
      for scenario,variant in (cases if repeat==0 else cases[::-1]):
        contenders=lab.other_godot_processes()
        if contenders: raise RuntimeError(f'Competing Godot: {contenders}')
        case=OUT/f'{batch}-{scenario}-{variant}-{repeat+1}';case.mkdir()
        os.environ['APHELION_PROBE_VARIANT']=variant
        config=dict(scenario=scenario,output_dir=str(case),expected_resolution=[1280,720],seed=17171,warmup_seconds=2.0,sample_seconds=8.0,capture=True)
        print(case.name,flush=True)
        ok,_=lab.run_case('/tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64',case,config)
        if not ok: raise RuntimeError(f'Failed: {case}')
    after=lab.source_snapshot();lab.write_json(OUT/f'{batch}-source-after.json',after)
    assert hashes==after,'Diagnostic source changed during capture'
    print('PASS: diagnostic trials and source stability',flush=True)

if __name__=='__main__':
    if sys.argv[1]=='prepare': prepare()
    else: run(sys.argv[1])
