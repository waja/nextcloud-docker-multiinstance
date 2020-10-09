#!/bin/bash
DC="docker-compose"
DC_COMMAND="exec"
NEXTCLOUD_CONTAINER_NAME="nextcloud"
REDIS_CONTAINER_NAME="nextcloud-redis"
DC_CALL="${DC} ${DC_COMMAND} ${NEXTCLOUD_CONTAINER_NAME}"

config_redis() {
	echo "Configure Redis connection to ${REDIS_CONTAINER_NAME}:6379"
	${DC_CALL} occ config:system:set redis port --value=6379 --type=integer
	${DC_CALL} occ config:system:set redis host --value=${REDIS_CONTAINER_NAME} --type=string
	echo "Configure Memcache Backend to Redis"
	${DC_CALL} occ config:system:set memcache.distributed --value='\OC\Memcache\Redis' --type=string
	${DC_CALL} occ config:system:set memcache.locking --value='\OC\Memcache\Redis' --type=string
	${DC_CALL} occ config:system:set memcache.local --value='\OC\Memcache\APCu' --type=string
}

config_https() {
	echo "Configure https as default protocol"
	${DC_CALL} occ config:system:set overwriteprotocol --value=https --type=string
}

config_mail_domain() {
	TRUSTED_DOMAIN="$(${DC_CALL} occ config:system:get trusted_domains | head -1 | sed 's/\r$//g')"
	echo "Configure ${TRUSTED_DOMAIN} as mail domain"
	${DC_CALL} occ config:system:set mail_domain --value=${TRUSTED_DOMAIN}
}

show_help() {
	echo "Available options:"
	echo "--version - Show this application version"
	echo "--app-install <app-id> - Install an application"
	echo "--app-remove <app-id> - Remove an application"
	echo "--app-enable <app-id> - Enable an application"
	echo "--app-disable <app-id> - Disable an application"
	echo "--app-update <app-id> - Update an application"
	echo "--app-update-list - List available application updates"
	echo "--app-update-all - Update all application"
	echo "--app-update-help - Output of 'occ app:update --help'"
	echo "--app-list - List installed applications"
	echo "--app-list-shipped - List installed shipped applications"
	echo "--app-list-notshipped - List installed not shipped applications"
	echo "--configure-smtp-host - Configure SMTP server to $(hostname -f):25"
	echo "--configure-redis - Configure Memcache Backend to Redis"
	echo "--configure-https - Configure https as default protocol"
	echo "--configure-mail-domain - Configure mail domain to first trusted domain"
	echo "--bootstrap - Alias for --configure-redis, --configure-https and --configure-mail-domain"
}

check_arg() {
	if [ -z "$1" ]; then
		echo "Required argument not set"
		show_help
		exit 1
	fi
}

case "$1" in
	--version)
		echo "Application version:"
		${DC_CALL} occ app:update --version
		;;
	--app-install)
		check_arg "$2"
		echo "Installing app '$2':"
		${DC_CALL} occ app:install $2
		;;
	--app-remove)
		check_arg "$2"
		echo "Removing app '$2':"
		${DC_CALL} occ app:remove $2
		;;
	--app-enable)
		check_arg "$2"
		echo "Enabling '$2':"
		${DC_CALL} occ app:enable $2
		;;
	--app-disable)
		check_arg "$2"
		echo "Disabling '$2':"
		${DC_CALL} occ app:disable $2
		;;
        --app-update)
		check_arg "$2"
		echo "Updating '$2':"
		${DC_CALL} occ app:update $2
		;;
	--app-update-list)
		echo "Available app updates:"
		${DC_CALL} occ app:update --showonly
		;;
	--app-update-all)
		echo "Updating all apps:"
		${DC_CALL} occ app:update --all
		;;
	--app-update-help)
		echo "Output of 'occ app:update --help'"
		echo "you can run with '${DC_CALL} occ app:update --help':"
		${DC_CALL} occ app:update --help
		;;
	--app-list)
		echo "Installed app:"
		${DC_CALL} occ app:list
		;;
	--app-list-shipped)
		echo "Installed shipped app:"
		${DC_CALL} occ app:list --shipped=true
		;;
	--app-list-notshipped)
		echo "Installed not shipped app:"
		${DC_CALL} occ app:list --shipped=false
		;;
	--configure-smtp-host)
		echo "Configure SMTP server to $(hostname -f):25"
		${DC_CALL} occ config:system:set mail_smtpmode --value=smtp
		${DC_CALL} occ config:system:set mail_smtphost --value=$(hostname -f)
		${DC_CALL} occ config:system:set mail_smtpport --value=25
		;;
	--configure-redis)
		config_redis
		;;
	--configure-https)
		config_https
		;;
	--configure-mail-domain)
		config_mail_domain
		;;
	--bootstrap)
		config_redis
		config_https
		config_mail_domain
		;;
	*)
		show_help
		;;
esac
 
#docker-compose exec nextcloud occ app:update --showonly
