#!/usr/bin/env python3
"""Prints hitches per phase from an Animation Hitches trace made by profile.sh.

    python3 -I docs/perf/analyze_hitches.py perf-traces/loader-Animation-Hitches.trace

Phases are the spans between the app's Points of Interest markers. Reports hitches the app caused (not
system ones): how many, their total duration, and the ratio in ms per second, which Apple's guidance
rates under 5 ms/s good, 5 to 10 warning and over 10 critical.
"""
import subprocess
import sys
import xml.etree.ElementTree as ET

def export(trace, schema):
    xpath = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
    return subprocess.Popen(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout

def rows(trace, schema):
    """Yields each row's children as {tag: (fmt, text)}, resolving refs to earlier rows."""
    ids = {}
    for _, row in ET.iterparse(export(trace, schema), events=["end"]):
        if row.tag != "row":
            continue
        values = {}
        for child in row:
            if child.get("ref"):
                values[child.tag] = ids.get(child.get("ref"), (None, None))
            else:
                values[child.tag] = (child.get("fmt"), child.text)
            if child.get("id"):
                ids[child.get("id")] = values[child.tag]
            for node in child.iter():
                if node.get("id") and node is not child:
                    ids[node.get("id")] = (node.get("fmt"), node.text)
        yield values
        row.clear()

def main(trace):
    # Marker name prefix -> time (ns). Signposts can be dropped under load, so work with what survived.
    found = {}
    for v in rows(trace, "os-signpost"):
        name = (v.get("signpost-name") or (None,))[0] or ""
        if name.startswith("Phase") and "event-time" in v:
            found.setdefault(name[:7], int(v["event-time"][1]))   # "Phase 1", "Phase 2", "Phase 3"
    pager_opened, pager_closed = found.get("Phase 2"), found.get("Phase 3")
    if pager_opened is None or pager_closed is None:
        sys.exit("the pager markers are missing: add the Points of Interest instrument")
    if "Phase 1" in found:
        spans = [("1 scroll down", 0, found["Phase 1"]), ("2 scroll back", found["Phase 1"], pager_opened)]
    else:
        spans = [("1+2 scrolling", 0, pager_opened)]
        print("  (the phase 1 marker was dropped from this trace: scrolling is reported as one span)")
    spans.append(("3 pager", pager_opened, pager_closed))

    durations = [[] for _ in spans]
    for v in rows(trace, "hitches"):
        if v.get("is-system", (None,))[0] == "Yes":
            continue
        start, duration = int(v["start-time"][1]), int(v["duration"][1])
        for i, (_, begin, end) in enumerate(spans):
            if begin <= start < end:
                durations[i].append(duration / 1e6)  # ms
    print(trace)
    for (name, begin, end), hitches in zip(spans, durations):
        span = (end - begin) / 1e9
        total = sum(hitches)
        print(f"  {name:14} {span:6.1f} s   {len(hitches):4d} hitches   {total:8.1f} ms   "
              f"{total / span:5.2f} ms/s   longest {max(hitches, default=0):5.1f} ms")

if __name__ == "__main__":
    for path in sys.argv[1:]:
        main(path)
