```
helm upgrade --install -n spire-server spire-crds spire-crds --repo https://spiffe.github.io/helm-charts-hardened/ --create-namespace --version 0.2.0
helm upgrade --install -n spire-server spire spire --repo https://spiffe.github.io/helm-charts-hardened/ --version 0.16.0 -f spire-values.yaml

kubectl apply -f mysqlclient-configmap.yaml
kubectl apply -f mysqlclient-statefulset.yaml

kubectl wait pod mysqlclient-0 --for=condition=ready --timeout=60s

# Run, and get the x500UniqueIdentifier value:
kubectl exec -it mysqlclient-0 -c main -- bash -c 'openssl x509 -in /certs/tls.crt -noout -text | grep Subject:'

# Edit mysql-values.yaml and update the x509UniqueIdentifer
vim mysql-values.yaml

helm upgrade --install -f mysql-values.yaml mysql mysql --version 9.15.0 --repo https://charts.bitnami.com/bitnami

kubectl wait pod mysql-0 --for=condition=ready --timeout=60s

kubectl exec -it mysqlclient-0 -- bash -c 'mysql -u mysqlclient --protocol tcp --ssl-key /certs/tls.key --ssl-cert /certs/tls.crt --ssl-ca /certs/ca.pem -h mysql.default.svc.cluster.local'
```
