{{/*
Chart name, optionally overridden by nameOverride.
*/}}
{{- define "besu-sandbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "besu-sandbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource in the chart.
*/}}
{{- define "besu-sandbox.labels" -}}
helm.sh/chart: {{ include "besu-sandbox.chart" . }}
app.kubernetes.io/name: {{ include "besu-sandbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: besu-sandbox
{{- end }}

{{/*
Besu container image tag — defaults to Chart.appVersion when node.image.tag is unset.
*/}}
{{- define "besu-sandbox.imageTag" -}}
{{- .Values.node.image.tag | default .Chart.AppVersion -}}
{{- end }}

{{/*
Normalized consensus mechanism: qbft (default) or ibft2. Fails on invalid input.
*/}}
{{- define "besu-sandbox.consensus" -}}
{{- $c := .Values.consensus | default "qbft" | lower -}}
{{- if not (has $c (list "qbft" "ibft2")) -}}
{{- fail (printf "consensus must be qbft or ibft2, got %q" .Values.consensus) -}}
{{- end -}}
{{- $c -}}
{{- end }}

{{/*
Genesis config key for the active consensus engine.
*/}}
{{- define "besu-sandbox.consensusGenesisKey" -}}
{{- if eq (include "besu-sandbox.consensus" .) "ibft2" -}}ibft2{{- else -}}qbft{{- end -}}
{{- end }}

{{/*
RPC API namespace (QBFT or IBFT) matching the consensus engine.
*/}}
{{- define "besu-sandbox.consensusRpcNamespace" -}}
{{- if eq (include "besu-sandbox.consensus" .) "ibft2" -}}IBFT{{- else -}}QBFT{{- end -}}
{{- end }}

{{/*
JSON-RPC method to query the active validator set.
*/}}
{{- define "besu-sandbox.consensusValidatorsRpcMethod" -}}
{{- if eq (include "besu-sandbox.consensus" .) "ibft2" -}}ibft_getValidatorsByBlockNumber{{- else -}}qbft_getValidatorsByBlockNumber{{- end -}}
{{- end }}

{{/*
Human-readable consensus label for install notes.
*/}}
{{- define "besu-sandbox.consensusLabel" -}}
{{- if eq (include "besu-sandbox.consensus" .) "ibft2" -}}IBFT 2.0{{- else -}}QBFT{{- end -}}
{{- end }}

{{/*
Genesis extraData RLP encoding — differs between IBFT 2.0 and QBFT for the same
validator set. Values live in genesis.extraData.
*/}}
{{- define "besu-sandbox.consensusExtraData" -}}
{{- if eq (include "besu-sandbox.consensus" .) "ibft2" -}}
{{- .Values.genesis.extraData.ibft2 -}}
{{- else -}}
{{- .Values.genesis.extraData.qbft -}}
{{- end -}}
{{- end }}

{{/*
Default rpc-http-api list for the active consensus (override via rpc.http.api).
*/}}
{{- define "besu-sandbox.rpcHttpApi" -}}
{{- if .Values.rpc.http.api -}}
{{- .Values.rpc.http.api | toJson -}}
{{- else if eq (include "besu-sandbox.consensus" .) "ibft2" -}}
{{- list "DEBUG" "ETH" "ADMIN" "WEB3" "IBFT" "NET" "EEA" | toJson -}}
{{- else -}}
{{- list "DEBUG" "ETH" "ADMIN" "WEB3" "QBFT" "NET" | toJson -}}
{{- end -}}
{{- end }}

{{/*
Default rpc-ws-api list for the active consensus (override via rpc.ws.api).
*/}}
{{- define "besu-sandbox.rpcWsApi" -}}
{{- if .Values.rpc.ws.api -}}
{{- .Values.rpc.ws.api | toJson -}}
{{- else if eq (include "besu-sandbox.consensus" .) "ibft2" -}}
{{- list "DEBUG" "ETH" "ADMIN" "WEB3" "IBFT" "NET" "EEA" | toJson -}}
{{- else -}}
{{- list "DEBUG" "ETH" "ADMIN" "WEB3" "QBFT" "NET" | toJson -}}
{{- end -}}
{{- end }}

{{/*
How validator node private keys are supplied: values | existingSecret | externalSecrets.
*/}}
{{- define "besu-sandbox.validatorKeysSource" -}}
{{- $vk := .Values.validatorKeys | default dict -}}
{{- $src := $vk.source | default "values" -}}
{{- if not (has $src (list "values" "existingSecret" "externalSecrets")) -}}
{{- fail (printf "validatorKeys.source must be values, existingSecret, or externalSecrets, got %q" $src) -}}
{{- end -}}
{{- $src -}}
{{- end -}}

{{/*
Kubernetes Secret name holding validator nodekey (dict: root, n).
*/}}
{{- define "besu-sandbox.validatorKeySecretName" -}}
{{- $root := .root -}}
{{- $n := .n | toString -}}
{{- $vk := $root.Values.validatorKeys | default dict -}}
{{- $src := include "besu-sandbox.validatorKeysSource" $root -}}
{{- if eq $src "externalSecrets" -}}
{{- ($vk.externalSecrets.target.nameTemplate | default ($vk.existingSecret.nameTemplate | default "besu-validator{{n}}-key")) | replace "{{n}}" $n -}}
{{- else if eq $src "values" -}}
{{- printf "%s-validator%s-key" $root.Release.Name $n -}}
{{- else -}}
{{- ($vk.existingSecret.nameTemplate | default "besu-validator{{n}}-key") | replace "{{n}}" $n -}}
{{- end -}}
{{- end -}}

{{/*
Validate validatorKeys source vs validators[] shape.
*/}}
{{- define "besu-sandbox.validateValidatorKeys" -}}
{{- $root := . -}}
{{- $src := include "besu-sandbox.validatorKeysSource" $root -}}
{{- range $i, $v := $root.Values.validators -}}
{{- if eq $src "values" -}}
{{- if not $v.nodeKey -}}
{{- fail (printf "validators[%d].nodeKey is required when validatorKeys.source=values" $i) -}}
{{- end -}}
{{- else -}}
{{- if $v.nodeKey -}}
{{- fail (printf "validators[%d].nodeKey must not be set when validatorKeys.source=%s — supply keys via Secret/ExternalSecret only" $i $src) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if eq $src "externalSecrets" -}}
{{- $vk := $root.Values.validatorKeys | default dict -}}
{{- if not $vk.externalSecrets.secretStoreRef.name -}}
{{- fail "validatorKeys.externalSecrets.secretStoreRef.name is required when validatorKeys.source=externalSecrets" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate the canonical validators list (called from workload templates).
*/}}
{{- define "besu-sandbox.validateValidators" -}}
{{- if not .Values.validators -}}
{{- fail "validators: list is required" -}}
{{- end -}}
{{- if lt (len .Values.validators) 2 -}}
{{- fail "validators: at least 2 entries required for bootnodes" -}}
{{- end -}}
{{- range $i, $v := .Values.validators -}}
{{- if or (not $v.pubKey) (not $v.address) -}}
{{- fail (printf "validators[%d]: pubKey and address are required" $i) -}}
{{- end -}}
{{- end -}}
{{- include "besu-sandbox.validateValidatorKeys" . -}}
{{- end -}}

{{/*
Whether genesis enables London (EIP-1559) with zeroBaseFee from block 0.
Controlled by genesis.london (boolean, default false). See values.yaml for the
two-layer free-gas model.
*/}}
{{- define "besu-sandbox.genesisLondon" -}}
{{- if and (hasKey .Values.genesis "london") (not (kindIs "bool" .Values.genesis.london)) -}}
{{- fail "genesis.london must be a boolean (true or false)" -}}
{{- end -}}
{{- .Values.genesis.london | default false | toString -}}
{{- end -}}

{{/*
Ensure genesis.extraData encodes the same validator addresses as validators[].
Only the extraData for the active consensus engine is required and checked.
Also validates genesis.london is a boolean when set.
*/}}
{{- define "besu-sandbox.validateGenesis" -}}
{{- include "besu-sandbox.validateValidators" . -}}
{{- if and (hasKey .Values.genesis "london") (not (kindIs "bool" .Values.genesis.london)) -}}
{{- fail "genesis.london must be a boolean (true or false)" -}}
{{- end -}}
{{- $extraData := "" -}}
{{- $extraDataLabel := "" -}}
{{- if eq (include "besu-sandbox.consensus" .) "ibft2" -}}
{{- $extraData = .Values.genesis.extraData.ibft2 -}}
{{- $extraDataLabel = "genesis.extraData.ibft2" -}}
{{- else -}}
{{- $extraData = .Values.genesis.extraData.qbft -}}
{{- $extraDataLabel = "genesis.extraData.qbft" -}}
{{- end -}}
{{- if not $extraData -}}
{{- fail (printf "%s is required when consensus=%s" $extraDataLabel (include "besu-sandbox.consensus" .)) -}}
{{- end -}}
{{- $extraData = $extraData | lower -}}
{{- range $i, $v := .Values.validators -}}
{{- $addr := $v.address | lower | trimPrefix "0x" -}}
{{- if not (contains $addr $extraData) -}}
{{- fail (printf "%s does not include validators[%d] address %s — regenerate with besu rlp encode (see doc/creating-validators-and-values.md)" $extraDataLabel $i $v.address) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Number of validators in the canonical set.
*/}}
{{- define "besu-sandbox.validatorCount" -}}
{{- len .Values.validators -}}
{{- end -}}

{{/*
BFT fault tolerance: f = floor((n-1)/3) for a set of n validators (3f+1 layout).
*/}}
{{- define "besu-sandbox.bftFaultTolerance" -}}
{{- $n := len .Values.validators -}}
{{- div (sub $n 1) 3 -}}
{{- end -}}

{{/*
PodDisruptionBudget minAvailable: n - f — keep quorum during voluntary disruption.
*/}}
{{- define "besu-sandbox.podDisruptionBudgetMinAvailable" -}}
{{- $n := len .Values.validators -}}
{{- sub $n (include "besu-sandbox.bftFaultTolerance" . | int) -}}
{{- end -}}

{{/*
Labels that identify validator pods across all StatefulSets in this release.
*/}}
{{- define "besu-sandbox.unifiedRpcServiceName" -}}
{{- .Values.unifiedRpcService.name | default (printf "%s-rpc-unified" .Release.Name) -}}
{{- end -}}

{{- define "besu-sandbox.validatorPodSelectorLabels" -}}
app.kubernetes.io/part-of: besu-sandbox
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/component: validator
{{- end -}}

{{/*
Soft pod anti-affinity — prefer not to co-locate validators on the same node.
*/}}
{{- define "besu-sandbox.validatorPodAntiAffinity" -}}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: {{ .Values.podAntiAffinity.weight }}
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "besu-sandbox.validatorPodSelectorLabels" . | nindent 12 }}
        topologyKey: kubernetes.io/hostname
{{- end -}}

