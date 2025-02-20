# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

GOARCH  := $(shell go env GOARCH)
GOOS    := $(shell go env GOOS)

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

.PHONY: kind kind-clean network network-examples

kind-cluster: kind ## Create a kind cluster
	$(KIND) create cluster --config kind/kind-config.yaml

network: kind
	$(KUBECTL) apply -k cluster/local/metalbond
	$(KUBECTL) apply -k cluster/local/dpservice
	$(KUBECTL) apply -k cluster/local/metalnet

network-examples: kind
	$(KUBECTL) apply -f network/examples/network.yaml
	$(KUBECTL) apply -f network/examples/networkinterface.yaml
	$(KUBECTL) apply -f network/examples/networkinterface2.yaml

install-libvirtd: kind ## Install libvirtd on the kind nodes
	$(KIND) get nodes | xargs -I {} docker exec {} bash -c "\
		apt-get update && \
		apt-get install -y libvirt-daemon libvirt-clients"

delete-network-examples: kind
	$(KUBECTL) delete -f network/examples/network.yaml
	$(KUBECTL) delete -f network/examples/networkinterface.yaml
	$(KUBECTL) delete -f network/examples/networkinterface2.yaml

delete-network: kind
	$(KUBECTL) delete -k cluster/local/metalbond
	$(KUBECTL) delete -k cluster/local/dpservice
	$(KUBECTL) delete -k cluster/local/metalnet

delete: ## Delete the kind cluster
	$(KIND) delete cluster

## Install components
up: prepare ironcore ironcore-net apinetlet metalbond dpservice metalnet ## Bring up the ironcore stack

prepare: kubectl cmctl ## Prepare the environment
	$(KUBECTL) apply -k cluster/local/prepare
	$(CMCTL) check api --wait 120s

ironcore: prepare kubectl ## Install the ironcore stack
	$(KUBECTL) apply -k cluster/local/ironcore

ironcore-net: kubectl ## Install the ironcore-net stack
	$(KUBECTL) apply -k cluster/local/ironcore-net

apinetlet: kubectl ## Install the apinetlet stack
	$(KUBECTL) apply -k cluster/local/apinetlet

metalbond: kubectl ## Install metalbond
	$(KUBECTL) apply -k cluster/local/metalbond

dpservice: kubectl ## Install dpservice
	$(KUBECTL) apply -k cluster/local/dpservice

metalnet: kubectl ## Install metalnet
	$(KUBECTL) apply -k cluster/local/metalnet

## Remove components
down: remove-ironcore remove-ironcore-net remove-apinetlet remove-metalnet remove-dpservice remove-metalbond unprepare ## Remove the ironcore stack

remove-ironcore: kubectl ## Remove the ironcore stack
	$(KUBECTL) delete -k cluster/local/ironcore

remove-ironcore-net: kubectl ## Remove the ironcore stack
	$(KUBECTL) delete -k cluster/local/ironcore-net

remove-apinetlet: kubectl ## Remove the apinetlet stack
	$(KUBECTL) delete -k cluster/local/apinetlet

remove-metalbond: kubectl ## Remove metalbond
	$(KUBECTL) delete -k cluster/local/metalbond

remove-dpservice: kubectl ## Remove dpservice
	$(KUBECTL) delete -k cluster/local/dpservice

remove-metalnet: kubectl ## Remove metalnet
	$(KUBECTL) delete -k cluster/local/metalnet

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
	curl --retry $(CURL_RETRIES) -fsL https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(GOOS)/$(GOARCH)/kubectl -o $(KUBECTL)
	ln -sf "$(KUBECTL)" "$(KUBECTL_BIN)"
	chmod +x "$(KUBECTL_BIN)" "$(KUBECTL)"

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
