#!/bin/bash

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
    apt-get remove --purge -y 'apache2-*' > /dev/null
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
logger success "System cleanup completed"

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
service apache2 start > /dev/null
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
service mysql start > /dev/null
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