{{/*
Validator pod affinity — merges optional podAntiAffinity + node.affinity.
*/}}
{{- define "besu-sandbox.validatorAffinity" -}}
{{- if or .Values.podAntiAffinity.enabled (not (empty .Values.node.affinity)) -}}
affinity:
{{- if .Values.podAntiAffinity.enabled }}
  {{- include "besu-sandbox.validatorPodAntiAffinity" . | nindent 2 }}
{{- end }}
{{- with .Values.node.affinity }}
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Enode URL for validator at zero-based index (dict with keys root, idx).
*/}}
{{- define "besu-sandbox.validatorEnode" -}}
{{- $root := .root -}}
{{- $idx := .idx -}}
{{- $n := add $idx 1 -}}
{{- $v := index $root.Values.validators $idx -}}
enode://{{ $v.pubKey }}@{{ $root.Release.Name }}-validator{{ $n }}-0.{{ $root.Release.Name }}-validator{{ $n }}.{{ $root.Release.Namespace }}.svc.cluster.local:30303
{{- end -}}

{{/*
Comma-separated bootnodes from the first two validators.
*/}}
{{- define "besu-sandbox.bootnodes" -}}
{{- $root := . -}}
{{- $enodes := list -}}
{{- range $i := until 2 -}}
{{- $enodes = append $enodes (include "besu-sandbox.validatorEnode" (dict "root" $root "idx" $i)) -}}
{{- end -}}
{{- join "," $enodes -}}
{{- end -}}

{{/*
JSON array of all validator enode URLs (for static-nodes.json).
*/}}
{{- define "besu-sandbox.staticNodesJson" -}}
[
{{- range $i, $v := .Values.validators }}
  {{ include "besu-sandbox.validatorEnode" (dict "root" $ "idx" $i) | quote }}{{ if lt (add $i 1) (len $.Values.validators) }},{{ end }}
{{- end }}
]
{{- end -}}

{{/*
Besu node-permissions allowlist (for nodes-allowlist.yml).
*/}}
{{- define "besu-sandbox.nodesAllowlist" -}}
nodes-allowlist=[
{{- range $i, $v := .Values.validators }}

  {{ include "besu-sandbox.validatorEnode" (dict "root" $ "idx" $i) | quote }}{{- if lt (add $i 1) (len $.Values.validators) }},{{ end }}
{{- end }}

]
{{- end -}}
