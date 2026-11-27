#!/bin/bash
set -e

# Keep hostname case conversion and character classes ASCII-only on every host.
export LC_ALL=C

BASE_DIR="/srv/docker/nextcloud"
NEXTCLOUD_VERSION=35

version_check() {
       local config_dir instance env_file env_version container_ids container_ids_after container_ids_final container_ids_sorted container_ids_after_sorted container_ids_final_sorted container_id container_info container_state container_image image_reference image_version
       local instances found=0 error=0

       if ! command -v timeout >/dev/null 2>&1; then
               echo "ERROR: timeout is not available; cannot perform a bounded Docker check." >&2
               return 1
       fi

       instances="$(mktemp)" || {
               echo "ERROR: unable to create temporary file for version check." >&2
               return 1
       }

       if ! find "${BASE_DIR}" -mindepth 1 -maxdepth 1 -type d ! -name container.conf -print0 > "${instances}"; then
               echo "ERROR: unable to scan ${BASE_DIR} for Nextcloud instances." >&2
               rm -f "${instances}"
               return 1
       fi

       while IFS= read -r -d '' instance; do
               config_dir="${instance}/container.conf"
               if [[ ! -d "${config_dir}" ]]; then
                       echo "ERROR: expected configuration directory ${config_dir} is missing." >&2
                       error=1
                       continue
               fi
               env_file="${config_dir}/.env"
               if [[ ! -r "${env_file}" ]]; then
                       echo "ERROR: unable to read ${env_file}." >&2
                       error=1
                       continue
               fi

               # Docker Compose uses the last assignment when a key is repeated.
               env_version="$(sed -n 's/^[[:space:]]*NEXTCLOUD_VERSION[[:space:]]*=//p' "${env_file}" | tail -n 1)"
               # Remove Compose-style inline comments before checking for an empty value.
               env_version="$(printf '%s\n' "${env_version}" | sed -E 's/^[[:space:]]+#.*$//; s/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
               env_version="${env_version#\"}"
               env_version="${env_version%\"}"
               env_version="${env_version#\'}"
               env_version="${env_version%\'}"
               if [[ -z "${env_version//[[:space:]]/}" ]]; then
                       echo "ERROR: NEXTCLOUD_VERSION is missing or empty in ${env_file}." >&2
                       error=1
                       continue
               fi

               if ! container_ids="$(cd "${instance}" && env -u NEXTCLOUD_VERSION -u COMPOSE_PROJECT_NAME timeout --kill-after=5s 30s /usr/local/bin/docker-compose \
                       -f docker-compose.yml \
                       -f container.conf/production.yml \
                       ps -q nextcloud)"; then
                       echo "ERROR: unable to query the Nextcloud container for ${instance##*/}." >&2
                       error=1
                       break
               fi

               for container_id in ${container_ids}; do
                       if ! container_info="$(timeout --kill-after=5s 30s docker inspect --format '{{.State.Status}}|{{.Config.Image}}' "${container_id}")"; then
                               echo "ERROR: unable to inspect a Nextcloud container for ${instance##*/}." >&2
                               error=1
                               break 2
                       fi

                       container_state="${container_info%%|*}"
                       container_image="${container_info#*|}"
                       if [[ "${container_state}" != running && ! "${container_state}" =~ ^(created|exited|dead)$ ]]; then
                               echo "ERROR: unexpected Nextcloud container state for ${instance##*/}: ${container_state}." >&2
                               error=1
                       fi
               done
               (( error == 0 )) || break

               # Detect containers replaced while their image versions were inspected.
               if ! container_ids_after="$(cd "${instance}" && env -u NEXTCLOUD_VERSION -u COMPOSE_PROJECT_NAME timeout --kill-after=5s 30s /usr/local/bin/docker-compose \
                       -f docker-compose.yml \
                       -f container.conf/production.yml \
                       ps -q nextcloud)"; then
                       echo "ERROR: unable to re-check the Nextcloud container set for ${instance##*/}." >&2
                       error=1
                       break
               fi
               container_ids_sorted="$(printf '%s\n' "${container_ids}" | tr ' ' '\n' | sed '/^$/d' | sort)"
               container_ids_after_sorted="$(printf '%s\n' "${container_ids_after}" | tr ' ' '\n' | sed '/^$/d' | sort)"
               if [[ "${container_ids_sorted}" != "${container_ids_after_sorted}" ]]; then
                       echo "ERROR: the Nextcloud container set changed during the version check for ${instance##*/}; please run the check again." >&2
                       error=1
                       break
               fi

               # Confirm that no container was created or replaced during the final inspection.
               if ! container_ids_final="$(cd "${instance}" && env -u NEXTCLOUD_VERSION -u COMPOSE_PROJECT_NAME timeout --kill-after=5s 30s /usr/local/bin/docker-compose \
                       -f docker-compose.yml \
                       -f container.conf/production.yml \
                       ps -q nextcloud)"; then
                       echo "ERROR: unable to confirm the final Nextcloud container set for ${instance##*/}." >&2
                       error=1
                       break
               fi
               container_ids_final_sorted="$(printf '%s\n' "${container_ids_final}" | tr ' ' '\n' | sed '/^$/d' | sort)"
               if [[ "${container_ids_after_sorted}" != "${container_ids_final_sorted}" ]]; then
                       echo "ERROR: the Nextcloud container set changed during the final inspection for ${instance##*/}; please run the check again." >&2
                       error=1
                       break
               fi

               # Recheck the final container set after inspection. Retry once if a
               # container was created or replaced while Docker inspect was running.
               local attempt instance_found container_ids_verified container_ids_verified_sorted
               for attempt in 1 2; do
                       instance_found=0
                       if ! container_ids_final="$(cd "${instance}" && env -u NEXTCLOUD_VERSION -u COMPOSE_PROJECT_NAME timeout --kill-after=5s 30s /usr/local/bin/docker-compose \
                               -f docker-compose.yml \
                               -f container.conf/production.yml \
                               ps -q nextcloud)"; then
                               echo "ERROR: unable to confirm the final Nextcloud container set for ${instance##*/}." >&2
                               error=1
                               break
                       fi
                       container_ids_final_sorted="$(printf '%s\n' "${container_ids_final}" | tr ' ' '\n' | sed '/^$/d' | sort)"
                       if [[ "${container_ids_after_sorted}" != "${container_ids_final_sorted}" ]]; then
                               echo "ERROR: the Nextcloud container set changed during the final inspection for ${instance##*/}; please run the check again." >&2
                               error=1
                               break
                       fi

                       for container_id in ${container_ids_final}; do
                               if ! container_info="$(timeout --kill-after=5s 30s docker inspect --format '{{.State.Status}}|{{.Config.Image}}' "${container_id}")"; then
                                       echo "ERROR: unable to inspect a final Nextcloud container for ${instance##*/}." >&2
                                       error=1
                                       break
                               fi
                               container_state="${container_info%%|*}"
                               container_image="${container_info#*|}"
                               if [[ "${container_state}" == running ]]; then
                                       image_reference="${container_image%@*}"
                                       image_version="${image_reference##*:}"
                                       if [[ "${image_reference}" != *:* || ! "${image_version}" =~ ^[0-9]+$ ]]; then
                                               echo "ERROR: unable to determine the running Nextcloud version for ${instance##*/} from image ${container_image}." >&2
                                               error=1
                                               continue
                                       fi
                                       if (( 10#${image_version} < NEXTCLOUD_VERSION )); then
                                               echo "WARNING: ${instance##*/} is running Nextcloud ${image_version}; new deployments use Nextcloud ${NEXTCLOUD_VERSION}. No migration performed." >&2
                                               instance_found=1
                                       fi
                               elif [[ ! "${container_state}" =~ ^(created|exited|dead)$ ]]; then
                                       echo "ERROR: unexpected Nextcloud container state for ${instance##*/}: ${container_state}." >&2
                                       error=1
                               fi
                       done
                       (( error == 0 )) || break

                       if ! container_ids_verified="$(cd "${instance}" && env -u NEXTCLOUD_VERSION -u COMPOSE_PROJECT_NAME timeout --kill-after=5s 30s /usr/local/bin/docker-compose \
                               -f docker-compose.yml \
                               -f container.conf/production.yml \
                               ps -q nextcloud)"; then
                               echo "ERROR: unable to verify the Nextcloud container set after inspection for ${instance##*/}." >&2
                               error=1
                               break
                       fi
                       container_ids_verified_sorted="$(printf '%s\n' "${container_ids_verified}" | tr ' ' '\n' | sed '/^$/d' | sort)"
                       if [[ "${container_ids_final_sorted}" == "${container_ids_verified_sorted}" ]]; then
                               (( instance_found == 0 )) || found=1
                               break
                       fi
                       if (( attempt == 2 )); then
                               echo "ERROR: the Nextcloud container set kept changing during inspection for ${instance##*/}; please run the check again." >&2
                               error=1
                               break
                       fi
                       container_ids_after="${container_ids_verified}"
                       container_ids_after_sorted="${container_ids_verified_sorted}"
               done
               (( error == 0 )) || break
       done < "${instances}"

       rm -f "${instances}"

       if (( error != 0 )); then
               return 1
       fi

       if (( found == 0 )); then
               echo "No active instances older than Nextcloud ${NEXTCLOUD_VERSION} found."
       fi
}
case "${1:-}" in
       --version-check)
               if (( $# != 1 )); then
                       echo "Usage: $0 [--version-check]" >&2
                       exit 2
               fi
               version_check
               exit $?
               ;;
       "")
               ;;
       *)
               echo "Usage: $0 [--version-check]" >&2
               exit 2
               ;;
esac

# Migrate existing per-instance hard links to symlinks so service updates
# are picked up by every instance instead of retaining an old inode.
for service_file in "${BASE_DIR}"/*/container.conf/nextcloud-*.service; do
        [[ -e "${service_file}" ]] || continue
        if [[ ! -L "${service_file}" ]]; then
                rm "${service_file}"
                ln -s ../../container.conf/nextcloud.service "${service_file}"
        fi
done

while [[ -z "${NAME:-}" ]]; do
        read -r -p 'Hostname (<host>): ' NAME
done

if (( ${#NAME} > 233 )) || [[ ! "${NAME}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]; then
        echo "ERROR: '${NAME}' is not a valid hostname or exceeds the 233-character limit imposed by generated Docker container names." >&2
        exit 1
fi

# DNS hostnames are case-insensitive; LC_ALL=C above makes this ASCII-only.
NAME="${NAME,,}"

shopt -s nullglob
for existing_dir in "${BASE_DIR}"/*/; do
        existing_name="${existing_dir%/}"
        existing_name="${existing_name##*/}"
        if [[ "${existing_name,,}" == "${NAME,,}" ]]; then
                echo "ERROR: an instance for hostname ${NAME} already exists as ${existing_name}; hostnames are case-insensitive." >&2
                exit 1
        fi
done

# Reserve the instance directory atomically. A concurrent deployment for the
# same hostname will fail here before it can write any instance configuration.
mkdir -p "${BASE_DIR}"
if ! mkdir "${BASE_DIR}/${NAME}"; then
        echo "ERROR: ${BASE_DIR}/${NAME} already exists or is being created by another deployment; refusing to overwrite it." >&2
        exit 1
fi

HASH="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo '')"
MYSQL_ROOT_PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo '')"
MYSQL_PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo '')"
JWT_SECRET="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo '')"

