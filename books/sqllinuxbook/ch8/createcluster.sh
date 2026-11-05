sudo pcs cluster auth bwsqllinuxag1 bwsqllinuxag2 sqllinuxcfgag -u hacluster -p Sql2017isfast
sudo pcs cluster setup --name footballcluster bwsqllinuxag1 bwsqllinuxag2 sqllinuxcfgag 
sudo pcs cluster start --all
