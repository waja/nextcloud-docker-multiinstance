#!/bin/bash
BASE_DIR="/srv/docker/nextcloud"

while [[ ! ${NAME} || -z "${NAME}" ]]; do
        read -p 'Hostname (<host>): ' NAME
done

# Provide symlink infrastructure for making use of global configrations
mkdir -p ${BASE_DIR}/${NAME}/container.conf /etc/systemd/system/nextcloud-${NAME}.service.d
ln -s ../../container.conf/update.sh ${BASE_DIR}/${NAME}/container.conf/update.sh
ln -s ../../container.conf/docker-compose.yml ${BASE_DIR}/${NAME}/container.conf/docker-compose.yml
ln -s ../../container.conf/.env ${BASE_DIR}/${NAME}/container.conf/.env
ln -s container.conf/docker-compose.yml ${BASE_DIR}/${NAME}/
ln -s container.conf/.env ${BASE_DIR}/${NAME}

# Create instance specific docker-compose configuration
cat > ${BASE_DIR}/${NAME}/container.conf/production.yml <<EOF
# Inspired by https://github.com/Wonderfall/dockerfiles/tree/master/nextcloud#docker-compose-file
version: '3'

services:
  nextcloud:
    labels:
      - traefik.frontend.rule=Host:${NAME}
    environment:
      - DOMAIN=${NAME}
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
