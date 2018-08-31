#!/usr/bin/env bash
swapoff -a
setenforce 0
sed -i --follow-symlinks "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/sysconfig/selinux
modprobe br_netfilter
sysctl -w net.ipv4.ip_forward=1 
sysctl -w net.bridge.bridge-nf-call-iptables=1
yum -y install docker wget conntrack
systemctl enable docker
systemctl start docker
cd /tmp
wget https://github.com/kubernetes/kubernetes/releases/download/v1.11.2/kubernetes.tar.gz
tar xzf kubernetes.tar.gz && rm -f kubernetes.tar.gz
cd kubernetes
yes | ./cluster/get-kube-binaries.sh
rm -rf LICENSES README.md  client
tar xzf server/kubernetes-server-linux-amd64.tar.gz
rm -f kubernetes/kubernetes-src.tar.gz
mv kubernetes /opt
cd /
rm -rf /tmp/kubernetes
cat <<EOF >> /etc/profile
export SERVICE_CLUSTER_IP_RANGE="10.0.0.0/12"
export MASTER_IP="192.168.10.10"
export CLUSTER_NAME="max-k8s"
export PATH="$PATH:/opt/kubernetes/server/bin"
EOF
source /etc/profile
mkdir -p /var/lib/kube-proxy/ /var/lib/kubelet/
#Подсунуть kubeconfig с мастера в:
#cp ~/.kube/config /var/lib/kube-proxy/kubeconfig
#cp ~/.kube/config /var/lib/kubelet/kubeconfig
#А также сертификат client.crt в /srv/kubernetes/client.crt

mkdir -p /etc/kubernetes
cat <<EOT > /etc/kubernetes/kubelet.yml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
authentication:
  x509:
    clientCAFile: /srv/kubernetes/client.crt
clusterDomain: cluster.local
clusterDNS:
  - 10.0.0.10
EOT
cat <<EOT > /etc/kubernetes/kube-proxy.yml 
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.32.0.0/12"
EOT
cat <<EOT > /etc/systemd/system/kubelet.service
[Unit]
Description=Kubelet service
After=docker.service
Requires=docker.service

[Service]
CPUAccounting=true
MemoryAccounting=true
User=root
Group=root
ExecStart=/opt/kubernetes/server/bin/kubelet --kubeconfig=/var/lib/kubelet/kubeconfig --config=/etc/kubernetes/kubelet.yml --network-plugin=cni
Restart=on-failure
KillMode=process

[Install]
WantedBy=multi-user.target
EOT
cat <<EOT > /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://kubernetes.io/docs/concepts/overview/components/#kube-proxy https://kubernetes.io/docs/reference/generated/kube-proxy/
After=network.target

[Service]
ExecStart=/opt/kubernetes/server/bin/kube-proxy --config=/etc/kubernetes/kube-proxy.yml
restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOT
mkdir -p /opt/cni/bin
cd /opt/cni/bin
wget https://github.com/containernetworking/cni/releases/download/v0.6.0/cni-amd64-v0.6.0.tgz
wget https://github.com/containernetworking/plugins/releases/download/v0.7.1/cni-plugins-amd64-v0.7.1.tgz
tar xzf cni-amd64-v0.6.0.tgz
tar xzf cni-plugins-amd64-v0.7.1.tgz
rm -f cni-plugins-amd64-v0.7.1.tgz cni-amd64-v0.6.0.tgz
systemctl enable kubelet kube-proxy
systemctl start kubelet kube-proxy
