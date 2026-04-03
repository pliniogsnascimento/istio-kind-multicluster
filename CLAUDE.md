# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository automates two-cluster Istio multicluster deployments using Kind (Kubernetes in Docker). Each deployment model is self-contained under `deployments/<model>/` with its own Makefile, scripts, and samples.

**Prerequisites:** Docker, kind, kubectl, helm, istioctl, openssl

## Common Commands

```bash
# List available deployment models
make help

# Full deployment — ambient mode
make multi-primary-ambient
# or equivalently:
make -C deployments/multi-primary-ambient run

# Full deployment — sidecar mode
make multi-primary-sidecar
# or equivalently:
make -C deployments/multi-primary-sidecar run

# Per-model step-by-step targets (ambient example)
make -C deployments/multi-primary-ambient clusters     # Create Kind clusters
make -C deployments/multi-primary-ambient vars         # Extract node IPs
make -C deployments/multi-primary-ambient routes       # Configure inter-cluster routing
make -C deployments/multi-primary-ambient metalb       # Deploy MetalLB with IP pools
make -C deployments/multi-primary-ambient certs        # Generate root CA + per-cluster CAs
make -C deployments/multi-primary-ambient istio        # Deploy Istio + East-West gateways
make -C deployments/multi-primary-ambient sample       # Deploy test apps (nginx + curl)
make -C deployments/multi-primary-ambient waypoint     # Create waypoint gateways (ambient only)
make -C deployments/multi-primary-ambient sec-baseline # Apply AuthorizationPolicy + PeerAuthentication
make -C deployments/multi-primary-ambient delete       # Tear down both clusters
make -C deployments/multi-primary-ambient clear-certs  # Remove generated certificate files

# Sidecar-specific
make -C deployments/multi-primary-sidecar injection    # Enable sidecar injection

# Per-model help
make -C deployments/multi-primary-ambient help
make -C deployments/multi-primary-sidecar help
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
deployments/<model>/certs/root-cert.pem        ← Shared root CA (self-signed)
deployments/<model>/certs/istio-1/ca-cert.pem  ← Cluster 1 intermediate CA
deployments/<model>/certs/istio-2/ca-cert.pem  ← Cluster 2 intermediate CA
```

Certificates are generated via `tools/certs/Makefile.selfsigned.mk` using OpenSSL. The `cacerts` Kubernetes secret is created in each cluster's `istio-system` namespace before Istio is installed. All certs use 4096-bit RSA keys with 3650-day validity (demo only).

### Code Organization

```
Makefile                          ← Dispatcher: auto-discovers models, delegates via make -C
scripts/kind.sh                   ← create_cluster(): shared by all models
scripts/metalb.sh                 ← deploy_metalb(): shared by all models
tools/certs/                      ← Makefile includes for self-signed CA generation
deployments/
  multi-primary-ambient/
    Makefile                      ← Full orchestration for ambient mode
    scripts/istio.sh              ← deploy_istio() (ambient), deploy_sample()
    samples/                      ← Manifests: app1, curl-pod, waypoint, security/
  multi-primary-sidecar/
    Makefile                      ← Full orchestration for sidecar mode
    scripts/istio.sh              ← deploy_istio() (sidecar), deploy_sample(), enable_injection()
    samples/                      ← Manifests: app1, curl-pod, security/
```

### Adding a New Deployment Model

1. Create `deployments/<model-name>/` with `Makefile`, `scripts/istio.sh`, and `samples/`.
2. Reference shared scripts via `$(REPO_ROOT)/scripts/kind.sh` and `$(REPO_ROOT)/scripts/metalb.sh`.
3. Include cert tooling via `include $(REPO_ROOT)/tools/certs/Makefile.selfsigned.mk`.
4. The root `Makefile` auto-discovers models — no changes needed there.

### Istio Helm Components (ambient mode)

Installed in this order: `istio-base` → `istiod` → `istio-cni` → `ztunnel`. The `istiod` chart receives values for mesh ID, cluster name, network, and ambient profile enablement.

### Ambient vs Sidecar Mode

- **Ambient** (`multi-primary-ambient`): Uses ztunnel for L4 mTLS, optional waypoint gateways for L7. Namespaces are labeled `istio.io/dataplane-mode: ambient`.
- **Sidecar** (`multi-primary-sidecar`): Uses traditional Envoy sidecar injection. Namespaces are labeled for injection.

### `make vars` Pattern

The `vars` target dynamically populates `NODE_ISTIO_0` and `NODE_ISTIO_1` shell variables by querying kubectl for the node's internal IP, then passes them to subsequent targets (e.g., `routes`). The Makefile uses `$(eval ...)` with shell command substitution for this.
