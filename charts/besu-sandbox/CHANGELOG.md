# Changelog

All notable changes to the **besu-sandbox** chart are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this chart adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The `## [<version>]` section is used as the GitHub Release body by the release
workflow, and must match `Chart.yaml`'s `version` (CI enforces this).

## [Unreleased]

## [0.2.0] - 2026-06-14

### Added

- Account permissioning (transaction authorization), opt-in and **off by
  default** so existing 0.1.0 installs are unaffected. New values:
  `permissioning.accounts.enabled` and `permissioning.accounts.allowlist`.
- When enabled, the chart renders `accounts-allowlist.toml` into the
  `node-permissions` ConfigMap, sets `permissions-accounts-config-file-*` in
  `config.toml`, and appends the `PERM` namespace to the derived
  `rpc-http-api` / `rpc-ws-api` so `perm_*` methods are reachable.
- `values.schema.json` validation for the `permissioning` object (allowlist
  entries must match `^0x[0-9a-fA-F]{40}$`).
- `doc/account-permissioning.md` — enable procedure (sequenced one-at-a-time
  rolling restart to preserve BFT quorum) and runtime allowlist management via
  `perm_*` methods.

## [0.1.0]

### Added

- Initial release: four-validator Hyperledger Besu private network for
  Kubernetes with QBFT consensus by default, switchable to IBFT 2.0.
- Per-validator StatefulSets, PodDisruptionBudget, optional pod anti-affinity.
- Validator key delivery via inline values, existing Secrets, or External
  Secrets Operator.
- Unified round-robin RPC Service, optional GraphQL, ServiceMonitor, and
  NetworkPolicy. `helm test` network-validation hook.
