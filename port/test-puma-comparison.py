import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class PumaComparisonTest(unittest.TestCase):
    def setUp(self):
        self.receipt = {
            'schema_version': 3,
            'config': {'rounds': 6, 'requests': 100, 'clients': 5, 'idle': 1, 'warmup_rounds': 1},
            'requests_checked': 700,
            'identity': {
                'cpus': [0, 1], 'client_cpus': [2, 3], 'load_generator': 'python-process-pool-v1',
                'driver_sha256': 'driver', 'workload_sha256': 'workload', 'limits': {},
                'python': '3.13.5', 'platform': 'Linux',
                'server': {'ruby': 'release description', 'ruby_version': '4.0.9',
                           'ruby_engine': 'ruby', 'ruby_patchlevel': 0, 'ruby_platform': 'x86_64-linux',
                           'puma': '8.0.2', 'nio4r': '2.7.5', 'threads': 5, 'yjit': False, 'zjit': False},
            },
            'metrics': {
                'rss_kb': {'median': 100, 'peak': 100, 'late_growth': 0},
                'performance': {'requests': 600, 'rounds': [{} for _ in range(6)],
                                'requests_per_second': 100, 'load_seconds': 6,
                                'latency_ms': {'p50': 1, 'p95': 2, 'p99': 3},
                                'max_round_client_cpu_utilization': 0.2},
            },
        }

    def compare(self, filc, stock=None):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / name for name in ('stock.json', 'filc.json')]
            for path, receipt in zip(paths, (stock or self.receipt, filc)):
                path.write_text(json.dumps(receipt))
            return subprocess.run([sys.executable, str(Path(__file__).with_name('compare-puma-memory.py')), *paths],
                                  text=True, capture_output=True)

    def test_patched_revision_is_not_a_version_mismatch(self):
        filc = copy.deepcopy(self.receipt)
        filc['identity']['server']['ruby'] = 'different local revision and build date'
        result = self.compare(filc)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_runtime_identity_must_match(self):
        for key, value in [('ruby_version', '4.0.8'), ('ruby_engine', 'jruby'),
                           ('ruby_patchlevel', 1), ('ruby_platform', 'aarch64-linux'),
                           ('puma', '8.0.1'), ('nio4r', '2.7.4'), ('threads', 4),
                           ('yjit', True), ('zjit', True)]:
            with self.subTest(key=key):
                filc = copy.deepcopy(self.receipt)
                filc['identity']['server'][key] = value
                result = self.compare(filc)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'incomparable server: {key}', result.stderr)

    def test_legacy_receipts_are_rejected(self):
        for version in (1, 2):
            filc = copy.deepcopy(self.receipt)
            filc['schema_version'] = version
            self.assertNotEqual(self.compare(filc).returncode, 0)

    def test_each_memory_gate_is_independent(self):
        for key in ('median', 'peak'):
            with self.subTest(key=key):
                filc = copy.deepcopy(self.receipt)
                filc['metrics']['rss_kb'][key] = 106
                result = self.compare(filc)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'RSS {key}:', result.stdout)

    def test_each_performance_gate_is_independent_of_memory(self):
        for key in ('throughput', 'p50', 'p95', 'p99'):
            with self.subTest(key=key):
                filc = copy.deepcopy(self.receipt)
                filc['metrics']['rss_kb'].update(median=50, peak=50)
                performance = filc['metrics']['performance']
                if key == 'throughput':
                    performance['requests_per_second'] = 94
                else:
                    performance['latency_ms'][key] *= 1.06
                self.assertNotEqual(self.compare(filc).returncode, 0)

    def test_boundaries_are_inclusive(self):
        filc = copy.deepcopy(self.receipt)
        filc['metrics']['rss_kb'].update(median=105, peak=105)
        filc['metrics']['performance']['requests_per_second'] = 95
        # Use exactly representable baselines for all percentile ratios.
        stock = copy.deepcopy(self.receipt)
        for key in ('p50', 'p95', 'p99'):
            stock['metrics']['performance']['latency_ms'][key] = 100
            filc['metrics']['performance']['latency_ms'][key] = 105
        result = self.compare(filc, stock)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_shared_client_server_cpus_are_rejected(self):
        filc = copy.deepcopy(self.receipt)
        filc['identity']['client_cpus'] = [1, 2]
        self.assertNotEqual(self.compare(filc).returncode, 0)

    def test_stock_growth_and_client_saturation_are_not_ignored(self):
        for key in ('growth', 'client_saturation'):
            with self.subTest(key=key):
                stock = copy.deepcopy(self.receipt)
                if key == 'growth':
                    stock['metrics']['rss_kb']['late_growth'] = 6
                else:
                    stock['metrics']['performance']['max_round_client_cpu_utilization'] = 0.81
                self.assertNotEqual(self.compare(self.receipt, stock).returncode, 0)


if __name__ == '__main__':
    unittest.main()
