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

echo "${BGreen}This script set up the whole ossm3.0 control plane setup.${NC}"

echo "${BYellow}Installing Minio for Tempo${NC}"
oc new-project tracing-system
oc apply -f ./k8/TempoOtel/minio.yaml -n tracing-system
echo "${BYellow}Waiting for Minio to become available...${NC}"
oc wait --for condition=Available deployment/minio --timeout 150s -n tracing-system

echo "${BYellow}Installing TempoCR${NC}"
oc apply -f ./k8/TempoOtel/tempo.yaml -n tracing-system
echo "${BYellow}Waiting for TempoStack to become ready...${NC}"
oc wait --for condition=Ready TempoStack/sample --timeout 150s -n tracing-system
echo "${BYellow}Waiting for Tempo deployment to become available...${NC}"
oc wait --for condition=Available deployment/tempo-sample-compactor --timeout 150s -n tracing-system

echo "${BYellow}Exposing Jaeger UI route (will be used in kiali ui)${NC}"
oc expose svc tempo-sample-query-frontend --port=jaeger-ui --name=tracing-ui -n tracing-system

echo "${BYellow}Installing OpenTelemetryCollector...${NC}"
oc new-project opentelemetrycollector
oc apply -f ./k8/TempoOtel/opentelemetrycollector.yaml -n opentelemetrycollector
echo "${BYellow}Waiting for OpenTelemetryCollector deployment to become available..."
oc wait --for condition=Available deployment/otel-collector --timeout 60s -n opentelemetrycollector

echo "${BYellow}Installing ossm3.0...${NC}"
oc new-project istio-system
echo "${BYellow}Installing IstioCR...${NC}"
oc apply -f ./k8/ossm3.0/istiocr.yaml  -n istio-system
echo "${BYellow}Waiting for istio to become ready...${NC}"
oc wait --for condition=Ready istio/default --timeout 60s  -n istio-system

echo "${BYellow}Installing Telemetry resource...${NC}"
oc apply -f ./k8/TempoOtel/istioTelemetry.yaml  -n istio-system
echo "${BYellow}Adding OTEL namespace as a part of the mesh${NC}"
oc label namespace opentelemetrycollector istio-injection=enabled

echo "${BYellow}Installing IstioCNI...${NC}"
oc new-project istio-cni
oc apply -f ./k8/ossm3.0/istioCni.yaml -n istio-cni
echo "${BYellow}Waiting for istiocni to become ready...${NC}"
oc wait --for condition=Ready istiocni/default --timeout 60s -n istio-cni

echo "${BYellow}Creating ingress gateway via Gateway API...${NC}"
oc new-project istio-ingress
echo "${BYellow}Adding istio-ingress namespace as a part of the mesh${NC}"
oc label namespace istio-ingress istio-injection=enabled
oc apply -k ./k8/gateway

echo "${BYellow}Creating ingress gateway via Istio Deployment...${NC}"
#oc new-project istio-ingress
#echo "Adding istio-ingress namespace as a part of the mesh"
#oc label namespace istio-ingress istio-injection=enabled
oc apply -f ./k8/ossm3.0/istioIngressGateway.yaml  -n istio-ingress
echo "${BYellow}Waiting for deployment/istio-ingressgateway to become available...${NC}"
oc wait --for condition=Available deployment/istio-ingressgateway --timeout 60s -n istio-ingress
echo "${BYellow}Exposing Istio ingress route${NC}"
oc expose svc istio-ingressgateway --port=http2 --name=istio-ingressgateway -n istio-ingress

echo "${BYellow}Enabling user workload monitoring in OCP${NC}"
oc apply -f ./k8/Monitoring/ocpUserMonitoring.yaml
echo "${BYellow}Enabling service monitor in istio-system namespace${NC}"
oc apply -f ./k8/Monitoring/serviceMonitor.yaml -n istio-system
echo "${BYellow}Enabling pod monitor in istio-system namespace${NC}"
oc apply -f ./k8/Monitoring/podMonitor.yaml -n istio-system
echo "${BYellow}Enabling pod monitor in istio-ingress namespace${NC}"
oc apply -f ./k8/Monitoring/podMonitor.yaml -n istio-ingress

echo "${BYellow}Installing Kiali...${NC}"
oc project istio-system
echo "${BYellow}Creating cluster role binding for kiali to read ocp monitoring${NC}"
oc apply -f ./k8/Kiali/kialiCrb.yaml -n istio-system
echo "${BYellow}Installing KialiCR...${NC}"
export TRACING_INGRESS_ROUTE="http://$(oc get -n tracing-system route tracing-ui -o jsonpath='{.spec.host}')"
cat ./k8/Kiali/kialiCr.yaml | JAEGERROUTE="${TRACING_INGRESS_ROUTE}" envsubst | oc -n istio-system apply -f - 
echo "${BYellow}Waiting for kiali to become ready...${NC}"
oc wait --for condition=Successful kiali/kiali --timeout 150s -n istio-system 
oc annotate route kiali haproxy.router.openshift.io/timeout=60s -n istio-system 

echo "${BYellow}Install Kiali OSSM Console plugin...${NC}"
oc apply -f ./k8/Kiali/kialiOssmcCr.yaml -n istio-system

