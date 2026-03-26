MESH_ID="mesh1"
CLUSTER1="istio-1"
NETWORK1="network1"
CLUSTER1_POD_CIDR="10.10.0.0/16"
CLUSTER1_SERVICE_CIDR="110.255.0.0/24"

CLUSTER2="istio-2"
NETWORK2="network2"
CLUSTER2_POD_CIDR="10.11.0.0/16"
CLUSTER2_SERVICE_CIDR="111.255.0.0/24"


NODE_ISTIO_0=
NODE_ISTIO_1=

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(SELF_DIR)/tools/certs/Makefile.selfsigned.mk

run: clusters vars routes metalb certs istio sample waypoint

run-sidecar: clusters vars routes metalb certs istio-sidecar sample-sidecar

clusters:
	bash -c "source scripts/kind.sh && create_cluster $(CLUSTER1) '$(CLUSTER1_POD_CIDR)' '$(CLUSTER1_SERVICE_CIDR)'"
	bash -c "source scripts/kind.sh && create_cluster $(CLUSTER2) '$(CLUSTER2_POD_CIDR)' '$(CLUSTER2_SERVICE_CIDR)'"

vars:
	$(eval NODE_ISTIO_0 := $(shell kubectl get nodes --context=kind-istio-1 -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'))
	$(eval NODE_ISTIO_1 := $(shell kubectl get nodes --context=kind-istio-2 -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'))

istio:
	bash -c "source scripts/istio.sh && deploy_istio kind-$(CLUSTER1) $(CLUSTER1) network1"
	bash -c "source scripts/istio.sh && deploy_istio kind-$(CLUSTER2) $(CLUSTER2) network2"
	istioctl create-remote-secret --context=kind-$(CLUSTER2) --name=$(CLUSTER2) --server https://$(NODE_ISTIO_1):6443 | kubectl apply -f - --context=kind-$(CLUSTER1)
	istioctl create-remote-secret --context=kind-$(CLUSTER1) --name=$(CLUSTER1) --server https://$(NODE_ISTIO_0):6443 | kubectl apply -f - --context=kind-$(CLUSTER2)

istio-sidecar:
	bash -c "source scripts/istio.sh && deploy_istio_sidecar kind-$(CLUSTER1) $(CLUSTER1) network1"
	bash -c "source scripts/istio.sh && deploy_istio_sidecar kind-$(CLUSTER2) $(CLUSTER2) network2"
	istioctl create-remote-secret --context=kind-$(CLUSTER2) --name=$(CLUSTER2) --server https://$(NODE_ISTIO_1):6443 | kubectl apply -f - --context=kind-$(CLUSTER1)
	istioctl create-remote-secret --context=kind-$(CLUSTER1) --name=$(CLUSTER1) --server https://$(NODE_ISTIO_0):6443 | kubectl apply -f - --context=kind-$(CLUSTER2)

metalb:
	bash -c "source scripts/metalb.sh && deploy_metalb kind-$(CLUSTER1) 10"
	bash -c "source scripts/metalb.sh && deploy_metalb kind-$(CLUSTER2) 30"

routes:
	docker exec $(CLUSTER1)-control-plane ip route add $(CLUSTER2_POD_CIDR) via $(NODE_ISTIO_1)
	docker exec $(CLUSTER2)-control-plane ip route add $(CLUSTER1_POD_CIDR) via $(NODE_ISTIO_0)

delete:
	kind delete cluster --name $(CLUSTER1)
	kind delete cluster --name $(CLUSTER2)

sample:
	bash -c "source scripts/istio.sh && deploy_sample kind-$(CLUSTER1) $(CLUSTER1) samples/ambient"
	bash -c "source scripts/istio.sh && deploy_sample kind-$(CLUSTER2) $(CLUSTER2) samples/ambient"

sample-sidecar:
	bash -c "source scripts/istio.sh && deploy_sample kind-$(CLUSTER1) $(CLUSTER1) samples/sidecar"
	bash -c "source scripts/istio.sh && deploy_sample kind-$(CLUSTER2) $(CLUSTER2) samples/sidecar"

clear-certs:
	rm -r certs/* || true
	mkdir -p certs


move-certs:
	mv root-* certs
	mv istio* certs

certs: clear-certs root-ca $(CLUSTER1)-cacerts $(CLUSTER2)-cacerts move-certs

sec-baseline:
	kubectl apply -f samples/security --context kind-$(CLUSTER1)
	kubectl apply -f samples/security --context kind-$(CLUSTER2)

waypoint:
	kubectl apply -f samples/ambient/waypoint.yaml --context kind-$(CLUSTER1) -n app1
	kubectl apply -f samples/ambient/waypoint.yaml --context kind-$(CLUSTER1) -n curl
	kubectl apply -f samples/ambient/waypoint.yaml --context kind-$(CLUSTER2) -n app1
	kubectl apply -f samples/ambient/waypoint.yaml --context kind-$(CLUSTER2) -n curl