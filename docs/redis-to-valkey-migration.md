# Redis to Valkey migration

This guide describes how to migrate an existing deployment from Redis to Valkey and how to roll back if necessary.

## Current cache setup

The cache service runs `valkey/valkey:9-alpine` but keeps the Compose service name `nextcloud-redis` and port `6379`. Existing Nextcloud `config.php` settings therefore remain unchanged.

Valkey is an ephemeral cache and file-locking backend:

- RDB snapshots and AOF are disabled.
- Each instance uses a fresh `./data/valkey/data` directory.
- Valkey is excluded from the database-backup container; only the database is backed up there.
- Do not reuse the old `./data/redis/data` directory or copy persistence files into Valkey.

Redis Community Edition 7.4 and later (including Redis 8) produce RDB and AOF persistence files that are incompatible with Valkey. Valkey supports the Redis OSS 7.2 persistence format. Keep the old Redis directory untouched for inspection.

## Before you start

**The Compose file is shared by all instances.** The deployment script creates symlinks from each instance to the same central `container.conf/docker-compose.yml`. Changing that file changes the configuration used by every instance the next time it is started or recreated. This is a coordinated migration, not a per-instance rollout. Do not migrate one instance while leaving other instances running with the old Redis service.

Plan a maintenance window for all instances.

## Migration

1. Enable Nextcloud maintenance mode in **every** instance before taking any backup. Run this from each instance directory:

   ```sh
   docker-compose exec nextcloud occ maintenance:mode --on
   ```

   Keep maintenance mode enabled until the migration is complete.

2. Back up the Nextcloud databases and application data for **all** instances while maintenance mode is enabled. This prevents writes from making the database and file backups inconsistent.

3. Stop every instance:

   ```sh
   systemctl stop nextcloud-<instance>.service
   ```

   Do not restart any instance while changing the shared Compose file.

4. Deploy the updated shared Compose configuration.

5. Start every instance:

   ```sh
   systemctl start nextcloud-<instance>.service
   ```

   The systemd unit runs Compose `down`, `pull`, and `up -d`, so it recreates the containers and applies the new image and mounts. Do not use `docker-compose start` for this migration; it would only start existing containers without applying the updated configuration.

6. Disable maintenance mode in each instance:

   ```sh
   docker-compose exec nextcloud occ maintenance:mode --off
   ```

   Verify for every instance that Valkey responds to `PING` and Nextcloud can access files normally. The database-backup container intentionally backs up only the database; Valkey cache data is not backed up.

## Operational note

Cache and lock state can be lost when Valkey restarts. In particular, losing a lock while a request is still writing can allow concurrent operations on the same file.

As with the previous Redis service, Watchtower updates remain enabled for Valkey. This repository does not configure the shared Watchtower instance, so verify its update policy separately. An automatic update can restart Valkey during active requests; if avoiding that risk is required, exclude this container from automatic updates and perform controlled maintenance instead.

For planned manual restarts, stop or drain Nextcloud requests first, then restart Valkey, verify it is healthy, and bring Nextcloud back.

## Rollback to Redis

1. Check each instance. If its Nextcloud container is running, enable maintenance mode:

   ```sh
   docker-compose exec nextcloud occ maintenance:mode --on
   ```

   If the container is already stopped or failed to start, leave it stopped; do not try to use `exec` against it.

2. Back up the current state if needed.

3. Stop every instance:

   ```sh
   systemctl stop nextcloud-<instance>.service
   ```

4. Restore the previous shared Compose definition using `redis:8-alpine`. This change affects all instances because they share the Compose file.

5. Do not mount any old `./data/redis/data` directory. Start each Redis service with its own new, empty directory (for example, `./data/redis-rollback/data:/data`). Do not load old Redis snapshots because they may contain stale cache or file-lock state.

6. Start every instance:

   ```sh
   systemctl start nextcloud-<instance>.service
   ```

   This recreates the containers with the rollback configuration.

7. Once Nextcloud is running, disable maintenance mode in instances where it was enabled and verify service health.
