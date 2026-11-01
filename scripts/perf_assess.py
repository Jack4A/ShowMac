#!/usr/bin/env python3
"""Assess a single capture without turning missing energy/frame coverage into a pass."""
import argparse,json
from pathlib import Path

def assess(report):
 scene=report['scenario'].split('-')[0];s=report['summary']
 targets={'B01':1,'B02':3,'B03':5,'B04':5}
 limits={'cpu_mean_one_core_pct':targets[scene]} if scene in targets else {}
 if scene=='B01':limits['interrupt_wakeups_per_s']=20
 observations={k:{'measured':s[k],'target_max':v,'within_target':s[k]<=v} for k,v in limits.items()}
 return {'scenario':report['scenario'],'observations':observations,'short_sample_warning':s['duration_s']<120,'status':'needs_investigation' if any(not x['within_target'] for x in observations.values()) else 'observed_within_targets' if limits else 'no_target_for_scenario','formal_regression_pass':False,'formal_regression_note':'Requires >=120 s, >=3 alternating runs, long-run memory coverage and actual energy/frame tooling; a single capture is observation only.','coverage':{k:'measured' if s.get(k) is not None else 'unmeasured' for k in ['process_average_watts','actual_fps','animation_hitches']}}

def main():
 p=argparse.ArgumentParser();p.add_argument('summary',type=Path);p.add_argument('--out',type=Path,required=True);a=p.parse_args();result=assess(json.loads(a.summary.read_text()));a.out.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n');print(result['status'])
if __name__=='__main__':main()
