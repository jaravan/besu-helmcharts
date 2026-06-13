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

| Value                                 | Effect                                                                                                                                                                                                                                                                                                                                                             |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `permissioning.accounts.enabled=true` | Adds `permissions-accounts-config-file-enabled=true` + `permissions-accounts-config-file="/etc/permissions/accounts-allowlist.toml"` to `config.toml`, renders `accounts-allowlist.toml` into the `node-permissions` ConfigMap (mounted at `/etc/permissions`), and appends `PERM` to the derived `rpc-http-api` / `rpc-ws-api` so `perm_*` methods are reachable. |
| `permissioning.accounts.allowlist`    | The `0x` addresses permitted to submit transactions.                                                                                                                                                                                                                                                                                                               |

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

| Method                                                             | Effect                                      | Persists restart?                         | Latency                                                                            |
| ------------------------------------------------------------------ | ------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------- |
| `perm_getAccountsAllowlist`                                        | read the current in-memory allowlist        | —                                         | immediate                                                                          |
| `perm_addAccountsToAllowlist` / `perm_removeAccountsFromAllowlist` | change the in-memory allowlist              | **No**                                    | immediate                                                                          |
| `perm_reloadPermissionsFromFile`                                   | re-read `accounts-allowlist.toml` from disk | **Yes** (the file is the source of truth) | after the ConfigMap edit propagates to the mounted file — kubelet sync, up to ~60s |

The **file (ConfigMap) is the source of truth across restarts**; the in-memory
`perm_add*` / `perm_remove*` calls are fast but lost on restart.
`perm_reloadPermissionsFromFile` reconciles in-memory state back to the file.

> **Apply on every node that validates transactions.** Each validator keeps its
> own permissioning state — an in-memory `perm_add*` on one node does not
> propagate. Either call it on every validator, or edit the ConfigMap (single
> source of truth) and `perm_reloadPermissionsFromFile` on every validator.

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

### Durable change (edit the file, then reload)

```sh
kubectl edit configmap sbx-node-permissions -n besu   # edit accounts-allowlist.toml
# wait for the mounted file to update (≤ ~60s), then on each validator:
$RPC '{"jsonrpc":"2.0","method":"perm_reloadPermissionsFromFile","id":1}'
```

---

## Disabling

Set `permissioning.accounts.enabled=false` and perform the same one-at-a-time
rolling restart. With it off, behaviour is identical to a chart without the
feature — no `PERM` API, no accounts file, no account gate.
