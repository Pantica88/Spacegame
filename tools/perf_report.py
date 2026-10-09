"""Standard-library performance statistics and a self-contained local report."""
from __future__ import annotations
import csv
import html
import json
import math
import statistics
from pathlib import Path

METRICS = ("frame_ms", "gpu_ms", "render_cpu_ms", "game_physics_ms", "game_process_ms")
COMPAT_CONFIG = ("resolution", "renderer", "warmup_seconds", "sample_seconds", "repeats", "seed", "budget_ms")
COMPAT_META = ("engine", "renderer", "gpu", "gpu_vendor", "driver", "viewport", "seed", "fixture_version", "physics_hz", "mode", "logical_viewport")


def stats(values):
    values = sorted(float(v) for v in values)
    if not values or any(not math.isfinite(v) or v < 0 for v in values):
        raise ValueError("Expected finite nonnegative timing samples")
    return {"count": len(values), "mean": statistics.fmean(values), "median": statistics.median(values),
            "p95": values[max(0, math.ceil(len(values) * .95) - 1)],
            "p99": values[max(0, math.ceil(len(values) * .99) - 1)], "max": values[-1]}


def summarize_result(result, budget_ms=1000 / 60):
    errors = list(result.get("errors", []))
    if result.get("status") != "ok":
        errors.append("Scenario process did not complete successfully")
    if not isinstance(result.get("samples", []), list) or any(not isinstance(s, dict) for s in result.get("samples", [])):
        result = dict(result, samples=[])
        errors.append("Malformed sample rows")
    phases = {}
    for phase in ("warmup", "measure"):
        rows = [s for s in result.get("samples", []) if s.get("phase") == phase]
        if not rows:
            errors.append(f"Missing {phase} samples")
            continue
        metrics = {}
        for metric in METRICS:
            try:
                metrics[metric] = stats([r[metric] for r in rows])
            except (KeyError, TypeError, ValueError, OverflowError) as exc:
                errors.append(f"Invalid {phase} {metric}: {exc}")
        if "gpu_ms" in metrics and metrics["gpu_ms"]["max"] <= 0:
            errors.append(f"No valid GPU timing in {phase}; zero is not a speedup")
        if "frame_ms" in metrics:
            missed = sum(float(r["frame_ms"]) > budget_ms for r in rows)
            metrics.update(missed_frames=missed, missed_percent=100 * missed / len(rows))
        phases[phase] = metrics
    for name in ("setup_ms", "first_frame_ms", "startup_to_first_frame_ms"):
        try:
            value = float(result[name])
            if not math.isfinite(value) or value < 0:
                raise ValueError(name)
        except (KeyError, ValueError, TypeError):
            errors.append(f"Missing or invalid {name}")
    return {"scenario": result.get("scenario"), "valid": not errors, "errors": errors, "phases": phases,
            "setup_ms": result.get("setup_ms"), "first_frame_ms": result.get("first_frame_ms"),
            "startup_to_first_frame_ms": result.get("startup_to_first_frame_ms")}


def load_run(directory):
    directory = Path(directory)
    manifest = json.loads((directory / "run.json").read_text())
    budget = manifest["config"]["budget_ms"]
    errors = []
    if manifest.get("status") != "complete":
        errors.append("Run is incomplete or a scenario process failed")
    groups = {name: [] for name in manifest["scenarios"]}
    loaded = []
    seen_paths = set()
    for relative in manifest.get("results", []):
        path = (directory / relative).resolve()
        if not path.is_relative_to(directory.resolve()):
            errors.append("Result path escapes run directory")
            continue
        if path in seen_paths:
            errors.append("Duplicate result path")
            continue
        seen_paths.add(path)
        try:
            result = json.loads(path.read_text())
            if not isinstance(result, dict) or not isinstance(result.get("samples", []), list) or any(not isinstance(row, dict) for row in result.get("samples", [])):
                raise ValueError("Malformed result/sample rows")
            result.setdefault("samples", [])
            result["_relative_path"] = relative
            summary = summarize_result(result, budget)
            if result["scenario"] not in groups:
                raise ValueError("Unexpected scenario")
            groups[result["scenario"]].append(result)
            loaded.append(result)
            errors.extend(f"{relative}: {e}" for e in summary["errors"])
            if result.get("simulation_ticks") != round(manifest["config"]["sample_seconds"] * 60):
                errors.append(f"{relative}: wrong simulation duration")
            meta = result.get("metadata", {})
            for key, expected in (("viewport", manifest["config"]["resolution"]), ("renderer", manifest["config"]["renderer"]), ("seed", manifest["config"]["seed"])):
                if meta.get(key) != expected:
                    errors.append(f"{relative}: unexpected {key}")
        except (OSError, ValueError, KeyError, TypeError) as exc:
            errors.append(f"{relative}: {exc}")
    scenarios = {}
    for name, results in groups.items():
        if len(results) != manifest["config"]["repeats"]:
            errors.append(f"{name}: missing repeats ({len(results)}/{manifest['config']['repeats']})")
        if not results:
            continue
        for other in results[1:]:
            for key in COMPAT_META:
                if other.get("metadata", {}).get(key) != results[0].get("metadata", {}).get(key):
                    errors.append(f"{name}: {key} changed between repeats")
        measured = [s for result in results for s in result["samples"] if s.get("phase") == "measure"]
        aggregate = dict(results[0], samples=[s for result in results for s in result["samples"]])
        stats_result = summarize_result(aggregate, budget)
        scenarios[name] = {**stats_result, "metadata": results[0].get("metadata", {}),
                           "repeats": [summarize_result(r, budget) for r in results],
                           "measured_frames": len(measured)}
    if manifest.get("source_changed_during_run"):
        errors.append("Source files changed while this run was executing: " + ", ".join(manifest.get("changed_source_files", [])))
    return manifest, {"schema_version": 1, "id": manifest["id"], "label": manifest["label"],
                      "valid": not errors, "errors": errors, "budget_ms": budget, "scenarios": scenarios}, loaded


