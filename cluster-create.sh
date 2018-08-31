#!/usr/bin/env bash
FILE=k8s-cluster.yml
case "$1" in
-n) NODES_COUNT="$2";;
*) 
	echo 'Number of nodes was not provided(-n). Will be used default value: 1'
	NODES_COUNT=1;;
esac
cat <<EOF > $FILE
---
- name: k8s-master
  box: "k8s-master"
  mem: 3048
  cpu: 1
  ip: 192.168.10.10
EOF
for (( NODE=1; NODE<=$NODES_COUNT; NODE++ )) 
do
	cat <<EOF >> $FILE
- name: k8s-node$NODE
  box: "k8s-node"
  mem: 3048
  cpu: 1
  ip: 192.168.10.1$NODE
EOF
done
