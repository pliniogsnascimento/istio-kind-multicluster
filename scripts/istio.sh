#!/bin/bash

function deploy_istio() {
    local context=$1
    local cluster=$2
    local network=$3
    local meshID=$4

    echo "Deploying istio on $context"

    # Deploy gatewayapi
    kubectl get crd gateways.gateway.networking.k8s.io --context=$context &> /dev/null || \
  	kubectl apply --context=$context --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml
	kubectl wait --context=$context --for=condition=established crd/gateways.gateway.networking.k8s.io --timeout=60s

    echo "Gateway API deployed on cluster $cluster"

    # Create istio-system namespace and label it with the network name for each cluster
	kubectl create ns istio-system --context=$context || true
	kubectl --context=$context label namespace istio-system topology.istio.io/network=$network
    
    # Configure istio CA
    kubectl --context=$context create secret generic cacerts -n istio-system \
        --from-file=certs/$cluster/ca-cert.pem \
        --from-file=certs/$cluster/ca-key.pem \
        --from-file=certs/$cluster/root-cert.pem \
        --from-file=certs/$cluster/cert-chain.pem

	# Install Istio with the ambient profile in each cluster
	helm install istio-base istio/base -n istio-system --kube-context $context
	helm install istiod istio/istiod -n istio-system --kube-context $context \
		--set global.meshID=$meshID \
		--set global.multiCluster.clusterName=$cluster \
		--set global.network=$network \
		--set profile=ambient \
		--set env.AMBIENT_ENABLE_MULTI_NETWORK="true" \
		--set env.AMBIENT_ENABLE_BAGGAGE="true"
	helm install istio-cni istio/cni -n istio-system --kube-context $context --set profile=ambient
	helm install ztunnel istio/ztunnel -n istio-system --kube-context $context --set multiCluster.clusterName=$cluster --set global.network=$network
	
    echo "Istio deployed on cluster $cluster"

    cat <<EOF | kubectl apply --context=$context -f -
kind: Gateway
apiVersion: gateway.networking.k8s.io/v1
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
  labels:
    topology.istio.io/network: "$network"
spec:
  gatewayClassName: istio-east-west
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE
    tls:
      mode: Terminate # represents double-HBONE
      options:
        gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
EOF

    echo "EW Gateway deployed on cluster $cluster"
}

function deploy_istio_sidecar() {
    local context=$1
    local cluster=$2
    local network=$3
    local meshID=$4

    echo "Deploying istio (sidecar) on $context"

    # Deploy gatewayapi
    kubectl get crd gateways.gateway.networking.k8s.io --context=$context &> /dev/null || \
  	kubectl apply --context=$context --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml
	kubectl wait --context=$context --for=condition=established crd/gateways.gateway.networking.k8s.io --timeout=60s

    echo "Gateway API deployed on cluster $cluster"

    # Create istio-system namespace and label it with the network name for each cluster
	kubectl create ns istio-system --context=$context || true
	kubectl --context=$context label namespace istio-system topology.istio.io/network=$network
    
    # Configure istio CA
    kubectl --context=$context create secret generic cacerts -n istio-system \
        --from-file=certs/$cluster/ca-cert.pem \
        --from-file=certs/$cluster/ca-key.pem \
        --from-file=certs/$cluster/root-cert.pem \
        --from-file=certs/$cluster/cert-chain.pem

	# Install Istio with the default sidecar profile in each cluster
	helm install istio-base istio/base -n istio-system --kube-context $context
	helm install istiod istio/istiod -n istio-system --kube-context $context \
		--set global.meshID=$meshID \
		--set global.multiCluster.clusterName=$cluster \
		--set global.network=$network \
		--set meshConfig.accessLogFile=/dev/stdout

    echo "Istio (sidecar) deployed on cluster $cluster"

    cat <<EOF | kubectl apply --context=$context -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
spec:
  gatewayClassName: istio
  listeners:
  - name: cross-cluster
    port: 15443
    protocol: TLS
    tls:
      mode: Passthrough
    allowedRoutes:
      namespaces:
        from: All
EOF

    echo "EW Gateway (sidecar) deployed on cluster $cluster"
}

function deploy_sample() {
    local context=$1
    local cluster=$2
    local samples_dir=${3:-samples/ambient}

    sed "s/kind-cluster/$cluster/" $samples_dir/app1.yaml | kubectl --context=$context apply -f -
    kubectl --context=$context apply -f $samples_dir/curl-pod.yaml
}