def compare_runs(before_manifest, before, after_manifest, after):
    reasons = []
    if not before["valid"] or not after["valid"]:
        reasons.append("Both runs must be complete and valid")
    for key in COMPAT_CONFIG:
        if before_manifest["config"].get(key) != after_manifest["config"].get(key):
            reasons.append(f"Different {key}")
    if before_manifest.get("host", {}).get("cpu") != after_manifest.get("host", {}).get("cpu"):
        reasons.append("Different CPU")
    if set(before["scenarios"]) != set(after["scenarios"]):
        reasons.append("Different scenario selection")
    for name in set(before["scenarios"]) & set(after["scenarios"]):
        for key in COMPAT_META:
            if before["scenarios"][name]["metadata"].get(key) != after["scenarios"][name]["metadata"].get(key):
                reasons.append(f"{name}: different {key}")
    comparison = {"baseline_id": before["id"], "compatible": not reasons, "reasons": reasons, "scenarios": {}}
    if reasons:
        return comparison
    for name in after["scenarios"]:
        a = before["scenarios"][name]["phases"]["measure"]
        b = after["scenarios"][name]["phases"]["measure"]
        deltas = {}
        for metric in METRICS:
            deltas[metric] = {}
            for statistic in ("median", "p95", "p99"):
                old, new = a[metric][statistic], b[metric][statistic]
                deltas[metric][statistic] = {"before": old, "after": new, "delta_ms": new - old,
                                           "percent": 100 * (new - old) / old if old else None}
        frame = deltas["frame_ms"]["p95"]
        gpu = deltas["gpu_ms"]["median"]
        deltas["suspected_regression"] = any(d["delta_ms"] > .5 and (d["percent"] or 0) > 5 for d in (frame, gpu))
        deltas["missed_percent_delta"] = b["missed_percent"] - a["missed_percent"]
        comparison["scenarios"][name] = deltas
    return comparison


