#!/usr/bin/env python3
"""Generates ansible/files/grafana/golden-signals.json. Run: python3 scripts/gen_dashboard.py ansible/files/grafana/golden-signals.json"""
import json, sys
DS = {"type": "prometheus", "uid": "prometheus"}
CNT = 'nginx_http_response_count_total'
HB = 'nginx_http_response_time_seconds_hist_bucket'
HC = 'nginx_http_response_time_seconds_hist_count'
pid = 0
def nid():
    global pid; pid += 1; return pid
def tgt(expr, legend="", ref="A"):
    return {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": ref}
def thresholds(steps):
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for c, v in steps]}
def stat(title, expr, x, y, w, h, unit, steps, desc, decimals=None):
    d = {"id": nid(), "type": "stat", "title": title, "description": desc, "datasource": DS,
         "gridPos": {"x": x, "y": y, "w": w, "h": h}, "targets": [tgt(expr)],
         "fieldConfig": {"defaults": {"unit": unit, "thresholds": thresholds(steps), "color": {"mode": "thresholds"}}, "overrides": []},
         "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                     "colorMode": "background", "graphMode": "area", "textMode": "value", "justifyMode": "center"}}
    if decimals is not None: d["fieldConfig"]["defaults"]["decimals"] = decimals
    return d
def ts(title, targets, x, y, w, h, unit, desc, max_=None, threshold=None, stack=False):
    defaults = {"unit": unit, "custom": {"lineWidth": 2, "fillOpacity": 10, "showPoints": "never",
                "stacking": {"mode": "normal" if stack else "none", "group": "A"}}}
    if max_ is not None: defaults["max"] = max_; defaults["min"] = 0
    if threshold is not None:
        defaults["thresholds"] = thresholds([("green", None), ("red", threshold)])
        defaults["custom"]["thresholdsStyle"] = {"mode": "dashed"}
    return {"id": nid(), "type": "timeseries", "title": title, "description": desc, "datasource": DS,
            "gridPos": {"x": x, "y": y, "w": w, "h": h},
            "targets": [tgt(e, l, chr(65 + i)) for i, (e, l) in enumerate(targets)],
            "fieldConfig": {"defaults": defaults, "overrides": []},
            "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}}}
def row(title, y):
    return {"id": nid(), "type": "row", "title": title, "collapsed": False, "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []}

err5m = f'sum by (instance) (rate({CNT}{{status=~"5.."}}[5m])) / sum by (instance) (rate({CNT}[5m]))'
err1h = f'sum(rate({CNT}{{status=~"5.."}}[1h])) / sum(rate({CNT}[1h]))'
p = []
p.append({"id": nid(), "type": "text", "title": "", "gridPos": {"x": 0, "y": 0, "w": 24, "h": 3},
          "options": {"mode": "markdown", "content":
            "### The four golden signals of nginx\n"
            "**Latency** (how long requests take) · **Traffic** (how many requests) · **Errors** (how many fail) · **Saturation** (how full the servers are)  \n"
            "**SLO:** 99% of requests succeed (error budget = 1%) and p95 latency stays under 500 ms. "
            "Generate traffic from your laptop: `make load`, `make load MODE=errors`, `make load MODE=slow`"}})
y = 3
p.append(stat("Availability (SLI, 1h)", f"1 - ({err1h})", 0, y, 5, 5, "percentunit",
              [("red", None), ("orange", 0.95), ("green", 0.99)], "Share of requests that did not return 5xx in the last hour. SLO: 99%.", 2))
p.append(stat("Error budget left (1h)", f"clamp_min(1 - (({err1h}) / 0.01), 0)", 5, y, 5, 5, "percentunit",
              [("red", None), ("orange", 0.01), ("green", 0.5)], "The SLO allows 1% of requests to fail. 100% = nothing used yet; 0% = budget gone, the SLO is broken.", 0))
p.append(stat("p95 latency (5m)", f"histogram_quantile(0.95, sum by (le) (rate({HB}[5m])))", 10, y, 5, 5, "s",
              [("green", None), ("orange", 0.25), ("red", 0.5)], "95% of requests finished faster than this. SLO: under 500 ms.", 3))
p.append(stat("Traffic", f"sum(rate({CNT}[1m]))", 15, y, 5, 5, "reqps",
              [("blue", None)], "Requests per second, all web servers.", 1))
p.append(stat("Firing alerts", 'count(ALERTS{alertstate="firing"}) or vector(0)', 20, y, 4, 5, "none",
              [("green", None), ("red", 1)], "Alerts firing in Prometheus right now (see Prometheus > Alerts).", 0))
y += 5
p.append(row("Latency: how long do requests take?", y)); y += 1
p.append(ts("Request time percentiles", [
    (f"histogram_quantile(0.50, sum by (le) (rate({HB}[1m])))", "p50"),
    (f"histogram_quantile(0.95, sum by (le) (rate({HB}[1m])))", "p95"),
    (f"histogram_quantile(0.99, sum by (le) (rate({HB}[1m])))", "p99")],
    0, y, 12, 8, "s", "Half of the requests are faster than p50, 95% faster than p95. The dashed line is the 500 ms SLO.", threshold=0.5))
p.append(ts("Requests faster than 500 ms", [
    (f'sum(rate({HB}{{le="0.5"}}[1m])) / sum(rate({HC}[1m]))', "fast enough")],
    12, y, 12, 8, "percentunit", "Latency as an SLI: the share of requests that met the 500 ms target.", max_=1))
y += 8
p.append(row("Traffic: how much demand is there?", y)); y += 1
p.append(ts("Requests per second by status", [(f"sum by (status) (rate({CNT}[1m]))", "{{status}}")],
            0, y, 12, 8, "reqps", "From the nginx access log. 2xx = OK, 4xx = client error, 5xx = server error.", stack=True))
p.append(ts("Active connections", [("sum by (instance) (nginx_connections_active)", "{{instance}}")],
            12, y, 12, 8, "short", "Open client connections, from nginx stub_status."))
y += 8
p.append(row("Errors: how many requests fail?", y)); y += 1
p.append(ts("5xx error ratio", [(err5m, "{{instance}}")], 0, y, 12, 8, "percentunit",
            "Share of requests that returned 5xx (5 minute window). The dashed line is the 1% error budget.", threshold=0.01))
p.append(ts("Errors per second", [(f'sum by (status) (rate({CNT}{{status=~"4..|5.."}}[1m]))', "{{status}}")],
            12, y, 12, 8, "reqps", "4xx are usually the client's fault (e.g. 404). 5xx are the server's fault and count against the SLO."))
y += 8
p.append(row("Saturation: how full are the servers?", y)); y += 1
p.append(ts("CPU busy", [('1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[1m]))', "{{instance}}")],
            0, y, 8, 8, "percentunit", "Share of CPU time not idle. Alert above 80% for 5 minutes.", max_=1, threshold=0.8))
p.append(ts("Memory used", [("instance:node_memory_used:ratio", "{{instance}}")],
            8, y, 8, 8, "percentunit", "1 - MemAvailable / MemTotal. Alert above 90%.", max_=1, threshold=0.9))
p.append(ts("Root disk used", [("instance:node_disk_root_used:ratio", "{{instance}}")],
            16, y, 8, 8, "percentunit", "Alert above 85%. Our demo disks are small on purpose.", max_=1, threshold=0.85))

dash = {"uid": "golden-signals", "title": "Nginx Golden Signals", "tags": ["sre", "nginx", "golden-signals"],
        "timezone": "browser", "schemaVersion": 39, "version": 1, "editable": False,
        "refresh": "10s", "time": {"from": "now-30m", "to": "now"}, "panels": p, "templating": {"list": []}, "annotations": {"list": []}}
json.dump(dash, open(sys.argv[1], "w"), indent=2)
print(len(p), "panels")
