#!/bin/bash

RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\e[32m'
BLINK='\e[5m'

cd /work/mycluster/mke

# Create a Service Account for MKE:
dcos security org service-accounts keypair mke-priv.pem mke-pub.pem
dcos security org service-accounts create -p mke-pub.pem -d 'Kubernetes service account' kubernetes
dcos security secrets create-sa-secret mke-priv.pem kubernetes kubernetes/sa

# Mesosphere Kubernetes Engine permissions:
dcos security org users grant kubernetes dcos:mesos:master:reservation:role:kubernetes-role create
dcos security org users grant kubernetes dcos:mesos:master:reservation:principal:kubernetes delete
dcos security org users grant kubernetes dcos:mesos:master:framework:role:kubernetes-role create
dcos security org users grant kubernetes dcos:mesos:master:task:user:nobody create

# Install MKE:
dcos package install --yes kubernetes --options=mke-options.json

Is_MKE_Ready1=`dcos marathon app list | grep "^/kubernetes"|awk '{print$7}'`
Is_MKE_Ready2=`dcos marathon app show /kubernetes | jq '.tasksHealthy'`

while :

do
	Is_MKE_Ready1=`dcos marathon app list | grep "^/kubernetes"|awk '{print$7}'`
	Is_MKE_Ready2=`dcos marathon app show /kubernetes | jq '.tasksHealthy'`

        if [[ -z "$Is_MKE_Ready1" || "$Is_MKE_Ready1" == "True" ]]
               then
                    printf "${GREEN}MKE is being${NC} ${BLINK}installed, please wait ...${NC}\n"
                    sleep 10
	elif [[ $Is_MKE_Ready2 -eq "1" ]]
		then
	     		sleep 20
			echo "MKE should be ready now, let's install Kubernetes-cluster1 now"
                	break
        fi
done

cd /work/mycluster/k8sdcos

# Create K8s Service Account:
dcos security org service-accounts keypair kube1-priv.pem kube1-pub.pem
dcos security org service-accounts create -p kube1-pub.pem -d 'Service account for kubernetes-cluster1' kubernetes-cluster1
dcos security secrets create-sa-secret kube1-priv.pem kubernetes-cluster1 kubernetes-cluster1/sa

# Set permissions for the K8s Service Account:
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:framework:role:kubernetes-cluster1-role create
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:task:user:root create
dcos security org users grant kubernetes-cluster1 dcos:mesos:agent:task:user:root create
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:reservation:role:kubernetes-cluster1-role create
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:reservation:principal:kubernetes-cluster1 delete
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:volume:role:kubernetes-cluster1-role create
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:volume:principal:kubernetes-cluster1 delete
dcos security org users grant kubernetes-cluster1 dcos:secrets:default:/kubernetes-cluster1/* full
dcos security org users grant kubernetes-cluster1 dcos:secrets:list:default:/kubernetes-cluster1 read
dcos security org users grant kubernetes-cluster1 dcos:adminrouter:ops:ca:rw full
dcos security org users grant kubernetes-cluster1 dcos:adminrouter:ops:ca:ro full
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:framework:role:slave_public/kubernetes-cluster1-role create
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:framework:role:slave_public/kubernetes-cluster1-role read
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:reservation:role:slave_public/kubernetes-cluster1-role create
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:volume:role:slave_public/kubernetes-cluster1-role create
dcos security org users grant kubernetes-cluster1 dcos:mesos:master:framework:role:slave_public read
dcos security org users grant kubernetes-cluster1 dcos:mesos:agent:framework:role:slave_public read

# Install K8S in DC/OS:
dcos kubernetes cluster create --options=kubernetes1-options.json --yes

echo -e "Cluster is deploying. Please run the following command to monitor its progress:\ndcos kubernetes cluster debug plan status deploy --cluster-name=kubernetes-cluster1"


printf "${RED}Monitoring Kubernetes deployment until complete ... ${NC}\n"
seconds=0

until [[ $(dcos kubernetes cluster debug plan status deploy --cluster-name=kubernetes-cluster1 | grep -vi 'Using Kubernetes cluster' | head -n 1) == "deploy (serial strategy) (COMPLETE)" ]]; 
do
  seconds=$((seconds+30))
  printf "${GREEN}You have been waiting %s seconds for this Kubernetes deployment to complete. Please allow at least 400s for completion.${NC}\n" "$seconds" 
  printf "${RED}PHASE${NC}             ${RED}STATUS${NC}\n" && dcos kubernetes cluster debug plan status deploy --cluster-name=kubernetes-cluster1 --json | grep -vi 'Using Kubernetes cluster' | jq -r '"\(.phases[] | .name + " " + .status)"' | column -t
  sleep 30
done
printf "${RED}Kubernetes deployment completed ${NC}"
