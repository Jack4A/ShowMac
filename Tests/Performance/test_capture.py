import importlib.util,unittest
from pathlib import Path
path=Path(__file__).resolve().parents[2]/'scripts/perf_capture.py'
spec=importlib.util.spec_from_file_location('perf_capture',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class CaptureTests(unittest.TestCase):
 def rows(self):
  return [dict(monotonic_s=str(t),epoch_s=str(t+1000),user_ns=str(u),system_ns='0',footprint_bytes='10485760',resident_bytes='12582912',pkg_idle_wakeups=str(t*2),interrupt_wakeups=str(t*4),read_bytes='0',write_bytes='0',start_id='12345678901234567890',energy_nj='0',rusage_version='6') for t,u in [(0,0),(1,10000000),(2,20000000)]]
 def test_cpu_units_and_wakeups(self):
  x=module.analyze(self.rows());self.assertEqual(x['cpu_mean_one_core_pct'],1);self.assertEqual(x['interrupt_wakeups_per_s'],4);self.assertEqual(x['footprint_peak_mib'],10)
 def test_missing_energy_is_not_zero_power(self):
  x=module.analyze(self.rows());self.assertIsNone(x['process_average_watts']);self.assertIsNone(x['actual_fps']);self.assertIsNone(x['animation_hitches'])
 def test_energy_units(self):
  r=self.rows();r[0]['energy_nj']='1000000000';r[-1]['energy_nj']='3000000000';self.assertEqual(module.analyze(r)['process_average_watts'],1)
 def test_identity_and_counter_changes_fail(self):
  r=self.rows();r[1]['start_id']='12345678901234567891'
  with self.assertRaises(ValueError):module.analyze(r)
  r=self.rows();r[-1]['user_ns']='0'
  with self.assertRaises(ValueError):module.analyze(r)
 def test_each_monotonic_counter(self):
  for key in ['system_ns','pkg_idle_wakeups','interrupt_wakeups','read_bytes','write_bytes']:
   with self.subTest(counter=key):
    r=self.rows();r[0][key]='100';r[1][key]='99'
    with self.assertRaises(ValueError):module.analyze(r)
 def test_nonfinite_input_rejected(self):
  for key in ['monotonic_s','user_ns','footprint_bytes']:
   for value in ['nan','inf','-inf']:
    with self.subTest(counter=key,value=value):
     r=self.rows();r[1][key]=value
     with self.assertRaises(ValueError):module.analyze(r)
 def test_percentile(self):self.assertEqual(module.percentile([4,1,3,2],.95),4)
if __name__=='__main__':unittest.main()
