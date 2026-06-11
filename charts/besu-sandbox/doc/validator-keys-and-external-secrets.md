# Validator node keys — values, existing Secrets, External Secrets

Besu validator **node private keys** (`nodekey`) must be mounted at
`/secrets/nodekey`. **Public** identity (`pubKey`, `address`) stays in
`validators[]` and genesis — those drive enodes and `extraData` and are not
treated as secrets in this chart.

## Three modes (`validatorKeys.source`)

| Mode                   | Who creates the Secret                                                                     | `validators[].nodeKey` in Helm values    |
| ---------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------- |
| **`values`** (default) | Chart — named `<release>-validator<N>-key`                                                 | **Required** — sandbox plaintext keys    |
| **`existingSecret`**   | You (kubectl, Sealed Secrets, CI, …) — named per `existingSecret.nameTemplate`             | **Must omit** — keys never in Git/Helm   |
| **`externalSecrets`**  | [External Secrets Operator](https://external-secrets.io/) syncs from Vault / AWS SM / etc. | **Must omit** — needs ESO CRD on cluster |

Secret shape (all modes — what Besu mounts):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <release>-validator1-key # source=values: auto-generated; other modes: per nameTemplate
type: Opaque
stringData:
  nodekey: "<64 hex chars, no 0x prefix>"
```

`pubKey` and `address` remain in `values.yaml` in every mode so genesis and
`static-nodes.json` stay consistent.

---

## Default: `validatorKeys.source=values`

Current sandbox behaviour — deterministic keys in `values.yaml` for one-command
local installs. **Not for production.**

```yaml
validatorKeys:
  source: values

validators:
  - nodeKey: "0fd4aecd..."
    pubKey: "c1979a8a..."
    address: "0x4592c8e4..."
```

---

## `existingSecret` — you manage Kubernetes Secrets

Use when keys are injected by your pipeline (manual, Sealed Secrets, SOPS, etc.)
without External Secrets Operator.

```yaml
validatorKeys:
  source: existingSecret
  existingSecret:
    nameTemplate: "besu-validator{{n}}-key"
    dataKey: nodekey

validators:
  - pubKey: "b4bdf7e5fc7d75bf481c51824ff3c10433e8c58cc18cda3aeed7654a2a49bffde2375ba3e4bb703c9220d799695aaeee958d38dbfe04db1c8f75d75395ae7762"
    address: "0x5e6bb0a9afcae09c2d0aebc85a71b08ec4118e5f"
  # … no nodeKey fields
```

Create secrets **before** validators start:

```bash
kubectl -n besu create secret generic besu-validator1-key \
  --from-literal=nodekey=82b394491f89a13abd506bb45f85ee77043154cc2de738a2d44ca8347f0da416
# repeat for validator2-key … validator4-key
```

Then install:

```bash
helm upgrade --install sbx . -n besu --create-namespace --wait --timeout=600s
```

---

## `externalSecrets` — Vault or AWS Secrets Manager (showcase)

### Is `ExternalSecret` a Kubernetes built-in?

**No.** `ExternalSecret` is **not** a core API type like `Pod` or `Secret`. It is a
**Custom Resource (CRD)** registered when you install
[External Secrets Operator (ESO)](https://external-secrets.io/) on the cluster.

```text
ExternalSecret (CRD)  →  ESO controller  →  native Secret  →  Besu pod mount
```

This chart **does not** install ESO, Vault, or AWS Secrets Manager — it only
renders `ExternalSecret` manifests when `validatorKeys.source=externalSecrets`.
On a plain kind/minikube cluster without ESO, `helm install` may succeed but
those objects sit unprocessed and validator pods will fail until native Secrets
exist.

### Check ESO is installed (before using this mode)

```bash
# CRD must exist (name may vary slightly by ESO version)
kubectl get crd externalsecrets.external-secrets.io

# Should list ExternalSecret, SecretStore, ClusterSecretStore, …
kubectl api-resources | grep external-secrets
```

**Expected when ESO is present:**

```text
NAME                                  CREATED AT
externalsecrets.external-secrets.io   2024-…

externalsecrets             es          external-secrets.io/v1   true   ExternalSecret
secretstores                ss          external-secrets.io/v1   true   SecretStore
clustersecretstores         css         external-secrets.io/v1   true   ClusterSecretStore
```

**If the CRD is missing** (`NotFound` / empty grep): install ESO first — see
[ESO getting started](https://external-secrets.io/latest/introduction/getting-started/).
Then configure a `ClusterSecretStore` for your backend (steps below).

Also confirm your **SecretStore** exists and is ready:

```bash
kubectl get clustersecretstore
# or namespaced: kubectl get secretstore -n besu
```

Requires **External Secrets Operator** and a **SecretStore** / **ClusterSecretStore**
already configured for your backend.

### 1. Store keys remotely

**AWS Secrets Manager** (JSON secret per validator):

```json
{
  "nodekey": "82b394491f89a13abd506bb45f85ee77043154cc2de738a2d44ca8347f0da416"
}
```

Secret id / name example: `besu-sandbox/validator1`

**HashiCorp Vault** (KV v2 example):

```bash
vault kv put secret/besu-sandbox/validator1 nodekey=82b394491f89a13abd506bb45f85ee77043154cc2de738a2d44ca8347f0da416
```

Remote ref key for ESO depends on your Vault mount and ESO provider config — see
[ESO Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/).

### 2. ClusterSecretStore (cluster admin — not rendered by this chart)

Example names only; use your org’s ESO manifests:

- AWS: [ESO AWS Secrets Manager](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- Vault: [ESO HashiCorp Vault](https://external-secrets.io/latest/provider/hashicorp-vault/)

### 3. Helm values

```yaml
validatorKeys:
  source: externalSecrets
  externalSecrets:
    apiVersion: external-secrets.io/v1 # use v1beta1 on older ESO if needed
    refreshInterval: 1h
    secretStoreRef:
      name: aws-secrets-manager # or vault-backend
      kind: ClusterSecretStore
    target:
      nameTemplate: "besu-validator{{n}}-key"
    remoteRef:
      keyTemplate: "besu-sandbox/validator{{n}}"
      property: nodekey

validators:
  - pubKey: "b4bdf7e5fc7d75bf481c51824ff3c10433e8c58cc18cda3aeed7654a2a49bffde2375ba3e4bb703c9220d799695aaeee958d38dbfe04db1c8f75d75395ae7762"
    address: "0x5e6bb0a9afcae09c2d0aebc85a71b08ec4118e5f"
  # … validators 2–4: pubKey + address only
```

Install:

```bash
helm upgrade --install sbx . -n besu -f examples/values-external-secrets.yaml --wait --timeout=600s
```

Or copy `examples/values-external-secrets.yaml` and adjust `secretStoreRef` /
`keyTemplate` for your Vault or AWS SM layout.

The chart renders one **ExternalSecret** per validator. ESO creates/updates the
Secret named per `externalSecrets.target.nameTemplate`; StatefulSets mount it the
same way as chart-owned Secrets.

Verify sync before Besu pods crash-loop:

```bash
# ESO installed? (cluster-wide — run once)
kubectl get crd externalsecrets.external-secrets.io
kubectl api-resources | grep external-secrets

# Per release (namespace besu, release name sbx → secret sbx-validator1-key by default for source=values)
kubectl -n besu get externalsecret,secret | grep validator
kubectl -n besu describe externalsecret -l app.kubernetes.io/instance=sbx
```

---

## Trade-offs

|                               | `values`        | `existingSecret`             | `externalSecrets`         |
| ----------------------------- | --------------- | ---------------------------- | ------------------------- |
| **Sandbox / portfolio demos** | ✓ default       | Optional                     | Showcase only             |
| **Keys in Git**               | Yes (plaintext) | No                           | No                        |
| **Extra cluster deps**        | None            | None                         | ESO + backend store       |
| **Rotation**                  | Helm upgrade    | Replace Secret + restart pod | ESO refresh + pod restart |
| **genesis / enodes**          | `validators[]`  | `validators[]`               | `validators[]`            |

Changing keys requires regenerating `genesis.extraData` and redeploying the
**whole** validator set — see
[creating-validators-and-values.md](creating-validators-and-values.md).

---

## Validation errors

```text
validators[0].nodeKey must not be set when validatorKeys.source=externalSecrets
```

→ Remove `nodeKey` from `validators[]`; keys live only in the backend store.

```text
validatorKeys.externalSecrets.secretStoreRef.name is required
```

→ Set `secretStoreRef.name` to your ClusterSecretStore.

```text
validators[0].nodeKey is required when validatorKeys.source=values
```

→ Default mode still needs inline keys (or switch source).
