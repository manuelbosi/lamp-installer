#!/bin/bash

#### GLOBAL ####

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
    logger info "Stopping apache2 service if running"
    service apache2 stop > /dev/null
    logger info "Stopping mysql service if running"
    service mysql stop > /dev/null
    apt-get purge -y 'apache2*' 'mysql*' 'php*' 'phpmyadmin' > /dev/null
    rm -rf /etc/apache2/
    rm -rf /var/www/
    rm -rf /etc/mysql
    rm -rf /var/lib/mysql*
    rm -rf /etc/php/
    rm -rf /usr/share/phpMyAdmin* > /dev/null
    rm -rf /usr/share/phpmyadmin* > /dev/null
    rm -f /etc/apache2/conf-available/phpmyadmin.conf > /dev/null
}

update_repositories() {
    logger info "Updating repositories"
    apt-get update > /dev/null
}

add_ppa_repository () {
    add-apt-repository -y $1 > /dev/null 
}

remove_anonymous_users () {
    mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
    logger success "Anonymous users have been removed"
}

remove_remote_root () {
    mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    logger success "Remote root login has been disabled"
}

remove_test_db () {
    mysql -u root -e "DROP DATABASE IF EXISTS test;"
    logger success "Test database has been deleted"
}

flush_privileges () {
    mysql -u root -e "FLUSH PRIVILEGES;"
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

# Install dependencies
logger info "Installing script dependencies"
apt-get install -y software-properties-common net-tools > /dev/null

# Install apache
logger info "Adding latest apache2 repository"
add_ppa_repository ppa:ondrej/apache2
update_repositories
logger info "Installing apache2"
apt-get install -y apache2 > /dev/null
logger success "Apache has been installed"
logger info "Running apache2 service"
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
logger info "Running mysql service"
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

# Export mysql password environment variable
export MYSQL_PWD="$ROOT_PASSWORD"

# Update root password
if [ "$ROOT_PASSWORD" != '' ]
then
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '"$ROOT_PASSWORD"';"
    logger success "Root password has been changed"
    flush_privileges
else
    logger error "Root password cannot be empty"
    exit
fi

# Remove anonymous users
if [ "$REMOVE_ANONYMOUS_USER" = 'yes' ]
then
    remove_anonymous_users
fi

# Disable remote login on root user
if [ "$REMOVE_REMOTE_ROOT" = 'yes' ]
then
    remove_remote_root
fi

# Remove test database
if [ "$REMOVE_TEST_DB" = 'yes' ]
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
ip="$(ifconfig | grep -Eo '(addr:)?([0-9]*\.){3}[0-9]*' | head -1)"
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

cd "$OLDPWD"
phpmyadmin_conf=phpmyadmin.conf
if [ -f "$phpmyadmin_conf" ]
then
    logger success "phpMyAdmin apache configuration updated"
    cp "$phpmyadmin_conf" /etc/apache2/conf-available/
fi

# Create phpmyadmin database
logger info "Creating phpMyAdmin database configuration"
wget -q https://raw.githubusercontent.com/phpmyadmin/phpmyadmin/STABLE/sql/create_tables.sql
mysql -u root < create_tables.sql
rm create_tables.sql

# Delete mysql password environment variable
unset MYSQL_PWD

# Setup blowfish secret
blowfish_secret=''
if [ "$BLOWFISH_SECRET" != '' ]
then
    blowfish_secret="$BLOWFISH_SECRET"
else
    blowfish_secret=$(openssl rand -base64 32)
fi
sed -e "s|cfg\['blowfish_secret'\] = ''|cfg['blowfish_secret'] = '$blowfish_secret'|" /usr/share/phpmyadmin/config.sample.inc.php > /usr/share/phpmyadmin/config.inc.php
logger success "Blowfish secret updated"

# Enable phpmyadmin apache configuration
a2enconf phpmyadmin > /dev/null
logger success "phpMyAdmin configuration has been updated"
restart_service apache2