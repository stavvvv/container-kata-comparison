# container-kata-comparison
sudo openvpn --config /home/stav/Downloads/stavroula.ovpn

ssh -i /home/stav/Desktop/my_key stavroula@147.102.13.62


Tunnel Creation that forwards port 3000 on local machine to port 3000 on the vm
From local machine:
ssh -i /home/stav/Desktop/my_key -L 3000:localhost:3000 stavroula@147.102.13.62

From vm:
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring --address 0.0.0.0

Username: admin
Password: prom-operator
