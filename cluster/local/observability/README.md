# Observability overlay (opt-in)

**Status: operational.** Three parallel stacks running, all verified end-to-end.
Part of the [SAP IronCore observability proposal](https://github.tools.sap/ironcore-dev/documentation/issues/51).
Nothing here is applied by `make up`; use `make observability` to deploy.

## Quick Overview

Three parallel stacks in one kind cluster, all scraping the same 5 IronCore
controller-managers (4× :8443 + metalnet :28080):

| Stack | Metrics Collector | Metrics Store | Log Collector | Log Store | Grafana Datasources |
|---|---|---|---|---|---|
| **vm** | vmagent (VMAgent CR) | VMSingle (1d) | fluent-bit DaemonSet | VLSingle (1d) | `vm-metrics` (prometheus type), `vm-logs` (native VL plugin), `vm-logs-loki` (Loki via loki-vl-proxy) |
| **prom** | Prometheus (Prometheus CR) | Prometheus (1d) | fluent-bit Deployment | Loki 3.5 single-binary (1d) | `prom-metrics`, `prom-logs` |
| **otel** | OTel Collector (contrib 0.127) prometheus receiver | → VMSingle (`source=otel`) | OTel Collector filelog receiver | → VLSingle (`_stream_source=otel-collector`) | Shares vm datasources, filter by `source` label |

**Shared infrastructure** (namespace-isolated):
- `monitoring-prom`: prom-operator v0.93.1
- `monitoring-vm`: vm-operator v0.74.1 (no webhook)
- `monitoring-otel` / `opentelemetry-operator-system`: otel-operator v0.158.0
- `monitoring-ui`: Grafana OSS 12.4.3 with projected-volume datasource mount

**Loki-VL-proxy** (ghcr.io/reliablyobserve/loki-vl-proxy:1.63.1) in `monitoring-vm`
translates LogQL → LogsQL for VLSingle. Enables Grafana's native Loki Explore +
Logs Drilldown (works perfectly on Grafana 12.x).

**Log parsing pipeline** (identical in vm + prom fluent-bit configs):
1. CRI parser (containerd format)
2. JSON parser (`Time_Key ts`, `Time_Strict Off`) → zap structured fields at top level, app timestamp used as `_time`
3. logfmt parser (`Time_Key time`, `Time_Strict Off`) → logrus fields at top level (metalbond)
4. Fallback: raw text → `_msg`

## iiab Baseline Changes

Changes required to make IronCore components observable (committed to iiab
proper, not the observability overlay):

| Change | Why |
|---|---|
| `metalnet --metrics-bind-address=0.0.0.0:28080` | Default binds localhost only, unreachable from scrapers |
| `libvirt-provider --metrics-bind-address=0.0.0.0:8080` | Same |
| `containerPort: {name: metrics}` on all 6 components | Without declared `containerPort`, k8s pod SD doesn't surface `__meta_kubernetes_pod_container_port_number` → VMPodScrape/PodMonitor target filters silently drop everything |
| `--zap-encoder=json` opt-in via `IRONCORE_LOG_FORMAT=json` | JSON logs needed for structured extraction. Console-format stays default for `kubectl logs` UX. Gated on env var; `hack/mutate-log-format.sh` patches 6 components |
| Server-side apply (`--server-side --force-conflicts`) | prom-operator CRD annotations exceed the 262144 byte client-side apply limit |

## Known Issues / Still Missing

| Issue | Impact | Fix path |
|---|---|---|
| **libvirt-provider stuck in `Init:0/1`** | Not scraped by any stack (pre-existing iiab bug, not observability-related) | Debug the init container; likely needs a host device/socket |
| **OTel filelog `move` errors** | Some CRI lines (partial/multiline) don't match regex → `attributes.log` missing → non-fatal error spam. `on_error: send` skips gracefully | Add a `router` operator before `move` to handle non-CRI lines, or switch to OTel's built-in `container` parser |
| **Old `_msg` field warnings in VL** | Stale records from pre-fix fluent-bit runs show "missing _msg field" | Will age out with 1d retention; harmless |
| **`dpservice-exporter` CrashLoopBackOff** | iiab TAP mode has no DPDK telemetry socket; can't scrape | Not scrapeable in iiab; dropped from scope |
| **Aggregated apiservers reject `--logging-format=json`** | `ironcore-apiserver` and `ironcore-net-apiserver` don't have `k8s.io/component-base/logs` wiring | Upstream PR needed in `ironcore-dev/ironcore` and `ironcore-dev/ironcore-net` |
| **metalbond (logrus) / dpservice (DPDK EAL)** have no JSON-log CLI switch | logfmt works for metalbond; dpservice is unstructured | Upstream gaps; logfmt parsing covers metalbond |
| **metalnet `/metrics` is HTTPS + authenticated** | Works in testbed (SA token auth); prod needs kube-rbac-proxy or bearer token from `<component>-metrics-reader` ClusterRole | ClusterRoles already exist upstream — just wire the token |
| **VictoriaMetrics 1d minimum retention** | Wanted 1h for quick iteration; VM enforces 1d floor | Acceptable for testbed; long-term tier (1w) is next experiment |
| **Dashboards are starter-only** | Two provisioned dashboards (`IronCore / Controllers`, `IronCore / Logs`) — useful starting points, not battle-tested | Iterate during Experiment A/B review sessions |
| **`VMSingle`/`VLSingle` are singles, not clustered** | No replication, no HA, no per-tenant routing; vmselect tier-merge is hand-wired (injected 8401 sidecar services) | After experiments A/B/C: migrate to operator `VMCluster` with multi-retention storage groups (1d raw + 7d recording-rule tier in ONE cluster), vminsert/vlinsert for ingest, provisioned vmselect/vlselect. Logs keep a single store — no log downsampling exists |
| **prom-operator dropped `bearerTokenFile` from PodMonitor** | Required creating a long-lived SA token Secret for PodMonitor auth — somewhat ugly | Standard pattern for prom-operator ≥0.70; acceptable |

## Layout

```
cluster/local/observability/
├── README.md
├── kustomization.yaml           # top-level; composes shared + stacks
├── shared/                      # things all read-tools need
│   ├── kustomization.yaml
│   ├── namespaces.yaml          # monitoring-ui only
│   └── grafana/                 # Grafana OSS deployment + projected volume
└── stacks/
    ├── kustomization.yaml       # composes all three
    ├── vm/                      # vm-operator + namespace + VMSingle + VLSingle
    │                            # + vmagent + fluent-bit + loki-vl-proxy
    ├── prom/                    # prom-operator + namespace + Prometheus + Thanos
    │                            # + Loki + fluent-bit
    └── otel/                    # otel-operator + namespace + OTel Collector
                                 # (contrib; borrows vm stores)
```

Each stack directory is self-contained: its `namespace.yaml`, operator
(`operator/`), collector, stores and Grafana datasources all live together,
so a stack commit can be cherry-picked or dropped wholesale. Exceptions:
otel borrows the vm stack's stores (drop vm ⇒ drop otel), and every stack's
Grafana datasource lands in the shared `monitoring-ui` namespace.

## Built-in UIs

Each store ships an embedded web UI. These are deliberately **debugging /
exploration surfaces** — no dashboards, no auth, no multi-user sharing.
Grafana remains the user-facing UI; the built-in UIs are where you answer
"is this data actually in the store and what shape does it have?" before
touching Grafana at all.

Access pattern: the vmui apps use relative paths, so the Kubernetes apiserver
proxy works without any extra config (no Ingress, no port-forward per store):

```sh
kubectl proxy --port=8001
```

| UI | URL via apiserver proxy | What it's for |
|---|---|---|
| **VictoriaLogs vmui** | [vlsingle vmui](http://127.0.0.1:8001/api/v1/namespaces/monitoring-vm/services/vlsingle-vlogs:9428/proxy/select/vmui/) | LogsQL editor, stream field/label explorer, per-stream histogram, live tail. **The exploration workhorse for log aggregation**: inspect which streams exist, what fields got parsed (`level`, `logger`, `_stream_source=...`), verify the fluent-bit JSON/logfmt pipeline end-to-end before writing Grafana queries. |
| **VMSingle vmui** | [vmsingle vmui](http://127.0.0.1:8001/api/v1/namespaces/monitoring-vm/services/vmsingle-vm:8428/proxy/vmui/) | PromQL playground against the vm store, cardinality explorer, "which metrics does this component actually emit" |
| **Prometheus UI** | [prometheus](http://127.0.0.1:8001/api/v1/namespaces/monitoring-prom/services/prometheus-operated:9090/proxy/) | Prom targets page (relabel debugging!), classic PromQL |
| **Thanos querier UI** | [thanos-query](http://127.0.0.1:8001/api/v1/namespaces/monitoring-prom/services/thanos-query:10902/proxy/) | Live-vs-longterm store merge, verify that historical blocks exist in MinIO |
| **Loki** | — | No built-in UI (Grafana Explore is its UI) |

Same trick works for any ClusterIP service under
`/api/v1/namespaces/<ns>/services/<name>:<port>/proxy/...` — useful for
probing vmagent/vmalert state endpoints during debugging.

## Usage

```sh
make up             # bring up iiab as usual (unchanged behavior)
make observability  # apply the observability overlay on top

# Grafana at localhost:3000 (port-forward monitoring-ui/grafana)
# 5 datasources: vm-metrics, vm-logs, vm-logs-loki, prom-metrics, prom-logs
# otel data visible via vm datasources with {source="otel"} filter

# iterate on stacks; each stack is independent:
kubectl delete -k .tmp/config/cluster/local/observability/stacks/otel

make down           # tear down iiab (deletes kind cluster)
```

## Clean Comparisons Enabled

- **Metrics store**: Prometheus vs. VictoriaMetrics — `prom` vs. `vm`
- **Log store**: Loki vs. VictoriaLogs — `prom` vs. `vm`
- **Metrics collector**: vmagent vs. OTel Collector vs. Prometheus — `vm` vs. `otel` vs. `prom`
- **Log shipper**: fluent-bit vs. OTel Collector — `vm`/`prom` vs. `otel`
- **Log UI**: native VL plugin (LogsQL) vs. Loki datasource via proxy (LogQL) — same data, two UIs

## Not in Scope

- Modifying `make up` — the overlay is deliberately separate
- Deciding the final stack — this is the experimentation surface
- Upstream PRs to `ironcore-dev/*` — discoveries here inform targeted PRs later
- Tracing (per IEP #60)
