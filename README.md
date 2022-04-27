## Example deployment

```sh
apt install git &&\
git clone https://github.com/waja/nextcloud-docker-multiinstance.git /usr/local/src/nextcloud-docker-multiinstance &&\
mkdir -p /srv/docker/nextcloud && cd /srv/docker/nextcloud &&\
ln -s /usr/local/src/nextcloud-docker-multiinstance/ container.conf &&\
ln -s container.conf/deploy_nextcloud.sh . &&\
./deploy_nextcloud.sh 
```

### Initial configuration

In your instance directory

```sh
./container.conf/update.sh  --bootstrap
```
