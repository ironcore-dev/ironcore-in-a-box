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

kind-cluster:
	$(KIND) create cluster

kind-hugepages:
	$(KIND) create cluster --config kind/kind-config.yaml

network:
	$(KUBECTL) apply -f network/metalbond/metalbond.yaml --context kind-kind
	$(KUBECTL) apply -k network/dpservice --context kind-kind
	$(KUBECTL) apply -k network/metalnet --context kind-kind

network-hugepages:
	$(KUBECTL) apply -f network/metalbond/metalbond.yaml --context kind-kind
	$(KUBECTL) apply -k network/dpservice-hugepages --context kind-kind
	$(KUBECTL) apply -k network/metalnet --context kind-kind

network-examples:
	$(KUBECTL) apply -f network/examples/network.yaml --context kind-kind
	$(KUBECTL) apply -f network/examples/networkinterface.yaml --context kind-kind
	$(KUBECTL) apply -f network/examples/networkinterface2.yaml --context kind-kind

clean:
	$(KIND) delete cluster

prepare: kubectl ## Prepare the environment
	$(KUBECTL) apply -k cluster/local/prepare

install: kustomize kubectl ## Install the ironcore stack
	$(KUBECTL) apply -k cluster/local/ironcore
	$(KUBECTL) apply -k cluster/local/ironcore-net

uninstall: kubectl ## Uninstall the ironcore stack
	$(KUBECTL) delete -k cluster/local/ironcore
	$(KUBECTL) delete -k cluster/local/ironcore-net

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
KUSTOMIZE ?= $(LOCALBIN)/kustomize-$(KUSTOMIZE_VERSION)
KIND ?= $(LOCALBIN)/kind-$(KIND_VERSION)

## Tool Versions
KUSTOMIZE_VERSION ?= v5.3.0
KUBECTL_VERSION ?= v1.32.0
KIND_VERSION ?= v0.27.0

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))

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