# Provide symlink infrastructure for making use of global configurations

mkdir -p "${BASE_DIR}/${NAME}/container.conf" "/etc/systemd/system/nextcloud-${NAME}.service.d"
for DIR in data/nextcloud/php-sessions data/nextcloud/logs/php data/nextcloud/logs/nginx data/nextcloud/apps data/nextcloud/config data/nextcloud/data data/nextcloud/themes; do
	mkdir -p "${BASE_DIR}/${NAME}/${DIR}"
	chown 1000:1000 "${BASE_DIR}/${NAME}/${DIR}"
done
for DIR in data/calcardbackup data/db-backups data/mysql data/redis; do
	mkdir -p "${BASE_DIR}/${NAME}/${DIR}"
done
ln -s ../../container.conf/update.sh "${BASE_DIR}/${NAME}/container.conf/update.sh"
ln -s ../../container.conf/docker-compose.yml "${BASE_DIR}/${NAME}/container.conf/docker-compose.yml"
ln -s container.conf/docker-compose.yml "${BASE_DIR}/${NAME}/"
ln -s container.conf/.env "${BASE_DIR}/${NAME}"

# Create instance specific docker-compose configuration
cat > "${BASE_DIR}/${NAME}/container.conf/production.yml" <<EOF
# Inspired by https://github.com/Wonderfall/dockerfiles/tree/master/nextcloud#docker-compose-file
services:
  nextcloud:
    labels:
      - traefik.http.routers.\${TRAEFIK_PROJECT}-\${TRAEFIK_SERVICE_01}-\${TRAEFIK_HASH}.rule=Host(\`${NAME}\`)
    environment:
      - DOMAIN=${NAME}
EOF

INSTANCE="$(printf '%s' "${NAME}" | sed 's/\./_/g')"
# Create .env file with needed traefik variables
cat > "${BASE_DIR}/${NAME}/container.conf/.env" <<EOF
# tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo ''
TRAEFIK_HASH=${HASH}
TRAEFIK_PROJECT=nextcloud-${INSTANCE}
COMPOSE_PROJECT_NAME=nextcloud-${INSTANCE}
TRAEFIK_SERVICE_01=nextcloud
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
JWT_SECRET=${JWT_SECRET}
NEXTCLOUD_IMAGE=ghcr.io/hoellen/nextcloud
NEXTCLOUD_VERSION=${NEXTCLOUD_VERSION}
EOF

# Creating environment file for systemd
cat > "${BASE_DIR}/${NAME}/container.conf/environment.conf" <<EOF
[Service]
Environment="WORK_DIR=/srv/docker/nextcloud/${NAME}/"
WorkingDirectory=/srv/docker/nextcloud/${NAME}/
EOF

# Needed symlinks for systemd
ln -s ../../container.conf/nextcloud.service "${BASE_DIR}/${NAME}/container.conf/nextcloud-${NAME}.service"
ln -s "/srv/docker/nextcloud/${NAME}/container.conf/environment.conf" "/etc/systemd/system/nextcloud-${NAME}.service.d/environment.conf"
ln -s "${BASE_DIR}/${NAME}/container.conf/nextcloud-${NAME}.service" "/etc/systemd/system/nextcloud-${NAME}.service"

# Enable unitfiles
systemctl daemon-reload
systemctl enable "nextcloud-${NAME}"
