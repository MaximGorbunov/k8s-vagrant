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
mkdir -p /etc/k8s-certs
cd /etc/k8s-certs
cat <<EOF > csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = RU
ST = UDMURTIA
L = IZHEVSK
O = EPAM
OU = EPAM-IZHEVSK
CN = 192.168.10.10

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster
DNS.5 = kubernetes.default.svc.cluster.local
IP.1 = 192.168.10.10
IP.2 = 10.0.0.1

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=${MASTER_IP}" -days 10000 -out ca.crt
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -config csr.conf
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 10000 -extensions v3_ext -extfile csr.conf
openssl genrsa -out client.key 2048
openssl req -new -key client.key -out client.csr -subj "/CN=admin/O=system:masters"
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days 500
openssl genrsa -des3 -passout pass:x -out dashboard.pass.key 2048
openssl rsa -passin pass:x -in dashboard.pass.key -out dashboard.key
rm -f  dashboard.pass.key
openssl req -new -key dashboard.key -out dashboard.csr -subj "/CN=kubernetes-dashboard"
mkdir -p /srv/kubernetes
cp ca.crt server.crt server.key client.crt client.key dashboard.csr  dashboard.key /srv/kubernetes
mkdir -p /var/lib/kube-apiserver/
echo "kMIBI0BoGrollnTQin8lycXQHVLTBCaH,admin,admin,system:masters" >> /var/lib/kube-apiserver/known_tokens.csv
cp /var/lib/kube-apiserver/known_tokens.csv /srv/kubernetes/known_tokens.csv
kubectl config set-cluster $CLUSTER_NAME --certificate-authority=/srv/kubernetes/ca.crt --embed-certs=true --server=https://$MASTER_IP
kubectl config set-credentials admin --client-certificate=/srv/kubernetes/client.crt --client-key=/srv/kubernetes/client.key --embed-certs=true --token=kMIBI0BoGrollnTQin8lycXQHVLTBCaH
kubectl config set-context default --cluster=$CLUSTER_NAME --user=admin
kubectl config use-context default
mkdir -p /var/lib/kube-proxy/ /var/lib/kubelet/
cp ~/.kube/config /var/lib/kube-proxy/kubeconfig
cp ~/.kube/config /var/lib/kubelet/kubeconfig
mkdir -p /etc/kubernetes/manifests
cd /etc/kubernetes/manifests
cat <<EOT > api.json
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "kube-apiserver"
  },
  "spec": {
    "hostNetwork": true,
    "containers": [
      {
        "name": "kube-apiserver",
        "image": "k8s.gcr.io/hyperkube:v1.11.2",
        "command": [
          "/hyperkube",
          "apiserver",
          "--address=127.0.0.1",
          "--allow-privileged=true",
          "--secure-port=443",
          "--authorization-mode=RBAC",
		  "--advertise-address=192.168.10.10",
          "--service-cluster-ip-range=10.0.0.0/12",
          "--etcd-servers=http://127.0.0.1:4001",
          "--tls-cert-file=/srv/kubernetes/server.crt",
          "--tls-private-key-file=/srv/kubernetes/server.key", "--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota",
          "--client-ca-file=/srv/kubernetes/ca.crt",
          "--kubelet-client-certificate=/srv/kubernetes/client.crt",
          "--kubelet-client-key=/srv/kubernetes/client.key",
          "--service-account-key-file=/srv/kubernetes/server.key",
          "--token-auth-file=/srv/kubernetes/known_tokens.csv"
        ],
        "ports": [
          {
            "name": "https",
            "hostPort": 443,
            "containerPort": 443
          },
          {
            "name": "local",
            "hostPort": 8080,
            "containerPort": 8080
          }
        ],
        "volumeMounts": [
          {
            "name": "srvkube",
            "mountPath": "/srv/kubernetes",
            "readOnly": true
          },
          {
            "name": "etcssl",
            "mountPath": "/etc/ssl",
            "readOnly": true
          }
        ],
        "livenessProbe": {
          "httpGet": {
            "scheme": "HTTP",
            "host": "127.0.0.1",
            "port": 8080,
            "path": "/healthz"
          },
          "initialDelaySeconds": 15,
          "timeoutSeconds": 15
        }
      }
    ],
    "volumes": [
      {
        "name": "srvkube",
        "hostPath": {
          "path": "/srv/kubernetes"
        }
      },
      {
        "name": "etcssl",
        "hostPath": {
          "path": "/etc/ssl"
        }
      }
    ]
  }
}
EOT
cat <<EOT > controller.json 
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "kube-controller-manager"
  },
  "spec": {
    "hostNetwork": true,
    "containers": [
      {
        "name": "kube-controller-manager",
        "image": "k8s.gcr.io/hyperkube:v1.11.2",
        "command": [
          "/hyperkube",
          "controller-manager",
          "--root-ca-file=/srv/kubernetes/ca.crt",
          "--service-account-private-key-file=/srv/kubernetes/server.key",
          "--master=127.0.0.1:8080"
        ],
        "volumeMounts": [
          {
            "name": "srvkube",
            "mountPath": "/srv/kubernetes",
            "readOnly": true
          },
          {
            "name": "etcssl",
            "mountPath": "/etc/ssl",
            "readOnly": true
          }
        ],
        "livenessProbe": {
          "httpGet": {
            "scheme": "HTTP",
            "host": "127.0.0.1",
            "port": 10252,
            "path": "/healthz"
          },
          "initialDelaySeconds": 15,
          "timeoutSeconds": 15
        }
      }
    ],
    "volumes": [
      {
        "name": "srvkube",
        "hostPath": {
          "path": "/srv/kubernetes"
        }
      },
      {
        "name": "etcssl",
        "hostPath": {
          "path": "/etc/ssl"
        }
      }
    ]
  }
}
EOT
cat <<EOT > etcd.yml 
apiVersion: v1
kind: Pod
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - command:
    - etcd
    - --data-dir=/var/lib/etcd
    - --listen-client-urls=http://127.0.0.1:4001
    - --advertise-client-urls=http://127.0.0.1:4001
    image: gcr.io/google_containers/etcd-amd64:3.1.11
    name: etcd
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd
  hostNetwork: true
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd
EOT
cat <<EOT > scheduler.json 
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "kube-scheduler"
  },
  "spec": {
    "hostNetwork": true,
    "containers": [
      {
        "name": "kube-scheduler",
        "image": "k8s.gcr.io/hyperkube:v1.11.2",
        "command": [
          "/hyperkube",
          "scheduler",
          "--master=127.0.0.1:8080"
        ],
        "livenessProbe": {
          "httpGet": {
            "scheme": "HTTP",
            "host": "127.0.0.1",
            "port": 10251,
            "path": "/healthz"
          },
          "initialDelaySeconds": 15,
          "timeoutSeconds": 15
        }
      }
    ]
  }
} 
EOT
cat <<EOT > /etc/kubernetes/kubelet.yml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
staticPodPath: /etc/kubernetes/manifests
cgroupDriver: systemd
authentication:
  x509:
    clientCAFile: /srv/kubernetes/client.crt
clusterDomain: cluster.local
clusterDNS:
  - 10.0.0.10
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
cat <<EOT > /etc/kubernetes/kube-proxy.yml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.32.0.0/12"
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
sleep 50
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
kubectl create secret generic kubernetes-dashboard-certs --from-file=/srv/kubernetes -n kube-system
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
