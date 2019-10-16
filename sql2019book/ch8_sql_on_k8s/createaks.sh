z aks create \
    --resource-group bwaks \
    --name bwsqlaks \
    --node-count 2 \
    --enable-addons monitoring \
    --generate-ssh-keys