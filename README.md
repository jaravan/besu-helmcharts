# Hyperledger Besu Helm Charts

Helm charts for running [Hyperledger Besu](https://besu.hyperledger.org/) on
Kubernetes. This repository follows the usual **multi-chart layout**: each chart
lives under `charts/<name>/` with its own `Chart.yaml`, `values.yaml`, templates,
and README.

## Repository layout

```text
.
├── LICENSE
├── README.md                 ← you are here
├── .github/workflows/besu-sandbox-ci.yaml  ← besu-sandbox: lint, Checkov, kind test
├── scripts/checkov-scan.sh                 ← local Checkov for besu-sandbox
└── charts/
    ├── besu-sandbox/         ← local QBFT/IBFT2 sandbox network
    └── …                     ← additional charts as they land
```

Install and lint paths are always **relative to this repository root**, e.g.
`charts/besu-sandbox`, not the chart subdirectory alone (unless you `cd` into it
first — see each chart README).

## Sandbox disclaimer

**Do not use `besu-sandbox` in production or on networks that hold real value.**

`besu-sandbox` embeds validator private keys and pre-funded dev account keys in
manifests and `values.yaml` by design. Anyone with chart access can read them.
There is no HSM, Vault integration, or network hardening suitable for a
regulated consortium.

Each chart may carry its own caveats; read that chart's README before installing.

## Charts

| Chart                                  | Description                                                                                                           | Documentation                                                                                                          |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| [`besu-sandbox`](charts/besu-sandbox/) | Four-validator QBFT (or IBFT 2.0) private network in one `helm install` — tuned for kind/minikube and portfolio demos | [README](charts/besu-sandbox/README.md) · [example overlay](charts/besu-sandbox/examples/values-external-secrets.yaml) |

Additional charts will be added under `charts/` as the collection grows (e.g.
observability, key management helpers). This table is the index — configuration
and values reference live in **each chart's README**, not here.

## Quick start

From the **repository root**:

```sh
# Install a chart (example: besu-sandbox)
helm upgrade --install sbx charts/besu-sandbox \
  -n besu --create-namespace --wait --timeout=600s

# Optional post-install check (besu-sandbox only)
helm test sbx -n besu --timeout 300s --logs
```

General pattern for any chart in this repo:

```sh
helm lint charts/<chart-name>
helm upgrade --install <release> charts/<chart-name> -n <namespace> --create-namespace
```

For OCI installs after publish, use the chart name from that chart's `Chart.yaml`
(e.g. `oci://<registry>/<owner>/besu-sandbox`).

## CI and local checks

GitHub Actions ([`besu-sandbox-ci.yaml`](.github/workflows/besu-sandbox-ci.yaml))
runs on PRs that touch `charts/besu-sandbox/` (other charts will get their own
workflows as they are added):

| Job                                 | What it runs                                          |
| ----------------------------------- | ----------------------------------------------------- |
| **besu-sandbox / helm lint**        | `helm lint` + `helm template`                         |
| **besu-sandbox / checkov**          | Render manifests → Checkov (skips in `.checkov.yaml`) |
| **besu-sandbox / kind + helm test** | `helm install` on kind + `helm test`                  |

Local Checkov (same skips as CI):

```sh
./scripts/checkov-scan.sh
```

## Prior art

Early exploration used raw Kubernetes manifests from
[Consensys/quorum-kubernetes](https://github.com/Consensys/quorum-kubernetes)
([`playground/kubectl/quorum-besu/ibft2`](https://github.com/Consensys/quorum-kubernetes/tree/master/playground/kubectl/quorum-besu/ibft2))
and was rewritten as an independent Helm chart. It is not a fork of ConsenSys Helm
charts and is not maintained by ConsenSys.


## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
