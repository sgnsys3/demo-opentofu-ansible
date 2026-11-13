#!/usr/bin/env python3
"""Tiny load generator for the golden-signals demo (Python standard library only).

Sends HTTP requests to every host in the [web] group of ansible/inventory.ini.

  python3 scripts/loadgen.py                      # healthy traffic
  python3 scripts/loadgen.py --mode errors        # ~20% of requests fail with 500 -> burns the error budget
  python3 scripts/loadgen.py --mode slow          # ~30% of requests take ~1 s -> p95 latency goes up
  python3 scripts/loadgen.py --rps 50 --duration 120
"""
import argparse
import random
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

INVENTORY = Path(__file__).resolve().parent.parent / "ansible" / "inventory.ini"

# path -> weight, per mode
MODES = {
    "normal": {"/": 95, "/missing-page": 4, "/slow": 1},
    "errors": {"/": 75, "/error": 20, "/missing-page": 5},
    "slow":   {"/": 70, "/slow": 30},
}


def web_hosts():
    """Return the ansible_host of every host in the [web] group."""
    hosts, group = [], None
    for line in INVENTORY.read_text().splitlines():
        line = line.strip()
        if line.startswith("["):
            group = line.strip("[]")
        elif group == "web" and line and not line.startswith("#"):
            m = re.search(r"ansible_host=(\S+)", line)
            if m:
                hosts.append(m.group(1))
    return hosts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=MODES, default="normal")
    ap.add_argument("--rps", type=float, default=20, help="requests per second (default 20)")
    ap.add_argument("--duration", type=int, default=300, help="seconds to run (default 300)")
    ap.add_argument("--url", action="append", help="base URL to hit (default: [web] hosts from the inventory)")
    args = ap.parse_args()

    bases = args.url or [f"http://{h}" for h in web_hosts()]
    if not bases:
        sys.exit(f"No [web] hosts found in {INVENTORY}. Run `make instance` first, or pass --url.")

    paths, weights = zip(*MODES[args.mode].items())
    stats, lock = Counter(), threading.Lock()

    def hit():
        url = random.choice(bases) + random.choices(paths, weights)[0]
        try:
            with urllib.request.urlopen(url, timeout=10) as r:
                r.read()
                code = r.status
        except urllib.error.HTTPError as e:
            code = e.code
        except Exception:
            code = "conn-error"
        with lock:
            stats[code] += 1

    print(f"mode={args.mode} rps={args.rps} duration={args.duration}s targets={bases}")
    print("Watch Grafana while this runs. Press Ctrl+C to stop.\n")
    start = next_report = time.monotonic()
    interval = 1 / args.rps
    with ThreadPoolExecutor(max_workers=64) as pool:
        try:
            i = 0
            while time.monotonic() - start < args.duration:
                pool.submit(hit)
                i += 1
                time.sleep(max(0, start + i * interval - time.monotonic()))
                if time.monotonic() >= next_report:
                    next_report += 5
                    with lock:
                        summary = "  ".join(f"{k}={v}" for k, v in sorted(stats.items(), key=str))
                    print(f"[{int(time.monotonic() - start):4d}s] {summary}", flush=True)
        except KeyboardInterrupt:
            print("\nStopping...")
    print("Done:", dict(stats))


if __name__ == "__main__":
    main()
