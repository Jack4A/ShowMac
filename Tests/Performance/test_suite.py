import copy
import importlib.util
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'scripts'))
spec = importlib.util.spec_from_file_location('perf_suite', Path(__file__).resolve().parents[2]/'scripts/perf_suite.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class SuiteTests(unittest.TestCase):
    def fixture(self):
        return {'status': 'passed', 'invariant_failures': [], 'batch_200_samples': {'p95_ms': 10},
                'history_and_menu_render': {'p95_ms': 1}}

    def test_invariants_override_fast_metrics(self):
        f = self.fixture()
        f['invariant_failures'] = ['history_rewound']
        self.assertEqual(m.assess_run(f, {'footprint_peak_mib': 20}, m.DEFAULT_BUDGETS)['status'], 'failed')

    def test_short_run_does_not_claim_memory_coverage(self):
        result = m.assess_run(self.fixture(), {'footprint_peak_mib': 20}, m.DEFAULT_BUDGETS)
        self.assertFalse(result['long_memory_coverage'])
        self.assertIsNone(m.growth([{'monotonic_s': i, 'footprint_bytes': i*2**20} for i in range(60)]))

    def test_slope_units_and_warmup(self):
        rows = [{'monotonic_s': i, 'footprint_bytes': (100+i/60)*2**20} for i in range(181)]
        self.assertAlmostEqual(m.growth(rows), 1)
        self.assertEqual(m.assess_run(self.fixture(), {'footprint_peak_mib': 20,
            'footprint_growth_mib_per_minute': 10}, m.DEFAULT_BUDGETS)['status'], 'failed')

    def test_nonfinite_metric_fails_closed(self):
        f = self.fixture()
        f['batch_200_samples']['p95_ms'] = float('nan')
        self.assertEqual(m.assess_run(f, {'footprint_peak_mib': 20}, m.DEFAULT_BUDGETS)['status'], 'failed')

    def report(self):
        return {'status': 'passed', 'profile': 'smoke', 'workloads': ['hidden'], 'host': {'os': 'test'},
                'budgets': m.DEFAULT_BUDGETS, 'runs': [{'scenario': 'hidden', 'assessment': {
                    'metrics': {'batch_200_p95_ms': 10, 'menu_history_p95_ms': 1}}}]}

    def test_baseline_regression_and_host_mismatch(self):
        old = self.report()
        new = copy.deepcopy(old)
        new['runs'][0]['assessment']['metrics']['batch_200_p95_ms'] = 20
        self.assertEqual(m.compare(new, old, m.DEFAULT_BUDGETS)['status'], 'regressed')
        new['host']['os'] = 'different'
        self.assertEqual(m.compare(new, old, m.DEFAULT_BUDGETS)['status'], 'incompatible')
        old['status'] = 'failed'
        self.assertEqual(m.compare(self.report(), old, m.DEFAULT_BUDGETS)['status'], 'incompatible')

    def test_small_timing_noise_is_not_regression(self):
        old = self.report()
        new = copy.deepcopy(old)
        new['runs'][0]['assessment']['metrics']['menu_history_p95_ms'] = 1.3
        self.assertEqual(m.compare(new, old, m.DEFAULT_BUDGETS)['status'], 'within_targets')

    def test_owned_child_cleanup_and_failed_command_evidence(self):
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder)/'command.log'
            result = m.command([sys.executable, '-c', 'import sys; print("evidence"); sys.exit(3)'], log)
            self.assertEqual(result.returncode, 3)
            self.assertIn('evidence', log.read_text())
            child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'], start_new_session=True)
            m.stop_owned(child)
            self.assertIsNotNone(child.poll())

    def test_timeout_keeps_evidence(self):
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder)/'timeout.log'
            with self.assertRaises(subprocess.TimeoutExpired):
                m.command([sys.executable, '-u', '-c', 'import time; print("started"); time.sleep(30)'], log, .1)
            self.assertIn('TIMED OUT', log.read_text())

    def test_old_app_cannot_be_launched_as_stress_binary(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder)/'old-app'
            binary.write_bytes(b'normal app without fixture mode')
            with self.assertRaises(ValueError):
                m.validate_binary(binary)
            binary.write_bytes(b'hidden_stream_must_not_notify_views visibility_notification_count history_end_must_not_rewind_on_stale_sample')
            self.assertEqual(len(m.validate_binary(binary)), 64)
