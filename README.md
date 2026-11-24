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

### Redis to Valkey migration

The cache service uses Valkey but keeps the service name `nextcloud-redis` and port `6379`. Existing Nextcloud `config.php` settings therefore remain unchanged. Valkey is a disposable cache/locking backend and is intentionally excluded from the database-backup container.

Valkey runs as an ephemeral cache: both RDB snapshots and AOF are disabled. The new data directory is `./data/valkey/data`; do not reuse the old `./data/redis/data` directory. Redis Community Edition 7.4 and later (including Redis 8) produce RDB and AOF persistence files that are incompatible with Valkey; Valkey supports the Redis OSS 7.2 persistence format. Keep the old Redis directory untouched for inspection; do not copy its persistence files into Valkey.

**Important: the Compose file is shared by all instances.** The deployment script creates symlinks from each instance to the same central `container.conf/docker-compose.yml`. Changing that file therefore changes the configuration used by every instance the next time it is started or recreated. This procedure is a coordinated migration, not a per-instance rollout. Do not update only one instance while leaving others running on the old Redis service.

For an existing deployment:

1. Back up the Nextcloud databases and application data for **all** instances.
2. Stop Nextcloud and its Redis/cache service in **every** instance before changing the shared Compose file. Ensure that no instance is restarted during the change.
3. Deploy the updated shared Compose configuration. When each instance is started again, Valkey uses its own fresh `./data/valkey/data` directory; the old Redis directories are not mounted.
4. Start the instances and verify for each one that Valkey responds to `PING` and Nextcloud can access files normally. The database-backup container intentionally backs up only the database; Valkey cache data is not backed up.

Cache and lock state can be lost when Valkey restarts. In particular, losing a lock while a request is still writing can allow concurrent operations on the same file. As with the previous Redis service, Watchtower updates remain enabled for Valkey. Because this repository does not configure the shared Watchtower instance, verify its update policy separately. An automatic update can restart Valkey during active requests; if avoiding that risk is required, exclude this container from automatic updates and perform controlled maintenance instead. For planned manual restarts, stop or drain Nextcloud requests first, then restart Valkey, verify it is healthy, and bring Nextcloud back.

To roll back, stop Nextcloud and its cache service in **every** instance before restoring the previous shared Compose definition using `redis:8-alpine`. This change also affects all instances because they share the Compose file. Do not mount any old `./data/redis/data` directory. Start each Redis service with its own new, empty directory (for example, `./data/redis-rollback/data:/data`). Do not load old Redis snapshots because they may contain stale cache or file-lock state. Start the instances again only after the shared rollback configuration is in place.
