"""Measurement integrity: failed runs and incompatible captures cannot show speedups."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import perf_report as report
import perf_lab as lab

class PerformanceReports(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = dict(id='sample', label='sample', status='complete', scenarios=['launch'],
            config=dict(preset='quick', resolution=[1280,720], renderer='gl_compatibility', warmup_seconds=1,
                        sample_seconds=3, repeats=1, seed=17171, budget_ms=1000/60), results=['launch/repeat-01/result.json'])
        self.result = dict(scenario='launch',status='ok',errors=[],simulation_ticks=180,
            metadata=dict(viewport=[1280,720],renderer='gl_compatibility',seed=17171),
            setup_ms=20, first_frame_ms=30,startup_to_first_frame_ms=40,
            samples=[dict(phase=phase, frame_ms=v,gpu_ms=5,render_cpu_ms=1,game_physics_ms=2,game_process_ms=.1)
                     for phase in ('warmup','measure') for v in (10,12,30)])

    def save(self):
        (self.root / 'run.json').write_text(json.dumps(self.manifest))
        path = self.root / self.manifest['results'][0]
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(self.result))

    def test_statistics_and_budget(self):
        s=report.summarize_result(self.result)
        self.assertTrue(s['valid'])
        self.assertEqual(s['phases']['measure']['frame_ms']['median'],12)
        self.assertEqual(s['phases']['measure']['frame_ms']['p99'],30)
        self.assertEqual(s['phases']['measure']['missed_frames'],1)

    def test_zero_gpu_and_nonfinite_are_invalid(self):
        for row in self.result['samples']: row['gpu_ms']=0
        self.assertFalse(report.summarize_result(self.result)['valid'])
        self.result['samples'][0]['frame_ms']=float('nan')
        self.assertFalse(report.summarize_result(self.result)['valid'])

    def test_reports_and_baseline(self):
        self.save()
        self.assertTrue(report.build_report(self.root)['valid'])
        for name in ('report.html','report.md','frames.csv','summary.json'):
            self.assertTrue((self.root/name).is_file())
        lab.save_baseline(self.root,self.root)
        self.assertTrue((self.root/'baselines.json').is_file())

    def test_invalid_baseline_rejected(self):
        self.result['status']='error';self.save()
        with self.assertRaises(ValueError):lab.save_baseline(self.root,self.root)

    def test_incompatible_comparison_blocked(self):
        self.save();m,s,_=report.load_run(self.root)
        other=copy.deepcopy(m);other['config']['resolution']=[1920,1080]
        self.assertFalse(report.compare_runs(m,s,other,s)['compatible'])
        self.assertTrue(report.compare_runs(m,s,m,s)['compatible'])

    def test_missing_repeats_or_changed_sources_rejected(self):
        self.manifest['config']['repeats']=2;self.save()
        self.assertFalse(report.load_run(self.root)[1]['valid'])
        self.manifest['config']['repeats']=1;self.manifest['source_changed_during_run']=True;self.save()
        self.assertFalse(report.load_run(self.root)[1]['valid'])

    def test_wrong_duration_rejected(self):
        self.result['simulation_ticks']=179;self.save()
        self.assertFalse(report.load_run(self.root)[1]['valid'])

    def test_duplicate_repeat_cannot_replace_missing_trial(self):
        self.save()
        self.manifest['config']['repeats']=2
        self.manifest['results'] *= 2
        (self.root/'run.json').write_text(json.dumps(self.manifest))
        self.assertFalse(report.load_run(self.root)[1]['valid'])

    def test_malformed_samples_produce_invalid_report(self):
        self.result['samples']=[None];self.save()
        self.assertFalse(report.build_report(self.root)['valid'])

    def test_result_path_escape_rejected(self):
        self.save();self.manifest['results']=['../outside.json']
        (self.root/'run.json').write_text(json.dumps(self.manifest))
        self.assertFalse(report.load_run(self.root)[1]['valid'])

if __name__=='__main__':unittest.main()
