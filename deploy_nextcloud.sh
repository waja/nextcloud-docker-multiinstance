#!/bin/bash
BASE_DIR="/srv/docker/nextcloud"
NEXTCLOUD_VERSION=35

version_check() {
       local env_file current_version instance container_id container_state
       local line version_value version_count env_files found=0 error=0

       env_files="$(mktemp)" || {
               echo "ERROR: unable to create temporary file for version check." >&2
               return 1
       }

       if ! find "${BASE_DIR}" -mindepth 3 -maxdepth 3 \
               -path '*/container.conf/.env' -type f -print0 > "${env_files}"; then
               echo "ERROR: unable to scan ${BASE_DIR} for Nextcloud instances." >&2
               rm -f "${env_files}"
               return 1
       fi

       while IFS= read -r -d '' env_file; do
               if [[ ! -r "${env_file}" ]]; then
                       echo "ERROR: unable to read ${env_file}." >&2
                       error=1
                       continue
               fi

               current_version=""
               version_count=0
               while IFS= read -r line || [[ -n "${line}" ]]; do
                       if [[ "${line}" =~ ^[[:space:]]*NEXTCLOUD_VERSION[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                               version_value="${BASH_REMATCH[1]}"
                               version_value="$(printf '%s\n' "${version_value}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
                               if [[ "${version_value}" =~ ^\"([0-9]+)\"$ ]]; then
                                       version_value="${BASH_REMATCH[1]}"
                               elif [[ "${version_value}" =~ ^\\'([0-9]+)\\'$ ]]; then
                                       version_value="${BASH_REMATCH[1]}"
                               fi
                               current_version="${version_value}"
                               ((version_count += 1))
                       fi
               done < "${env_file}"

               if (( version_count != 1 )) || [[ ! "${current_version}" =~ ^[0-9]+$ ]]; then
                       echo "ERROR: ${env_file} must contain exactly one numeric NEXTCLOUD_VERSION." >&2
                       error=1
                       continue
               fi

               if (( 10#${current_version} >= NEXTCLOUD_VERSION )); then
                       continue
               fi

               instance="${env_file%/container.conf/.env}"
               if ! container_id="$(cd "${instance}" && /usr/local/bin/docker-compose \
                       -f docker-compose.yml \
                       -f container.conf/production.yml \
                       ps -q nextcloud)"; then
                       echo "ERROR: unable to query the Nextcloud container for ${instance##*/}." >&2
                       error=1
                       continue
               fi

               [[ -n "${container_id}" ]] || continue
               if ! container_state="$(docker inspect --format '{{.State.Status}}' "${container_id}")"; then
                       echo "ERROR: unable to inspect the Nextcloud container for ${instance##*/}." >&2
                       error=1
                       continue
               fi

               if [[ "${container_state}" == running ]]; then
                       echo "WARNING: ${instance##*/} is running Nextcloud ${current_version}; new deployments use Nextcloud ${NEXTCLOUD_VERSION}. No migration performed." >&2
                       found=1
               elif [[ ! "${container_state}" =~ ^(created|exited|dead)$ ]]; then
                       echo "ERROR: unexpected Nextcloud container state for ${instance##*/}: ${container_state}." >&2
                       error=1
               fi
       done < "${env_files}"

       rm -f "${env_files}"

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

while [[ ! ${NAME} || -z "${NAME}" ]]; do
        read -p 'Hostname (<host>): ' NAME
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

mkdir -p ${BASE_DIR}/${NAME}/container.conf /etc/systemd/system/nextcloud-${NAME}.service.d
for DIR in data/nextcloud/php-sessions data/nextcloud/logs/php data/nextcloud/logs/nginx data/nextcloud/apps data/nextcloud/config data/nextcloud/data data/nextcloud/themes; do
	mkdir -p ${BASE_DIR}/${NAME}/${DIR}
	chown 1000:1000 ${BASE_DIR}/${NAME}/${DIR}
done
for DIR in data/calcardbackup data/db-backups data/mysql data/redis; do
	mkdir -p ${BASE_DIR}/${NAME}/${DIR}
done
ln -s ../../container.conf/update.sh ${BASE_DIR}/${NAME}/container.conf/update.sh
ln -s ../../container.conf/docker-compose.yml ${BASE_DIR}/${NAME}/container.conf/docker-compose.yml
ln -s container.conf/docker-compose.yml ${BASE_DIR}/${NAME}/
ln -s container.conf/.env ${BASE_DIR}/${NAME}

# Create instance specific docker-compose configuration
cat > ${BASE_DIR}/${NAME}/container.conf/production.yml <<EOF
# Inspired by https://github.com/Wonderfall/dockerfiles/tree/master/nextcloud#docker-compose-file
services:
  nextcloud:
    labels:
      - traefik.http.routers.\${TRAEFIK_PROJECT}-\${TRAEFIK_SERVICE_01}-\${TRAEFIK_HASH}.rule=Host(\`${NAME}\`)
    environment:
      - DOMAIN=${NAME}
EOF

INSTANCE="$(echo ${NAME} | sed s/\\./_/g)"
# Create .env file with needed traefik variables
cat > ${BASE_DIR}/${NAME}/container.conf/.env <<EOF
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
cat > ${BASE_DIR}/${NAME}/container.conf/environment.conf <<EOF
[Service]
Environment="WORK_DIR=/srv/docker/nextcloud/${NAME}/"
WorkingDirectory=/srv/docker/nextcloud/${NAME}/
EOF

# Needed symlinks for systemd
ln ${BASE_DIR}/container.conf/nextcloud.service ${BASE_DIR}/${NAME}/container.conf/nextcloud-${NAME}.service
ln -s /srv/docker/nextcloud/${NAME}/container.conf/environment.conf /etc/systemd/system/nextcloud-${NAME}.service.d/environment.conf
ln -s ${BASE_DIR}/${NAME}/container.conf/nextcloud-${NAME}.service /etc/systemd/system/nextcloud-${NAME}.service

# Enable unitfiles
systemctl daemon-reload
systemctl stop nextcloud-${NAME} && systemctl enable nextcloud-${NAME}
