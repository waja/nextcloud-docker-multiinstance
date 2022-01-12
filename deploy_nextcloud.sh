#!/bin/bash
BASE_DIR="/srv/docker/nextcloud"

while [[ ! ${NAME} || -z "${NAME}" ]]; do
        read -p 'Hostname (<host>): ' NAME
done
HASH="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo '')"
MYSQL_ROOT_PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo '')"
MYSQL_PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo '')"
JWT_SECRET="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo '')"

# Provide symlink infrastructure for making use of global configurations

mkdir -p ${BASE_DIR}/${NAME}/container.conf /etc/systemd/system/nextcloud-${NAME}.service.d
for DIR in php-sessions logs/php logs/nginx apps config data themes; do
	mkdir -p ${BASE_DIR}/${NAME}/${DIR}
	chown 1000:1000 ${BASE_DIR}/${NAME}/${DIR}
done
ln -s ../../container.conf/update.sh ${BASE_DIR}/${NAME}/container.conf/update.sh
ln -s ../../container.conf/docker-compose.yml ${BASE_DIR}/${NAME}/container.conf/docker-compose.yml
ln -s container.conf/docker-compose.yml ${BASE_DIR}/${NAME}/
ln -s container.conf/.env ${BASE_DIR}/${NAME}

# Create instance specific docker-compose configuration
cat > ${BASE_DIR}/${NAME}/container.conf/production.yml <<EOF
# Inspired by https://github.com/Wonderfall/dockerfiles/tree/master/nextcloud#docker-compose-file
version: '3'

services:
  nextcloud:
    labels:
      - traefik.http.routers.\${TRAEFIK_PROJECT}-\${TRAEFIK_SERVICE_01}-\${TRAEFIK_HASH}.rule=Host(\`${NAME}\`)
      # v1.7
      - traefik.frontend.rule=Host:${NAME}
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
