# Validator 1 — useful commands

Commands for querying **validator 1** in the `besu` namespace.

> **Release-name assumption:** these commands use release name `sbx`
> (`helm install sbx charts/besu-sandbox -n besu`). Pod and StatefulSet
> names are prefixed with the release name — adjust if yours differs.

| Resource      | Value              |
| ------------- | ------------------ |
| Namespace     | `besu`             |
| Service       | `sbx-validator1`   |
| Pod           | `sbx-validator1-0` |
| JSON-RPC port | `8545`             |

---

## Minimal Besu image (what is missing)

The `hyperledger/besu:26.6.0` container is a **minimal runtime**. Do not expect standard debugging tools inside `sbx-validator1-0` (or any Besu pod).

| Tool                     | In Besu pod? | Typical use                            |
| ------------------------ | ------------ | -------------------------------------- |
| `curl` / `wget`          | No           | JSON-RPC HTTP calls                    |
| `nc` / `netcat` / `ncat` | No           | TCP/UDP socket reachability            |
| `netstat` / `ss` / `ip`  | No           | Listening ports, routes                |
| `lsof`                   | No           | Which process holds a port             |
| `ping` / `traceroute`    | No           | ICMP path checks                       |
| `dig` / `nslookup`       | No           | DNS lookups                            |
| `/opt/besu/bin/besu`     | **Yes**      | Besu CLI (config, export, etc.)        |
| `sh`                     | **Yes**      | Basic shell, read files/logs           |
| `/proc/net/tcp`          | **Yes**      | Raw kernel socket table (hard to read) |

`kubectl exec -it -n besu sbx-validator1-0 -- sh` is still useful for **logs**, **mounted config** (`/etc/besu`, `/etc/genesis`, `/secrets`), and **data** (`/data`) — not for HTTP or socket tests.

Use the options below instead.

---

## Option A: Port-forward (run from your machine)

Forward JSON-RPC to localhost, then call the API with `curl`:

```bash
kubectl port-forward -n besu svc/sbx-validator1 8545:8545
```

In another terminal:

```bash
RPC=http://127.0.0.1:8545
```

All `curl` examples below assume `$RPC` is set and port-forward is running.

---

## Option B: In-cluster (no port-forward)

