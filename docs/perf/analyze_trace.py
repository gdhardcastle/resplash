#!/usr/bin/env python3
"""Reads a Time Profiler trace made by profile.sh and prints CPU per phase.

    python3 -I docs/perf/analyze_trace.py perf-traces/loader-Time-Profiler.trace

Phases are the spans between the app's Points of Interest markers. For each: CPU time of the whole
process and of the main thread (1 ms per running sample), and the app's most expensive functions on
the main thread by inclusive samples, and which libraries the main thread's time is spent in.
"""
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter

PHASES = ["1 scroll down", "2 scroll back", "3 pager"]

def export(trace, xpath):
    return subprocess.Popen(
        ["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout

def markers(trace):
    """Marker times in ns, in order."""
    found = []
    xpath = '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost" and @category="PointsOfInterest"]'
    for _, el in ET.iterparse(export(trace, xpath), events=["end"]):
        if el.tag == "row":
            name = el.find("signpost-name")
            if name is not None and name.get("fmt", "").startswith("Phase"):
                found.append(int(el.find("event-time").text))
            el.clear()
    return sorted(found)

def analyse(trace):
    bounds = markers(trace)
    if len(bounds) != 3:
        sys.exit(f"expected 3 phase markers, found {len(bounds)}")
    edges = [0, *bounds[:2], bounds[2]]  # phase 1 is launch to the first marker, 3 ends at the last

    ids = {}        # id -> (fmt, text), so a later `ref` can be resolved
    stacks = {}     # backtrace id -> [(function, binary)]
    binaries = {}   # binary id -> name
    frame_by_id = {}  # frame id -> (function, binary)
    cpu = [Counter() for _ in PHASES]       # "all" / "main" -> ms
    inclusive = [Counter() for _ in PHASES]
    by_library = [Counter() for _ in PHASES]   # binary of the innermost frame -> ms, main thread

    def field(row, tag):
        node = row.find(tag)
        if node is None:
            return None, None
        return ids.get(node.get("ref")) if node.get("ref") else (node.get("fmt"), node.text)

    xpath = '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'
    for _, el in ET.iterparse(export(trace, xpath), events=["end"]):
        if el.tag != "row":
            continue
        for node in el.iter():
            if node.get("id"):
                ids[node.get("id")] = (node.get("fmt"), node.text)

        time = int(field(el, "sample-time")[1])
        phase = next((i for i in range(3) if edges[i] <= time < edges[i + 1]), None)
        if phase is not None and field(el, "thread-state")[0] == "Running":
            weight_ms = int(field(el, "weight")[1]) / 1e6
            cpu[phase]["all"] += weight_ms
            if (field(el, "thread")[0] or "").startswith("Main Thread"):
                cpu[phase]["main"] += weight_ms
                backtrace = el.find("tagged-backtrace")
                if backtrace is None:
                    el.clear()
                    continue
                key = backtrace.get("id") or backtrace.get("ref")
                if backtrace.get("id"):
                    frames = []
                    for frame in backtrace.iter("frame"):
                        if frame.get("ref"):               # a frame already seen in an earlier stack
                            frames.append(frame_by_id.get(frame.get("ref"), (None, None)))
                            continue
                        binary = frame.find("binary")
                        if binary is not None and binary.get("name"):
                            binaries[binary.get("id")] = binary.get("name")
                        binary_id = None if binary is None else binary.get("id") or binary.get("ref")
                        entry = (frame.get("name"), binaries.get(binary_id))
                        frame_by_id[frame.get("id")] = entry
                        frames.append(entry)
                    stacks[key] = frames
                leaf = stacks.get(key, [(None, None)])[0][1] or "(unknown)"
                by_library[phase][leaf] += weight_ms
                for name in {n for n, b in stacks.get(key, []) if b == "Resplash"}:
                    inclusive[phase][name] += weight_ms
        el.clear()

    for i, name in enumerate(PHASES):
        span = (edges[i + 1] - edges[i]) / 1e9
        print(f"\nPhase {name}  ({span:.1f} s)")
        print(f"  process CPU {cpu[i]['all'] / 1000:6.2f} s  ({cpu[i]['all'] / 10 / span:5.1f}% of one core)")
        print(f"  main thread {cpu[i]['main'] / 1000:6.2f} s  ({cpu[i]['main'] / 10 / span:5.1f}% of the phase)")
        total = cpu[i]["main"] or 1
        print("  main thread, where the innermost frame is:")
        for library, ms in by_library[i].most_common(5):
            print(f"    {ms / 1000:6.2f} s  {100 * ms / total:4.1f}%  {library}")
        print("  the app's own functions on the main thread (inclusive):")
        for function, ms in inclusive[i].most_common(6):
            print(f"    {ms:7.0f} ms  {function[:90]}")

if __name__ == "__main__":
    analyse(sys.argv[1])
