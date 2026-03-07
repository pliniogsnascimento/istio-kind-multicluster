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

function deploy_sample() {
    local context=$1
    local cluster=$2

    cat <<EOF | kubectl apply --context=$context -f -
apiVersion: v1
kind: Namespace
metadata:
  name: app1
  labels:
    istio.io/dataplane-mode: ambient
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app1
  namespace: app1
---
apiVersion: v1
data:
  index.html: hello from $cluster
kind: ConfigMap
metadata:
  name: app1
  namespace: app1
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: app1
  name: app1
  namespace: app1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app1
  strategy: {}
  template:
    metadata:
      labels:
        app: app1
    spec:
      serviceAccountName: app1
      containers:
      - image: nginx
        name: nginx
        resources: {}
        volumeMounts:
        - mountPath: /usr/share/nginx/html
          name: html
      volumes:
      - name: html
        configMap:
          name: app1
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: app1
  name: app1
  namespace: app1
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: app1
status:
  loadBalancer: {}
---
apiVersion: v1
kind: Namespace
metadata:
  name: curl
  labels:
    istio.io/dataplane-mode: ambient
spec: {}
status: {}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: curl
  namespace: curl
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: curl
  name: curl
  namespace: curl
spec:
  serviceAccountName: curl
  containers:
  - command:
    - /bin/sh
    - -c
    - while true; do curl -v http://app1.app1.svc.cluster.local; sleep 3; done
    image: nicolaka/netshoot
    name: curl
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
status: {}
EOF

}
