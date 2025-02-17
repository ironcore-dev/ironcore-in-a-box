.PHONY: kind clean network network-examples

kind:
	kind create cluster --config kind/kind-config.yaml

network:
	kubectl apply -f network/metalbond/metalbond.yaml --context kind-kind
	kubectl apply -k network/dpservice --context kind-kind
	kubectl apply -k network/metalnet --context kind-kind

network-hugepages:
	kubectl apply -f network/metalbond/metalbond.yaml --context kind-kind
	kubectl apply -k network/dpservice-hugepages --context kind-kind
	kubectl apply -k network/metalnet --context kind-kind

network-examples:
	kubectl apply -f network/examples/network.yaml --context kind-kind
	kubectl apply -f network/examples/networkinterface.yaml --context kind-kind
	kubectl apply -f network/examples/networkinterface2.yaml --context kind-kind

clean:
	kind delete cluster
