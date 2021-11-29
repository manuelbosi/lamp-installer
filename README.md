# LAMP INSTALLER

*DISCLAIMER:<br>
do not use the script in a production environment. The script is for development purposes.<br> Before installing the stack, the script delete all data of apache, mysql, php and phpmyadmin.*

## Usage
Clone this repository
```git
git clone https://github.com/manuelbosi/lamp-installer.git
```
Make the script executable
```shell
cd lamp-installer && chmod +x lamp-installer.sh
```

Edit .env file with your configuration
```.env
# PHP Configuration
PHP_VERSION=8.0

# MYSQL Configuration
ROOT_PASSWORD=root_user_password
REMOVE_ANONYMOUS_USER=yes
REMOVE_REMOTE_ROOT=yes
REMOVE_TEST_DB=yes

# PHPMYADMIN Configuration
PHPMYADMIN_VERSION=5.1.1
BLOWFISH_SECRET=
```

Run the script executable
```shell
sudo ./lamp-installer.sh
```

For more details on configuration check the .env file
