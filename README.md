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

The cache service uses Valkey but keeps the service name `nextcloud-redis` and port `6379`. Existing Nextcloud `config.php` settings and the database-backup configuration (`DB02_TYPE=redis`) therefore remain unchanged.

Valkey uses its default persistence configuration: RDB snapshots are enabled and AOF is disabled, matching the previous Redis setup. The new data directory is `./data/valkey/data`; do not reuse the old `./data/redis/data` directory. Redis 8 RDB files (format version 17) are incompatible with Valkey 9 and cause Valkey to fail during startup. Keep the old Redis directory untouched for rollback/inspection.

For an existing deployment:

1. Back up the Nextcloud database and application data as usual.
2. Stop the stack (or at least Nextcloud, Redis and the database-backup service) before changing the Compose file.
3. Deploy the updated Compose configuration. Valkey starts with a fresh data directory; the old Redis directory is not mounted.
4. Verify that Valkey responds to `PING`, Nextcloud can access files normally, and the database-backup service successfully backs up Valkey using its existing Redis-compatible configuration.
5. Test restoring a Valkey backup before relying on it.

Cache and lock state can be lost when Valkey restarts. In particular, losing a lock while a request is still writing can allow concurrent operations on the same file. As with the previous Redis service, Watchtower updates remain enabled for Valkey. This has worked in the existing deployment, but an update can still restart Valkey during active requests. For planned manual restarts, stop or drain Nextcloud requests first, then restart Valkey, verify it is healthy, and bring Nextcloud back.

To roll back, stop the stack and restore the previous Compose definition using `redis:8-alpine`, but do not mount the old `./data/redis/data` directory. Start Redis with a new, empty directory such as `./data/redis-rollback/data:/data`. Do not load the old Redis snapshot during rollback because it may contain stale cache or file-lock state.