def build_report(run_dir, baseline_dir=None):
    run_dir = Path(run_dir)
    manifest, summary, results = load_run(run_dir)
    if baseline_dir:
        bm, bs, _ = load_run(baseline_dir)
        summary["comparison"] = compare_runs(bm, bs, manifest, summary)
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2, allow_nan=False) + "\n")
    fields = ["scenario", "repeat", "phase", "frame_index", "elapsed_ms", "simulation_tick", *METRICS,
              "physics_ticks", "draw_calls", "objects", "primitives"]
    with (run_dir / "frames.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for result in results:
            for sample in result.get("samples", []):
                writer.writerow(dict(sample, scenario=result["scenario"], repeat=Path(result["_relative_path"]).parent.name))
    lines = [f"# Performance lab: {manifest['label']}", "", f"Run: `{manifest['id']}`. Valid: **{summary['valid']}**.",
             "", "Native 60 Hz gameplay checkpoints; not an end-to-end flight or a guarantee of continuous 60 FPS.",
             "Frame time is wall time; GPU sums active viewports. Game CPU covers main callbacks only. CPU/GPU overlap.", "",
             f"| Scenario | Frame median | p95 | p99 | max | >{summary['budget_ms']:.2f} ms | GPU median | Main physics median |", "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for name, scenario in summary["scenarios"].items():
        data = scenario["phases"].get("measure", {})
        if all(m in data for m in METRICS):
            f = data["frame_ms"]
            lines.append(f"| {name} | {f['median']:.3f} | {f['p95']:.3f} | {f['p99']:.3f} | {f['max']:.3f} | {data['missed_percent']:.1f}% | {data['gpu_ms']['median']:.3f} | {data['game_physics_ms']['median']:.3f} |")
    lines += ["", "All timings in milliseconds. Full setup/first-frame, warmup, per-repeat and CPU/GPU statistics are in summary.json.", ""]
    if summary["errors"]:
        lines += ["Errors:", *[f"- {e}" for e in summary["errors"]], ""]
    comp = summary.get("comparison")
    if comp:
        lines += [f"Baseline: `{comp['baseline_id']}`. Comparable: **{comp['compatible']}**.", ""]
        if not comp["compatible"]:
            lines += [f"- {r}" for r in comp["reasons"]]
        else:
            lines += ["| Scenario | Frame p95 change | GPU median change | Suspected regression |", "|---|---:|---:|---|"]
            for name, delta in comp["scenarios"].items():
                lines.append(f"| {name} | {delta['frame_ms']['p95']['delta_ms']:+.3f} ms | {delta['gpu_ms']['median']['delta_ms']:+.3f} ms | {delta['suspected_regression']} |")
    (run_dir / "report.md").write_text("\n".join(lines) + "\n")
    # Embed traces, no network dependencies or file-fetch/CORS requirements.
    payload = json.dumps({"manifest": manifest, "summary": summary, "results": results}, allow_nan=False).replace("<", "\\u003c")
    page = HTML.replace("REPORT_TITLE", html.escape(manifest["label"])).replace("REPORT_DATA", payload)
    (run_dir / "report.html").write_text(page)
    return summary


HTML = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Performance lab — REPORT_TITLE</title>
<style>body{margin:2rem auto;padding:0 1rem;max-width:1250px;background:#111d28;color:#e4edf6;font:15px system-ui}h1{font-size:28px}p{line-height:1.5;color:#bfcedd}a{color:#8fcfff}select{padding:.55rem;font:inherit;background:#26384a;color:white;border:1px solid #789;margin:0 .6rem .8rem 0}canvas{width:100%;height:330px;background:#172838;border:1px solid #40556a}table{width:100%;border-collapse:collapse;margin:1.5rem 0;font-variant-numeric:tabular-nums}td,th{text-align:right;padding:.6rem;border-bottom:1px solid #354556}td:first-child,th:first-child{text-align:left}.bad{color:#ff9a9a}.ok{color:#88deb1}img{max-width:100%;max-height:520px}pre{white-space:pre-wrap;font:inherit}#tooltip{min-height:1.6rem}</style>
<h1>Performance lab — REPORT_TITLE</h1><p id="meta"></p><p>Native 60 Hz gameplay checkpoints. Frame time is measured between completed draws; GPU measurements may lag events. Main CPU timings cover the game's main callbacks, not all child scripts. CPU and GPU overlap. First-use timing does not guarantee an empty driver shader cache.</p><div id="status"></div><div id="table"></div><h2>Frame timeline</h2><select id="scenario" aria-label="Scenario and repeat"></select><select id="phase" aria-label="Capture phase"><option value="measure">Measured gameplay</option><option value="warmup">Warmup</option></select><p>White: frame · Cyan: GPU · Green: main callbacks · Purple: render CPU · Red: 60 FPS budget · Yellow: events</p><canvas id="chart" width="1200" height="330"></canvas><p id="tooltip"></p><p id="startup"></p><div id="events"></div><h2>Baseline comparison</h2><div id="comparison"></div><h2>Final checkpoint</h2><img id="capture" alt="Scenario final frame"><p><a href="frames.csv">Raw frames CSV</a> · <a href="summary.json">Summary JSON</a> · <a href="run.json">Run metadata</a> · <a href="report.md">Text report</a></p>
<script>const data=REPORT_DATA;const summary=data.summary;const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));const fmt=n=>Number(n).toFixed(3);document.getElementById('meta').textContent=data.manifest.id+' · '+data.manifest.config.resolution.join('×')+' · '+data.manifest.config.renderer+' · '+data.manifest.config.repeats+' repeat(s)';document.getElementById('status').innerHTML='<b class="'+(summary.valid?'ok':'bad')+'">'+(summary.valid?'Capture valid':'Capture incomplete / invalid')+'</b>'+summary.errors.map(e=>'<p class="bad">'+esc(e)+'</p>').join('');let table='<table><tr><th>Scenario</th><th>Frame median</th><th>p95</th><th>p99</th><th>max</th><th>Over budget</th><th>GPU median</th></tr>';for(const [name,s] of Object.entries(summary.scenarios)){let m=s.phases.measure;if(!m?.frame_ms||!m?.gpu_ms)continue;let f=m.frame_ms;table+='<tr><td>'+esc(name)+'</td>'+[f.median,f.p95,f.p99,f.max].map(v=>'<td>'+fmt(v)+'</td>').join('')+'<td>'+m.missed_percent.toFixed(1)+'%</td><td>'+fmt(m.gpu_ms.median)+'</td></tr>'}document.getElementById('table').innerHTML=table+'</table>';const select=document.getElementById('scenario');data.results.forEach((r,i)=>{const o=document.createElement('option');o.value=i;o.textContent=r.scenario+' — '+r._relative_path.split('/').slice(-2,-1);select.append(o)});const comp=summary.comparison;document.getElementById('comparison').innerHTML=!comp?'<p>No baseline selected. This valid run can be saved as a baseline with perf.sh baseline RUN.</p>':!comp.compatible?'<p class="bad">Comparison blocked: '+comp.reasons.map(esc).join('; ')+'</p>':'<p>Baseline '+esc(comp.baseline_id)+'. Positive changes are slower. Regression flags require >5% and >0.5 ms; they are signals to investigate, not statistical proof.</p><table><tr><th>Scenario</th><th>Frame p95 change</th><th>GPU median change</th><th>Flag</th></tr>'+Object.entries(comp.scenarios).map(([n,d])=>'<tr><td>'+esc(n)+'</td><td>'+fmt(d.frame_ms.p95.delta_ms)+' ms</td><td>'+fmt(d.gpu_ms.median.delta_ms)+' ms</td><td>'+d.suspected_regression+'</td></tr>').join('')+'</table>';let rows=[],maxY=40,maxX=1;const canvas=document.getElementById('chart'),ctx=canvas.getContext('2d');function draw(){const r=data.results[Number(select.value)];if(!r)return;const phase=document.getElementById('phase').value;rows=(r.samples||[]).filter(s=>s.phase===phase);ctx.clearRect(0,0,1200,330);if(!rows.length)return;maxY=rows.reduce((m,s)=>Math.max(m,s.frame_ms),20)*1.1;maxX=rows.at(-1).elapsed_ms||1;function point(s,v){return [55+s.elapsed_ms/maxX*1130,300-v/maxY*275]}ctx.strokeStyle='#41556a';ctx.fillStyle='#bed0df';ctx.font='12px system-ui';for(let i=0;i<=4;i++){let v=maxY*i/4,y=point(rows[0],v)[1];ctx.beginPath();ctx.moveTo(55,y);ctx.lineTo(1185,y);ctx.stroke();ctx.fillText(v.toFixed(1),5,y+4)}const y=point(rows[0],summary.budget_ms)[1];ctx.strokeStyle='#ff8484';ctx.beginPath();ctx.moveTo(55,y);ctx.lineTo(1185,y);ctx.stroke();for(const [key,color] of [['frame_ms','#eef5ff'],['gpu_ms','#64ccf5'],['main','#7dde99'],['render_cpu_ms','#bba0ff']]){ctx.strokeStyle=color;ctx.beginPath();rows.forEach((s,i)=>{const v=key==='main'?s.game_physics_ms+s.game_process_ms:s[key];const [x,y]=point(s,v);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.stroke()}if(phase==='measure')for(const e of r.events||[]){let x=55+e.elapsed_ms/maxX*1130;ctx.strokeStyle='#eec873';ctx.beginPath();ctx.moveTo(x,10);ctx.lineTo(x,300);ctx.stroke()}ctx.fillStyle='#bed0df';ctx.fillText('0 s',55,322);ctx.fillText((maxX/1000).toFixed(1)+' s',1130,322);document.getElementById('startup').textContent='Fixture setup '+fmt(r.setup_ms)+' ms; fixture-to-first-draw '+fmt(r.first_frame_ms)+' ms; engine-start-to-first-draw '+fmt(r.startup_to_first_frame_ms)+' ms.';document.getElementById('events').textContent=(r.events||[]).map(e=>e.name+' at '+(e.elapsed_ms/1000).toFixed(3)+' s').join(' · ');document.getElementById('capture').src=r._relative_path.replace('result.json','final.png')}select.onchange=draw;document.getElementById('phase').onchange=draw;canvas.onmousemove=e=>{if(!rows.length)return;let x=(e.clientX-canvas.getBoundingClientRect().left)/canvas.clientWidth*1200,t=(x-55)/1130*maxX;let s=rows.reduce((a,b)=>Math.abs(a.elapsed_ms-t)<Math.abs(b.elapsed_ms-t)?a:b);document.getElementById('tooltip').textContent=(s.elapsed_ms/1000).toFixed(3)+' s · Frame '+fmt(s.frame_ms)+' ms · GPU '+fmt(s.gpu_ms)+' ms · Main physics '+fmt(s.game_physics_ms)+' ms · '+s.physics_ticks+' physics tick(s)'};draw();</script></html>'''
