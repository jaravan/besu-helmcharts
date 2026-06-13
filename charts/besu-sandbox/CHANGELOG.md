# Changelog

All notable changes to the **besu-sandbox** chart are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this chart adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The `## [<version>]` section is used as the GitHub Release body by the release
workflow, and must match `Chart.yaml`'s `version` (CI enforces this).

## [Unreleased]

## [0.2.1] - 2026-06-14

### Fixed

- Account permissioning could not start in 0.2.0: the allowlist was mounted
  directly from a ConfigMap, which is **read-only**, but Besu persists the
  allowlist back to its config file on startup — so the node failed immediately
  with `ERROR_ALLOWLIST_PERSIST_FAIL`. The chart now stages
  `accounts-allowlist.toml` from the (read-only) ConfigMap onto a **writable
  `emptyDir`** via a `stage-permissions` init container, and points Besu at the
  writable copy. Account permissioning now starts and works.
- New `permissioning.accounts.stagingImage` value (default `busybox:1.36`) for
  the staging init container; overridable for air-gapped / mirrored registries.

> Note: with the `emptyDir` working copy, runtime `perm_*` changes persist until
> pod restart, after which the allowlist resets to the ConfigMap baseline (the
> ConfigMap remains the source of truth across restarts). See
> `doc/account-permissioning.md`.

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
