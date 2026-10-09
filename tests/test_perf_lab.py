"""Runner isolation, error detection and baseline selection safeguards."""
import json
import argparse
import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import perf_lab as lab

class RunnerSafeguards(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)

    def fake_engine(self,body):
        engine=self.root/'fake-godot'
        engine.write_text('#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\nc=json.loads(Path(sys.argv[-1]).read_text())\np=Path(c["output_dir"])\n'+body)
        engine.chmod(0o755)
        return str(engine)

    def case(self,name):
        case=self.root/name;case.mkdir()
        config=dict(output_dir=str(case),expected_resolution=[1280,720],scenario='launch',sample_seconds=3)
        return case,config

    def test_fresh_save_directories_for_each_process(self):
        engine=self.fake_engine('p.joinpath("env.json").write_text(json.dumps({k:v for k,v in os.environ.items() if k.startswith("XDG_")}))\np.joinpath("result.json").write_text(json.dumps(dict(status="ok",errors=[],samples=[])))\n')
        dirs=[]
        for name in ('first','second'):
            case,config=self.case(name)
            self.assertEqual(lab.run_case(engine,case,config),(True,False))
            env=json.loads((case/'env.json').read_text())
            for kind in ('DATA','CONFIG','CACHE'):
                self.assertTrue(Path(env['XDG_'+kind+'_HOME']).is_relative_to(case))
            dirs.append(env['XDG_DATA_HOME'])
        self.assertNotEqual(*dirs)

    def test_script_error_is_failure_even_with_zero_exit(self):
        engine=self.fake_engine('print("SCRIPT ERROR: broken fixture")\np.joinpath("result.json").write_text(json.dumps(dict(status="ok",errors=[],samples=[])))\n')
        case,config=self.case('error')
        self.assertEqual(lab.run_case(engine,case,config),(False,False))
        self.assertEqual(json.loads((case/'result.json').read_text())['status'],'error')

    def test_missing_result_cannot_be_success(self):
        engine=self.fake_engine('pass\n');case,config=self.case('missing')
        self.assertEqual(lab.run_case(engine,case,config),(False,False))
        self.assertTrue((case/'godot.log').exists())

    def test_renderer_started_during_capture_invalidates_trial(self):
        engine=self.fake_engine('import time; time.sleep(30)\n')
        case,config=self.case('contended')
        with patch.object(lab,'other_godot_processes',return_value=[{'pid':123,'executable':'Godot'}]):
            self.assertEqual(lab.run_case(engine,case,config),(False,False))
        result=json.loads((case/'result.json').read_text())
        self.assertIn('Other graphical Godot process',result['errors'][0])

    def test_two_complete_batches_save_and_reuse_baseline(self):
        engine=self.fake_engine("r=dict(status='ok',errors=[],scenario=c['scenario'],simulation_ticks=round(c['sample_seconds']*60),setup_ms=1,first_frame_ms=2,startup_to_first_frame_ms=3,metadata=dict(viewport=c['expected_resolution'],renderer='gl_compatibility',seed=c['seed']),samples=[dict(phase=phase,frame_ms=10,gpu_ms=5,render_cpu_ms=1,game_physics_ms=2,game_process_ms=1) for phase in ['warmup','measure']])\np.joinpath('result.json').write_text(json.dumps(r))\n")
        args=argparse.Namespace(preset='quick',repeats=2,warmup_seconds=None,sample_seconds=None,
            resolution=None,scenario=None,godot=engine,label='before',baseline=None,no_capture=True,fail_on_regression=True)
        config=dict(presets={'quick':dict(repeats=1,warmup_seconds=1,sample_seconds=3)},
                    resolution=[1280,720],renderer='gl_compatibility',seed=1,target_fps=60,
                    scenarios={'launch':'launch','map':'map'})
        with patch.object(lab,'source_snapshot',return_value={'fixture':'unchanged'}), \
             patch.object(lab,'other_godot_processes',return_value=[]), \
             patch.object(lab.subprocess,'run'), \
             patch.object(lab.subprocess,'check_output',return_value='test-head'), \
             patch.dict(lab.os.environ,{'DISPLAY':':test'}), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(lab.capture(args,self.root,config),0)
            args.label='after'
            self.assertEqual(lab.capture(args,self.root,config),0)
        after=lab.resolve_run('after',self.root)
        summary=json.loads((after/'summary.json').read_text())
        self.assertTrue(summary['valid'])
        self.assertTrue(summary['comparison']['compatible'])
        self.assertEqual(summary['comparison']['scenarios']['map']['gpu_ms']['median']['delta_ms'],0)
        manifest=json.loads((after/'run.json').read_text())
        self.assertEqual([p.split('/')[0] for p in manifest['results']],['launch','map','map','launch'])
        self.assertTrue((self.root/'baselines.json').is_file())

    def test_other_renderer_detected_but_own_and_headless_ignored(self):
        for pid,args in [(111,b'/bin/Godot_v4\0--path\0project'),
                         (112,b'/bin/godot\0--headless'),(113,b'/bin/godot\0'),
                         (114,b'/bin/python3\0godot-script')]:
            folder=self.root/str(pid);folder.mkdir();(folder/'cmdline').write_bytes(args)
        self.assertEqual([p['pid'] for p in lab.other_godot_processes(113,self.root)],[111])

    def test_ambiguous_label_rejected(self):
        for name in ('a','b'):
            p=self.root/name;p.mkdir();(p/'run.json').write_text('{"label":"same"}')
        with self.assertRaises(ValueError):lab.resolve_run('same',self.root)
        self.assertEqual(lab.resolve_run('a',self.root),self.root/'a')

if __name__=='__main__':unittest.main()
