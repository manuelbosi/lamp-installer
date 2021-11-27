#!/bin/bash

#### GLOBAL ####
ip="$(ifconfig | grep -Eo '(addr:)?([0-9]*\.){3}[0-9]*' | head -1)"

#### COLOR ####
INFO=$(tput setaf 6)
QUESTION=$(tput setaf 3)
ERROR=$(tput setaf 1)
SUCCESS=$(tput setaf 2)
NO_COLOR=$(tput sgr0)

### FUNCTIONS ###
logger () {
    case $1 in
    question)
        echo "${QUESTION}[?]${NO_COLOR} $2"
    ;;
    info)
        echo "${INFO}[i]${NO_COLOR} $2"
    ;;
    error)
        echo "${ERROR}[x]${NO_COLOR} $2"
    ;;
    success)
        echo "${SUCCESS}[v]${NO_COLOR} $2"
    ;;
    esac
}

remove_old_installations () {
    apt-get clean > /dev/null
    apt-get purge -y 'apache2*' 'mysql*' 'php*' 'phpmyadmin*' > /dev/null
    # rm -rf /etc/apache2
    # rm -rf /etc/mysql
    # rm -rf /var/lib/mysql
    # rm -rf /usr/share/phpMyAdmin* > /dev/null
    # rm -rf /usr/share/phpmyadmin* > /dev/null
    # rm -f /etc/apache2/conf-available/phpmyadmin.conf > /dev/null
}

update_repositories() {
    logger info "Updating repositories"
    apt-get update > /dev/null
}

add_ppa_repository () {
    add-apt-repository -y $1 > /dev/null 
}

remove_anonymous_users () {
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    logger success "Anonoymous users have been removed"
}

remove_remote_root () {
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    logger success "Remote root login has been disabled"
}

remove_test_db () {
    mysql -e "DROP DATABASE IF EXISTS test;"
    logger success "Test database has been deleted"
}

flush_privileges () {
    mysql -e "FLUSH PRIVILEGES;"
    logger success "Privileges have been reloaded"
}

start_service () {
    service "$1" start > /dev/null
}

restart_service () {
    service "$1" restart > /dev/null
}

### MAIN ###

# Check if the script is running as root
if [ $(id -u) -ne 0 ]
then
    logger error "Please run the script as root"
    exit
fi

# Export .env variables
if [ -f .env ]
then
    export $(cat .env | sed '/^#/d' | xargs)
else
    logger error ".env file not found"
    exit
fi

# Clean the system
logger info "Cleaning the system from previous installations"
remove_old_installations
update_repositories
logger success "System cleanup completed"

exit 

# Install dependencies
apt-get install -y software-properties-common > /dev/null

# Install apache
logger info "Adding latest apache2 repository"
add_ppa_repository ppa:ondrej/apache2
update_repositories
logger info "Installing apache2"
apt-get install -y apache2 > /dev/null
logger success "Apache has been installed"
logger info "Starting apache2 service"
start_service apache2
exit_status=$?

# Check exit status and log response
if [ "$exit_status" -eq 0 ]
then
    logger success "Apache2 service started"
else
    logger error "Cannot start apache2"
fi

# Install mysql (client and server)
logger info "Installing mysql"
apt-get install -y mysql-server mysql-client > /dev/null
logger success "Mysql has been installed"
logger info "Starting mysql service"
usermod -d /var/lib/mysql/ mysql > /dev/null
start_service mysql
exit_status=$?

# Check exit status and log response
if [ "$exit_status" -eq 0 ]
then
    logger success "Mysql service started"
else
    logger error "Cannot start mysql"
fi

## CONFIGURE MYSQL
# Update root password
if [ $ROOT_PASSWORD != '' ]
then
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '"$ROOT_PASSWORD"';"
    logger success "Root password has been changed"
    flush_privileges
else
    logger error "Root password cannot be empty"
    exit
fi

# Remove anonymous users
if [ $REMOVE_ANONYMOUS_USER = 'yes' ]
then
    remove_anonymous_users
fi

# Disable remote login on root user
if [ $REMOVE_REMOTE_ROOT = 'yes' ]
then
    remove_remote_root
fi

# Remove test database
if [ $REMOVE_TEST_DB = 'yes' ]
then
    remove_test_db
fi

# Reload privileges table
flush_privileges

# PHP Installation
logger info "Adding latest php repository"
sudo add-apt-repository -y ppa:ondrej/php > /dev/null
logger info "Updating repositories"
apt-get update > /dev/null
logger info "Installing php"
apt-get install -y php"$PHP_VERSION" > /dev/null
logger success "PHP has been installed"
logger info "Restarting apache2 service"
rm -rf /var/www/html/*
echo "<?php phpinfo(); ?>" > /var/www/html/index.php
restart_service apache2
exit_status=$?

# Check exit status and log response
if [ "$exit_status" -eq 0 ]
then
    logger success "Apache2 service restarted"
    logger info "Check if everything works fine here: $ip"
else
    logger error "Cannot start apache2"
fi

# PHPMYADMIN Installation
logger info "Installing phpMyAdmin dependencies"
apt-get install -y php"$PHP_VERSION"-mbstring php"$PHP_VERSION"-gettext php"$PHP_VERSION"-mysqli php"$PHP_VERSION"-xml > /dev/null
logger info "Downloading phpMyAdmin"
cd /usr/share/

# Download phpMyAdmin
phpMyAdminArchive=phpMyAdmin-"$PHPMYADMIN_VERSION"-all-languages.tar.gz
wget -q https://files.phpmyadmin.net/phpMyAdmin/"$PHPMYADMIN_VERSION"/"$phpMyAdminArchive"
exit_status=$?

# Check exit status and log response
if [ "$exit_status" -ne 0 ]
then
    logger error "Error while downloading phpMyAdmin"
    exit
fi

# Install
logger info "Installing phpMyAdmin"
tar -xf "$phpMyAdminArchive" > /dev/null
mv phpMyAdmin-"$PHPMYADMIN_VERSION"-all-languages phpmyadmin > /dev/null
rm -rf phpMyAdmin-"$PHPMYADMIN_VERSION"-all-languages
rm -rf "$phpMyAdminArchive"
chown -R www-data: phpmyadmin
chmod -R 744 phpmyadmin

logger success "phpMyAdmin has been installed"

phpmyadmin_conf="$OLDPWD"/phpmyadmin.conf
if [ -f "$phpmyadmin_conf" ]
then
    logger info "Updating phpMyAdmin configuration"
    # sed -i "s/IP_ADDRESS/$ip/" "$phpmyadmin_conf"
    cp "$phpmyadmin_conf" /etc/apache2/conf-available/
fi

a2enconf phpmyadmin > /dev/null
logger success "phpMyAdmin configuration has beed updated"
restart_service apache2