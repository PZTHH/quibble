import unittest
from benchmark_metrics import word_errors

class BenchmarkMetricsTests(unittest.TestCase):
    def test_dropped_negation_counts_as_an_error(self):
        self.assertEqual(word_errors("Do not send it", "Do send it"), 1)

if __name__ == "__main__":
    unittest.main()
