#!/bin/bash

set -e
shopt -s expand_aliases

alias k='kubectl'

mkdir -p ./tmpcfg

echo "#==> Create Chart Custom Values - Consul"
tee ./tmpcfg/helm-consul-values.yaml <<EOF
# Choose an optional name for the datacenter
global:
  datacenter: dc1

client:
  enabled: true

# Use only one Consul server for local development
server:
  replicas: 3 # 1 for dev. 3 is default
  bootstrapExpect: 3 # Should <= replicas count
  disruptionBudget:
    maxUnavailable: 0

# Enable Connect for secure communication between nodes
connectInject:
  enabled: true

# Enable the Consul Web UI. Optionally enable NodePort
ui:
  # service:
  #   type: 'NodePort'
  enabled: true
EOF

echo "#==> Install Helm Chart - Consul"
helm install -f ./tmpcfg/helm-consul-values.yaml dc1 \
  https://github.com/hashicorp/consul-helm/archive/master.tar.gz || true

echo
echo "#--- Complete"

read -p "Press enter to continue"

echo "#==> Create Chart Custom Values - Vault"
tee ./tmpcfg/helm-vault-values.yaml <<EOF
server:
  image:
    repository: "hashicorp/vault-enterprise"
    tag: "1.4.0_ent"
  ha:
    enabled: true
    replicas: 3
EOF

echo "#==> Install Helm Chart - Vault"
helm install -f ./tmpcfg/helm-vault-values.yaml vault \
  https://github.com/hashicorp/vault-helm/archive/master.tar.gz || true

echo "
helm upgrade -f ./tmpcfg/helm-vault-values.yaml vault \
  --set server.dev.enabled=true \
  https://github.com/hashicorp/vault-helm/archive/master.tar.gz
"

echo "#==> Create Ingress - Vault"
tee ./tmpcfg/vault-ingress.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: vault-ingress
spec:
  rules:
  - host: vault.hashi.local
    http:
      paths:
      - path: /
        backend:
          serviceName: vault
          servicePort: 8200
EOF

read -p "Press enter to continue"

echo "#==> Apply Ingress - Vault"
k apply -f ./tmpcfg/vault-ingress.yaml


echo #==> Create Ingress - Consul
tee ./tmpcfg/consul-ingress.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: consul-ingress
spec:
  rules:
  - host: consul.hashi.local
    http:
      paths:
      - path: /
        backend:
          serviceName: dc1-consul-ui
          servicePort: 80
EOF

k apply -f ./tmpcfg/consul-ingress.yaml


read -p "Press enter to end"
