.DEFAULT_GOAL := help

DEPLOYMENTS_DIR := deployments
MODELS := $(patsubst $(DEPLOYMENTS_DIR)/%/Makefile,%,$(wildcard $(DEPLOYMENTS_DIR)/*/Makefile))

$(MODELS):
	$(MAKE) -C $(DEPLOYMENTS_DIR)/$@

help:
	@echo ""
	@echo "Available deployment models:"
	@echo ""
	@for m in $(MODELS); do echo "  $$m"; done
	@echo ""
	@echo "Usage:"
	@echo "  make <model>                    Full deployment for a model"
	@echo "  make -C deployments/<model> <target>   Run a specific target"
	@echo "  make -C deployments/<model> help        Show model-specific targets"
	@echo ""
	@echo "Examples:"
	@echo "  make multi-primary-ambient"
	@echo "  make -C deployments/multi-primary-sidecar certs"
	@echo ""

.PHONY: help $(MODELS)
