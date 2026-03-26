# GEMINI.md - Istio Kind Multicluster Context

This project provides a complete, automated setup for a two-cluster Istio multicluster deployment using **Kind** and the **Istio Ambient** profile. It focuses on demonstrating multi-network routing, shared trust (via custom root CA), and ambient waypoint functionality across clusters.

## Project Overview

- **Main Technologies:** Kubernetes (Kind), Istio (Ambient Profile), Helm, MetalLB, Docker, Bash.
- **Goal:** Demonstrate a functional Istio multicluster environment where pods in different clusters can communicate securely across networks using the ambient mesh.

## Architecture & Configuration

- **Clusters:** Two Kind clusters named `istio-1` and `istio-2`.
- **Networking:**
  - Custom Pod and Service CIDRs for each cluster to avoid overlap.
  - **Inter-cluster Routing:** Configured at the Docker container level using `ip route` on control-plane nodes.
  - **Load Balancing:** MetalLB is used in each cluster to provide `LoadBalancer` services (e.g., for Istio East-West Gateways).
  - **Multi-Network:** Istio is configured with `AMBIENT_ENABLE_MULTI_NETWORK="true"`.
- **Trust Domain:** A shared root CA is used to generate cluster-specific intermediate CAs (`cacerts`), enabling mutual TLS (mTLS) across the mesh.

## Building and Running

The project is orchestrated via a `Makefile`.

| Command | Description |
| :--- | :--- |
| `make run` | Full setup: clusters, routes, MetalLB, certs, Istio, and samples. |
| `make clusters` | Creates the two Kind clusters with specified CIDRs. |
| `make istio` | Deploys Istio (Ambient) and configures remote secrets for cross-cluster visibility. |
| `make routes` | Configures pod-to-pod routing between clusters on Kind nodes. |
| `make metalb` | Deploys and configures MetalLB for both clusters. |
| `make certs` | Generates self-signed root and intermediate certificates. |
| `make delete` | Tears down both Kind clusters. |
| `make waypoint` | Configures Istio Waypoints for sample namespaces. |

## Project Structure

- `scripts/`: Modular bash scripts for cluster creation (`kind.sh`), Istio deployment (`istio.sh`), and MetalLB setup (`metalb.sh`).
- `samples/`: Kubernetes manifests for testing.
  - `multicluster/`: Sample applications (app1, curl) for cross-cluster testing.
  - `ambient/`: Waypoint configuration for ambient mode.
  - `security/`: Baseline security and authentication policies.
- `tools/certs/`: Makefiles and tools for generating the self-signed certificate hierarchy.
- `certs/`: (Generated) Storage for root and cluster-specific certificates.

## Development Conventions

- **Modular Automation:** Prefer adding logic to `scripts/` and invoking it via the `Makefile` to keep the entry points clean and reusable.
- **Context Management:** Most commands require explicit `--context` (e.g., `kind-istio-1`) to target the correct cluster.
- **Idempotency:** Scripts should generally handle existing resources (e.g., `kubectl apply` or checking for existence) to allow for repeated runs.
- **Ambient Testing:** When testing connectivity, remember that ambient mode relies on ztunnel for L4 and Waypoints for L7 features. Labels are used to opt namespaces into the mesh.
