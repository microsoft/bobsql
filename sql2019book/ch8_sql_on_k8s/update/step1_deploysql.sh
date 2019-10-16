kubectl create namespace mssql
kubectl config set-context mssql --namespace=mssql --cluster=bwsqlaks --user=clusterUser_bwaks_bwsqlaks
kubectl config use-context mssql
kubectl apply -f sqlloadbalancer.yaml
kubectl create secret generic mssql-secret --from-literal=SA_PASSWORD="Sql2017isfast"
kubectl apply -f storage.yaml
kubectl apply -f sql2017deployment.yaml