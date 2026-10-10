#!/usr/bin/env python3
"""Prints the XCTest metrics of one or more .xcresult bundles as a table.

    python3 -I docs/perf/extract_metrics.py run.xcresult [more.xcresult ...]
"""
import json
import subprocess
import sys

WANTED = {
    "Clock Monotonic Time": "time",
    "CPU Time": "cpu time",
    "Absolute Memory Physical": "memory (end)",
    "Memory Peak Physical": "memory (peak)",
    "Hitch Time Ratio": "hitch ratio",
    "Hitches": "hitches",
}

def rows(path):
    out = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", path],
        capture_output=True, text=True, check=True).stdout
    for test in json.loads(out):
        name = test["testIdentifier"].replace("()", "")
        for run in test["testRuns"]:
            values = {}
            for metric in run["metrics"]:
                label = next((v for k, v in WANTED.items() if metric["displayName"].startswith(k)), None)
                if label and metric["measurements"]:
                    values[label] = f'{metric["measurements"][0]:,.1f} {metric["unitOfMeasurement"]}'
            yield name, values

if __name__ == "__main__":
    for path in sys.argv[1:]:
        print(path)
        for name, values in rows(path):
            print(f"  {name}")
            for key, value in values.items():
                print(f"    {key:14} {value}")
