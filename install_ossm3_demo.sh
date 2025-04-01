#!/bin/bash

NC='\033[0m'          # Text Reset
BGreen='\033[1;32m'   # Green
BYellow='\033[1;33m'  # Yellow
#BBlack='\033[1;30m'  # Black
#BRed='\033[1;31m'    # Red
BBlue='\033[1;34m'    # Blue
#BPurple='\033[1;35m' # Purple
#BCyan='\033[1;36m'   # Cyan
#BWhite='\033[1;37m'  # White

echo "${BGreen}This script set up the simple VM and container with ossm3 demo.${NC}"

echo "${BYellow}Installing demo-vm-ossm3...${NC}"
oc new-project demo-vm-ossm3
echo "${BYellow}Adding demo-vm-ossm3 namespace as a part of the mesh${NC}"
oc label namespace demo-vm-ossm3 istio-injection=enabled
echo "${BYellow}Enabling pod monitor in demo-vm-ossm3 namespace${NC}"
oc apply -f ./k8/Monitoring/podMonitor.yaml -n demo-vm-ossm3
echo "${BYellow}applying demo-gateway for VM and containers in demo-vm-ossm3 namespace${NC}"
oc apply -f ./k8/Bookinfo/demo-vm-gateway.yaml -n demo-vm-ossm3
echo "${BYellow}Installing VM and Container in a OSSM3 demo${NC}"
oc apply -f ./k8/deployments/vm/vm-template-vm1.yaml -n demo-vm-ossm3
oc apply -f ./k8/deployments/vm/vm-template-vm2.yaml -n demo-vm-ossm3
oc apply -f ./k8/deployments/vm/service.yaml -n demo-vm-ossm3
oc apply -f ./k8/deployments/vm/virtual-service.yaml -n demo-vm-ossm3
oc apply -f ./k8/deployments/container/deployment.yaml -n demo-vm-ossm3
oc apply -f ./k8/deployments/container/service.yaml -n demo-vm-ossm3
oc apply -f ./k8/deployments/container/virtual-service.yaml -n demo-vm-ossm3
oc apply -f ./k8/deployments/container/destinate-rule.yaml -n demo-vm-ossm3
echo "${BYellow}Waiting for demo pods and services to become ready...${NC}"
oc wait --for=condition=Ready pods --all -n demo-vm-ossm3 --timeout 60s
oc wait --for=condition=Ready svc --all -n demo-vm-ossm3 --timeout 60s

echo "${BYellow}Installation finished!${NC}"
echo "${BYellow}NOTE: Kiali will show metrics of demo-vm-ossm3 app right after pod monitor will be ready. You can check it in OCP console Observe->Metrics${NC}" 