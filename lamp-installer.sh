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

### MAIN ###

# Check if the script is running as root
if [ $(id -u) -ne 0 ]
then
    logger error "Please run the script as root"
    exit
fi

# Clean system
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
logger success "Apache2 service started"
