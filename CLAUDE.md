# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository automates a two-cluster Istio multicluster deployment using Kind (Kubernetes in Docker) and the Istio Ambient profile. It demonstrates secure, multi-network pod-to-pod communication across two Kubernetes clusters with shared mTLS trust.

**Prerequisites:** Docker, kind, kubectl, helm, istioctl, openssl

## Common Commands

```bash
# Full deployment (ambient mode)
make run

# Full deployment (sidecar mode)
make run-sidecar

# Tear down both clusters
make delete

# Step-by-step targets
make clusters      # Create Kind clusters
make vars          # Extract node IPs into NODE_ISTIO_0 / NODE_ISTIO_1
make routes        # Configure inter-cluster pod routing
make metalb        # Deploy MetalLB with IP pools
make certs         # Generate root CA + per-cluster intermediate CAs
make istio         # Deploy Istio (ambient) + East-West gateways
make sample        # Deploy test apps (nginx + curl)
make waypoint      # Create waypoint gateways
make sec-baseline  # Apply AuthorizationPolicy + PeerAuthentication
make injection     # Enable sidecar injection (for sidecar mode)
make clear-certs   # Remove generated certificate files
```

## Architecture

### Cluster Configuration

| | Cluster 1 (`istio-1`) | Cluster 2 (`istio-2`) |
|---|---|---|
| Pod CIDR | `10.10.0.0/16` | `10.11.0.0/16` |
| Service CIDR | `110.255.0.0/24` | `111.255.0.0/24` |
| Network | `network1` | `network2` |
| kubectl context | `kind-istio-1` | `kind-istio-2` |

Both clusters share `MESH_ID=mesh1`.

### How Multi-Cluster Networking Works

1. **Non-overlapping CIDRs** prevent IP conflicts between clusters.
2. **IP routes** are added directly on Kind control-plane nodes via `docker exec ip route add`, enabling direct pod-to-pod routing across clusters.
3. **MetalLB** (v0.15.3) provides LoadBalancer IPs for East-West gateways, with each cluster using a distinct subnet range derived from the Kind Docker bridge IP.
4. **East-West gateways** handle cross-cluster traffic:
   - Ambient mode: port 15008, HBONE protocol
   - Sidecar mode: port 15443, TLS passthrough
5. **Remote secrets** are created in each cluster pointing to the other, enabling cross-cluster service discovery by istiod.

### Certificate Hierarchy

```
certs/root-cert.pem        ← Shared root CA (self-signed)
certs/istio-1/ca-cert.pem  ← Cluster 1 intermediate CA
certs/istio-2/ca-cert.pem  ← Cluster 2 intermediate CA
```

Certificates are generated via `tools/certs/Makefile.selfsigned.mk` using OpenSSL. The `cacerts` Kubernetes secret is created in each cluster's `istio-system` namespace before Istio is installed. All certs use 4096-bit RSA keys with 3650-day validity (demo only).

### Code Organization

- **`Makefile`** — Orchestration entry point; defines cluster variables and sequences targets.
- **`scripts/kind.sh`** — `create_cluster()`: creates a Kind cluster with custom CIDRs via heredoc config.
- **`scripts/istio.sh`** — `deploy_istio()` and `deploy_istio_sidecar()`: Helm-based Istio install with ambient/sidecar profiles; `deploy_sample()`: applies test manifests with cluster name substitution.
- **`scripts/metalb.sh`** — `deploy_metalb()`: computes IP pool range from Kind subnet, installs MetalLB, creates IPAddressPool.
- **`samples/`** — Kubernetes manifests for test apps, waypoint gateways, and security policies.
- **`tools/certs/`** — Makefile includes for self-signed CA generation and k8s-sourced root CA signing.

### Istio Helm Components (ambient mode)

Installed in this order: `istio-base` → `istiod` → `istio-cni` → `ztunnel`. The `istiod` chart receives values for mesh ID, cluster name, network, and ambient profile enablement.

### Ambient vs Sidecar Mode

- **Ambient** (`make run`): Uses ztunnel for L4 mTLS, optional waypoint gateways for L7. Namespaces are labeled `istio.io/dataplane-mode: ambient`.
- **Sidecar** (`make run-sidecar`): Uses traditional Envoy sidecar injection. Namespaces are labeled for injection.

### `make vars` Pattern

The `vars` target dynamically populates `NODE_ISTIO_0` and `NODE_ISTIO_1` shell variables by querying kubectl for the node's internal IP, then passes them to subsequent targets (e.g., `routes`). The Makefile uses `$(eval ...)` with shell command substitution for this.
