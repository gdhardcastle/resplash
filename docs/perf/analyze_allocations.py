#!/usr/bin/env python3
"""Prints the Allocations statistics of a trace made by profile.sh: live and total bytes by category.

    python3 -I docs/perf/analyze_allocations.py perf-traces/loader-Allocations.trace

These are whole-run figures: live bytes at the end of the recording, and everything allocated during it.
"""
import re
import subprocess
import sys

XPATH = '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]'
SHOWN = ("All Heap & Anonymous VM", "All Heap Allocations", "All Anonymous VM")

def main(trace):
    xml = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", XPATH],
                         capture_output=True, text=True, check=True).stdout
    print(trace)
    for category, persistent, total, events in re.findall(
            r'<row category="([^"]*)" persistent-bytes="(\d+)" count-persistent="\d+" '
            r'total-bytes="(\d+)" transient-bytes="\d+" count-events="(\d+)"', xml):
        category = category.replace("&amp;", "&")
        if category in SHOWN or category.startswith(("VM: CG", "VM: ImageIO", "VM: IOSurface")):
            print(f"  {category:30} live {int(persistent) / 1e6:8.1f} MB   "
                  f"allocated in total {int(total) / 1e6:9.1f} MB   events {int(events):>11,}")

if __name__ == "__main__":
    for path in sys.argv[1:]:
        main(path)
