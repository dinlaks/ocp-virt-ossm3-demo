#!/bin/bash

# Define color codes
NC='\033[0m'          # Text Reset
BGreen='\033[1;32m'   # Bright Green
BYellow='\033[1;33m'  # Bright Yellow
BBlue='\033[1;34m'    # Bright Blue

echo -e "${BGreen}This script installs operators from OperatorHub.${NC}"
echo -e "${BGreen}This script will also enable the Kubernetes Gateway API.${NC}" # This may be unnecessary in future OCP versions.

# Apply subscriptions
oc apply -f ./k8/subscriptions.yaml

echo -e "${BYellow}Waiting until all operator pods are ready...${NC}"

# Wait for each operator pod to be in Running state
until oc get pods -n openshift-operators | grep servicemesh-operator3 | grep Running; do 
    echo -e "${BBlue}Waiting for servicemesh-operator3 to be running...${NC}"; 
    sleep 10;
done

until oc get pods -n openshift-operators | grep kiali-operator | grep Running; do 
    echo -e "${BBlue}Waiting for kiali-operator to be running...${NC}"; 
    sleep 10;
done

until oc get pods -n openshift-operators | grep opentelemetry-operator | grep Running; do 
    echo -e "${BBlue}Waiting for opentelemetry-operator to be running...${NC}"; 
    sleep 10;
done

until oc get pods -n openshift-operators | grep tempo-operator | grep Running; do 
    echo -e "${BBlue}Waiting for tempo-operator to be running...${NC}"; 
    sleep 10;
done

echo -e "${BGreen}All operators were installed successfully!${NC}"

# Display the installed operator pods
oc get pods -n openshift-operators

: <<'COMMENT'
# Enable Gateway API (This section is currently disabled)
echo -e "${BYellow}Enabling Gateway API...${NC}"
oc get crd gateways.gateway.networking.k8s.io &> /dev/null || { 
    echo -e "${BBlue}Applying Gateway API Custom Resource Definitions...${NC}";
    oc kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.0.0" | oc apply -f -; 
}
echo -e "${BGreen}Gateway API enabled successfully!${NC}"
COMMENT 