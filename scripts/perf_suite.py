#!/usr/bin/env python3
"""Reproducible fixture stress suite. No hardware control or UI automation."""
import argparse
import csv
import hashlib
import json
import math
import os
import platform
import signal
import statistics
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from perf_capture import analyze

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    'smoke': {'seconds': 8, 'seeds': [1, 42], 'samples': 20000},
    'standard': {'seconds': 120, 'seeds': [1, 42, 2026], 'samples': 20000},
    'soak': {'seconds': 1800, 'seeds': [2026], 'samples': 20000},
}
DEFAULT_BUDGETS = {
    'batch_200_p95_ms': 250, 'menu_history_p95_ms': 16.7,
    'footprint_peak_mib': 512, 'long_run_growth_mib_per_minute': 5,
    'regression_fraction': .25, 'regression_absolute_ms': .5,
}


def validate_binary(binary):
    data = binary.read_bytes()
    # Long diagnostic literals remain in optimized Swift binaries; short CLI flags may be immediate constants.
    markers = (b'hidden_stream_must_not_notify_views', b'visibility_notification_count',
               b'history_end_must_not_rewind_on_stale_sample')
    if any(marker not in data for marker in markers):
        raise ValueError('Binary lacks the isolated fixture harness; refusing to launch a normal app as stress input')
    return hashlib.sha256(data).hexdigest()


def growth(rows):
    """OLS slope after initial 20% warmup, only for >=120s captures."""
    if len(rows) < 2:
        return None
    times = [float(r['monotonic_s']) for r in rows]
    if times[-1] - times[0] < 120:
        return None
    cutoff = times[0] + (times[-1] - times[0]) * .2
    pairs = [(t, float(r['footprint_bytes']) / 2**20) for t, r in zip(times, rows) if t >= cutoff]
    center = statistics.mean(t for t, _ in pairs)
    memory = statistics.mean(v for _, v in pairs)
    divisor = sum((t-center)**2 for t, _ in pairs)
    return 60 * sum((t-center)*(v-memory) for t, v in pairs) / divisor if divisor else None


def assess_run(fixture, capture, budgets):
    problems = list(fixture.get('invariant_failures', []))
    if fixture.get('status') != 'passed':
        problems.append('fixture_failed')
    observations = {
        'batch_200_p95_ms': fixture['batch_200_samples']['p95_ms'],
        'menu_history_p95_ms': fixture['history_and_menu_render']['p95_ms'],
        'footprint_peak_mib': capture['footprint_peak_mib'],
        'long_run_growth_mib_per_minute': capture.get('footprint_growth_mib_per_minute'),
    }
    for key, value in observations.items():
        if value is not None and (not math.isfinite(value) or value > budgets[key]):
            problems.append('budget:' + key)
    return {'status': 'failed' if problems else 'passed', 'problems': problems, 'metrics': observations,
            'long_memory_coverage': observations['long_run_growth_mib_per_minute'] is not None}


def compare(current, baseline, budgets):
    # Binary hash deliberately differs; all workload and host identity fields must match.
    for key in ('profile', 'workload_config', 'workloads', 'host', 'budgets'):
        if current.get(key) != baseline.get(key):
            return {'status': 'incompatible', 'reason': key + ' differs', 'regressions': []}
    if baseline.get('status') != 'passed' or not baseline.get('runs'):
        return {'status': 'incompatible', 'reason': 'baseline must be a passing completed run', 'regressions': []}
    regressions = []
    for scene in current['workloads']:
        for metric in ('batch_200_p95_ms', 'menu_history_p95_ms'):
            a = [r['assessment']['metrics'][metric] for r in current['runs'] if r['scenario'] == scene]
            b = [r['assessment']['metrics'][metric] for r in baseline['runs'] if r['scenario'] == scene]
            if not a or len(a) != len(b):
                return {'status': 'incompatible', 'reason': 'missing workload repeats', 'regressions': []}
            now, old = statistics.median(a), statistics.median(b)
            if now > old * (1 + budgets['regression_fraction']) and now-old > budgets['regression_absolute_ms']:
                regressions.append({'scenario': scene, 'metric': metric, 'baseline': old, 'current': now})
    return {'status': 'regressed' if regressions else 'within_targets', 'regressions': regressions,
            'note': 'Same-host synthetic timings; repeat with alternating versions to establish causality.'}


