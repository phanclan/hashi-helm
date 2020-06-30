#!/bin/bash
set -ex

echo "#==> Create four VMs."
multipass launch --name k3s-master --cpus 1 --mem 1536M --disk 3G || true
multipass launch --name k3s-worker1 --cpus 1 --mem 1G --disk 3G || true
multipass launch --name k3s-worker2 --cpus 1 --mem 1G --disk 3G || true
multipass launch --name k3s-worker3 --cpus 1 --mem 1280M --disk 3G || true

echo "#==> Deploy k3s on the master node"
multipass exec k3s-master -- /bin/bash -c \
  "curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -"
echo "#==> Complete"

sleep 5

echo "#==> Get the IP of the master node"
K3S_NODEIP_MASTER="https://$(multipass info k3s-master | \
  grep "IPv4" | awk -F' ' '{print $2}'):6443"
echo $K3S_NODEIP_MASTER

echo "#==> Get the TOKEN from the master node"
K3S_TOKEN="$(multipass exec k3s-master -- /bin/bash -c \
  "sudo cat /var/lib/rancher/k3s/server/node-token")"
echo $K3S_TOKEN

echo "#==> Deploy k3s on the worker nodes - 3 min"
for i in 1 2 3; do
multipass exec k3s-worker${i} -- /bin/bash -c \
  "curl -sfL https://get.k3s.io | K3S_TOKEN=${K3S_TOKEN} K3S_URL=${K3S_NODEIP_MASTER} sh -"
done
echo "# ==> Complete"

sleep 5

echo
echo "#==> CHECK EVERYTHING"
echo

multipass list
multipass exec k3s-master -- kubectl get nodes

#-------------------------------------------------------------
# Step 4. Configure kubectl
#-------------------------------------------------------------

echo "#==> Copy kubeconfig from VM to host."
multipass exec k3s-master -- sudo cat /etc/rancher/k3s/k3s.yaml \
  > ${HOME}/.kube/k3s.yaml

echo "#==> Point server key to VM external IP."
IP=$(multipass info k3s-master | grep IP | awk '{print $2}')
sed -i '' "s/127.0.0.1/$IP/" ${HOME}/.kube/k3s.yaml

echo "#==> Specify the KUBECONFIG to set the context used by kubectl:"
export KUBECONFIG=${HOME}/.kube/k3s.yaml
alias k="kubectl --kubeconfig=${HOME}/.kube/k3s.yaml"

#-------------------------------------------------------------
# Step 5. Configure cluster node roles and taint
#-------------------------------------------------------------

echo "#==> Configure the node roles:"

#kubectl --kubeconfig=${HOME}/.kube/k3s.yaml label node k3s-master node-role.kubernetes.io/master=""
for i in 1 2 3; do
  kubectl label node k3s-worker${i} node-role.kubernetes.io/node=""
done

# Configure taint NoSchedule for the k3s-master node
kubectl taint node k3s-master node-role.kubernetes.io/master=effect:NoSchedule

echo
echo "#==> Display nodes. Nodes should be labeled with correct roles: master and node"
echo

kubectl get nodes

echo '
Run these two commands:
export KUBECONFIG=${HOME}/.kube/k3s.yaml
alias k="kubectl --kubeconfig=${HOME}/.kube/k3s.yaml"
'