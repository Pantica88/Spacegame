#!/usr/bin/env python3
"""Sequential, isolated gameplay performance captures. Standard library only."""
from __future__ import annotations
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import time

from perf_report import build_report, load_run
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / 'build/performance'


def write_json(path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')
    temp.replace(path)


def source_snapshot():
    # Include imported source assets, but exclude generated caches and lab output.
    hashes = {}
    for folder in ('scripts', 'assets', 'scenes', 'tests/performance'):
        for path in sorted((ROOT / folder).rglob('*')):
            if path.is_file() and path.suffix not in ('.uid', '.import'):
                with path.open('rb') as stream:
                    hashes[str(path.relative_to(ROOT))] = {'sha256': hashlib.file_digest(stream, 'sha256').hexdigest(), 'mtime_ns': path.stat().st_mtime_ns}
    for name in ('project.godot', 'tools/perf_lab.py', 'tools/perf_report.py', 'perf.sh'):
        hashes[name] = {'sha256': hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), 'mtime_ns': (ROOT / name).stat().st_mtime_ns}
    return hashes


def resolve_run(value, output):
    direct = Path(value).expanduser()
    if (direct / 'run.json').is_file():
        return direct.resolve()
    if (output / value / 'run.json').is_file():
        return (output / value).resolve()
    matches = []
    for path in output.glob('*/run.json'):
        if json.loads(path.read_text()).get('label') == value:
            matches.append(path.parent)
    if len(matches) != 1:
        raise ValueError(f'Run {value!r} not found or label is ambiguous; use its full path or ID')
    return matches[0].resolve()


def baseline_key(manifest):
    config = manifest['config']
    identity = {k: config[k] for k in ('preset', 'resolution', 'renderer', 'warmup_seconds', 'sample_seconds', 'repeats', 'seed', 'budget_ms')}
    identity['scenarios'] = sorted(manifest['scenarios'])
    # Only fullscreen runs carry the key, so earlier windowed baselines keep their identity.
    if config.get('fullscreen'):
        identity['fullscreen'] = True
    return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()[:20]


def save_baseline(directory, output):
    manifest, summary, _ = load_run(directory)
    if not summary['valid']:
        raise ValueError('An invalid or incomplete run cannot become a baseline')
    pointer = output / 'baselines.json'
    pointers = json.loads(pointer.read_text()) if pointer.exists() else {}
    pointers[baseline_key(manifest)] = str(directory.resolve())
    write_json(pointer, pointers)


def other_godot_processes(exclude_pid=None, proc_root=Path('/proc')):
    """Best-effort guard against other graphical Godot instances, not a GPU profiler."""
    found = []
    for path in proc_root.glob('[0-9]*/cmdline'):
        try:
            pid = int(path.parent.name)
            args = path.read_bytes().split(b'\0')
            name = Path(os.fsdecode(args[0])).name.lower()
            if pid not in (os.getpid(), exclude_pid) and 'godot' in name and b'--headless' not in args:
                found.append({'pid': pid, 'executable': os.fsdecode(args[0])})
        except (OSError, ValueError):
            continue
    return found


def run_case(godot, case, config):
    write_json(case / 'config.json', config)
    env = dict(os.environ)
    for key in ('DATA', 'CONFIG', 'CACHE'):
        path = case / ('xdg_' + key.lower())
        path.mkdir()
        env['XDG_' + key + '_HOME'] = str(path)
    cmd = [godot, '--path', str(ROOT), '--resolution', 'x'.join(map(str, config['expected_resolution'])),
           '--disable-vsync', '--audio-driver', 'Dummy', '--rendering-method', config.get('renderer', 'forward_plus'),
           *(['--fullscreen'] if config.get('fullscreen') else []),
           '--script', 'res://tests/performance/run_scenario.gd', '--', '--config', str(case / 'config.json')]
    started = time.monotonic()
    error = None
    with (case / 'godot.log').open('w') as log:
        child = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = started + max(120, config['sample_seconds'] * 5 + 90)
            while child.poll() is None:
                contenders = other_godot_processes(child.pid)
                if contenders:
                    error = 'Other graphical Godot process detected: ' + ', '.join(str(p['pid']) for p in contenders)
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
                    break
                if time.monotonic() >= deadline:
                    raise subprocess.TimeoutExpired(cmd, time.monotonic() - started)
                try:
                    child.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
            if child.returncode and not error:
                error = f'Godot exited with code {child.returncode}'
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as exc:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
            error = 'Capture interrupted' if isinstance(exc, KeyboardInterrupt) else 'Capture timed out'
    log_text = (case / 'godot.log').read_text(errors='replace')
    if re.search(r'(?m)^(?:SCRIPT ERROR:|ERROR:)', log_text):
        error = (error + '; ' if error else '') + 'Godot reported errors; inspect godot.log'
    result_path = case / 'result.json'
    try:
        result = json.loads(result_path.read_text())
    except (OSError, ValueError):
        result = {'scenario': config['scenario'], 'samples': [], 'errors': []}
        error = error or 'Godot did not produce a result'
    if error:
        result['status'] = 'error'
        result.setdefault('errors', []).append(error)
    result['process_wall_ms'] = (time.monotonic() - started) * 1000
    write_json(result_path, result)
    return result.get('status') == 'ok', error == 'Capture interrupted'


