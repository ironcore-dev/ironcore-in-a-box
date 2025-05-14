# Podman user guidance

## MacOS

The limitation mentioned above, for docker, still applies.
This was tested and applies to podman 5.4 and podman machine running Fedora CoreOS 41.
Running everything with podman requires that the podman machine runs in rootful mode; more details below.

```bash
NAME="Fedora Linux"
VERSION="41.20250215.3.0 (CoreOS)"
RELEASE_TYPE=stable
ID=fedora
VERSION_ID=41
VERSION_CODENAME=""
PLATFORM_ID="platform:f41"
PRETTY_NAME="Fedora CoreOS 41.20250215.3.0"
```

```bash
# we assume no other machines might be running, shutting down the default one
podman machine stop

# we create a new podman machine
# 2-4GiB of memory are unfortunately not enough
# must be rootful
podman machine init --cpus 8 --memory 8192 --rootful ironcore-in-a-box
podman machine start ironcore-in-a-box

# change the default system connection
podman system connection default ironcore-in-a-box-root

# the dp-service requires some extra kernel modules
podman machine ssh ironcore-in-a-box "sudo rpm-ostree install kernel-modules-extra"

# this kernel modules installation requires a restart of the VM
podman machine stop ironcore-in-a-box
podman machine start ironcore-in-a-box

# removing the sch_multiq kernel module from the blacklist
podman machine ssh ironcore-in-a-box grep -rle \"^blacklist sch_multiq\" /etc/modprobe.d/ \| xargs -r sudo sed -i \'s/blacklist sch_multiq/#blacklist sch_multiq/\'
```
