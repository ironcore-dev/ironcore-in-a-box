# ironcore-in-a-box

# Deploying ironcore network layer on a Kind Cluster

This repository includes a Makefile that simplifies the process of setting up a local Kubernetes cluster using [Kind](https://kind.sigs.k8s.io/) and deploying various network configurations.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Kind**: Refer to the [Kind installation guide](https://kind.sigs.k8s.io/docs/user/quick-start/)
- **kubectl**: Check out the [kubectl installation instructions](https://kubernetes.io/docs/tasks/tools/)
- (Optional) A Kubernetes context named `kind-kind` should be available in your configuration.
- **/dev mount**: Ensure that `/dev` is mounted and accessible on the host where kind cluster is running. This is used by qemu and libvirt to create interim tap device nodes.
  

## Example Workflow

1. **Create the Cluster**  
   Set up the Kind cluster using:
   ```sh
   make kind-cluster
   ```

2. **Deploy Network Components**  
   Apply the dpservice, metalnet and metalbond configurations:
   ```sh
   make network
   ```

3. **Deploy Network Examples**  
   Apply example network configurations (Example metalnet Network and NetworkInterface instances) :
   ```sh
   make network-examples
   ```

4. **Verify the Deployment**  
   Ensure that the network resources are active:
   ```sh
   kubectl get networkinterfaces --context kind-kind -A
   kubectl get networks --context kind-kind -A
   ```

5. **Clean Up the Cluster**  
   Remove the Kind cluster when finished:
   ```sh
   make kind-clean
   ```

## Verifying the Deployment

After running the `network-examples` target, verify that the network resources have been deployed correctly by executing:

```sh
kubectl get networkinterfaces --context kind-kind -A
kubectl get networks --context kind-kind -A
```

If your context name differs, substitute `kind-kind` with the appropriate name.


