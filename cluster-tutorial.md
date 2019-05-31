### Basic node settings

To use Fission a Kubernetes cluster is needed, and a tutorial to create one can be found below. The VM nodes have Ubuntu 18.04 with LVM enabled. In this example I have one master and three worker nodes. (This worker number is needed to handle dynamic storage.) To handle Kubernetes storage needs I added virtual HDDs to the VMs, but virtual block devices could be made too.

Example IP addresses with network settings:

Master	192.168.1.80  
Worker1	192.168.1.81  
Worker2	192.168.1.82  
Worker3	192.168.1.83  

Ubuntu 18.04: VM – Bridged network  
&nbsp;&nbsp;&nbsp;IPv4 – manual  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;address: 192.168.1.80  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;netmask: 255.255.255.0   
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;gateway: 192.168.1.254  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;dns: 8.8.8.8  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;route: automatic  
    
Set hostnames differently for each node. (18.04 – Cloud init)

&nbsp;&nbsp;&nbsp;`sudo touch /etc/cloud/cloud-init.disabled`

Open ports on master for Kubernetes:

&nbsp;&nbsp;&nbsp;`sudo ufw allow 6433/tcp && sudo ufw allow 2379:2380/tcp && sudo ufw allow 10250:10252/tcp`

Open ports on all of the workers:

&nbsp;&nbsp;&nbsp;`sudo ufw allow 10250/tcp && sudo ufw allow 30000:32767/tcp`

On all of the nodes the swap memory must be disabled, because Kubernetes does not support it. To do this permamently comment the swap memory specific lines from /etc/fstab file. After this a restart is required.

&nbsp;&nbsp;&nbsp;`sudo nano /etc/fstab`
  
Check swap memory with this command:  

&nbsp;&nbsp;&nbsp;`free -h`

Install Docker 18.06.3 on all of the nodes:

&nbsp;&nbsp;&nbsp;`sudo apt-get update`  
&nbsp;&nbsp;&nbsp;`sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common`  
&nbsp;&nbsp;&nbsp;`curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -`  
&nbsp;&nbsp;&nbsp;`sudo apt-key fingerprint 0EBFCD88`  
&nbsp;&nbsp;&nbsp;`sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"`  
&nbsp;&nbsp;&nbsp;`sudo apt-get update`  
&nbsp;&nbsp;&nbsp;`sudo apt-get install docker-ce=18.06.3~ce~3-0~ubuntu containerd.io`  

Change the cgroupdriver to systemd:

