#!/bin/bash

function create_cluster() {
    CLUSTER=$1
    CLUSTER_POD_CIDR=$2
    CLUSTER_SERVICE_CIDR=$3

    cat <<EOF | kind create cluster --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $CLUSTER
networking:
  podSubnet: "$CLUSTER_POD_CIDR"
  serviceSubnet: "$CLUSTER_SERVICE_CIDR"
EOF
}