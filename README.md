# ocp-virt-ossm3.0-demo


## Simple demo showing VM and containers in a Service Mesh

This demo shows a scenario where a container based deployment and VM based deployment are configured 
together in the same namespace and utilizing OpenShift Service Mesh (OSSM).  
  
There are a couple helper scripts to generate load, so that it can be observed in Service Mesh via Kiali.


```
   +-----------+       +----------------+       +-----------------------+       +-------------+  
   | API Caller | ---> | Ingress Gateway | ---> | Front-end Deployment  | --->  |  Back-end VM|  
   +-----------+       +----------------+       +-----------------------+       +-------------+  
         |                        |                        |                       |  
         |<-----------------------|<-----------------------|<----------------------|  
          (5) Response from       (4) Response from       (3) Call to VM          (2) Call to Front-end  
              Front-end to            VM to Front-end         from Front-end        from Ingress Gateway  
              API Caller  

(1) API Caller makes a call to the Ingress Gateway.
(2) The Ingress Gateway routes the call to the Front-end Deployment.
(3) The Front-end Deployment makes a call to the Back-end VM.
(4) The Back-end VM sends a response back to the Front-end Deployment.
(5) The Front-end Deployment sends the response from the Back-end VM to the API Caller.
```

### Install ossm3 operators and dependencies
*(Assumes the OpenShift Virtualization operator has already been installed and is up and running)*  

To install Red Hat OpenShift Service Mesh, you must install the Red Hat OpenShift Service Mesh 3.0 Operator. Repeat the procedure for each additional Operator you want to install. 

Additional Operators include:

- Kiali Operator provided by Red Hat

- Red Hat Build of OpenTelemetry 

- Tempo Operator
 
(Note: *Red Hat OpenShift distributed tracing* will need to be replaced with the *Tempo Operator* down the road)

You can install operatos using Openshift console UI, as described, or run the helper scripts in order to save some time:

```
sh install_operators.sh
```


### Create Service Mesh control plane

You can run the below instructions manually, as described, or run the helper scripts in order
to save some copy/paste time:

verify one script completes before running the next one in order.

TODO: add waiting until success capability in scripts

```
sh install_ossm3_control.sh
```


### Set up ossm3.0

```bash
oc new-project istio-system
```
First, install Istio custom resource
> **_NOTE:_**  In this example, the `.spec.version` is missing so the istio version is automatically set by OSSM operator. You can specify the version manually, but it must be one that is supported by the operator; otherwise, a validation error will occur.
```bash
oc apply -f ./k8/ossm3.0/istiocr.yaml  -n istio-system
oc wait --for condition=Ready istio/default --timeout 60s  -n istio-system
```

Then, install IstioCNI
> **_NOTE:_**  In this example, the `.spec.version` is missing so the istio version is automatically set by OSSM operator. the `.spec.version` is missing so the istio version is automatically set by OSSM operator. You can specify the version manually, but it must be one that is supported by the operator.
```bash
oc new-project istio-cni
oc apply -f ./k8/ossm3.0/istioCni.yaml -n istio-cni
oc wait --for condition=Ready istiocni/default --timeout 60s -n istio-cni
```

Set up the ingress gateway via istio in a different namespace as istio-system.
Add that namespace as a member of the mesh.
```bash
oc new-project istio-ingress
oc label namespace istio-ingress istio-injection=enabled
oc apply -f ./k8/ossm3.0/istioIngressGateway.yaml  -n istio-ingress
oc wait --for condition=Available deployment/istio-ingressgateway --timeout 60s -n istio-ingress
```
Expose Istio ingress route which will be used in the bookinfo traffic generator later (and via that URL, we will be accessing to the bookinfo app)
```bash
oc expose svc istio-ingressgateway --port=http2 --name=istio-ingressgateway -n istio-ingress
```
Set up the ingress gateway via Gateway API (this will live next to the previously created gateway in the same namespace)
```bash
oc apply -k ./k8/gateway
```

### Set up Tempo and OpenTelemetryCollector  
Provision and configure a tracing-system via a TempoStack for distributed tracing:
1. MinIO for persistent S3 storage
2. Tempo
3. OpenTelemetry CRs:
4. OpenTelemetryCollector