&nbsp;&nbsp;&nbsp;`sudo nano /etc/docker/daemon.json`   
&nbsp;&nbsp;&nbsp;{  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"exec-opts": ["native.cgroupdriver=systemd"],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"log-driver": "json-file",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"log-opts": {  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"max-size": "100m"  
&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"storage-driver": "overlay2"  
&nbsp;&nbsp;&nbsp;}  

&nbsp;&nbsp;&nbsp;`sudo mkdir -p /etc/systemd/system/docker.service.d`  

&nbsp;&nbsp;&nbsp;`sudo systemctl daemon-reload`  
&nbsp;&nbsp;&nbsp;`sudo systemctl restart docker`  

Check that Docker is working properly:

&nbsp;&nbsp;&nbsp;`sudo docker run hello-world`

Install Kubernetes an all of the nodes:

`curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list && sudo apt-get update -q && sudo apt-get install -qy kubelet=1.14.0-00 kubectl=1.14.0-00 kubeadm=1.14.0-00`  

&nbsp;&nbsp;&nbsp;`sudo sysctl net.bridge.bridge-nf-call-iptables=1`  

### GlusterFS

To be able to use dynamic storage provisioning in Kubernetes, I use GlusterFS with heketi, which needs at least 3 nodes to work. First of all, on each node open the ports and load all the kernel modules that are stated here:

&nbsp;&nbsp;&nbsp;https://github.com/gluster/gluster-kubernetes/blob/master/docs/setup-guide.md  

For the kernel modules permanent solution, add them to /etc/modules file.

For the remaining steps follow this guide or the steps below: https://medium.com/devopslinks/configuring-ha-kubernetes-cluster-on-bare-metal-servers-with-glusterfs-metallb-2-3-c9e0b705aa3d

Install glsuterfs_client on all workers:

&nbsp;&nbsp;&nbsp;`sudo apt-get install glusterfs-client`  
  
These steps must be made on the master node:  

&nbsp;&nbsp;&nbsp;`git clone https://github.com/heketi/heketi`  
&nbsp;&nbsp;&nbsp;`cd heketi/extras/kubernetes`  
&nbsp;&nbsp;&nbsp;`kubectl create -f glusterfs-daemonset.json` (gluster/gluster-centos:gluster4u0_centos7, with latest the pods fail to work again after node reboots.)  
  
&nbsp;&nbsp;&nbsp;`kubectl label node worker1 storagenode=glusterfs`  
&nbsp;&nbsp;&nbsp;`kubectl label node worker2 storagenode=glusterfs`  
&nbsp;&nbsp;&nbsp;`kubectl label node worker3 storagenode=glusterfs`  

&nbsp;&nbsp;&nbsp;`kubectl create -f heketi-service-account.json`  
&nbsp;&nbsp;&nbsp;`kubectl create clusterrolebinding heketi-gluster-admin --clusterrole=edit --serviceaccount=default:heketi-service-account`  
&nbsp;&nbsp;&nbsp;`kubectl create secret generic heketi-config-secret --from-file=./heketi.json`  
&nbsp;&nbsp;&nbsp;`kubectl create -f heketi-bootstrap.json`  
&nbsp;&nbsp;&nbsp;`wget https://github.com/heketi/heketi/releases/download/v9.0.0/heketi-client-v9.0.0.linux.amd64.tar.gz`  
&nbsp;&nbsp;&nbsp;`tar -xzvf ./heketi-client-v9.0.0.linux.amd64.tar.gz`  
&nbsp;&nbsp;&nbsp;`sudo cp ./heketi-client/bin/heketi-cli /usr/local/bin/`  
&nbsp;&nbsp;&nbsp;`heketi-cli -v`  
&nbsp;&nbsp;&nbsp;`export HEKETI_CLI_SERVER=http://`kubectl describe pod deploy-heketi-???? | grep IP | sed -E 's/IP:[[:space:]]+//'`:8080`  

Create the topology.json, which describes where are the storage nodes, which directory or partition should be used on them, what is their name. My example can be seen below:
  
&nbsp;&nbsp;&nbsp;`nano heketi/extras/kubernetes/topology-sample.json`

{  
&nbsp;&nbsp;&nbsp;"clusters": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;{  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"nodes": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;{  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"node": {  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"hostnames": {  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"manage": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"worker1"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"storage": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"192.168.1.81"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"zone": 1  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"devices": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"/dev/sdb"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;{  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"node": {  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"hostnames": {  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"manage": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"worker2"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"storage": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"192.168.1.82"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"zone": 1  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"devices": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"/dev/sdb"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;{  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"node": {  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"hostnames": {  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"manage": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"worker3"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"storage": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"192.168.1.83"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"zone": 1  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;},  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"devices": [  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"/dev/sdb"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;}  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;}  
&nbsp;&nbsp;&nbsp;]  
}  

&nbsp;&nbsp;&nbsp;`heketi-cli topology load --json=topology-sample.json`  
&nbsp;&nbsp;&nbsp;`heketi-cli setup-openshift-heketi-storage (This command creates heketi-storage.json)`   
&nbsp;&nbsp;&nbsp;`kubectl create -f heketi-storage.json`  
&nbsp;&nbsp;&nbsp;`kubectl delete all,service,jobs,deployment,secret --selector="deploy-heketi"`  
&nbsp;&nbsp;&nbsp;`kubectl create -f heketi-deployment.json`  
&nbsp;&nbsp;&nbsp;`kubectl get endpoints`  
&nbsp;&nbsp;&nbsp;`kubectl expose pod heketi-74cc7bb45c-5z46g --name=heketi-svc --port=8080 --type=NodePort`  
&nbsp;&nbsp;&nbsp;`nano storage-class.yml` (On reboot the resturl ip may change, so we expose it.)  

&nbsp;&nbsp;&nbsp;apiVersion: storage.k8s.io/v1beta1  
&nbsp;&nbsp;&nbsp;kind: StorageClass  
&nbsp;&nbsp;&nbsp;metadata:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;name: slow  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;annotations:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;storageclass.kubernetes.io/is-default-class: "true"  
&nbsp;&nbsp;&nbsp;provisioner: kubernetes.io/glusterfs  
&nbsp;&nbsp;&nbsp;parameters:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;resturl: http:// 192.168.1.80:32005  


If there is a typo in the json, or for some other reason we need to clean up the topology, we can use these commands. The first one prints out the topology info, the second one is deletes a volume. Instead of a volume, we can delete a cluster, a node, and a device too.

&nbsp;&nbsp;&nbsp;`heketi-cli topology info`  
&nbsp;&nbsp;&nbsp;`heketi-cli volume delete <volume_id>`  
  
### Kubernetes configuration

To create the cluster, I use the kubeadm init command. Where the --apiserver-advertise-address flag is the IP address of the master node, the --pod-network-cidr is the IP address of the chosen network plugin, here Flannel.

&nbsp;&nbsp;&nbsp;`sudo kubeadm init --apiserver-advertise-address=192.168.1.80 --pod-network-cidr=10.244.0.0/16`  
&nbsp;&nbsp;&nbsp;`mkdir -p $HOME/.kube`  
&nbsp;&nbsp;&nbsp;`sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config`  
&nbsp;&nbsp;&nbsp;`sudo chown $(id -u):$(id -g) $HOME/.kube/config`  
&nbsp;&nbsp;&nbsp;`kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/a70459be0084506e4ec919aa1c114638878db11b/Documentation/kube-flannel.yml`  

On the worker nodes use the command from the kubeadm init's output:

&nbsp;&nbsp;&nbsp;`sudo kubeadm join --???--`
	
To test if everything is working:

&nbsp;&nbsp;&nbsp;`kubectl get nodes`  
&nbsp;&nbsp;&nbsp;`kubectl get pods --all-namespaces`  

If the coredns pods are switching between CrashLoopBackOff and Running stated, then a solution is to disable the dnsmasq feature of the NetworkManager. The loop detector of corends does not like the dnsmasq. 
Comment out the dns=dnsmasq line and restart the NetworkManager, on all of the nodes.

&nbsp;&nbsp;&nbsp;`sudo nano /etc/NetworkManager/NetworkManager.conf`  
&nbsp;&nbsp;&nbsp;`sudo service network-manager restart`  

Another possible solution is to change the memory limit of the coredns pods, and to change the image version number if it is old, here:

&nbsp;&nbsp;&nbsp;`KUBE_EDITOR="nano" kubectl edit deployment -n kube-system coredns`  

With Glusterfs the dynamic provisioning is working, so we don't need to make manually Persistent Volumes.

### Fission install

To install Fission I use Helm, which makes it easier, but firstly Helm must be installed:

&nbsp;&nbsp;&nbsp;`curl -LO https://storage.googleapis.com/kubernetes-helm/helm-v2.13.1-linux-amd64.tar.gz`  
&nbsp;&nbsp;&nbsp;`tar xzf helm-v2.13.1-linux-amd64.tar.gz`  
&nbsp;&nbsp;&nbsp;`sudo mv linux-amd64/helm /usr/local/bin`  
&nbsp;&nbsp;&nbsp;`kubectl create serviceaccount --namespace kube-system tiller`  
&nbsp;&nbsp;&nbsp;`kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller`  
&nbsp;&nbsp;&nbsp;`helm init --service-account tiller`  

To use Jaeger tracing system with Fission, an easy way is to edit Fission's values.yaml before Fission installation. Create monitoring namespace for it. The traceCollectorEndpoint’s monitoring is the namespace of the jaeger pod.

&nbsp;&nbsp;&nbsp;`kubectl -n monitoring create -f https://raw.githubusercontent.com/jaegertracing/jaeger-kubernetes/master/all-in-one/jaeger-all-in-one-template.yml`  

&nbsp;&nbsp;&nbsp;`helm install --name fission --namespace fission --set serviceType=NodePort,routerServiceType=NodePort,traceCollectorEndpoint=http://jaeger-collector.monitoring.svc:14268/api/traces?format=jaeger.thrift,traceSamplingRate=0.75 https://github.com/fission/fission/releases/download/1.2.1/fission-all-1.2.1.tgz`  

&nbsp;&nbsp;&nbsp;`curl -Lo fission https://github.com/fission/fission/releases/download/1.2.1/fission-cli-linux && chmod +x fission && sudo mv fission /usr/local/bin/`  

Fission is working now if the pods are running:

&nbsp;&nbsp;&nbsp;`kubectl get pods -A`  

### Monitoring

Prometheus comes with the full Fission version, but to reach it it must be exposed. Change the pod's name to the actual name.

&nbsp;&nbsp;&nbsp;`kubectl expose pod fission-prometheus-server-7d85cf4fcb-4x7cp --name=prometheus-svc --port=9090 --type=NodePort –n=fission`

The given port number that can be accessed from outside can be found with this command:

&nbsp;&nbsp;&nbsp;`kubectl describe services prometheus-svc -n fission`

Grafana will be installed with Helm too. This command enables the storage for Grafana (10 GB), install the kubernetes plugin, and sets up a custom admin password.

&nbsp;&nbsp;&nbsp;`helm install stable/grafana --set persistence.enabled=true --set persistence.accessModes={ReadWriteOnce} --set plugins[0]=grafana-kubernetes-app --set adminPassword=<custom-admin-password> -n grafana --namespace monitoring`

If the admin password is lost, then it can be found here:

&nbsp;&nbsp;&nbsp;`kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo`

The Grafana pod must be exposed too:

&nbsp;&nbsp;&nbsp;`kubectl expose pod grafana-7dfc7fc75c-dmqbh --name=grafana-svc --port=3000 --type=NodePort --namespace=monitoring`  
&nbsp;&nbsp;&nbsp;`kubectl describe services grafana-svc -n monitoring`

To use the kubernetes app plugin in the web-ui, first a connection to the cluster must be established. By default, check the TLS Client Auth and With CA Cert checkboxes. All the required data can be gathered from the output of kubectl config view –raw command. The URL is the address of the cluster server, CA Cert equals to certificate-authority-data field (this needs to be decoded from base64,  and the other certificates too), Client Cert equals to client-certificate-data, and CLient Key equals to client-key-data field.  

&nbsp;&nbsp;&nbsp;URL - `kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}'`  
&nbsp;&nbsp;&nbsp;CA Cert - `kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 --decode ; echo`  
&nbsp;&nbsp;&nbsp;Client Cert - `kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 --decode ; echo`  
&nbsp;&nbsp;&nbsp;Client Key - `kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}' | base64 --decode ; echo`  

If the default Prometheus scrape interval is too slow, it can be changed here:
  
&nbsp;&nbsp;&nbsp;`KUBE_EDITOR="nano" kubectl edit configmap fission-prometheus-server -n=fission`  
  
### Usage of Fission  

In Fission there are severeal supported programming languages (Go, .NET, Python, NodeJS, Ruby). To use a function, first an environment must be made for it. The environment is language specific, which contains enough software to build and run a function. 
Example for a NodeJS environment:

fission env create --name nodejs --image fission/node-env:1.2.1

Example for a NodeJS function:

&nbsp;&nbsp;&nbsp;`curl -LO https://raw.githubusercontent.com/fission/fission/master/examples/nodejs/hello.js`  
&nbsp;&nbsp;&nbsp;`fission function create --name hello --env nodejs --code hello.js`  

 The function can be tested without a real invocation:

&nbsp;&nbsp;&nbsp;`fission function test --name hello`

With a route we can access the function through HTTP calls:

&nbsp;&nbsp;&nbsp;`fission route create --name hellourl --function hello --url /hello`  
&nbsp;&nbsp;&nbsp;`curl http://${FISSION_ROUTER}/hello`  

The ${FISSION_ROUTER} is an environment variable, which can be exported with the commands below, and it is the IP address of the Fission router.

&nbsp;&nbsp;&nbsp;`kubectl -n fission get svc router`  
&nbsp;&nbsp;&nbsp;`export FISSION_ROUTER=$(kubectl -n fission get svc router -o jsonpath='{...clusterIP}')`  
