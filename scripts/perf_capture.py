#!/usr/bin/env python3
"""Read-only external process capture. UI scenario setup is performed separately."""
import argparse,csv,hashlib,json,math,os,platform,subprocess,time
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo

def percentile(values,p):
 return sorted(values)[max(0,math.ceil(len(values)*p)-1)] if values else None

def analyze(rows):
 if len(rows)<2:raise ValueError('At least two samples required')
 numbers=[{k:float(v) for k,v in row.items()} for row in rows]
 if any(not math.isfinite(v) for row in numbers for v in row.values()):raise ValueError('Nonfinite counter or timestamp')
 first,last=numbers[0],numbers[-1];duration=last['monotonic_s']-first['monotonic_s']
 if duration<=0 or len({r['start_id'] for r in rows})!=1:raise ValueError('Invalid interval or changed PID identity')
 cpu=[]
 for a,b in zip(numbers,numbers[1:]):
  dt=b['monotonic_s']-a['monotonic_s'];delta=b['user_ns']+b['system_ns']-a['user_ns']-a['system_ns']
  counters=('user_ns','system_ns','pkg_idle_wakeups','interrupt_wakeups','read_bytes','write_bytes')
  if dt<=0 or any(b[k]<a[k] for k in counters):raise ValueError('Counter or clock moved backwards')
  cpu.append(delta/1e9/dt*100)
 energy_delta=last['energy_nj']-first['energy_nj']
 energy_available=first['rusage_version']==6 and last['rusage_version']==6 and first['energy_nj']>0 and energy_delta>0
 return {'duration_s':duration,'sample_count':len(rows),'cpu_mean_one_core_pct':(last['user_ns']+last['system_ns']-first['user_ns']-first['system_ns'])/1e9/duration*100,'cpu_p50_one_core_pct':percentile(cpu,.50),'cpu_p95_one_core_pct':percentile(cpu,.95),'cpu_p99_one_core_pct':percentile(cpu,.99),'cpu_max_one_core_pct':max(cpu),'footprint_peak_mib':max(r['footprint_bytes'] for r in numbers)/2**20,'footprint_change_mib':(last['footprint_bytes']-first['footprint_bytes'])/2**20,'package_idle_wakeups_per_s':(last['pkg_idle_wakeups']-first['pkg_idle_wakeups'])/duration,'interrupt_wakeups_per_s':(last['interrupt_wakeups']-first['interrupt_wakeups'])/duration,'read_bytes':last['read_bytes']-first['read_bytes'],'write_bytes':last['write_bytes']-first['write_bytes'],'process_energy_joules':energy_delta/1e9 if energy_available else None,'process_average_watts':energy_delta/1e9/duration if energy_available else None,'energy_coverage':'kernel per-process energy counter' if energy_available else 'unavailable: zero, unsupported or unreadable kernel energy counter','actual_fps':None,'animation_hitches':None}

def main():
 p=argparse.ArgumentParser();p.add_argument('--pid',type=int,required=True);p.add_argument('--seconds',type=int,default=30);p.add_argument('--scenario',required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--sampler',type=Path,required=True);p.add_argument('--app',type=Path,required=True);p.add_argument('--notes',default='');p.add_argument('--warmup',type=int,default=10);a=p.parse_args()
 if not 5<=a.seconds<=3600:p.error('seconds must be 5...3600')
 if not 0<=a.warmup<=300:p.error('warmup must be 0...300')
 time.sleep(a.warmup)
 a.out.mkdir(parents=True,exist_ok=True)
 binary=a.app/'Contents/MacOS/ThermalScope';started=datetime.now(ZoneInfo('Asia/Shanghai')).isoformat()
 result=subprocess.run([str(a.sampler.resolve()),str(a.pid),str(a.seconds)],capture_output=True,text=True)
 (a.out/'samples.csv').write_text(result.stdout);(a.out/'sampler.stderr.txt').write_text(result.stderr)
 if result.returncode:raise SystemExit(f'Capture failed ({result.returncode}); raw output preserved')
 report={'schema':1,'scenario':a.scenario,'pid':a.pid,'started_local':started,'timezone':'Asia/Shanghai','os':platform.platform(),'logical_cpus':os.cpu_count(),'app':str(a.app),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'notes':a.notes,'warmup_s':a.warmup,'scope':'named main process only; excludes WidgetKit host, WindowServer, observer and other apps','summary':analyze(list(csv.DictReader(result.stdout.splitlines())))}
 (a.out/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(report['summary'],ensure_ascii=False))
if __name__=='__main__':main()
