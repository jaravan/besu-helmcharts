# Creating validators and populating `values.yaml`

This guide walks through generating a **four-validator** set and the matching
genesis `extraData` strings for **QBFT** and **IBFT 2.0**, then shows how to
paste the results into `values.yaml`.

The chart treats `validators` and `genesis.extraData` as a **single contract**:

- `validators[]` drives Secrets, enodes, static-nodes, Services, StatefulSets, and the PDB.
- `genesis.extraData` must encode the same validator **addresses** as the active consensus engine.
- `helm template` / `helm install` **fail** if an address in `validators[]` is missing from the `extraData` for the selected `consensus` value.

For the deep dive on why QBFT and IBFT 2.0 `extraData` differ at the byte level,
see the Besu documentation on [QBFT](https://besu.hyperledger.org/private-networks/how-to/configure/consensus/qbft) and [IBFT 2.0](https://besu.hyperledger.org/private-networks/how-to/configure/consensus/ibft).

---

## What goes in `values.yaml`

Each validator is a **coupled triplet** — all three fields come from the same
keypair and must stay in sync:

| Field     | Used for                                                                     |
| --------- | ---------------------------------------------------------------------------- |
| `nodeKey` | Besu P2P private key (Kubernetes Secret → `/secrets/nodekey`)                |
| `pubKey`  | Node ID in enode URLs (`enode://{pubKey}@…`) — 128 hex chars, no `0x` prefix |
| `address` | Ethereum address in genesis `extraData` (QBFT/IBFT2 validator list)          |

```yaml
validators:
  - nodeKey: "<64 hex chars>"
    pubKey: "<128 hex chars>"
    address: "0x<40 hex chars>"
  # … repeat for each validator

genesis:
  extraData:
    qbft: "0x…" # required when consensus: qbft
    ibft2: "0x…" # required when consensus: ibft2
```

Everything else (Secrets, `static-nodes.json`, bootnodes, per-validator Services,
the unified RPC service) is **generated from `validators[]`** — you do not edit those
templates by hand.

### Sandbox note

The default chart ships a **fixed** validator set so every `helm install` /
teardown produces the same enodes, genesis hash, and addresses. Only replace
the keys when you intentionally want a **new** network identity (and accept that
saved MetaMask configs, test addresses, and docs referencing the old set will
break).

---

## What is inside `extraData`?

In Ethereum-style block headers, `extraData` is an optional hex field. On a **BFT
genesis block** (QBFT / IBFT 2.0), Besu uses it to store a **consensus-specific
RLP structure** — not JSON, not enodes, not node private keys.

That is why `values.yaml` carries a long `0xf87a…` string under
`genesis.extraData`, while `validators[]` carries the separate `nodeKey` /
`pubKey` / `address` triplets: **P2P identity and on-chain validator identity
are related but encoded in different places.**

### At genesis (block 0)

When you run `besu rlp encode` or `operator generate-blockchain-config`, the
encoded structure contains **five logical parts**:

| Part                | At genesis                         | What it means                                                                                                                                   |
| ------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **Vanity data**     | 32 zero bytes                      | Reserved header space (unused in practice; Besu sets all zeros).                                                                                |
| **Validator list**  | Your `validators[].address` values | Initial BFT validator set — **20-byte Ethereum addresses**, not node pubkeys. This is the only part you change when defining a new sandbox set. |
| **Vote**            | Empty                              | No validator vote pending at block 0 (used later for add/remove validator proposals).                                                           |
| **Round number**    | `0`                                | Consensus round at this block; always zero in the genesis header.                                                                               |
| **Committed seals** | Empty list                         | No aggregated validator signatures yet — no blocks have been committed.                                                                         |

Visually (QBFT genesis):

```text
extraData
├── vanity          (32 bytes, zeros)
├── validators[]    (0xAddr1, 0xAddr2, 0xAddr3, 0xAddr4)
├── vote            (empty)
├── round             (0)
└── committedSeals    (empty)
```

The **validator list** is the piece you must keep in sync with
`validators[].address` in `values.yaml`. The chart’s render-time check verifies
each address appears inside the active `extraData` string.

### What `extraData` is _not_

| Not in genesis `extraData`              | Where it lives instead                                         |
| --------------------------------------- | -------------------------------------------------------------- |
| Node private keys (`nodeKey`)           | `validators[].nodeKey` → Kubernetes Secrets                    |
| Node public keys / enode IDs (`pubKey`) | `validators[].pubKey` → enode URLs, static-nodes               |
| `chainId`, block period, epoch length   | `genesis.json` `config.qbft` / `config.ibft2` (chart template) |
| Pre-funded accounts                     | `genesis.json` `alloc` (chart template)                        |

### After block 0

On every **subsequent** block header, Besu replaces `extraData` with a live
consensus payload: round number, proposer seals, committed seals, and sometimes
votes as validators join or leave. You **never** hand-edit those — only the
**genesis** `extraData` is configured in `values.yaml`.

### QBFT vs IBFT 2.0 — same contents, different bytes

The five parts are the same idea for both engines. The **RLP encoding** of the
empty vote and round-0 fields differs, so the same four addresses produce two
different hex strings. That is why `values.yaml` holds both
`genesis.extraData.qbft` and `genesis.extraData.ibft2`.

---

## Before you start

- Use the same Besu version as the chart (`Chart.yaml` `appVersion`, e.g. `26.6.0`).
- BFT networks are usually sized **`n = 3f + 1`** (default **n = 4**, **f = 1**).
- Validator **addresses** in the `extraData` JSON array should be in **ascending**
  hex order (Besu convention).

Set the image tag once for the commands below:

```bash
export BESU_IMAGE=hyperledger/besu:26.6.0   # match Chart.appVersion
export WORKDIR=/tmp/besu-sandbox-validators
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"
# Besu refuses to write into an existing networkFiles directory — remove it
# explicitly if re-running (rm above only removes the whole tree on first run).
rm -rf "$WORKDIR/networkFiles"
```

---

## Two ways to generate validators

|                          | Option A — `generate-blockchain-config`                           | Option B — one keypair at a time                                                |
| ------------------------ | ----------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **Best for**             | Four validators in one command (recommended)                      | Learning / custom per-node control                                              |
| **Produces**             | All keys + QBFT `extraData` in `genesis.json`                     | Keys only — you build `extraData` yourself                                      |
| **IBFT 2.0 `extraData`** | Still run [Step 3](#step-3--generate-ibft-20-extradata-if-needed) | Run [Steps 2–3](#step-2--build-the-validator-address-list-option-b-and-ibft-20) |

Both options end at the same `values.yaml` shape. The chart **only** takes validator keys and `genesis.extraData` from your work — alloc, `chainId`, and consensus timing stay in the chart templates.

---

## Option A — Generate all four validators at once (recommended)

Besu’s [`operator generate-blockchain-config`](https://besu.hyperledger.org/private-networks/tutorials/qbft)
creates four keypairs, a `genesis.json` with QBFT `extraData` already encoded, and a
`keys/` tree — one directory per validator address.

### A.1 — Config file

Save as `$WORKDIR/qbftConfigFile.json` (aligned with this chart’s `chainId`, gas limit,
and `consensusConfig` defaults):

```json
{
  "genesis": {
    "config": {
      "chainId": 1337,
      "constantinoplefixblock": 0,
      "qbft": {
        "blockperiodseconds": 2,
        "epochlength": 30000,
        "requesttimeoutseconds": 10
      }
    },
    "nonce": "0x0",
    "timestamp": "0x58ee40ba",
    "gasLimit": "0xf7b760",
    "difficulty": "0x1",
    "mixHash": "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365",
    "coinbase": "0x0000000000000000000000000000000000000000",
    "alloc": {}
  },
  "blockchain": {
    "nodes": {
      "generate": true,
      "count": 4
    }
  }
}
```

Change `"count"` for other **`3f + 1`** sizes (7, 10, …).

### A.2 — Run Besu once

```bash
docker run --rm -v "$WORKDIR:/data" "$BESU_IMAGE" \
  operator generate-blockchain-config \
  --config-file=/data/qbftConfigFile.json \
  --to=/data/networkFiles \
  --private-key-file-name=key
```

> **Expected: `java.lang.IllegalArgumentException: Output directory already exists.`**
> This is a known bug in the Besu image — the command prints the exception and exits
> with code 1, but **all keys and `genesis.json` are written correctly**. Verify by
> checking that `networkFiles/keys/` contains four address directories before continuing.
> On re-runs, remove `networkFiles` first (the setup block above does this).

Output layout:

```text
networkFiles/
├── genesis.json          # extraData for QBFT is already inside
└── keys/
    ├── 0x<address1>/
    │   ├── key           # node private key (hex, no 0x)
    │   └── key.pub       # public key (hex, usually with 0x)
    ├── 0x<address2>/
    …
```

### A.3 — Map output → `values.yaml` fields

Extract **QBFT `extraData`** straight from the generated genesis:

```bash
# requires jq
jq -r '.extraData' "$WORKDIR/networkFiles/genesis.json" \
  > "$WORKDIR/extraData-qbft.txt"
```

Build the **`validators`** list (sorted by address — same order Besu uses in
`extraData`). This loop prints YAML you can paste into `values.yaml`:

```bash
for dir in $(find "$WORKDIR/networkFiles/keys" -mindepth 1 -maxdepth 1 -type d | sort); do
  addr=$(basename "$dir")
  [[ "$addr" != 0x* ]] && addr="0x$addr"
  nodeKey=$(tr -d '\n' < "$dir/key" | sed 's/^0x//')
  pubKey=$(tr -d '\n' < "$dir/key.pub" | sed 's/^0x//')
  echo "  - nodeKey: \"$nodeKey\""
  echo "    pubKey: \"$pubKey\""
  echo "    address: \"$addr\""
done
```

Also save addresses for IBFT 2.0 encoding (Step 3):

```bash
find "$WORKDIR/networkFiles/keys" -mindepth 1 -maxdepth 1 -type d | sort \
  | while read -r dir; do
      addr=$(basename "$dir")
      [[ "$addr" != 0x* ]] && addr="0x$addr"
      echo "  \"$addr\","
    done | sed '$ s/,$//' | {
      echo '['
      cat
      echo ']'
    } > "$WORKDIR/validators.json"
```

Then skip to [Step 3](#step-3--generate-ibft-20-extradata-if-needed) for `genesis.extraData.ibft2`
(if you keep both consensus strings), or [Step 4](#step-4--paste-into-valuesyaml) if you only
run QBFT.

> **Do not** replace the chart’s full `genesis.json` with Besu’s generated file — pre-funded
> `alloc` accounts and other fields live in the chart template. You only copy **`validators[]`**
> and **`genesis.extraData`**.

---

## Option B — Generate keypairs one at a time

Loop four times: create a 32-byte node key, then derive the public key and
Ethereum address with Besu.

```bash
for i in 1 2 3 4; do
  dir="$WORKDIR/validator$i"
  mkdir -p "$dir"

  # 32-byte ECDSA private key (nodekey file content)
  openssl rand -hex 32 > "$dir/nodekey"

  # Public key (strip 0x prefix).
  # Besu writes INFO log lines to stdout; grep -oE filters them out by matching
  # the exact 128-hex-char pubkey shape. head -1 picks the first (and only) match.
  docker run --rm -v "$dir:/data" "$BESU_IMAGE" \
    --data-path=/data public-key export \
    --node-private-key-file=/data/nodekey \
    | grep -oE '0x[0-9a-f]{128}' | head -1 | sed 's/^0x//' > "$dir/pubkey"

  # Ethereum address (keep 0x prefix).
  # grep -oE matches 40-hex-char values; tail -1 selects the address which
  # appears last, after any pubkey fragment the log line may also contain.
  docker run --rm -v "$dir:/data" "$BESU_IMAGE" \
    --data-path=/data public-key export-address \
    --node-private-key-file=/data/nodekey \
    | grep -oE '0x[0-9a-f]{40}' | tail -1 > "$dir/address"
done
```

Inspect the output:

```bash
for i in 1 2 3 4; do
  echo "=== validator$i ==="
  echo -n "  nodeKey:  "; cat "$WORKDIR/validator$i/nodekey"
  echo -n "  pubKey:   "; cat "$WORKDIR/validator$i/pubkey"
  echo -n "  address:  "; cat "$WORKDIR/validator$i/address"
  echo
done
```

Continue with Steps 2 and 3 below to build **both** `extraData` strings.

---

## Step 2 — Build the validator address list (Option B and IBFT 2.0)

Collect the four addresses into a JSON array for `besu rlp encode`:

```bash
cat > "$WORKDIR/validators.json" <<EOF
[
  "$(cat $WORKDIR/validator1/address)",
  "$(cat $WORKDIR/validator2/address)",
  "$(cat $WORKDIR/validator3/address)",
  "$(cat $WORKDIR/validator4/address)"
]
EOF

cat "$WORKDIR/validators.json"
```

If addresses are not already in ascending order, sort them before encoding
(manually reorder the JSON array). The default sandbox set is sorted.

Skip this step if you already created `validators.json` in [Option A.3](#a3--map-output--valuesyaml-fields).

---

## Step 3 — Generate `extraData`

### QBFT (Option B only)

Option A already produced `extraData-qbft.txt` from `genesis.json`. For Option B,
encode from `validators.json`:

```bash
docker run --rm -v "$WORKDIR/validators.json:/validators.json" "$BESU_IMAGE" \
  rlp encode --from=/validators.json --type=QBFT_EXTRA_DATA \
  | tr -d '\n' > "$WORKDIR/extraData-qbft.txt"
echo "QBFT extraData:"
cat "$WORKDIR/extraData-qbft.txt"
echo
```

### IBFT 2.0 (Option A and B)

The **same** address list produces a **different** hex string for IBFT 2.0 — the
RLP layout differs (vote + round encoding). Always use `besu rlp encode`; do not
hand-edit bytes.

```bash
docker run --rm -v "$WORKDIR/validators.json:/validators.json" "$BESU_IMAGE" \
  rlp encode --from=/validators.json --type=IBFT_EXTRA_DATA \
  | tr -d '\n' > "$WORKDIR/extraData-ibft2.txt"
echo "IBFT2 extraData:"
cat "$WORKDIR/extraData-ibft2.txt"
echo
```

Optional sanity check — decode and confirm four addresses:

```bash
docker run --rm -v "$WORKDIR/extraData-qbft.txt:/extradata.txt" "$BESU_IMAGE" \
  rlp decode --from=/extradata.txt --type=QBFT_EXTRA_DATA
```

---

## Step 4 — Paste into `values.yaml`

Copy the four triplets and both `extraData` strings into `values.yaml`:

```yaml
validators:
  - nodeKey: "<validator1/nodekey>"
    pubKey: "<validator1/pubkey>"
    address: "<validator1/address>"
  - nodeKey: "<validator2/nodekey>"
    pubKey: "<validator2/pubkey>"
    address: "<validator2/address>"
  - nodeKey: "<validator3/nodekey>"
    pubKey: "<validator3/pubkey>"
    address: "<validator3/address>"
  - nodeKey: "<validator4/nodekey>"
    pubKey: "<validator4/pubkey>"
    address: "<validator4/address>"

genesis:
  extraData:
    qbft: "<contents of extraData-qbft.txt>"
    ibft2: "<contents of extraData-ibft2.txt>"
```

Only the `extraData` entry matching your active `consensus` value is **required**
at install time. Keep both if you plan to switch engines.

---

## Step 5 — Validate before installing

```bash
cd besu-helmcharts/charts/besu-sandbox

helm lint .
helm template sbx . -n besu | less
```

If a validator `address` does not appear inside the active `extraData` string,
render fails with an error pointing at this doc.

Install when clean:

```bash
helm upgrade --install sbx . -n besu --create-namespace --wait --timeout=600s
```

---

## Checklist (four validators)

**Option A (`generate-blockchain-config`):**

1. Write `qbftConfigFile.json` with `"count": 4`.
2. Run `operator generate-blockchain-config` once.
3. Map `keys/*/` → `validators[]`; `jq` `extraData` → `genesis.extraData.qbft`.
4. Run `rlp encode` for `genesis.extraData.ibft2` if needed.
5. Paste into `values.yaml`; `helm template` succeeds.

**Option B (manual):**

1. Generate **four** keypairs → `nodeKey`, `pubKey`, `address` each.
2. Build `validators.json` from the four **addresses** (sorted).
3. Run `rlp encode` → `genesis.extraData.qbft` and `.ibft2`.
4. Paste into `values.yaml`; `helm template` succeeds.

Both: fresh install (or wipe PVCs) when keys change — genesis hash changes.

---

## Changing validator count

`len(validators)` drives StatefulSet count, bootnodes (first two validators),
PodDisruptionBudget `minAvailable`, and install notes. If you add or remove
validators:

1. Regenerate **all** keys and `extraData` for the new set (genesis is fixed at
   block 0).
2. Prefer **`n = 3f + 1`** (4, 7, 10, …) for standard BFT fault tolerance.
3. Re-run `helm template` to confirm validation passes.

---

## Related docs

| Doc                              | Topic                        |
| -------------------------------- | ---------------------------- |
| [../values.yaml](../values.yaml) | Live defaults for this chart |
| [../README.md](../README.md)     | Install, test, uninstall     |
