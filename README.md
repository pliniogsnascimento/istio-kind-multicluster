# Istio Kind Multicluster

This repository contains a complete setup for running a two-cluster Istio
multicluster deployment using [kind](https://kind.sigs.k8s.io/) and the
ambient profile of Istio.

## Overview

- Two `kind` clusters (`istio-1` and `istio-2`) are created with custom
  pod/service CIDRs.
- Istio is installed in each cluster using Helm with the ambient profile and
  multi-network support.
- Cross-cluster secrets are generated with `istioctl` so that the meshes can
  see each other.
- Routing between pod CIDRs is configured on the kind control-plane nodes.
- Helper scripts in `scripts/` encapsulate repeated logic (cluster creation
  and Istio deployment).

## Prerequisites

- Docker
- `kind` CLI
- `kubectl`
- `istioctl` (from an Istio release containing the ambient profile)
- `helm` (for Istio charts)

## Usage

Run `make` with various targets to control the environment.

```sh
# build everything (clusters, routing, Istio, etc.)
make run

# just create clusters
make clusters

# set node IP variables used elsewhere
make vars

# deploy Istio via helper scripts
make istio

# configure pod-to-pod routes between clusters
make routes

# tear down clusters
make delete
```

The `vars` target populates `NODE_ISTIO_0` and `NODE_ISTIO_1` which are used
for generating remote secrets and adding IP routes. This target is invoked by
`make run` automatically.

## Customization

You can modify CIDRs or cluster names by editing variables at the top of the
Makefile. The helper scripts accept parameters, so you may also call them
directly:

```sh
source scripts/kind.sh && create_cluster mycluster "10.20.0.0/16" "10.21.0.0/24"
source scripts/istio.sh && deploy_istio kind-mycluster mycluster networkX
```

## Troubleshooting

- If you hit an invalid JSON path error when retrieving node IPs, make sure
  your clusters are up (`kubectl get nodes --context=kind-istio-1`).
- If `make vars` fails due to shell quoting, ensure your shell is `bash` or
  compatible; the Makefile uses `$(shell ...)` with embedded quotes.

## Extending

You can add additional targets for deploying sample applications, security
landmarks, or ambient-waypoint demos (as in earlier versions of the Makefile).
The structure is intentionally minimal so you can layer on new clusters or
networks.

## License

BSD-like, see repository root for details.
