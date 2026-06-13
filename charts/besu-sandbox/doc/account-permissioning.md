# Account permissioning (transaction authorization)

File-based account permissioning restricts **which accounts may submit
transactions**. When `permissioning.accounts.enabled=true`, only accounts in the
allowlist are accepted by the node; transactions from any other account are
rejected. This is independent of the **balance gate** (Besu's layered txpool also
refuses a zero-balance sender) — a new consortium participant needs **both** an
allowlist entry **and** a non-zero balance before their transactions are mined.

> **Release-name assumption:** examples use release name `sbx` in namespace
> `besu` (`helm install sbx charts/besu-sandbox -n besu`). Adjust pod /
> StatefulSet names if yours differs.

OFF by default — existing installs are unaffected.

---

## What the chart renders when enabled

| Value                                 | Effect                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `permissioning.accounts.enabled=true` | Adds `permissions-accounts-config-file-enabled=true` + `permissions-accounts-config-file="/etc/permissions/accounts-allowlist.toml"` to `config.toml`, renders `accounts-allowlist.toml` into the `node-permissions` ConfigMap, stages it onto a **writable `emptyDir`** at `/etc/permissions` via a `stage-permissions` init container, and appends `PERM` to the derived `rpc-http-api` / `rpc-ws-api` so `perm_*` methods are reachable. |
| `permissioning.accounts.allowlist`    | The `0x` addresses permitted to submit transactions.                                                                                                                                                                                                                                                                                                                                                                                        |
| `permissioning.accounts.stagingImage` | Init-container image (default `busybox:1.36`) that copies the allowlist onto the writable volume. Override for air-gapped / mirrored registries.                                                                                                                                                                                                                                                                                            |

> **Why the staging step (the 0.2.0 → 0.2.1 fix):** Besu _persists_ the allowlist
> back to its config file on startup, so the file must be on a writable volume. A
> ConfigMap mount is always read-only, which made 0.2.0 fail immediately with
> `ERROR_ALLOWLIST_PERSIST_FAIL`. The chart now stages the ConfigMap copy onto a
> writable `emptyDir`. Consequence: the **ConfigMap is the source of truth across
> restarts** — on each pod start the live file is re-seeded from it, so runtime
> `perm_*` changes are lost on restart unless also written back to values/ConfigMap.

```yaml
permissioning:
  accounts:
    enabled: true
    allowlist:
      - "0x5e6bb0a9afcae09c2d0aebc85a71b08ec4118e5f" # genesis-funded / treasury
      - "0x9418ba4c44ebb8370a890121614028731119e31f"
```

> When enabling on an **existing** network, the allowlist MUST include every
> account that legitimately sends transactions (genesis-funded / treasury
> accounts) or they will immediately start being rejected.

---

## Enabling on a running network — sequenced rolling restart

`permissions-accounts-config-file-enabled` is read **only at node startup**, so
enabling the feature on a running network requires restarting the validators.

Each validator is its own StatefulSet, so a `helm upgrade` does **not** restart
them in sequence automatically — and the chart deliberately does **not** add a
config-checksum annotation, because that would recreate all validator pods at
once, which is **quorum loss** (BFT needs `2f+1` of `3f+1` online).

Restart **one validator at a time**, waiting for each to become Ready and rejoin
before moving to the next:

```sh
helm upgrade sbx charts/besu-sandbox -n besu \
  --set permissioning.accounts.enabled=true \
  --set 'permissioning.accounts.allowlist={0x5e6...,0x941...}'

# Then, one at a time (preserving quorum throughout):
for n in 1 2 3 4; do
  kubectl rollout restart statefulset/sbx-validator$n -n besu
  kubectl rollout status  statefulset/sbx-validator$n -n besu --timeout=300s
  # confirm it has rejoined before the next:
  kubectl exec -n besu sbx-validator$n-0 -- \
    curl -s -X POST localhost:8545 \
    -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}'
done
```

---

## Runtime allowlist changes (no restart)

Once enabled, you can change who is allowed **without** a restart. Two paths:

| Method                                                             | Effect                                                                                    | Persists restart? | Latency                                    |
| ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- | ----------------- | ------------------------------------------ |
| `perm_getAccountsAllowlist`                                        | read the current in-memory allowlist                                                      | —                 | immediate                                  |
| `perm_addAccountsToAllowlist` / `perm_removeAccountsFromAllowlist` | change the in-memory allowlist                                                            | **No**            | immediate                                  |
| `perm_reloadPermissionsFromFile`                                   | re-read `accounts-allowlist.toml` from the **staged writable copy** at `/etc/permissions` | until pod restart | immediate (reads the live file in the pod) |

> **The staged copy — not the ConfigMap mount — is what Besu reads.** Because the
> live file is an `emptyDir` seeded once at pod start, **`kubectl edit configmap`
> does NOT change the live file**, and `perm_reloadPermissionsFromFile` will not
> pick up a ConfigMap edit. To change the allowlist:
>
> - **Runtime (no restart):** use `perm_addAccountsToAllowlist` /
>   `perm_removeAccountsFromAllowlist` (writes through to the staged file). Lost
>   on pod restart, when the file is re-seeded from the ConfigMap.
> - **Durable across restart:** `helm upgrade` with the new `allowlist` (updates
>   the ConfigMap), then restart each validator one at a time so the init
>   container re-stages the file (see the rolling-restart procedure above).

> **Apply on every node that validates transactions.** Each validator keeps its
> own permissioning state — an in-memory `perm_add*` on one node does not
> propagate. Run the call on **every** validator.

### Rejection wording

A transaction submitted by a non-allowlisted sender is rejected at
`eth_sendRawTransaction` with (verified against Besu `26.6.0`):

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32007,
    "message": "Sender account not authorized to send transactions"
  }
}
```

After the sender is added to the allowlist, the same signed transaction is
accepted and returns a transaction hash — no restart.

### Fast deny → allow → deny demo (in-memory)

```sh
RPC="kubectl exec -n besu sbx-validator1-0 -- curl -s -X POST localhost:8545 -H content-type:application/json -d"

# read
$RPC '{"jsonrpc":"2.0","method":"perm_getAccountsAllowlist","id":1}'
# allow T
$RPC '{"jsonrpc":"2.0","method":"perm_addAccountsToAllowlist","params":[["0x<T>"]],"id":1}'
# deny T again
$RPC '{"jsonrpc":"2.0","method":"perm_removeAccountsFromAllowlist","params":[["0x<T>"]],"id":1}'
```

### Durable change (survives pod restart)

The ConfigMap is the restart baseline, so a durable change means updating values
and re-staging:

```sh
helm upgrade sbx charts/besu-sandbox -n besu --reuse-values \
  --set 'permissioning.accounts.allowlist={0x5e6...,0x941...,0x<T>}'
# then re-stage one validator at a time (init container re-seeds the live file):
for n in 1 2 3 4; do
  kubectl rollout restart statefulset/sbx-validator$n -n besu
  kubectl rollout status  statefulset/sbx-validator$n -n besu --timeout=300s
done
```

If you instead exec into a pod and edit the live file directly
(`/etc/permissions/accounts-allowlist.toml`), `perm_reloadPermissionsFromFile`
picks it up immediately — but that change is also lost on pod restart.

---

## Disabling

Set `permissioning.accounts.enabled=false` and perform the same one-at-a-time
rolling restart. With it off, behaviour is identical to a chart without the
feature — no `PERM` API, no accounts file, no account gate.
