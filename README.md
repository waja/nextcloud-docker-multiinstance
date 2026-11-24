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

For an existing deployment:

1. Back up the Nextcloud database and application data as usual.
2. Stop the stack (or at least Nextcloud, Redis and the database-backup service) before changing the Compose file.
3. Deploy the updated Compose configuration. Valkey starts with a fresh data directory; the old Redis directory is not mounted.
4. Verify that Valkey responds to `PING` and Nextcloud can access files normally. The database-backup container intentionally backs up only the database; Valkey cache data is not backed up.

Cache and lock state can be lost when Valkey restarts. In particular, losing a lock while a request is still writing can allow concurrent operations on the same file. As with the previous Redis service, Watchtower updates remain enabled for Valkey. Because this repository does not configure the shared Watchtower instance, verify its update policy separately. An automatic update can restart Valkey during active requests; if avoiding that risk is required, exclude this container from automatic updates and perform controlled maintenance instead. For planned manual restarts, stop or drain Nextcloud requests first, then restart Valkey, verify it is healthy, and bring Nextcloud back.

To roll back, stop the stack and restore the previous Compose definition using `redis:8-alpine`, but do not mount the old `./data/redis/data` directory. Start Redis with a new, empty directory such as `./data/redis-rollback/data:/data`. Do not load the old Redis snapshot during rollback because it may contain stale cache or file-lock state.
