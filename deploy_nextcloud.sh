#!/bin/bash
set -e

BASE_DIR="/srv/docker/nextcloud"
NEXTCLOUD_VERSION=35

version_check() {
       local config_dir instance env_file env_version container_ids container_id container_info container_state container_image image_reference image_version
       local instances found=0 error=0

       if ! command -v timeout >/dev/null 2>&1; then
               echo "ERROR: timeout is not available; cannot perform a bounded Docker check." >&2
               return 1
       fi

       instances="$(mktemp)" || {
               echo "ERROR: unable to create temporary file for version check." >&2
               return 1
       }

       if ! find "${BASE_DIR}" -mindepth 2 -maxdepth 2 -type d -name container.conf -print0 > "${instances}"; then
               echo "ERROR: unable to scan ${BASE_DIR} for Nextcloud instances." >&2
               rm -f "${instances}"
               return 1
       fi

       while IFS= read -r -d '' config_dir; do
               instance="${config_dir%/container.conf}"
               env_file="${config_dir}/.env"
               if [[ ! -r "${env_file}" ]]; then
                       echo "ERROR: unable to read ${env_file}." >&2
                       error=1
                       continue
               fi

               env_version="$(sed -n 's/^NEXTCLOUD_VERSION[[:space:]]*=[[:space:]]*//p' "${env_file}")"
               env_version="${env_version#\"}"
               env_version="${env_version%\"}"
               env_version="${env_version#\'}"
               env_version="${env_version%\'}"
               if [[ -z "${env_version//[[:space:]]/}" ]]; then
                       echo "ERROR: NEXTCLOUD_VERSION is missing or empty in ${env_file}." >&2
                       error=1
                       continue
               fi

               if ! container_ids="$(cd "${instance}" && env -u COMPOSE_PROJECT_NAME timeout --kill-after=5s 30s /usr/local/bin/docker-compose \
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
                                       found=1
                               fi
                       elif [[ ! "${container_state}" =~ ^(created|exited|dead)$ ]]; then
                               echo "ERROR: unexpected Nextcloud container state for ${instance##*/}: ${container_state}." >&2
                               error=1
                       fi
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

while [[ -z "${NAME:-}" ]]; do
        read -r -p 'Hostname (<host>): ' NAME
done

if (( ${#NAME} > 235 )) || [[ ! "${NAME}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]; then
        echo "ERROR: '${NAME}' is not a valid hostname or exceeds the 235-character systemd unit path limit." >&2
        exit 1
fi

# DNS hostnames are case-insensitive; use a stable lowercase instance/project name.
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

if [[ -e "${BASE_DIR}/${NAME}" || -L "${BASE_DIR}/${NAME}" ]]; then
        echo "ERROR: ${BASE_DIR}/${NAME} already exists; refusing to overwrite an existing or partially created instance." >&2
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
ln "${BASE_DIR}/container.conf/nextcloud.service" "${BASE_DIR}/${NAME}/container.conf/nextcloud-${NAME}.service"
ln -s "/srv/docker/nextcloud/${NAME}/container.conf/environment.conf" "/etc/systemd/system/nextcloud-${NAME}.service.d/environment.conf"
ln -s "${BASE_DIR}/${NAME}/container.conf/nextcloud-${NAME}.service" "/etc/systemd/system/nextcloud-${NAME}.service"

# Enable unitfiles
systemctl daemon-reload
systemctl enable "nextcloud-${NAME}"
