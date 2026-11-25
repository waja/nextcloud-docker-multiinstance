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

### Cache backend

The current deployment uses Valkey with RDB persistence as a cache and file-locking backend, and retains the Valkey backup job. It retains the service name `nextcloud-redis` and port `6379`, so the existing Nextcloud `config.php` settings remain unchanged.

For details on migrating an existing Redis deployment, including coordinated migration, backups, rollback and operational precautions, see [Redis to Valkey migration](docs/redis-to-valkey-migration.md).
