.DEFAULT_GOAL := help

REPO_ROOT := $(shell git rev-parse --show-toplevel)

MESH_ID              := mesh1
CLUSTER1             := istio-1
NETWORK1             := network1
CLUSTER1_POD_CIDR    := 10.10.0.0/16
CLUSTER1_SERVICE_CIDR := 110.255.0.0/24

CLUSTER2             := istio-2
NETWORK2             := network2
CLUSTER2_POD_CIDR    := 10.11.0.0/16
CLUSTER2_SERVICE_CIDR := 111.255.0.0/24

NODE_ISTIO_0 :=
NODE_ISTIO_1 :=

KIND_SH   := $(REPO_ROOT)/scripts/kind.sh
METALB_SH := $(REPO_ROOT)/scripts/metalb.sh
ISTIO_SH  := $(CURDIR)/scripts/istio.sh

include $(REPO_ROOT)/tools/certs/Makefile.selfsigned.mk

run: clusters vars routes metalb certs istio sample waypoint

clusters:
	bash -c "source $(KIND_SH) && create_cluster $(CLUSTER1) '$(CLUSTER1_POD_CIDR)' '$(CLUSTER1_SERVICE_CIDR)'"
	bash -c "source $(KIND_SH) && create_cluster $(CLUSTER2) '$(CLUSTER2_POD_CIDR)' '$(CLUSTER2_SERVICE_CIDR)'"

vars:
	$(eval NODE_ISTIO_0 := $(shell kubectl get nodes --context=kind-$(CLUSTER1) -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'))
	$(eval NODE_ISTIO_1 := $(shell kubectl get nodes --context=kind-$(CLUSTER2) -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'))

routes:
	docker exec $(CLUSTER1)-control-plane ip route add $(CLUSTER2_POD_CIDR) via $(NODE_ISTIO_1)
	docker exec $(CLUSTER2)-control-plane ip route add $(CLUSTER1_POD_CIDR) via $(NODE_ISTIO_0)

metalb:
	bash -c "source $(METALB_SH) && deploy_metalb kind-$(CLUSTER1) 10"
	bash -c "source $(METALB_SH) && deploy_metalb kind-$(CLUSTER2) 30"

clear-certs:
	rm -rf certs/* || true
	mkdir -p certs

move-certs:
	mv root-* certs/
	mv istio-* certs/

certs: clear-certs root-ca $(CLUSTER1)-cacerts $(CLUSTER2)-cacerts move-certs

istio:
	bash -c "source $(ISTIO_SH) && deploy_istio kind-$(CLUSTER1) $(CLUSTER1) $(NETWORK1) $(MESH_ID)"
	bash -c "source $(ISTIO_SH) && deploy_istio kind-$(CLUSTER2) $(CLUSTER2) $(NETWORK2) $(MESH_ID)"
	istioctl create-remote-secret --context=kind-$(CLUSTER2) --name=$(CLUSTER2) --server https://$(NODE_ISTIO_1):6443 | kubectl apply -f - --context=kind-$(CLUSTER1)
	istioctl create-remote-secret --context=kind-$(CLUSTER1) --name=$(CLUSTER1) --server https://$(NODE_ISTIO_0):6443 | kubectl apply -f - --context=kind-$(CLUSTER2)

sample:
	bash -c "source $(ISTIO_SH) && deploy_sample kind-$(CLUSTER1) $(CLUSTER1) $(CURDIR)/samples"
	bash -c "source $(ISTIO_SH) && deploy_sample kind-$(CLUSTER2) $(CLUSTER2) $(CURDIR)/samples"

waypoint:
	kubectl apply -f samples/waypoint.yaml --context kind-$(CLUSTER1) -n app1
	kubectl apply -f samples/waypoint.yaml --context kind-$(CLUSTER1) -n curl
	kubectl apply -f samples/waypoint.yaml --context kind-$(CLUSTER2) -n app1
	kubectl apply -f samples/waypoint.yaml --context kind-$(CLUSTER2) -n curl

sec-baseline:
	kubectl apply -f samples/security --context kind-$(CLUSTER1)
	kubectl apply -f samples/security --context kind-$(CLUSTER2)

delete:
	kind delete cluster --name $(CLUSTER1)
	kind delete cluster --name $(CLUSTER2)

help:
	@echo ""
	@echo "Model: multi-primary-ambient"
	@echo ""
	@echo "  run          Full deployment: clusters + routing + MetalLB + certs + Istio (ambient) + samples + waypoints"
	@echo ""
	@echo "Step-by-step targets:"
	@echo "  clusters     Create Kind clusters (istio-1 and istio-2)"
	@echo "  vars         Extract node IPs into NODE_ISTIO_0 / NODE_ISTIO_1"
	@echo "  routes       Configure inter-cluster pod routing"
	@echo "  metalb       Deploy MetalLB and configure IP address pools"
	@echo "  certs        Generate shared root CA and per-cluster intermediate CAs"
	@echo "  istio        Deploy Istio (ambient) and East-West gateways"
	@echo "  sample       Deploy test apps (nginx + curl)"
	@echo "  waypoint     Create waypoint gateways in app1 and curl namespaces"
	@echo "  sec-baseline Apply AuthorizationPolicy and PeerAuthentication"
	@echo ""
	@echo "Teardown / maintenance:"
	@echo "  delete       Delete both Kind clusters"
	@echo "  clear-certs  Remove generated certificate files"
	@echo ""

.PHONY: run clusters vars routes metalb certs istio sample waypoint sec-baseline delete clear-certs move-certs help