def capture(args, output, lab):
    if not os.environ.get('DISPLAY') and not os.environ.get('WAYLAND_DISPLAY'):
        raise ValueError('A graphical session is required; headless GPU timings are invalid')
    contenders = other_godot_processes()
    if contenders:
        raise ValueError('Another graphical Godot process is active (PIDs ' + ', '.join(str(p['pid']) for p in contenders) + '). Close it before benchmarking.')
    config = dict(lab['presets'][args.preset], preset=args.preset, resolution=lab['resolution'],
                  renderer=lab['renderer'], seed=lab['seed'], budget_ms=1000 / lab['target_fps'])
    for name in ('repeats', 'warmup_seconds', 'sample_seconds', 'renderer'):
        if getattr(args, name, None) is not None:
            config[name] = getattr(args, name)
    if config['repeats'] < 1 or config['warmup_seconds'] < .1 or config['sample_seconds'] < 2:
        raise ValueError('Require repeats >= 1, warmup >= 0.1 seconds, capture >= 2 simulation seconds')
    if not all(__import__('math').isfinite(config[k]) for k in ('warmup_seconds', 'sample_seconds')):
        raise ValueError('Durations must be finite')
    if args.resolution:
        if not re.fullmatch(r'[1-9][0-9]*x[1-9][0-9]*', args.resolution):
            raise ValueError('Resolution must be WIDTHxHEIGHT')
        config['resolution'] = [int(v) for v in args.resolution.split('x')]
    if getattr(args, 'fullscreen', False):
        config['fullscreen'] = True
    scenarios = list(dict.fromkeys(args.scenario or lab['scenarios']))
    if set(scenarios) - lab['scenarios'].keys():
        raise ValueError('Unknown scenario; use ./perf.sh scenarios')
    double_bin = Path.home() / 'godot-double/src/bin/godot.linuxbsd.editor.double.x86_64'
    godot = args.godot or os.environ.get('GODOT_BIN') or (str(double_bin) if double_bin.is_file() else None) or shutil.which('godot') or shutil.which('godot4') or '/tmp/aphelion-godot/Godot_v4.5.1-stable_linux.x86_64'
    if not Path(godot).is_file():
        raise ValueError('Godot not found; set GODOT_BIN or --godot')
    slug = re.sub(r'[^a-zA-Z0-9_-]+', '-', args.label).strip('-')[:60] or 'capture'
    run_id = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '-' + slug
    directory = output / run_id
    directory.mkdir()
    cpu = next((s.split(':', 1)[1].strip() for s in Path('/proc/cpuinfo').read_text().splitlines() if s.startswith('model name')), platform.machine())
    source = source_snapshot()
    write_json(directory / 'source-hashes.json', source)
    for filename, command in [('git-status.txt', ['git', 'status', '--short']), ('git-diff.patch', ['git', 'diff', '--binary', 'HEAD'])]:
        with (directory / filename).open('w') as stream:
            subprocess.run(command, cwd=ROOT, stdout=stream, check=True)
    manifest = dict(schema_version=1, id=run_id, label=args.label, status='running', config=config,
                    scenarios=scenarios, results=[], host={'cpu': cpu, 'platform': platform.platform()},
                    source={'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                            'sha256': hashlib.sha256(json.dumps(source, sort_keys=True).encode()).hexdigest()}, godot=str(godot))
    write_json(directory / 'run.json', manifest)
    baseline = resolve_run(args.baseline, output) if args.baseline else None
    pointers = output / 'baselines.json'
    if baseline is None and pointers.exists():
        saved = json.loads(pointers.read_text()).get(baseline_key(manifest))
        if saved and (Path(saved) / 'run.json').is_file():
            baseline = Path(saved)
    success, interrupted = True, False
    print(f'Run: {directory}', flush=True)
    for repeat in range(config['repeats']):
        # Reverse order each repeat to reduce systematic scenario-order bias.
        for scenario in (scenarios if repeat % 2 == 0 else scenarios[::-1]):
            case = directory / scenario / f'repeat-{repeat + 1:02d}'
            case.mkdir(parents=True)
            print(f'[{repeat + 1}/{config["repeats"]}] {scenario}', flush=True)
            case_config = dict(scenario=scenario, output_dir=str(case), expected_resolution=config['resolution'],
                               seed=config['seed'], warmup_seconds=config['warmup_seconds'],
                               sample_seconds=config['sample_seconds'], capture=not args.no_capture,
                               fullscreen=bool(config.get('fullscreen')))
            ok, interrupted = run_case(godot, case, case_config)
            success &= ok
            manifest['results'].append(str((case / 'result.json').relative_to(directory)))
            write_json(directory / 'run.json', manifest)
            if not ok:
                break
        if not success:
            break
    manifest['status'] = 'complete' if success else 'failed'
    source_after = source_snapshot()
    write_json(directory / 'source-hashes-after.json', source_after)
    manifest['changed_source_files'] = sorted(name for name in source.keys() | source_after.keys() if source.get(name) != source_after.get(name))
    manifest['source_changed_during_run'] = bool(manifest['changed_source_files'])
    if manifest['source_changed_during_run']:
        manifest['status'] = 'invalid'
    write_json(directory / 'run.json', manifest)
    summary = build_report(directory, baseline)
    if summary['valid'] and baseline is None:
        save_baseline(directory, output)
        print('Saved the first valid run for these settings as the baseline.')
    elif baseline:
        print(f'Compared with: {baseline}')
    print(f'Report: {directory / "report.html"}')
    for error in summary['errors']:
        print('ERROR:', error)
    comparison = summary.get('comparison', {})
    if comparison and not comparison['compatible']:
        print('Comparison blocked:', '; '.join(comparison['reasons']))
    if interrupted:
        return 130
    if not summary['valid'] or (comparison and not comparison['compatible']):
        return 1
    if args.fail_on_regression and any(s['suspected_regression'] for s in comparison.get('scenarios', {}).values()):
        return 2
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT, help='Artifact root (before command)')
    commands = parser.add_subparsers(dest='command')
    run = commands.add_parser('run', help='Capture sequential gameplay checkpoints')
    run.add_argument('--preset', choices=('quick', 'standard', 'soak'), default='standard')
    run.add_argument('--label', default='capture')
    run.add_argument('--scenario', action='append')
    run.add_argument('--resolution')
    run.add_argument('--renderer', choices=('forward_plus', 'mobile', 'gl_compatibility'), help='Rendering method; defaults to tests/performance/lab.json')
    run.add_argument('--fullscreen', action='store_true', help='Needed when --resolution matches the monitor; window decorations shrink a window that size')
    run.add_argument('--repeats', type=int)
    run.add_argument('--warmup-seconds', type=float)
    run.add_argument('--sample-seconds', type=float)
    run.add_argument('--godot')
    run.add_argument('--baseline')
    run.add_argument('--no-capture', action='store_true')
    run.add_argument('--fail-on-regression', action='store_true')
    baseline = commands.add_parser('baseline', help='Select a valid saved baseline for its settings')
    baseline.add_argument('run')
    compare = commands.add_parser('compare', help='Regenerate candidate report against a saved baseline')
    compare.add_argument('before')
    compare.add_argument('after')
    commands.add_parser('list')
    commands.add_parser('scenarios')
    argv = sys.argv[1:] if argv is None else argv
    args = parser.parse_args(argv or ['run'])
    lab = json.loads((ROOT / 'tests/performance/lab.json').read_text())
    if args.command == 'scenarios':
        for name, description in lab['scenarios'].items():
            print(f'{name:14} {description}')
        return 0
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.command == 'list':
        for path in sorted(output.glob('*/run.json')):
            data = json.loads(path.read_text())
            status = data['status']
            summary_path = path.parent / 'summary.json'
            if summary_path.exists() and not json.loads(summary_path.read_text()).get('valid'):
                status = 'invalid'
            print(f'{data["id"]}  {status}  {data["label"]}')
        return 0
    try:
        # One GPU capture/baseline writer across worktrees. Automatically released on exit.
        with open(f'/tmp/aphelion-performance-{os.getuid()}.lock', 'a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('Another performance lab command is running; GPU captures must be sequential')
            if args.command == 'run':
                return capture(args, output, lab)
            if args.command == 'baseline':
                directory = resolve_run(args.run, output)
                save_baseline(directory, output)
                print(f'Baseline saved: {directory}')
                return 0
            if args.command == 'compare':
                summary = build_report(resolve_run(args.after, output), resolve_run(args.before, output))
                print(json.dumps(summary['comparison'], indent=2))
                return 0 if summary['comparison']['compatible'] else 1
            parser.print_help()
            return 1
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Performance lab: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