### Telemetry  
```bash
oc new-project tracing-system
```
First, set up MiniO storage which is used by Tempo to store data (or you can use S3 storage, see Tempo documentation)
```bash
oc apply -f ./k8/TempoOtel/minio.yaml -n tracing-system
oc wait --for condition=Available deployment/minio --timeout 150s -n tracing-system
```
Then, set up Tempo CR
```bash
oc apply -f ./k8/TempoOtel/tempo.yaml -n tracing-system
oc wait --for condition=Ready TempoStack/sample --timeout 150s -n tracing-system
oc wait --for condition=Available deployment/tempo-sample-compactor --timeout 150s -n tracing-system
```
Expose Jaeger UI route which will be used in the Kiali CR later
```bash
oc expose svc tempo-sample-query-frontend --port=jaeger-ui --name=tracing-ui -n tracing-system
```
Next, set up OpenTelemetryCollector
```bash
oc new-project opentelemetrycollector
oc apply -f ./k8/TempoOtel/opentelemetrycollector.yaml -n opentelemetrycollector
oc wait --for condition=Available deployment/otel-collector --timeout 60s -n opentelemetrycollector
```
Then, set up Telemetry resource to enable tracers defined in Istio custom resource
```bash
oc apply -f ./k8/TempoOtel/istioTelemetry.yaml  -n istio-system
```
The opentelemetrycollector namespace needs to be added as a member of the mesh
```bash
oc label namespace opentelemetrycollector istio-injection=enabled
```
> **_NOTE:_** `istio-injection=enabled` label works only when the name of Istio CR is `default`. If you use a different name as `default`, you need to use `istio.io/rev=<istioCR_NAME>` label instead of `istio-injection=enabled` in the all next steps of this example. Also, you will need to update values `config_map_name`, `istio_sidecar_injector_config_map_name`, `istiod_deployment_name`, `url_service_version` in the Kiali CR.

### Set up Kiali & OpenShift Service Mesh Console Plugin
Create cluster role binding for kiali to be able to read ocp monitoring
```bash
oc apply -f ./k8/Kiali/kialiCrb.yaml -n istio-system
```
Set up Kiali CR. The URL for Jaeger UI (which was exposed earlier) needs to be set to Kiali CR in `.spec.external_services.tracing.url`
> **_NOTE:_**  In this example, the `.spec.version` is missing so the istio version is automatically set by Kiali operator. You can specify the version manually, but it must be one that is supported by the operator; otherwise, an error will appear in events on the Kiali resource.
```bash
export TRACING_INGRESS_ROUTE="http://$(oc get -n tracing-system route tracing-ui -o jsonpath='{.spec.host}')"
cat ./k8/Kiali/kialiCr.yaml | JAEGERROUTE="${TRACING_INGRESS_ROUTE}" envsubst | oc -n istio-system apply -f -
oc wait --for condition=Successful kiali/kiali --timeout 150s -n istio-system 
```
Increase timeout for the Kiali ui route in OCP since big queries for spans can take longer
```bash
oc annotate route kiali haproxy.router.openshift.io/timeout=60s -n istio-system
```
Optionally, OSSMC plugin can be installed as well
> **_NOTE:_**  In this example, the `.spec.version` is missing so the istio version is automatically set by Kiali operator. You can specify the version manually, but it must be one that is supported by the operator and the version needs to be **the same as Kiali CR**.
```bash
oc apply -f ./k8/Kiali/kialiOssmcCr.yaml -n istio-system
oc wait -n istio-system --for=condition=Successful OSSMConsole ossmconsole --timeout 120s
```

### Monitoring Configuration:
1. Enable User Monitoring with OpenShift Observability (Prometheus).
2. Enable SystemMonitor in the istio-system namespace.
3. Enable PodMonitor in all Istio-related namespaces as well as application namespaces:
   3a. istio-system
   3b. istio-ingress
   3c. demo-vm-ossm3
4. Ensure Labelling all Istio-related and application namespaces with istio-injection=enabled.

