# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

GOARCH  := $(shell go env GOARCH)
GOOS    := $(shell go env GOOS)

# Instead of using kindest/node:v1.32.0 we use our own image with the necessary tools installed
KIND_IMAGE := ghcr.io/ironcore-dev/kind-node:latest

# Configure the kind cluster name
KIND_CLUSTER_NAME ?= ironcore-in-a-box
export KIND_CLUSTER_NAME

# Expected kubectl context for the kind cluster
KIND_CONTEXT := kind-$(KIND_CLUSTER_NAME)

# Command wrappers pre-configured to target the kind cluster
KIND_CTX = $(KIND) --name $(KIND_CLUSTER_NAME)
KUBECTL_CTX = $(KUBECTL) --context $(KIND_CONTEXT)

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: guard-cluster
guard-cluster: ## Verify the target kind cluster exists and kubectl context is correct
	@if ! $(KIND) get clusters 2>/dev/null | grep -qx '$(KIND_CLUSTER_NAME)'; then \
		echo "ERROR: kind cluster '$(KIND_CLUSTER_NAME)' does not exist."; \
		echo "       Run 'make kind-cluster' to create it first."; \
		exit 1; \
	fi
	@CURRENT_CTX=$$($(KUBECTL) config current-context 2>/dev/null); \
	if [ "$$CURRENT_CTX" != "$(KIND_CONTEXT)" ]; then \
		echo "ERROR: Current kubectl context is '$$CURRENT_CTX', expected '$(KIND_CONTEXT)'."; \
		echo "       Run: kubectl config use-context $(KIND_CONTEXT)"; \
		exit 1; \
	fi

.PHONY: render-public-vip-overlays
render-public-vip-overlays: guard-cluster ## Render runtime kustomize overlays from detected public VIP config
	@hack/render-public-vip-overlays.sh "$(CRE)" "$(KIND_CLUSTER_NAME)" "$(PUBLIC_VIP_RUNTIME_OVERLAYS_DIR)"

kind-cluster: kind ## Create a kind cluster
	$(KIND_CTX) create cluster --image $(KIND_IMAGE) --config kind/kind-config.yaml

setup-network: guard-cluster metalbond metalbond-client dpservice metalnet ## Customize the network on the kind nodes
	$(KUBECTL_CTX) rollout status daemonset/dpservice -n dpservice-system --timeout=360s && \
	$(KIND_CTX) get nodes | xargs -I {} sh -c '$(CRE) cp hack/setup-network.sh {}:/setup-network.sh && $(CRE) exec {} bash -c "bash /setup-network.sh"'

delete: ## Delete the kind cluster
	$(KIND_CTX) delete cluster

## Install components
up: prepare ironcore ironcore-net apinetlet setup-network metalnetlet libvirt-provider ## Bring up the ironcore stack

prepare: kubectl cmctl kind-cluster ## Prepare the environment
	$(KUBECTL_CTX) apply -k cluster/local/prepare
	$(CMCTL) check api --wait 120s

ironcore: prepare kubectl ## Install the ironcore
	$(KUBECTL_CTX) apply -k cluster/local/ironcore

ironcore-net: render-public-vip-overlays guard-cluster kubectl ## Install the ironcore-net
	$(KUBECTL_CTX) apply -k $(if $(wildcard $(PUBLIC_VIP_RUNTIME_OVERLAYS_DIR)/ironcore-net),"$(PUBLIC_VIP_RUNTIME_OVERLAYS_DIR)/ironcore-net",cluster/local/ironcore-net)

apinetlet: guard-cluster kubectl ## Install the apinetlet
	$(KUBECTL_CTX) apply -k cluster/local/apinetlet

metalnetlet: guard-cluster kubectl ## Install the metalnetlet
	$(KUBECTL_CTX) apply -k cluster/local/metalnetlet

metalbond: guard-cluster kubectl ## Install metalbond
	$(KUBECTL_CTX) apply -k cluster/local/metalbond

metalbond-client: render-public-vip-overlays guard-cluster kubectl ## Install metalbond-client
	$(KUBECTL_CTX) apply -k $(if $(wildcard $(PUBLIC_VIP_RUNTIME_OVERLAYS_DIR)/metalbond-client),"$(PUBLIC_VIP_RUNTIME_OVERLAYS_DIR)/metalbond-client",cluster/local/metalbond-client)

dpservice: guard-cluster kubectl ## Install dpservice
	$(KUBECTL_CTX) apply -k cluster/local/dpservice

metalnet: guard-cluster kubectl ## Install metalnet
	$(KUBECTL_CTX) apply -k cluster/local/metalnet


libvirt-provider: guard-cluster kubectl ## Install the libvirt-provider
	$(KUBECTL_CTX) apply -k cluster/local/libvirt-provider

## Remove components
down: remove-ironcore remove-ironcore-net remove-apinetlet remove-metalnet remove-dpservice remove-metalbond remove-metalbond-client remove-metalnetlet remove-libvirt-provider unprepare ## Remove the ironcore stack

