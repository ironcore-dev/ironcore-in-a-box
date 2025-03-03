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
	$(KIND) create cluster --image kindest/node:v1.32.0 --config kind/kind-config.yaml

customize-network: metalbond metalbond-client dpservice metalnet ## Customize the network on the kind nodes
	$(KIND) get nodes | xargs -I {} docker exec {} bash -c "\
		timeout 30s bash -c 'until ip link show dtap0 up >/dev/null 2>&1; do sleep 0.5; done' && \
		ip link show dtap0 up >/dev/null 2>&1 || { echo \"dtap0 not up after 30s\"; exit 1; } && \
		ip link add overlay-tun type ip6tnl mode any external ttl 32 && \
		ip link set mtu 1500 dev overlay-tun && \
		ip addr add 2001:db8:dead:beef::1/128 dev overlay-tun && \
		ip link set overlay-tun up && \
		sysctl -w net.ipv6.conf.all.forwarding=1 && \
		sysctl -w net.ipv4.conf.eth0.rp_filter=0 && \
		sysctl -w net.ipv4.ip_forward=1 && \
		sysctl -w net.ipv4.conf.overlay-tun.rp_filter=0 && \
		iptables -t mangle -I PREROUTING 1 -i overlay-tun -j MARK --set-mark 1 && \
		echo '100 ironcore_eth0' >> /etc/iproute2/rt_tables && \
		ip route add default via 172.18.0.1 dev eth0 table 100 && \
		ip rule add fwmark 1 lookup 100 && \
		for i in {1..3}; do \
			ip -6 route add 2001:db8:fefe::/48 via fe80::1 dev dtap0 && \
			break || \
			{ echo \"Retrying route addition in 1s...\"; sleep 1; }; done && \
		ip -6 neigh add fe80::1 lladdr 22:22:22:22:22:00 dev dtap0 nud permanent"

install-libvirtd: kind ## Install libvirtd on the kind nodes
	$(KIND) get nodes | xargs -I {} docker exec {} bash -c "\
		sed -i 's/UID_MAX.*/UID_MAX 65536/' /etc/login.defs && \
		sed -i 's/#SYS_UID_MAX.*/SYS_UID_MAX 65536/' /etc/login.defs && \
		sed -i 's/SUB_UID_MIN.*/SUB_UID_MIN 1/' /etc/login.defs && \
		sed -i 's/SUB_UID_COUNT.*/SUB_UID_COUNT 100/' /etc/login.defs && \
		sed -i 's/SYS_UID_MAX.*/SYS_UID_MAX 65536/' /etc/login.defs && \
		sed -i '/exit 101/d' /usr/sbin/policy-rc.d && \
		apt-get update && \
		apt-get install -y libvirt-daemon libvirt-clients qemu-kvm libvirt-daemon-system virtinst ceph-common && \
		systemctl restart libvirtd && \
		systemctl restart virtlogd.service && \
		systemctl restart virtlockd.service "

delete: ## Delete the kind cluster
	$(KIND) delete cluster

## Install components
up: prepare ironcore ironcore-net apinetlet customize-network metalnetlet libvirt-provider ## Bring up the ironcore stack

prepare: kubectl cmctl ## Prepare the environment
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


libvirt-provider: kubectl install-libvirtd ## Install the libvirt-provider
	$(KUBECTL) apply -k cluster/local/libvirt-provider

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
