#!/bin/bash

function deploy_metalb() {
    local context=$1
    local l2pool_start=$2
    local l2pool_end=$((l2pool_start+9))
    kind_subnet_prefix=$(docker network inspect kind | jq -r ".[].IPAM.Config[].Subnet | select(test(\":\") | not)" | cut -d'.' -f1,2).255

    kubectl apply --context=$context \
        -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml \
		>/dev/null

    kubectl wait deployments.apps/controller \
		--context=$context \
		-n metallb-system \
		--timeout=1m \
		--for=condition=Available \
		>/dev/null

	kubectl wait daemonsets.app/speaker \
		--context=$context \
		-n metallb-system \
		--timeout=1m \
		--for=jsonpath='{.status.numberReady}'=1 \
		>/dev/null
    
    kubectl apply \
		--context=$context \
		-f - <<-EOM >/dev/null
			apiVersion: metallb.io/v1beta1
			kind: IPAddressPool
			metadata:
			  name: pool
			  namespace: metallb-system
			spec:
			  addresses:
			  - ${kind_subnet_prefix}.${l2pool_start}-${kind_subnet_prefix}.${l2pool_end}
		EOM

	kubectl apply \
		--context=$context \
		-f - <<-EOM >/dev/null
			apiVersion: metallb.io/v1beta1
			kind: L2Advertisement
			metadata:
			  name: pool
			  namespace: metallb-system
			spec:
			  ipAddressPools:
			  - pool
		EOM

}