remove-ironcore: guard-cluster kubectl ## Remove the ironcore
	$(KUBECTL_CTX) delete -k cluster/local/ironcore

remove-ironcore-net: guard-cluster kubectl ## Remove the ironcore
	$(KUBECTL_CTX) delete -k cluster/local/ironcore-net

remove-apinetlet: guard-cluster kubectl ## Remove the apinetlet
	$(KUBECTL_CTX) delete -k cluster/local/apinetlet

remove-metalnetlet: guard-cluster kubectl ## Remove the metalnetlet
	$(KUBECTL_CTX) delete -k cluster/local/metalnetlet

remove-metalbond: guard-cluster kubectl ## Remove metalbond
	$(KUBECTL_CTX) delete -k cluster/local/metalbond

remove-metalbond-client: guard-cluster kubectl ## Remove metalbond
	$(KUBECTL_CTX) delete -k cluster/local/metalbond-client

remove-dpservice: guard-cluster kubectl ## Remove dpservice
	$(KUBECTL_CTX) delete -k cluster/local/dpservice

remove-metalnet: guard-cluster kubectl ## Remove metalnet
	$(KUBECTL_CTX) delete -k cluster/local/metalnet

remove-libvirt-provider: guard-cluster kubectl ## Remove libvirt-provider
	$(KUBECTL_CTX) delete -k cluster/local/libvirt-provider

unprepare: guard-cluster kubectl ## Unprepare the environment
	$(KUBECTL_CTX) delete -k cluster/local/prepare

##@ Dependencies

## Location to install dependencies to
LOCALDIR ?= $(shell pwd)
LOCALBIN ?= $(LOCALDIR)/bin
LOCALBATS ?= $(LOCALDIR)/.bats
PUBLIC_VIP_RUNTIME_OVERLAYS_DIR ?= $(LOCALDIR)/.tmp/runtime-overlays
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

# curl retries
CURL_RETRIES=3

## Tool Binaries
KUBECTL ?= $(LOCALBIN)/kubectl-$(KUBECTL_VERSION)
KUBECTL_BIN ?= $(LOCALBIN)/kubectl
KIND ?= $(LOCALBIN)/kind-$(KIND_VERSION)
KIND_BIN ?= $(LOCALBIN)/kind
CMCTL ?= $(LOCALBIN)/cmctl-$(CMCTL_VERSION)
BATS ?= $(LOCALDIR)/.bats/bats-core/bin/bats
CRE ?= $(shell if cre=$$(command -v docker); then echo $$cre; elif cre=$$(command -v podman); then echo $$cre; fi)
ifeq ($(CRE),)
$(error no docker or podman found, exiting...)
endif

## Tool Versions
KUBECTL_VERSION ?= v1.32.0
KIND_VERSION ?= v0.27.0
CMCTL_VERSION ?= latest

.PHONY: cmctl
cmctl: $(CMCTL) ## Download cmctl locally if necessary.
$(CMCTL): $(LOCALBIN)
	$(call go-install-tool,$(CMCTL),github.com/cert-manager/cmctl/v2,$(CMCTL_VERSION))

.PHONY: kind
kind: $(KIND) ## Download kind locally if necessary.
$(KIND): $(LOCALBIN)
	$(call go-install-tool,$(KIND),sigs.k8s.io/kind,$(KIND_VERSION)); \
	ln -sf "$(KIND)" "$(KIND_BIN)"

.PHONY: kubectl
kubectl: $(KUBECTL) ## Download kubectl locally if necessary.
$(KUBECTL): $(LOCALBIN)
	@if ! $(KUBECTL) &>/dev/null; then \
		echo "$(KUBECTL) is not installed. Installing kubectl..."; \
		curl --retry $(CURL_RETRIES) -fsL https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(GOOS)/$(GOARCH)/kubectl -o $(KUBECTL); \
		ln -sf "$(KUBECTL)" "$(KUBECTL_BIN)"; \
		chmod +x "$(KUBECTL_BIN)" "$(KUBECTL)"; \
	else \
		echo "$(KUBECTL) is already installed."; \
	fi

.PHONY: check-submodules
check-submodules:
	@if git submodule status | grep -q "^-"; then \
		echo "Submodules missing. Initializing..."; \
		git submodule update --init --recursive; \
	fi

.PHONY: test
test: check-submodules $(KIND) $(KUBECTL)
	@export "PATH=$(LOCALBIN):$(PATH)"; \
	export BATS_SOURCES=$(LOCALBATS); \
	export EXAMPLES=$(LOCALDIR)/examples; \
	export KUBECTL_CTX="$(KUBECTL_CTX)"; \
	export KIND="$(KIND)"; \
	$(BATS) --tap tests/

.PHONY: lint-tests
lint-tests:
	@find tests/ -name "*.sh" -o -name "*.bats" | xargs shellcheck && echo "Success."

# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary (ideally with version)
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f $(1) ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
GOBIN=$(LOCALBIN) go install $${package} ;\
mv "$$(echo "$(1)" | sed "s/-$(3)$$//")" $(1) ;\
}
endef
