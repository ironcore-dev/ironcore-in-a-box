FROM kindest/node:v1.32.0

# Configure the system
RUN sed -i 's/UID_MAX.*/UID_MAX 65536/' /etc/login.defs && \
    sed -i 's/#SYS_UID_MAX.*/SYS_UID_MAX 65536/' /etc/login.defs && \
    sed -i 's/SUB_UID_MIN.*/SUB_UID_MIN 1/' /etc/login.defs && \
    sed -i 's/SUB_UID_COUNT.*/SUB_UID_COUNT 100/' /etc/login.defs && \
    sed -i 's/SYS_UID_MAX.*/SYS_UID_MAX 65536/' /etc/login.defs && \
    sed -i '/exit 101/d' /usr/sbin/policy-rc.d

# Install libvirt and qemu-kvm
RUN apt-get update && \
    apt-get install -y libvirt-daemon libvirt-clients qemu-kvm libvirt-daemon-system virtinst ceph-common && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
