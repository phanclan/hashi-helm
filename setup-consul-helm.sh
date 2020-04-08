#!/bin/bash

set -e
shopt -s expand_aliases

alias k='kubectl'

mkdir -p ./tmpcfg

echo "#==> Create Chart Custom Values - Consul"
tee ./tmpcfg/helm-consul-values.yaml <<EOF
global:
  datacenter: dc1

client:
  enabled: true

server:
  replicas: 1
  bootstrapExpect: 1
  disruptionBudget:
    maxUnavailable: 0

ui:
  # service:
  #   type: 'NodePort'
  enabled: true
EOF

echo "#==> Install Helm Chart - Consul"
helm install -f ./tmpcfg/helm-consul-values.yaml dc1 ./consul-helm || true

read

echo "#==> Install Helm Chart - Vault"
helm install vault \
  --set server.dev.enabled=true \
  https://github.com/hashicorp/vault-helm/archive/master.tar.gz || true


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

read

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