### Set up OCP user monitoring workflow
First, OCP user monitoring needs to be enabled
```bash
oc apply -f ./k8/Monitoring/ocpUserMonitoring.yaml
```
Then, create service monitor and pod monitor for istio namespaces
```bash
oc apply -f ./k8/Monitoring/serviceMonitor.yaml -n istio-system
oc apply -f ./k8/Monitoring/podMonitor.yaml -n istio-system
oc apply -f ./k8/Monitoring/podMonitor.yaml -n istio-ingress
```

## Demo VM and container with OSSM 3.0 Configuration

You can run the below instructions manually, as described, or run the helper scripts in order
to save some copy/paste time:

verify one script completes before running the next one in order.

TODO: add waiting until success capability in scripts

```
sh install_ossm3_demo.sh
```

### Create Namespace for app

Create a namespace/project called `demo-vm-ossm` which is where the control plane will be deployed.  
 
 `oc apply -f k8/deployments/namespace.yaml`  


Deploy demo-vm-gateway  

`oc apply -f k8/deployments/demo-vm-gateway.yaml -n demo-vm-ossm3.0`


### Add namespace to ossm3 injection

`oc label namespace demo-vm-ossm3 istio-injection=enabled`

### Create placeholder container deployment and VM with service mesh annotations (back-end)

#### VM Deployement (backend-end)

`oc apply -f ./k8/deployments/vm/vm-template-vm1.yaml -n demo-vm-ossm3`

`oc apply -f ./k8/deployments/vm/vm-template-vm2.yaml -n demo-vm-ossm3`

`oc apply -f ./k8/deployments/vm/service.yaml -n demo-vm-ossm3`

`oc apply -f ./k8/deployments/vm/virtual-service.yaml -n demo-vm-ossm3`


#### Container Deployement (front-end)
 
`oc apply -f ./k8/deployments/container/deployment.yaml -n demo-vm-ossm3`

`oc apply -f ./k8/deployments/container/service.yaml -n demo-vm-ossm3`

`oc apply -f ./k8/deployments/container/virtual-service.yaml -n demo-vm-ossm3`

`oc apply -f ./k8/deployments/container/destinate-rule.yaml -n demo-vm-ossm3`

### Ensure setup is working
1. Get the ingress-gateway URL

```
export GATEWAY=$(oc get route istio-ingressgateway -n istio-ingress -o template --template '{{ .spec.host }}')

echo $GATEWAY                                                                                                

istio-ingressgateway-istio-ingress.apps.cluster-phx5k.dynamic.redhatworkshops.io
```
2. Call the front-end service (the container based deployment)
  
  Returns from the local front-end service without makeing any backend calls

```
curl $GATEWAY/web/hello
{"message":"Hello World from web-front-end"}
```

3. Call the back-end service via the front-end  

```
curl $GATEWAY/web/hello-service                               
{"response":{"message":"Hello World from vm-backend-b1"}}
```
This is calling the container deployment via the gateway. Internally this API is making a call to the back-end service running on the VM and passing the response from it back

```
   +-----------+       +----------------+       +-----------------------+       +-------------+  
   | API Caller | ---> | Ingress Gateway | ---> | Front-end Deployment  | --->  |  Back-end VM|  
   +-----------+       +----------------+       +-----------------------+       +-------------+  
         |                        |                        |                       |  
         |<-----------------------|<-----------------------|<----------------------|  
          (5) Response from       (4) Response from       (3) Call to VM          (2) Call to Front-end  
              Front-end to            VM to Front-end         from Front-end        from Ingress Gateway  
              API Caller  

(1) API Caller makes a call to the Ingress Gateway.
(2) The Ingress Gateway routes the call to the Front-end Deployment.
(3) The Front-end Deployment makes a call to the Back-end VM.
(4) The Back-end VM sends a response back to the Front-end Deployment.
(5) The Front-end Deployment sends the response from the Back-end VM to the API Caller.
```

You can also use the helper script to generate traffic continuously 
`sh generate-traffic-app.sh`

**_Credits_** : Thanks to `Leon Levy` who assisted and helped to build this demo.  