#!/bin/sh
# Example 
# sh phabricator-setup.sh sql_pass server_name smtp_host smtp_user smtp_pass
# sh phabricator-setup.sh password phabricator.codemaster.io smtp.mandrillapp.com forhadsustbd ljsouwoejrljwoerj

MYSQL_PASSWORD=${1}
SERVER_NAME=${2}
SMTP_HOST=${3}
SMTP_USER=${4}
SMTP_PASS=${5}

# Linux update
sudo apt-get -y update

# install vim
sudo apt-get -y install vim

# Apache install
sudo apt-get -y install apache2

# Surpresses Mysql password prompt
echo mysql-server-5.5 mysql-server/root_password password $MYSQL_PASSWORD | debconf-set-selections
echo mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASSWORD | debconf-set-selections

# Mysql install
sudo apt-get -y install mysql-server php5-mysql

# PHP install
sudo apt-get -y install php5 libapache2-mod-php5 php5-mcrypt php5-mysql php5-gd php5-dev php5-curl php-apc php5-cli php5-json php5-cgi

# Install bonus package
sudo apt-get -y install mercurial subversion python-pygments imagemagick

# Git install
sudo apt-get -y install git

# Git clone
cd /var/www
git clone https://github.com/phacility/libphutil.git
git clone https://github.com/phacility/arcanist.git
git clone https://github.com/phacility/phabricator.git

# Set users
sudo adduser phd --gecos "" --disabled-password --quiet
sudo adduser phd sudo --quiet
sudo adduser git --gecos "" --disabled-password --quiet

# Set permissions
sudo echo '
phd ALL=(ALL) SETENV: NOPASSWD: /var/www/phabricator
git ALL=(phd) SETENV: NOPASSWD: /usr/bin/git-upload-pack, /usr/bin/git-receive-pack, /usr/bin/hg, /usr/bin/svnserve
www-data ALL=(phd) SETENV: NOPASSWD: /usr/bin/git-upload-pack, /usr/lib/git-core/git-http-backend, /usr/bin/hg
 ' >> /etc/sudoers

# And create repo directory if phabricator will be hosting repos:
sudo mkdir /var/repo
sudo chown -R phd /var/repo
sudo chgrp -R phd /var/repo


# Enable mod_rewrite
sudo a2enmod rewrite
sudo service apache2 restart

# General settings phabricator
cd phabricator
./bin/config set mysql.user root
./bin/config set mysql.pass $MYSQL_PASSWORD
./bin/config set phabricator.base-uri 'http://'$SERVER_NAME'/'
./bin/config set phd.user phd
./bin/config set diffusion.ssh-user git
./bin/config set pygments.enabled true
./bin/config set diffusion.ssh-port 2222
./bin/config set account.minimum-password-length 6
./bin/storage upgrade --force

# Configuring webserver
sudo echo '<VirtualHost *:80>
        ServerName '$SERVER_NAME'
        ServerAdmin webmaster@'$SERVER_NAME'
        DocumentRoot /var/www/phabricator/webroot

        <Directory /var/www/phabricator/webroot/>
                Require all granted
        </Directory>

        RewriteEngine on
        RewriteRule ^/rsrc/(.*)     -                       [L,QSA]
        RewriteRule ^/favicon.ico   -                       [L,QSA]
        RewriteRule ^(.*)$          /index.php?__path__=$1  [B,L,QSA]

        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
' > /etc/apache2/sites-available/000-default.conf

sudo sed -i 's/^\(;\)\(date\.timezone\s*=\).*$/\2 \"Asia\/Dhaka\"/' /etc/php5/apache2/php.ini
sudo sed -i 's/^\(post_max_size\s*=\).*$/\1 32M/' /etc/php5/apache2/php.ini
sudo sed -i 's/^\(;\)\(opcache\.validate_timestamps\s*=\).*$/\20/' /etc/php5/apache2/php.ini

#sudo a2ensite phabricator
sudo service apache2 restart

# Configure mysql and storage:
sudo sed -i '/\[mysqld\]/a\#\n# * Phabricator settings\n#\ninnodb_buffer_pool_size=512M\nsql_mode=STRICT_ALL_TABLES\n' /etc/mysql/my.cnf
sudo sed -i 's/^\(max_allowed_packet\s*=\s*\).*$/\132M/' /etc/mysql/my.cnf
sudo service mysql restart
./bin/storage upgrade --force

# Make executable ssh hook for phabricator ssh daemon
cp /var/www/phabricator/resources/sshd/phabricator-ssh-hook.sh /usr/lib/phabricator-ssh-hook.sh
chown root /usr/lib/phabricator-ssh-hook.sh
chmod 755 /usr/lib/phabricator-ssh-hook.sh
sudo sed -i 's/^\(VCSUSER=\).*$/\1"git"/' /usr/lib/phabricator-ssh-hook.sh
sudo sed -i 's/^\(ROOT=\).*$/\1"\/var\/www\/phabricator"/' /usr/lib/phabricator-ssh-hook.sh

# Create phabricator ssh daemon on port 2222
cp /var/www/phabricator/resources/sshd/sshd_config.phabricator.example /etc/ssh/sshd_config.phabricator
# Edit AuthorizedKeysCommand, AuthorizedKeysCommandUser, and AllowUsers
sudo sed -i 's/^\(AuthorizedKeysCommand \).*$/\1\/usr\/lib\/phabricator-ssh-hook.sh/' /etc/ssh/sshd_config.phabricator
sudo sed -i 's/^\(AuthorizedKeysCommandUser \).*$/\1git/' /etc/ssh/sshd_config.phabricator
sudo sed -i 's/^\(AllowUsers \).*$/\1git/' /etc/ssh/sshd_config.phabricator
# Start the phabricator sshd
/usr/sbin/sshd -f /etc/ssh/sshd_config.phabricator

# Outbound email setup
./bin/config set metamta.mail-adapter 'PhabricatorMailImplementationPHPMailerAdapter'
./bin/config set phpmailer.smtp-host $SMTP_HOST
./bin/config set phpmailer.smtp-user $SMTP_USER
./bin/config set phpmailer.smtp-password $SMTP_PASS


# SSL configure [certbot.eff.org]
./bin/config set phabricator.base-uri 'https://'$SERVER_NAME'/'
sudo apt-get -y install software-properties-common
sudo add-apt-repository -y ppa:certbot/certbot
sudo apt-get -y update
sudo apt-get -y install python-certbot-apache 
sudo certbot --apache -d $SERVER_NAME

# Phabricator daemon start
# tmp dir create
sudo mkdir -p /var/tmp/phd
sudo chown phd:phd /var/tmp/phd
exec sudo -En -u phd -- ./bin/phd start

# Generating public/private rsa key pair.
ssh-keygen -t rsa -C "admin@example.com"

# Test
echo {} | ssh -p 2222 git@phabricator.codemaster.io conduit conduit.ping