The Besu pod has no `curl` (see [Minimal Besu image](#minimal-besu-image-what-is-missing)). Use cluster DNS from a temporary curl pod instead (same image as the validator init containers):

```bash
NS=besu
RPC=http://sbx-validator1.besu.svc.cluster.local:8545

kubectl run curl-rpc -n $NS --rm -i --restart=Never \
  --image=curlimages/curl:8.11.1 -- \
  curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC
```

For **multiple** queries without port-forward, start an interactive shell in a curl pod:

```bash
kubectl run curl-rpc -n besu --rm -it --restart=Never \
  --image=curlimages/curl:8.11.1 -- sh
```

Inside the pod:

```bash
RPC=http://sbx-validator1.besu.svc.cluster.local:8545
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC
```

Type `exit` when done (the pod is removed automatically because of `--rm`).

---

## Network & peers

For peer and connectivity info, prefer **JSON-RPC** (`net_peerCount`, `admin_peers`) over shell tools inside the Besu pod.

**Peer count**

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  $RPC
```

Convert hex result to decimal: `printf "%d\n" 0x5`

**List connected peers**

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"admin_peers","params":[],"id":1}' \
  $RPC | jq .
```

**Is the node listening for connections?**

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_listening","params":[],"id":1}' \
  $RPC
```

**Network / client version**

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
  $RPC
```

---

## Chain & blocks

**Latest block number**

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC
```

```sh
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC | jq -r '.result' | xargs printf "%d\n"
```

**Sync status** (`false` when fully synced)

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  $RPC
```

**Chain ID**

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  $RPC
```

**Block details** (replace `latest` with a hex block number, e.g. `"0x1"`)

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
  $RPC | jq .
```

---

## IBFT / QBFT / validator info

**Validators for the latest block**

IBFT2:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"ibft_getValidatorsByBlockNumber","params":["latest"],"id":1}' \
  $RPC | jq .
```

QBFT:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}' \
  $RPC | jq .
```

**Node info** (enode, network IDs, etc.)

```bash
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
  $RPC | jq .
```

---

## Kubernetes helpers

**Pod status**

```bash
kubectl get pod -n besu sbx-validator1-0
kubectl describe pod -n besu sbx-validator1-0
```

**Recent logs**

```bash
kubectl logs -n besu sbx-validator1-0 --tail=100
kubectl logs -n besu sbx-validator1-0 -f
```

**Service endpoints**

```bash
kubectl get svc -n besu sbx-validator1
kubectl get endpoints -n besu sbx-validator1
```

**Check listening ports from outside the Besu pod** (see [Minimal Besu image](#minimal-besu-image-what-is-missing)):

```bash
# Which ports the pod exposes
kubectl get pod -n besu sbx-validator1-0 -o jsonpath='{range .spec.containers[0].ports[*]}{.name}{"\t"}{.containerPort}{"\n"}{end}'

# Optional: debug pod with net-tools (removed automatically)
kubectl run netdebug -n besu --rm -it --restart=Never \
  --image=nicolaka/netshoot -- \
  ss -tlnp
```

Inside a `netshoot` pod you can also reach Besu via `curl` at `http://sbx-validator1.besu.svc.cluster.local:8545`.

---

## Socket connectivity (netcat / IP whitelisting)

When a remote firewall **whitelists the Besu pod IP**, you need to test outbound connections **from that pod's network identity** — not from your laptop and not from a random debug pod (which has a different source IP).

### Validator 1 pod IP

```bash
kubectl get pod -n besu sbx-validator1-0 -o wide
# note the IP column — that is what the remote side must allow
```

### Recommended: ephemeral debug container (same network as Besu)

Attaches a `netshoot` sidecar to `sbx-validator1-0` sharing its network namespace (same source IP and routes as Besu):

```bash
HOST=203.0.113.10   # remote IP you want to reach
PORT=8545           # remote TCP port

kubectl debug -it sbx-validator1-0 -n besu \
  --image=nicolaka/netshoot --target=validator1 -- \
  nc -zv -w 5 "$HOST" "$PORT"
```

Interactive shell (run multiple checks, then `exit`):

```bash
kubectl debug -it sbx-validator1-0 -n besu \
  --image=nicolaka/netshoot --target=validator1 -- sh
```

Inside the debug shell:

```bash
# TCP (e.g. JSON-RPC, HTTPS)
nc -zv -w 5 203.0.113.10 8545

# UDP (e.g. Besu discovery on 30303)
nc -zvu -w 5 203.0.113.10 30303

# HTTP-level check (netshoot includes curl)
curl -v --connect-timeout 5 http://203.0.113.10:8545

# See local addresses this pod uses (same as Besu)
ip addr
ss -tlnp
```

**How to read `nc` output:**

| Result               | Meaning                                                      |
| -------------------- | ------------------------------------------------------------ |
| `succeeded` / `open` | TCP connect worked — whitelist and route are OK              |
| `Connection refused` | Reached the host, but nothing listens on that port           |
| `Timed out`          | Firewall, wrong IP, or routing block (common whitelist miss) |
| `No route to host`   | Routing/NRP issue between cluster and target                 |

Requires **Ephemeral Containers** (enabled on most clusters including minikube). If `kubectl debug` fails, use the fallback below.

### Fallback: separate debug pod (different source IP)

Useful for general cluster egress tests, but the **source IP is not** `sbx-validator1-0`'s IP — do not rely on this alone for whitelist validation:

```bash
kubectl run netdebug -n besu --rm -it --restart=Never \
  --image=nicolaka/netshoot -- \
  nc -zv -w 5 203.0.113.10 8545
```

Compare `kubectl get pod -n besu netdebug -o wide` IP vs `sbx-validator1-0` — if they differ, the remote whitelist must allow **validator1's IP**, not netdebug's.

### Test another Besu node in the cluster

From a debug shell on `sbx-validator1-0`:

```bash
# Validator 2 P2P (TCP)
nc -zv sbx-validator2-0.sbx-validator2.besu.svc.cluster.local 30303
```

Or from a curl/netshoot pod using cluster DNS (see Option B).

---

## NetworkPolicy & Pod Security Standards (PSS)

This repo's minikube setup has **no** `NetworkPolicy` objects and **no** PSS labels on the `besu` namespace. Production clusters often add both. That changes which debug commands work and what Besu itself can reach.

### Check what applies to your cluster

```bash
# Namespace PSS enforcement (labels)
kubectl get ns besu monitoring -o yaml | grep -E 'pod-security|labels:' -A5

# Network policies in besu namespace
kubectl get networkpolicy -n besu
kubectl describe networkpolicy -n besu
```

### NetworkPolicy impact

NetworkPolicy controls **pod-to-pod / pod-to-external** traffic inside the cluster. It is **separate from** an external IP whitelist on a remote firewall — **both** must allow the connection.

| Scenario                                 | Effect                                                                                                                                                                   |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Default deny** (no policies)           | All traffic allowed (typical minikube)                                                                                                                                   |
| **Default deny** + explicit allows       | Only listed flows work; everything else times out                                                                                                                        |
| **`kubectl debug` on validator1**        | Uses the **same pod network** as Besu — NetworkPolicy for `sbx-validator1-0` applies. If Besu cannot egress to `HOST:PORT`, `nc` from the debug container will also fail |
| **Separate `netdebug` / `curl-rpc` pod** | **Different pod** — needs its **own** allow rules to reach targets (and DNS!)                                                                                            |
| **Port-forward from laptop**             | Bypasses in-cluster NetworkPolicy; tests RPC via the API server tunnel, not Besu pod egress                                                                              |

**Besu pods typically need NetworkPolicy allows for:**

| Direction        | Peer                         | Ports         | Protocol  |
| ---------------- | ---------------------------- | ------------- | --------- |
| Ingress / egress | other Besu validators        | `30303`       | TCP + UDP |
| Ingress          | Prometheus (`monitoring` ns) | `9545`        | TCP       |
| Ingress          | RPC clients (if allowed)     | `8545`        | TCP       |
| Egress           | kube-dns                     | `53`          | UDP + TCP |
| Egress           | external peers (if any)      | as configured | TCP/UDP   |

**Symptom:** `nc` times out, `net_peerCount` is `0x0`, or blocks stop advancing — often a missing allow rule or forgotten DNS egress.

**Example allow egress from validators to a whitelisted external host:**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: validator-egress-external
  namespace: besu
spec:
  podSelector:
    matchLabels:
      app: validator1 # repeat or broaden selector for all validators
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 203.0.113.10/32 # remote whitelisted IP
      ports:
        - protocol: TCP
          port: 8545
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

Adjust selectors and rules to match your topology. Debug pods need similar egress if run as separate pods.

### PSS / security restrictions impact

PSS is enforced via namespace labels (`pod-security.kubernetes.io/enforce`). It restricts **how pods run**, not IP routing.

| Profile        | Typical impact on this guide                                                                                                                                             |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **privileged** | No change — debug tools usually work                                                                                                                                     |
| **baseline**   | Usually fine; `netshoot` / `curl` pods generally allowed                                                                                                                 |
| **restricted** | May **block** `netshoot`, `kubectl debug`, or `kubectl run` debug pods (root user, extra capabilities, volume types). Ephemeral Containers may be **disabled** by policy |

**Common failures under `restricted`:**

```text
pods "netdebug" is forbidden: violates PodSecurity "restricted:latest":
  allowPrivilegeEscalation, runAsNonRoot, seccompProfile, capabilities...
```

```text
error: ephemeral containers are disabled for this cluster / namespace
```

**Workarounds when debug pods are blocked:**

1. **Port-forward + local `curl`** (Option A) — no extra pod in cluster
2. **JSON-RPC / Prometheus / Grafana** — already allowed paths for health checks
3. **Dedicated ops namespace** with `baseline` PSS and NetworkPolicy allowing egress + access to `besu` services
4. **Custom non-root debug image** matching `restricted` (minimal `curlimages/curl` often passes; `netshoot` often does not)
5. **Cluster admin** temporarily relaxes PSS on `besu` or enables Ephemeral Containers for troubleshooting

### Layered checks (whitelist + NetworkPolicy + PSS)

Use this order when something fails:

```text
1. PSS          → Can the debug pod / ephemeral container start at all?
2. NetworkPolicy → Can the Besu pod egress to HOST:PORT? (kubectl debug on validator1)
3. External FW  → Does the remote side allow validator1's pod IP?
4. Application  → Is anything listening? (connection refused vs timeout)
```

| Test                                   | Pass                      | Fail likely means                                                 |
| -------------------------------------- | ------------------------- | ----------------------------------------------------------------- |
| `kubectl debug ... nc` from validator1 | TCP open                  | NP or external FW block (timeout), or nothing listening (refused) |
| `kubectl run netdebug ... nc`          | Works from debug pod only | NP allows debug pod but maybe not Besu (or vice versa)            |
| `kubectl port-forward` + `curl` RPC    | RPC OK                    | In-cluster egress/NP irrelevant for this path                     |
| `net_peerCount` > 0                    | P2P OK                    | NP blocking 30303 between validators, or permissioning            |

---

## Minikube (from inside the cluster)

If you are on minikube and prefer cluster-internal DNS (as in the main README):

```bash
minikube ssh

curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  sbx-validator1.besu.svc.cluster.local:8545
```

---

## Quick health check (one-liner)

With port-forward active:

```bash
echo "Peers:  $(curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  $RPC | jq -r .result)" && \
echo "Block:  $(curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC | jq -r .result)" && \
echo "Syncing: $(curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  $RPC | jq -r .result)"
```

---

## Grafana monitoring

Forward Grafana to localhost:

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Open [http://localhost:3000](http://localhost:3000) and log in with `admin` / `password`.

Select the **Besu Overview** dashboard (Dashboards → Manage if it is not pinned).

Use the **System** dropdown at the top to filter by node (validators). It defaults to all nodes.

### Besu Overview dashboard panels

#### Overview (table)

Snapshot of every Besu node Prometheus is scraping. One row per node (`instance` = pod IP:metrics port).

| Column                    | What it shows                                                                             | What to look for                                                                         |
| ------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| **System**                | Node identifier (typically `pod-ip:9545`)                                                 | Use this to tell nodes apart when comparing rows                                         |
| **Chain Height**          | Current local block number (`ethereum_blockchain_height`)                                 | Should increase steadily; all nodes should be close to each other                        |
| **Target Chain Height**   | Highest block number the node knows about from peers (`ethereum_best_known_block_number`) | Should match or be slightly ahead of Chain Height on a synced node                       |
| **Blocks Behind**         | Target minus local height                                                                 | **0** = fully synced; rising values mean the node is falling behind                      |
| **Total Difficulty**      | Cumulative chain difficulty (`besu_blockchain_difficulty_total`)                          | Should be identical across synced nodes on the same chain                                |
| **Peer Count**            | Number of connected peers (`ethereum_peer_count`)                                         | Should be > 0; low or zero suggests connectivity or permissioning issues                 |
| **Block Time (5m avg)**   | Average seconds between blocks over the last 5 minutes                                    | For IBFT 2.0 / QBFT, expect this near your configured block period (often ~2s)           |
| **Time Since Last Block** | Seconds since the chain head timestamp                                                    | Turns yellow after 120s and red after 240s — indicates block production may have stalled |
| **% Peer Limit Used**     | Peer count divided by configured max peers                                                | High values mean the node is near its peer connection limit                              |

#### Block Time (graph)

Time series of average block interval per node, derived from the rate of `ethereum_blockchain_height` over 5 minutes.

Use this to spot consensus slowdowns, network partitions, or validator outages. A flat spike usually means blocks stopped being produced; a sustained drift above your IBFT/QBFT block period suggests the network is running slow.

#### Blocks Behind (graph)

Time series of how many blocks each node is behind the best-known height on the network.

Should stay at or near **0** for healthy nodes. A node that climbs and stays elevated is syncing slowly or has lost contact with the rest of the network.

#### CPU (graph)

Process CPU usage rate (`process_cpu_seconds_total`) per node.

Useful for spotting nodes under heavy load. Sustained high CPU on one validator can affect block production or RPC responsiveness.

#### GC time (graph)

JVM garbage-collection time as a percentage of wall-clock time (`jvm_gc_collection_seconds_sum`), broken out by GC type.

Frequent or long GC pauses can cause missed block proposals or slower RPC. Compare across nodes — one outlier may need more memory.

#### Memory Used (graph)

Total JVM memory in use (heap + non-heap) per node.

Watch for a steady upward trend that does not level off (possible memory leak) or nodes approaching their Kubernetes memory limit (`2048Mi` for validators in this setup).
