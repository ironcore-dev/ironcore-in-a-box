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

kind-cluster: kind ## Create a kind cluster
	$(KIND) create cluster --image $(KIND_IMAGE) --config kind/kind-config.yaml

setup-network: metalbond metalbond-client dpservice metalnet ## Customize the network on the kind nodes
	$(KUBECTL) rollout status daemonset/dpservice -n dpservice-system --timeout=360s && \
	$(KIND) get nodes | xargs -I {} sh -c '$(CRE) cp hack/setup-network.sh {}:/setup-network.sh && $(CRE) exec {} bash -c "bash /setup-network.sh"'

delete: ## Delete the kind cluster
	$(KIND) delete cluster

## Install components
up: prepare ironcore ironcore-net apinetlet setup-network metalnetlet libvirt-provider ## Bring up the ironcore stack

prepare: kubectl cmctl kind-cluster ## Prepare the environment
	$(KUBECTL) apply -k cluster/local/prepare
	$(CMCTL) check api --wait 120s

ironcore: prepare kubectl ## Install the ironcore
	$(KUBECTL) apply -k cluster/local/ironcore

ironcore-net: kubectl ## Install the ironcore-net
	$(KUBECTL) apply -k cluster/local/ironcore-net

apinetlet: kubectl ## Install the apinetlet
	$(KUBECTL) apply -k cluster/local/apinetlet

metalnetlet: kubectl ## Install the metalnetlet
	$(KUBECTL) apply -k cluster/local/metalnetlet

metalbond: kubectl ## Install metalbond
	$(KUBECTL) apply -k cluster/local/metalbond

metalbond-client: kubectl ## Install metalbond-client
	$(KUBECTL) apply -k cluster/local/metalbond-client

dpservice: kubectl ## Install dpservice
	$(KUBECTL) apply -k cluster/local/dpservice

metalnet: kubectl ## Install metalnet
	$(KUBECTL) apply -k cluster/local/metalnet


libvirt-provider: kubectl ## Install the libvirt-provider
	$(KUBECTL) apply -k cluster/local/libvirt-provider

cloud-hypervisor-provider: kubectl ## Install the cloud-hypervisor-provider
	$(KUBECTL) apply -k cluster/local/cloud-hypervisor-provider

## Remove components
down: remove-ironcore remove-ironcore-net remove-apinetlet remove-metalnet remove-dpservice remove-metalbond remove-metalbond-client remove-metalnetlet remove-libvirt-provider unprepare ## Remove the ironcore stack

remove-ironcore: kubectl ## Remove the ironcore
	$(KUBECTL) delete -k cluster/local/ironcore

remove-ironcore-net: kubectl ## Remove the ironcore
	$(KUBECTL) delete -k cluster/local/ironcore-net

remove-apinetlet: kubectl ## Remove the apinetlet
	$(KUBECTL) delete -k cluster/local/apinetlet

remove-metalnetlet: kubectl ## Remove the metalnetlet
	$(KUBECTL) delete -k cluster/local/metalnetlet

remove-metalbond: kubectl ## Remove metalbond
	$(KUBECTL) delete -k cluster/local/metalbond

remove-metalbond-client: kubectl ## Remove metalbond
	$(KUBECTL) delete -k cluster/local/metalbond-client

remove-dpservice: kubectl ## Remove dpservice
	$(KUBECTL) delete -k cluster/local/dpservice

remove-metalnet: kubectl ## Remove metalnet
	$(KUBECTL) delete -k cluster/local/metalnet

remove-libvirt-provider: kubectl ## Remove libvirt-provider
	$(KUBECTL) delete -k cluster/local/libvirt-provider

unprepare: kubectl ## Unprepare the environment
	$(KUBECTL) delete -k cluster/local/prepare

##@ Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

# curl retries
CURL_RETRIES=3

## Tool Binaries
KUBECTL ?= $(LOCALBIN)/kubectl-$(KUBECTL_VERSION)
KUBECTL_BIN ?= $(LOCALBIN)/kubectl
KIND ?= $(LOCALBIN)/kind-$(KIND_VERSION)
CMCTL ?= $(LOCALBIN)/cmctl-$(CMCTL_VERSION)
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
	$(call go-install-tool,$(KIND),sigs.k8s.io/kind,$(KIND_VERSION))

.PHONY: kubectl
kubectl: $(KUBECTL) ## Download kubectl locally if necessary.
$(KUBECTL): $(LOCALBIN)
	@if ! $(KUBECTL) version &>/dev/null; then \
		echo "$(KUBECTL) is not installed. Installing kubectl..."; \
		curl --retry $(CURL_RETRIES) -fsL https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(GOOS)/$(GOARCH)/kubectl -o $(KUBECTL); \
		ln -sf "$(KUBECTL)" "$(KUBECTL_BIN)"; \
		chmod +x "$(KUBECTL_BIN)" "$(KUBECTL)"; \
	else \
		echo "$(KUBECTL) is already installed."; \
	fi

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
