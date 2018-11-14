1. What images are in my local registry

sudo docker images

2. What does an image look like?

sudo docker inspect <imageid>

3. What is the docker deamon?

ps -axf | grep docker

4. Run a simple container

sudo docker run --name helloworld hello-world
sudo docker ps
sudo docker ps -a

4. How about one that stays around

sudo docker run -it -d --name dockerbash ubuntu bash

5. What about namespaces?

sudo lsns

6. What does this process look like outside the container?

sudo ps -axf

7. What is the Linux distribution outside the container?

cat /etc/os-release

8. What does this process look like inside the container?

sudo docker exec -it dockerbash bash

The GUID is the container ID
Run ps from the new bash shell

8. What is the Linux distribution inside the container?

cat /etc/os-release