def command(argv, destination, timeout=180):
    process = subprocess.Popen([str(a) for a in argv], cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        stop_owned(process)
        stdout, stderr = process.communicate()
        destination.write_text(stdout + '\nSTDERR:\n' + stderr + '\nINTERRUPTED OR TIMED OUT\n')
        raise
    destination.write_text(stdout + '\nSTDERR:\n' + stderr)
    return subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)


def stop_owned(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def write_report(report, out):
    (out/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)+'\n')
    lines = ['# ThermalScope performance and stress report', '',
             f"Result: **{report['status']}**", f"Profile: {report['profile']}; started: {report['started_local']}", '',
             'All stress inputs are fixtures. No fan, Turbo, power setting, or running production app is changed.', '',
             '| Scenario / seed | Samples | Samples/s | Batch p95 ms | Menu p95 ms | Peak MiB | Result |',
             '|---|---:|---:|---:|---:|---:|---|']
    for r in report['runs']:
        f, c = r['fixture'], r['capture']
        lines.append(f"| {r['scenario']} / {r['seed']} | {f['samples']} | {f['samples_per_second']:.0f} | {f['batch_200_samples']['p95_ms']:.2f} | {f['history_and_menu_render']['p95_ms']:.2f} | {c['footprint_peak_mib']:.1f} | {r['assessment']['status']} |")
    lines += ['', '## Findings', ''] + ['- '+p for p in report['problems']]
    if not report['problems']:
        lines.append('- No tested invariant or configured budget failed.')
    lines += ['', '## Coverage limits', '',
              '- Synthetic saturation CPU is throughput load, not an idle CPU or battery budget.',
              '- CPU-side menu generation timings are not screen FPS or animation hitch measurements.',
              '- Memory slope is reported only for captures >=120 s; short runs cannot establish absence of leaks.',
              '- Real UI clicks, hardware control, sleep/wake, WindowServer/GPU and whole-machine power remain separate manual/instrumented gates.',
              '- Passing this suite is not a claim that the application has no bugs.', '',
              'Raw logs, fixture JSON and sampler CSV are retained beside this report.']
    (out/'report.md').write_text('\n'.join(lines)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=PROFILES, default='smoke')
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--scenario', action='append', choices=['hidden', 'visible', 'mixed'], help='Limit scenarios; repeatable')
    parser.add_argument('--seed', action='append', type=int, help='Override fixed seeds; repeatable unsigned 64-bit integer')
    parser.add_argument('--binary', type=Path, help='Existing release ThermalScope executable; otherwise builds release')
    parser.add_argument('--baseline', type=Path, help='Prior report.json for same host/workload comparison')
    args = parser.parse_args()
    out = args.out.resolve()
    # Never overwrite evidence from an earlier run.
    out.mkdir(parents=True, exist_ok=False)
    profile = dict(PROFILES[args.profile])
    if args.seed:
        if any(seed < 0 or seed >= 2**64 for seed in args.seed):
            parser.error('seed must fit UInt64')
        profile['seeds'] = list(dict.fromkeys(args.seed))
    report = {'schema': 1, 'status': 'running', 'profile': args.profile,
              'started_local': datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
              'workload_config': profile,
              'host': {'os': platform.platform(), 'machine': platform.machine(), 'logical_cpus': os.cpu_count(),
                       'host_id_hash': hashlib.sha256(platform.node().encode()).hexdigest()[:16],
                       'hardware': subprocess.check_output(['sysctl', '-n', 'hw.model'], text=True).strip()},
              'workloads': list(dict.fromkeys(args.scenario or ['hidden', 'visible', 'mixed'])), 'budgets': DEFAULT_BUDGETS,
              'runs': [], 'checks': {}, 'problems': [], 'coverage': {'fixture_stress': True, 'real_ui': False,
              'hardware_control': False, 'actual_fps': None, 'animation_hitches': None, 'whole_machine_watts': None}}
    try:
        if args.binary:
            binary = args.binary.resolve()
        else:
            build = command(['swift', 'build', '-c', 'release', '--jobs', '2'], out/'build.log', 600)
            if build.returncode:
                raise RuntimeError('release build failed; see build.log')
            binary_dir = subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=ROOT, text=True).strip()
            binary = Path(binary_dir)/'ThermalScope'
        report['binary'] = str(binary)
        report['binary_sha256'] = validate_binary(binary)
        sampler = out/'perf-sample'
        if command(['xcrun', 'clang', '-O2', ROOT/'tools/perf-sample.c', '-o', sampler], out/'sampler-build.log').returncode:
            raise RuntimeError('sampler compilation failed')
        checks = {
            'python_contracts': [sys.executable, '-m', 'unittest', 'discover', '-s', 'Tests/Performance', '-v'],
            'core_functional': ['swift', 'run', '-c', 'release', '--jobs', '2', 'ThermalCoreChecks'],
            'hidden_updates': [binary, '--hidden-view-update-check'],
            'render_microbenchmark': [binary, '--render-performance-check'],
        }
        for name, argv in checks.items():
            print('CHECK', name, flush=True)
            result = command(argv, out/(name+'.log'), 600)
            report['checks'][name] = {'exit_code': result.returncode}
            if result.returncode:
                report['problems'].append('check:'+name)
            if name == 'render_microbenchmark' and result.returncode == 0:
                micro = json.loads(result.stdout)
                (out/'render-metrics.json').write_text(json.dumps(micro, indent=2)+'\n')
                if micro['menu_image_cpu_render']['p95_ms'] > DEFAULT_BUDGETS['menu_history_p95_ms']:
                    report['problems'].append('budget:render_microbenchmark_p95')
        for seed in profile['seeds']:
            for scene in report['workloads']:
                print('STRESS', scene, 'seed', seed, flush=True)
                folder = out/f'{scene}-{seed}'
                folder.mkdir()
                argv = ['/usr/bin/nice', '-n', '10', str(binary), '--stress-check', '--stress-scenario', scene,
                        '--stress-seconds', str(profile['seconds']+2), '--stress-seed', str(seed),
                        '--stress-samples', str(profile['samples']), '--stress-out', str(folder/'fixture.json')]
                with (folder/'process.log').open('w') as log:
                    child = subprocess.Popen(argv, stdout=log, stderr=log, start_new_session=True)
                    try:
                        result = command([sampler, child.pid, profile['seconds']], folder/'sampler.log', profile['seconds']+15)
                        (folder/'samples.csv').write_text(result.stdout)
                        rc = child.wait(timeout=profile['seconds']+30)
                        if result.returncode:
                            raise RuntimeError(f'{scene}/{seed}: sampler failed or child crashed; see raw logs')
                        fixture = json.loads((folder/'fixture.json').read_text())
                        rows = list(csv.DictReader(result.stdout.splitlines()))
                        capture = analyze(rows)
                        capture['footprint_growth_mib_per_minute'] = growth(rows)
                        (folder/'capture.json').write_text(json.dumps(capture, indent=2)+'\n')
                        assessment = assess_run(fixture, capture, DEFAULT_BUDGETS)
                        if rc != 0:
                            assessment['status'] = 'failed'
                            assessment['problems'].append('process_exit:'+str(rc))
                        report['runs'].append({'scenario': scene, 'seed': seed, 'fixture': fixture,
                                               'capture': capture, 'assessment': assessment})
                        report['problems'].extend(f'{scene}/{seed}: '+p for p in assessment['problems'])
                    finally:
                        stop_owned(child)
        report['status'] = 'failed' if report['problems'] else 'passed'
        if args.baseline:
            comparison = compare(report, json.loads(args.baseline.read_text()), DEFAULT_BUDGETS)
            report['comparison'] = comparison
            if comparison['status'] != 'within_targets':
                report['problems'].append('baseline:'+comparison['status'])
                report['status'] = 'failed'
    except (Exception, KeyboardInterrupt) as error:
        report['status'] = 'failed'
        report['problems'].append(type(error).__name__+': '+str(error))
    finally:
        write_report(report, out)
    print(report['status'].upper(), out/'report.md', flush=True)
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
