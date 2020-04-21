#!/bin/bash

set -e
shopt -s expand_aliases

alias k='kubectl'

echo "#==> Deploy counting service and serviceaccount"
tee ./tmpcfg/counting.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: counting
---
apiVersion: v1
kind: Pod
metadata:
  name: counting
  annotations:
    "consul.hashicorp.com/connect-inject": "true"
spec:
  containers:
  - name: counting
    image: hashicorp/counting-service:0.0.2
    ports:
    - containerPort: 9001
      name: http
  serviceAccountName: counting
EOF

kubectl apply -f ./tmpcfg/counting.yaml

echo "#==> Deploy dashboard service and serviceaccount"
tee ./tmpcfg/dashboard.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard
---
apiVersion: v1
kind: Pod
metadata:
  name: dashboard
  labels:
    app: 'dashboard'
  annotations:
    "consul.hashicorp.com/connect-inject": "true"
    "consul.hashicorp.com/connect-service-upstreams": "counting:9001"
spec:
  containers:
  - name: dashboard
    image: hashicorp/dashboard-service:0.0.4
    ports:
    - containerPort: 9002
      name: http
    env:
    - name: COUNTING_SERVICE_URL
      value: "http://localhost:9001"
  serviceAccountName: dashboard
---
apiVersion: 'v1'
kind: 'Service'
metadata:
  name: 'dashboard-service-load-balancer'
  namespace: 'default'
  labels:
    app: 'dashboard'
spec:
  ports:
    - protocol: 'TCP'
      port: 80
      targetPort: 9002
  selector:
    app: 'dashboard'
  type: 'LoadBalancer'
  loadBalancerIP: ''
EOF

kubectl apply -f ./tmpcfg/dashboard.yaml

echo "#==> Create Ingress - Counting Dashboard"
tee ./tmpcfg/dashboard-ingress.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: dashboard-ingress
spec:
  rules:
  - host: dashboard.hashi.local
    http:
      paths:
      - path: /
        backend:
          serviceName: dashboard-service-load-balancer
          servicePort: 80
EOF

k apply -f ./tmpcfg/dashboard-ingress.yaml


tee -a ./tmpcfg/helm-consul-values.yaml <<EOF
syncCatalog:
  enabled: true
EOF

echo "#==> Upgrade Helm Chart - Consul"
helm upgrade -f ./tmpcfg/helm-consul-values.yaml dc1 \
  https://github.com/hashicorp/consul-helm/archive/master.tar.gz || true



# CLEAN UP

k delete po counting dashboard
k delete -f ./tmpcfg/dashboard-ingress.yaml
kubectl delete -f ./tmpcfg/counting.yaml
kubectl delete -f ./tmpcfg/dashboard.yaml
k delete svc counting dashboard counting-sidecar-proxy dashboard-sidecar-proxy

echo #==> Manually delete pvc and pv
k get pvc
k get pv
