import importlib.util,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('perf_assess',Path(__file__).resolve().parents[2]/'scripts/perf_assess.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class BudgetTests(unittest.TestCase):
 def test_short_capture_never_claims_formal_pass(self):
  r=m.assess({'scenario':'B01-minimized','summary':{'duration_s':30,'cpu_mean_one_core_pct':.2,'interrupt_wakeups_per_s':1}})
  self.assertEqual(r['status'],'observed_within_targets');self.assertFalse(r['formal_regression_pass']);self.assertTrue(r['short_sample_warning']);self.assertEqual(r['coverage']['process_average_watts'],'unmeasured')
 def test_over_budget_is_investigation(self):
  r=m.assess({'scenario':'B01-minimized','summary':{'duration_s':120,'cpu_mean_one_core_pct':2,'interrupt_wakeups_per_s':1}})
  self.assertEqual(r['status'],'needs_investigation')
if __name__=='__main__':unittest.main()
