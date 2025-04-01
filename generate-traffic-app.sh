#!/bin/bash

# Get the Istio Ingress Gateway hostname
export GATEWAY=$(oc get route istio-ingressgateway -n istio-ingress -o template --template '{{ .spec.host }}')

# Print the gateway URL
echo "Gateway URL: $GATEWAY"

# Check if GATEWAY is retrieved correctly
if [[ -z "$GATEWAY" ]]; then
  echo "Error: Could not retrieve the Istio Ingress Gateway URL."
  exit 1
fi

# Perform initial curl requests
echo "Call the front-end service (the container based deployment)"
echo "" 
echo "Testing /web/hello..."
curl -s $GATEWAY/web/hello && echo ""
echo ""
echo "Call the back-end service via the front-end"  
echo ""
echo "Testing /web/hello-service..."
curl -s $GATEWAY/web/hello-service && echo ""

# Infinite loop to continuously curl /web/hello-service every second
echo "Starting continuous curl requests to back-end service VM via the front-end /web/hello-service..."
while true; do
  curl -s $GATEWAY/web/hello-service
  echo ""
  sleep 1
done
