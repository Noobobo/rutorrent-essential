#!/bin/bash
#
# Script d'installation ruTorrent / Nginx
# Auteur : Ex_Rat
#
# Nécessite Debian 7 ou 8 (32/64 bits) & un serveur fraîchement installé
#
# Multi-utilisateurs
# Inclus VsFTPd (ftp & ftps sur le port 21), Fail2ban (avec conf nginx, ftp & ssh) & Proxy php
# Seedbox-Manager, Auteurs: Magicalex, Hydrog3n et Backtoback
#
# Tiré du tutoriel de Magicalex pour mondedie.fr disponible ici:
# http://mondedie.fr/viewtopic.php?id=5302
# Aide, support & plus si affinités à la même adresse ! http://mondedie.fr/
#
# Merci Aliochka & Meister pour les conf de Munin et VsFTPd
# à Albaret pour le coup de main sur# la gestion d'users et
# Jedediah pour avoir joué avec le html/css du thème
#
# Installation:
#
# apt-get update && apt-get upgrade -y
# apt-get install git-core -y
#
# cd /tmp
# git clone https://github.com/exrat/rutorrent-essential
# cd rutorrent-essential
# chmod a+x essential.sh && ./essential.sh
#
# Pour gérer vos utilisateurs ultérieurement, il vous suffit de relancer le script


# variables
CSI="\033["
CEND="${CSI}0m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"

RUTORRENT="/var/www/rutorrent"

LIBZEN0="0.4.31"
LIBMEDIAINFO0="0.7.74"
MEDIAINFO="0.7.74"
MULTIMEDIA="deb-multimedia-keyring_2015.6.1_all.deb"

# contrôle droits utilisateur
if [ "$(id -u)" -ne 0 ]; then
	echo ""
	echo -e "${CRED}                      Ce script doit être exécuté en root.${CEND}" 1>&2
	echo ""
	exit 1
fi

clear

# Contrôle installation
if [ ! -f /etc/nginx/sites-enabled/rutorrent.conf ]; then

# log de l'installation
exec > >(tee "/tmp/install.log")  2>&1

####################################
# lancement installation ruTorrent #
####################################

# message d'accueil
echo ""
echo -e "${CBLUE}          Bienvenue dans cette installation automatique de ruTorrent${CEND}"
echo ""

# logo
echo -e "${CBLUE}
                                      |          |_)         _|
            __ \`__ \   _ \  __ \   _\` |  _ \  _\` | |  _ \   |    __|
            |   |   | (   | |   | (   |  __/ (   | |  __/   __| |
           _|  _|  _|\___/ _|  _|\__,_|\___|\__,_|_|\___|_)_|  _|

${CEND}"
echo ""
echo -e "${CYELLOW}  Le premier utilisateur sera l'administrateur de Seedbox-Manager si installé,${CEND}"
echo -e "${CYELLOW}     vous pourrez ajouter d'autres utilisateurs à la fin de l'installation.${CEND}"
echo ""

# demande nom et mot de passe
while :; do
echo -e "${CGREEN}Entrez le nom du premier utilisateur (en minuscule): ${CEND}"
read TESTUSER
if [[ "$TESTUSER" =~ ^[a-z0-9]{3,}$ ]];then
	USER="$TESTUSER"
	break
else
	echo ""
	echo -e "${CRED}Le nom de votre utilisateur doit être en minuscule,\nde plus de 3 lettres et sans caratères spéciaux.${CEND}"
	echo ""
fi
done

# email admin seedbox-Manager
echo ""
while :; do
echo -e "${CGREEN}Entrez le mot de passe pour cet utilisateur, ou appuyez\nsur \"${CEND}${CYELLOW}Entrée${CEND}${CGREEN}\" pour en générer un automatiquement: ${CEND}"
read REPPWD
if [ "$REPPWD" = "" ]; then
	AUTOPWD=$(tr -dc "1-9a-nA-Np-zP-Z" < /dev/urandom | head -c 8)
	echo ""
    echo -e -n "${CGREEN}Voulez vous utiliser${CEND} ${CYELLOW}$AUTOPWD${CEND}${CGREEN} comme mot de passe ? (y/n): ${CEND}"
        read REPONSEPWD
        if [ "$REPONSEPWD" = "n" ] || [ "$REPONSEPWD" = "N" ]; then
		echo
        else
			PWD="$AUTOPWD"
			break
		fi

else
	if [[ "$REPPWD" =~ ^[a-zA-Z0-9]{6,}$ ]];then
		PWD="$REPPWD"
       	break
	else
		echo ""
		echo -e "${CRED}Le mot de passe ne doit pas contenir de caratères\nspéciaux et faire plus de 5 chiffres ou lettres.${CEND}"
		echo ""
	fi
fi
done
echo ""

PORT=5001

# choix installation vsftpd & seedbox-manager
echo ""
echo -n -e "${CGREEN}Voulez vous installer Seedbox-Manager (y/n): ${CEND}"
read SEEDBOXMANAGER

if [ "$SEEDBOXMANAGER" = "y" ] || [ "$SEEDBOXMANAGER" = "Y" ] || [ "$SEEDBOXMANAGER" = "o" ] || [ "$SEEDBOXMANAGER" = "O" ]; then
	while :; do
	echo -e "${CGREEN}Entrez l'email de contact qui apparaîtra dans Seedbox-Manager: ${CEND}"
	read INSTALLMAIL
	if [ "$INSTALLMAIL" = "" ]; then
		EMAIL=contact@exemple.com
		break
	else
		if [[ "$INSTALLMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]*$ ]];then
			EMAIL="$INSTALLMAIL"
			break
		else
			echo ""
			echo -e "${CRED}L'adresse mail n'est pas valide, merci de corrigez ou laissez vide.${CEND}"
			echo ""
		fi
	fi
done
fi

echo ""
echo -n -e "${CGREEN}Voulez vous installer un serveur FTP (y/n): ${CEND}"
read SERVFTP
echo ""

# récupération 5% root sur /home ou /home/user si présent
FS=$(df -h | grep /home/"$USER" | cut -c 6-9)

if [ "$FS" = "" ]; then
    FS=$(df -h | grep /home | cut -c 6-9)
	if [ "$FS" = "" ]; then
		echo
	else
        tune2fs -m 0 /dev/"$FS"
        mount -o remount /home
	fi
else
    tune2fs -m 0 /dev/"$FS"
    mount -o remount /home/"$USER"
fi

# variable passe nginx
PASSNGINX=${PWD}
echo ""

# ajout utilisateur
useradd -M -s /bin/bash "$USER"

# création du mot de passe utilisateur
echo "${USER}:${PWD}" | chpasswd

# anti-bug /home/user déjà existant
mkdir -p /home/"$USER"
chown -R "$USER":"$USER" /home/"$USER"

# variable utilisateur majuscule
USERMAJ=$(echo "$USER" | tr "[:lower:]" "[:upper:]")

# récupération IP serveur
IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}' | head -1)
if [ "$IP" = "" ]; then
	IP=$(wget -qO- ipv4.icanhazip.com)
fi

# récupération threads & sécu -j illimité
THREAD=$(grep -c processor < /proc/cpuinfo)
if [ "$THREAD" = "" ]; then
    THREAD=1
fi

# modification DNS
rm /etc/resolv.conf && touch /etc/resolv.conf
cat <<'EOF' >  /etc/resolv.conf
nameserver 127.0.0.1
nameserver 208.67.220.220
nameserver 208.67.222.222
EOF

# contrôle version debian
VERSION=$(cat /etc/debian_version)

cd /tmp

if [[ $VERSION =~ 7. ]]; then

# ajout des dépots debian 7
echo "#dépôt paquet propriétaire
deb http://ftp2.fr.debian.org/debian/ wheezy main non-free
deb-src http://ftp2.fr.debian.org/debian/ wheezy main non-free" >> /etc/apt/sources.list.d/non-free.list

echo "# dépôt dotdeb php 5.6
deb http://packages.dotdeb.org wheezy-php56 all
deb-src http://packages.dotdeb.org wheezy-php56 all" >> /etc/apt/sources.list.d/dotdeb-php56.list

echo "# dépôt nginx
deb http://nginx.org/packages/debian/ wheezy nginx
deb-src http://nginx.org/packages/debian/ wheezy nginx ">> /etc/apt/sources.list.d/nginx.list

# ajout des clés

# dotdeb
wget http://www.dotdeb.org/dotdeb.gpg
apt-key add dotdeb.gpg

# nginx
wget http://nginx.org/keys/nginx_signing.key
apt-key add nginx_signing.key

elif [[ $VERSION =~ 8. ]]; then

# ouverture root "coucou les poneys"
sed -i "s/PermitRootLogin no/PermitRootLogin yes/g;" /etc/ssh/sshd_config
systemctl restart sshd.service

# ajout des dépots debian 8
echo "#dépôt paquet propriétaire
deb http://ftp2.fr.debian.org/debian/ jessie main non-free
deb-src http://ftp2.fr.debian.org/debian/ jessie main non-free" >> /etc/apt/sources.list.d/non-free.list

echo "# dépôt dotdeb
deb http://packages.dotdeb.org jessie all
deb-src http://packages.dotdeb.org jessie all" >> /etc/apt/sources.list.d/dotdeb.list

echo "# dépôt multimedia
deb http://www.deb-multimedia.org jessie main non-free" >> /etc/apt/sources.list.d/multimedia.list

# ajout des clés

# dotdeb
wget http://www.dotdeb.org/dotdeb.gpg
apt-key add dotdeb.gpg

# ffmpeg
wget http://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/"$MULTIMEDIA"
dpkg -i "$MULTIMEDIA"

else
	echo -e "${CRED}          Ce script doit être exécuté sur Debian 7 ou 8 exclusivement.${CEND}" 1>&2
	echo ""
	exit 1
fi

# installation des paquets
apt-get update && apt-get upgrade -y
echo ""
echo -e "${CBLUE}Mise à jour du serveur${CEND}     ${CGREEN}Done !${CEND}"
echo ""

apt-get install -y htop openssl apt-utils python build-essential libssl-dev pkg-config automake libcppunit-dev libtool whois libcurl4-openssl-dev libsigc++-2.0-dev libncurses5-dev nginx vim nano ccze screen subversion apache2-utils curl php5 php5-cli php5-fpm php5-curl php5-geoip unrar rar zip buildtorrent fail2ban ntp ntpdate ffmpeg aptitude

echo ""
echo -e "${CBLUE}Installation des paquets essentiels${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# génération clè 2048 bits
openssl dhparam -out dhparams.pem 2048 &

# téléchargement complément favicon
wget http://www.bonobox.net/script/favicon.tar.gz
tar xzfv favicon.tar.gz

# Config ntp & réglage heure fr
echo "Europe/Paris" > /etc/timezone
cp /usr/share/zoneinfo/Europe/Paris /etc/localtime

sed -i "s/server 0/#server 0/g;" /etc/ntp.conf
sed -i "s/server 1/#server 1/g;" /etc/ntp.conf
sed -i "s/server 2/#server 2/g;" /etc/ntp.conf
sed -i "s/server 3/#server 3/g;" /etc/ntp.conf

echo "
server 0.fr.pool.ntp.org
server 1.fr.pool.ntp.org
server 2.fr.pool.ntp.org
server 3.fr.pool.ntp.org">> /etc/ntp.conf

ntpdate -d 0.fr.pool.ntp.org

# installation XMLRPC LibTorrent rTorrent
svn checkout http://svn.code.sf.net/p/xmlrpc-c/code/stable xmlrpc-c
cd xmlrpc-c
./configure --disable-cplusplus
make -j $THREAD
make install
cd ..
rm -rv xmlrpc-c
echo ""
echo -e "${CBLUE}Installation XMLRPC${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# clone rTorrent et libTorrent
git clone https://github.com/rakshasa/libtorrent.git
git clone https://github.com/rakshasa/rtorrent.git

# libTorrent compilation
cd libtorrent
git checkout 0.13.4
./autogen.sh
./configure
make -j $THREAD
make install
echo ""
echo -e "${CBLUE}Installation libTorrent${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# rTorrent compilation
cd ../rtorrent
git checkout 0.9.4
./autogen.sh
./configure --with-xmlrpc-c
make -j $THREAD
make install
ldconfig
echo ""
echo -e "${CBLUE}Installation rTorrent${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# création des dossiers
su "$USER" -c 'mkdir -p ~/watch ~/torrents ~/.session '

# création accueil serveur
mkdir -p /var/www
cp -R /tmp/rutorrent-essential/base /var/www/base

# téléchargement et déplacement de rutorrent
git clone https://github.com/Novik/ruTorrent.git "$RUTORRENT"

echo ""
echo -e "${CBLUE}Installation ruTorrent${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# installation des Plugins
cd "$RUTORRENT"/plugins

# logoff
cp -R /tmp/rutorrent-essential/plugins/logoff "$RUTORRENT"/plugins/logoff

# chat
cp -R /tmp/rutorrent-essential/plugins/chat "$RUTORRENT"/plugins/chat

# tadd-labels
cp -R /tmp/rutorrent-essential/plugins/lbll-suite "$RUTORRENT"/plugins/lbll-suite

# nfo
cp -R /tmp/rutorrent-essential/plugins/nfo "$RUTORRENT"/plugins/nfo

# ruTorrentMobile (voir init.js)
git clone https://github.com/xombiemp/rutorrentMobile.git mobile

# filemanager
cp -R /tmp/rutorrent-essential/plugins/filemanager "$RUTORRENT"/plugins/filemanager

# filemanager config
cat <<'EOF' >  "$RUTORRENT"/plugins/filemanager/conf.php
<?php
$fm['tempdir'] = '/tmp';		// path were to store temporary data ; must be writable
$fm['mkdperm'] = 755;			// default permission to set to new created directories

// set with fullpath to binary or leave empty
$pathToExternals['rar'] = '/usr/bin/rar';
$pathToExternals['zip'] = '/usr/bin/zip';
$pathToExternals['unzip'] = '/usr/bin/unzip';
$pathToExternals['tar'] = '/bin/tar';
$pathToExternals['gzip'] = '/bin/gzip';
$pathToExternals['bzip2'] = '/bin/bzip2';

// archive mangling, see archiver man page before editing

$fm['archive']['types'] = array('rar', 'zip', 'tar', 'gzip', 'bzip2');




$fm['archive']['compress'][0] = range(0, 5);
$fm['archive']['compress'][1] = array('-0', '-1', '-9');
$fm['archive']['compress'][2] = $fm['archive']['compress'][3] = $fm['archive']['compress'][4] = array(0);

?>
EOF

# configuration du plugin create
sed -i "s#$useExternal = false;#$useExternal = 'buildtorrent';#" "$RUTORRENT"/plugins/create/conf.php
sed -i "s#$pathToCreatetorrent = '';#$pathToCreatetorrent = '/usr/bin/buildtorrent';#" "$RUTORRENT"/plugins/create/conf.php

# fileshare
cd "$RUTORRENT"/plugins
cp -R /tmp/rutorrent-essential/plugins/fileshare "$RUTORRENT"/plugins/fileshare
chown -R www-data:www-data "$RUTORRENT"/plugins/fileshare
ln -s "$RUTORRENT"/plugins/fileshare/share.php /var/www/base/share.php

# configuration share.php
cat <<'EOF' >  "$RUTORRENT"/plugins/fileshare/conf.php
<?php

// limits
// 0 = unlimited
$limits['duration'] = 200;		// maximum duration hours
$limits['links'] = 0;			//maximum sharing links per user

// path on domain where a symlink to share.php can be found
// example: http://mydomain.com/share.php
$downloadpath = 'http://@IP@/share.php';

?>
EOF
sed -i "s/@IP@/$IP/g;" "$RUTORRENT"/plugins/fileshare/conf.php

# favicons trackers
cp /tmp/favicon/*.png "$RUTORRENT"/plugins/tracklabels/trackers/

# ratiocolor
cp -R /tmp/rutorrent-essential/plugins/ratiocolor "$RUTORRENT"/plugins/ratiocolor

# pausewebui
cp -R /tmp/rutorrent-essential/plugins/pausewebui "$RUTORRENT"/plugins/pausewebui

# configuration logoff
sed -i "s/scars,user1,user2/$USER/g;" "$RUTORRENT"/plugins/logoff/conf.php

echo ""

# mediainfo
if [[ $(uname -m) == i686 ]]; then
	SYS="i386"
elif [[ $(uname -m) == x86_64 ]]; then
	SYS="amd64"
fi

wget http://mediaarea.net/download/binary/libzen0/"$LIBZEN0"/libzen0_"$LIBZEN0"-1_"$SYS".Debian_7.0.deb
wget http://mediaarea.net/download/binary/libmediainfo0/"$LIBMEDIAINFO0"/libmediainfo0_"$LIBMEDIAINFO0"-1_"$SYS".Debian_7.0.deb
wget http://mediaarea.net/download/binary/mediainfo/"$MEDIAINFO"/mediainfo_"$MEDIAINFO"-1_"$SYS".Debian_7.0.deb

dpkg -i libzen0_"$LIBZEN0"-1_"$SYS".Debian_7.0.deb
dpkg -i libmediainfo0_"$LIBMEDIAINFO0"-1_"$SYS".Debian_7.0.deb
dpkg -i mediainfo_"$MEDIAINFO"-1_"$SYS".Debian_7.0.deb

echo -e "${CBLUE}Installation des plugins${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# liens symboliques et permissions
ldconfig
chown -R www-data:www-data "$RUTORRENT"
chmod -R 777 "$RUTORRENT"/plugins/filemanager/scripts
chown -R www-data:www-data /var/www/base

# php
sed -i "s/2M/10M/g;" /etc/php5/fpm/php.ini
sed -i "s/8M/10M/g;" /etc/php5/fpm/php.ini
sed -i "s/expose_php = On/expose_php = Off/g;" /etc/php5/fpm/php.ini
sed -i "s/^;date.timezone =/date.timezone = Europe\/Paris/g;" /etc/php5/fpm/php.ini

sed -i "s/^;listen.owner = www-data/listen.owner = www-data/g;" /etc/php5/fpm/pool.d/www.conf
sed -i "s/^;listen.group = www-data/listen.group = www-data/g;" /etc/php5/fpm/pool.d/www.conf
sed -i "s/^;listen.mode = 0660/listen.mode = 0660/g;" /etc/php5/fpm/pool.d/www.conf

service php5-fpm restart
echo ""
echo -e "${CBLUE}Configuration PHP${CEND}     ${CGREEN}Done !${CEND}"
echo ""

mkdir -p /etc/nginx/passwd /etc/nginx/ssl
touch /etc/nginx/passwd/rutorrent_passwd
chmod 640 /etc/nginx/passwd/rutorrent_passwd

# configuration serveur web

# nginx.conf
cat <<'EOF' >  /etc/nginx/nginx.conf
user www-data;
worker_processes auto;

pid /var/run/nginx.pid;
events { worker_connections 1024; }

http {
	include /etc/nginx/mime.types;
	default_type  application/octet-stream;

	access_log /var/log/nginx/access.log combined;
	error_log /var/log/nginx/error.log error;

	sendfile on;
	keepalive_timeout 20;
	keepalive_disable msie6;
	keepalive_requests 100;
	tcp_nopush on;
	tcp_nodelay off;
	server_tokens off;

	gzip on;
	gzip_buffers 16 8k;
	gzip_comp_level 5;
	gzip_disable "msie6";
	gzip_min_length 20;
	gzip_proxied any;
	gzip_types text/plain text/css application/json  application/x-javascript text/xml application/xml application/xml+rss  text/javascript;
	gzip_vary on;

	include /etc/nginx/sites-enabled/*.conf;
}
EOF

# php
cat <<'EOF' >  /etc/nginx/conf.d/php.conf
location ~ \.php$ {
	fastcgi_index index.php;
	fastcgi_pass unix:/var/run/php5-fpm.sock;
	fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
	include /etc/nginx/fastcgi_params;
}
EOF

# cache
cat <<'EOF' > /etc/nginx/conf.d/cache.conf
location ~* \.(jpg|jpeg|gif|css|png|js|woff|ttf|svg|eot)$ {
	expires 30d;
	access_log off;
}

location ~* \.(eot|ttf|woff|svg)$ {
	add_header Acccess-Control-Allow-Origin *;
}
EOF

# ciphers
cat <<'EOF' > /etc/nginx/conf.d/ciphers.conf
ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
ssl_prefer_server_ciphers on;
ssl_dhparam /etc/nginx/ssl/dhparams.pem;
EOF

# configuration du vhost
mkdir /etc/nginx/sites-enabled
touch /etc/nginx/sites-enabled/rutorrent.conf

# rutorrent.conf
cat <<'EOF' >  /etc/nginx/sites-enabled/rutorrent.conf
server {
	listen 80 default_server;
	listen 443 default_server ssl;
	server_name _;

	index index.html index.php;
	charset utf-8;
	client_max_body_size 10M;

	ssl_certificate /etc/nginx/ssl/server.crt;
	ssl_certificate_key /etc/nginx/ssl/server.key;

	include /etc/nginx/conf.d/ciphers.conf;

	access_log /var/log/nginx/rutorrent-access.log combined;
	error_log /var/log/nginx/rutorrent-error.log error;

	error_page 500 502 503 504 /50x.html;
	location = /50x.html { root /usr/share/nginx/html; }

	auth_basic "seedbox";
	auth_basic_user_file "/etc/nginx/passwd/rutorrent_passwd";

	location = /favicon.ico {
		access_log off;
		log_not_found off;
	}

	## début config accueil serveur ##

	location ^~ / {
	    root /var/www/base;
	    include /etc/nginx/conf.d/php.conf;
	    include /etc/nginx/conf.d/cache.conf;
	    satisfy any;
	    allow all;
	}

	## fin config accueil serveur ##

	## début config rutorrent ##

	location ^~ /rutorrent {
	    root /var/www;
	    include /etc/nginx/conf.d/php.conf;
	    include /etc/nginx/conf.d/cache.conf;

	    location ~ /\.svn {
		    deny all;
	    }

	    location ~ /\.ht {
		    deny all;
	    }
	}

	location ^~ /rutorrent/conf/ {
		deny all;
	}

	location ^~ /rutorrent/share/ {
		deny all;
	}

	## fin config rutorrent ##

EOF
echo ""
echo -e "${CBLUE}Configuration Nginx${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# ssl configuration #

#!/bin/bash

openssl req -new -x509 -days 3658 -nodes -newkey rsa:2048 -out /etc/nginx/ssl/server.crt -keyout /etc/nginx/ssl/server.key<<EOF
RU
Russia
Moskva
wtf
wtf LTD
wtf.org
contact@wtf.org
EOF

rm -R /var/www/html
rm /etc/nginx/sites-enabled/default

# installation Seedbox-Manager
if [ "$SEEDBOXMANAGER" = "y" ] || [ "$SEEDBOXMANAGER" = "Y" ] || [ "$SEEDBOXMANAGER" = "o" ] || [ "$SEEDBOXMANAGER" = "O" ]; then

## composer
cd /tmp
curl -s http://getcomposer.org/installer | php
mv /tmp/composer.phar /usr/bin/composer
chmod +x /usr/bin/composer
echo ""
echo -e "${CBLUE}Installation de Composer${CEND}     ${CGREEN}Done !${CEND}"
echo ""

curl -sL https://deb.nodesource.com/setup | bash -
apt-get update && apt-get install -y nodejs
echo ""
echo -e "${CBLUE}Installation de Nodejs${CEND}     ${CGREEN}Done !${CEND}"
echo ""

## bower
npm install -g bower
echo ""
echo -e "${CBLUE}Installation de bower${CEND}     ${CGREEN}Done !${CEND}"
echo ""

## app
cd /var/www
composer create-project magicalex/seedbox-manager
cd seedbox-manager
bower install --allow-root --config.interactive=false
chown -R www-data:www-data /var/www/seedbox-manager
## conf app
cd source-reboot-rtorrent
chmod +x install.sh
./install.sh

cat <<'EOF' >  /etc/nginx/conf.d/php-manager.conf
location ~ \.php$ {
    root /var/www/seedbox-manager/public;
    include /etc/nginx/fastcgi_params;
    fastcgi_index index.php;
    fastcgi_pass unix:/var/run/php5-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $document_root/index.php;
}

EOF

echo "        ## début config seedbox-manager ##

        location ^~ /seedbox-manager {
            alias /var/www/seedbox-manager/public;
            include /etc/nginx/conf.d/php-manager.conf;
            include /etc/nginx/conf.d/cache.conf;
        }

        ## fin config seedbox-manager ##">> /etc/nginx/sites-enabled/rutorrent.conf

## conf user
cd /var/www/seedbox-manager/conf/users
mkdir "$USER"

cat <<'EOF' >  /var/www/seedbox-manager/conf/users/"$USER"/config.ini
; Manager de seedbox (adapté pour le tuto de mondedie.fr)
;
; Fichier de configuration :
; yes ou no pour activer les modules
; Si vous n'avez pas de nom de domaine, indiquez l'ip (ex: http://XX.XX.XX.XX/rutorrent)

[user]
active_bloc_info = yes
user_directory = "/"
scgi_folder = "/RPC1"
theme = "default"
owner = yes

[nav]
data_link = "url = ../rutorrent/, name = rutorrent"

[ftp]
active_ftp = yes
port_ftp = "21"
port_sftp = "22"

[rtorrent]
active_reboot = yes

[support]
active_support = yes
adresse_mail = "contact@mail.com"

[logout]
url_redirect = "http://mondedie.fr"

EOF
sed -i "s/\"\/\"/\"\/home\/$USER\"/g;" /var/www/seedbox-manager/conf/users/"$USER"/config.ini
sed -i "s/RPC1/$USERMAJ/g;" /var/www/seedbox-manager/conf/users/"$USER"/config.ini
sed -i "s/contact@mail.com/$EMAIL/g;" /var/www/seedbox-manager/conf/users/"$USER"/config.ini

# verrouillage option parametre seedbox-manager
rm /var/www/seedbox-manager/public/themes/default/template/header.html
cat <<'EOF' >  /var/www/seedbox-manager/public/themes/default/template/header.html
<div class="container">
    <div class="navbar-header">
        <button type="button" class="navbar-toggle" data-toggle="collapse" data-target=".phone-menu">
            <span class="sr-only">Toggle navigation</span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
        </button>
        <a class="navbar-brand" href="index.php">Seedbox Manager</a>
    </div>
    <nav class="collapse navbar-collapse phone-menu">
        <ul class="nav navbar-nav">
        {% for link in user.get_all_links %}
            <li class="nav-link"><a href="{{ link.url }}">{{ link.name }}</a></li>
        {% endfor %}
        </ul>
        <ul class="nav navbar-nav navbar-right">
            <li class="dropdown">
                <a href="#" class="dropdown-toggle user" data-toggle="dropdown"><i class="glyphicon glyphicon-user"></i> {{ userName }} <b class="caret"></b></a>
                <ul class="dropdown-menu">
                    {% if user.is_owner == true %}
                    <li><a href="?option"><i class="glyphicon glyphicon-wrench"></i> Paramètres</a></li>
                    <li><a href="?admin"><i class="glyphicon glyphicon-cog"></i> Administration</a></li>
                    {% endif %}
                    <li><a class="aboutlink" data-toggle="modal" href="#popupinfo"><i class="glyphicon glyphicon-info-sign"></i> A propos</a></li>
                    <li>
                        <a id="logout" href="#logout" title="Se déconnecter" data-host="{{ host }}" data-urlredirect="{{ serveur.logout_url_redirect }}">
                            <strong><i class="glyphicon glyphicon-log-out"></i> Déconnexion</strong>
                        </a>
                    </li>
                </ul>
            </li>
        </ul>
    </nav>
</div>

EOF

chown -R www-data:www-data /var/www/seedbox-manager/conf/users
chown -R www-data:www-data /var/www/seedbox-manager/public/themes/default/template/header.html

# plugin seedbox-manager
cd "$RUTORRENT"/plugins
git clone https://github.com/Hydrog3n/linkseedboxmanager.git
sed -i "2i\$host = \$_SERVER['HTTP_HOST'];\n" "$RUTORRENT"/plugins/linkseedboxmanager/conf.php
sed -i "s/http:\/\/seedbox-manager.ndd.tld/\/\/'. \$host .'\/seedbox-manager\//g;" "$RUTORRENT"/plugins/linkseedboxmanager/conf.php

echo ""
echo -e "${CBLUE}Installation de Seedbox-Manager${CEND}     ${CGREEN}Done !${CEND}"
echo ""
fi

# logrotate
rm /etc/logrotate.d/nginx && touch /etc/logrotate.d/nginx
cat <<'EOF' >  /etc/logrotate.d/nginx
/var/log/nginx/*.log {
	daily
	missingok
	rotate 7
	compress
	delaycompress
	notifempty
	create 640 root
	sharedscripts
		postrotate
			[ -f /var/run/nginx.pid ] && kill -USR1 `cat /var/run/nginx.pid`
	endscript
}
EOF

# ssh config
sed -i "s/Subsystem[[:blank:]]sftp[[:blank:]]\/usr\/lib\/openssh\/sftp-server/Subsystem sftp internal-sftp/g;" /etc/ssh/sshd_config
sed -i "s/UsePAM/#UsePAM/g;" /etc/ssh/sshd_config

# chroot user
echo "Match User $USER
ChrootDirectory /home/$USER">> /etc/ssh/sshd_config

# .rtorrent.rc conf
cat <<'EOF' >  /home/"$USER"/.rtorrent.rc
scgi_port = 127.0.0.1:5001
encoding_list = UTF-8
port_range = 45000-65000
port_random = no
check_hash = no
directory = /home/@USER@/torrents
session = /home/@USER@/.session
encryption = allow_incoming, try_outgoing, enable_retry
schedule = watch_directory,1,1,"load_start=/home/@USER@/watch/*.torrent"
schedule = untied_directory,5,5,"stop_untied=/home/@USER@/watch/*.torrent"
schedule = espace_disque_insuffisant,1,30,close_low_diskspace=500M
use_udp_trackers = yes
dht = off
peer_exchange = no
min_peers = 40
max_peers = 100
min_peers_seed = 10
max_peers_seed = 50
max_uploads = 15
execute = {sh,-c,/usr/bin/php @RUTORRENT@/php/initplugins.php @USER@ &}
EOF
sed -i "s/@USER@/$USER/g;" /home/"$USER"/.rtorrent.rc
sed -i "s|@RUTORRENT@|$RUTORRENT|;" /home/"$USER"/.rtorrent.rc

# permissions
chown -R "$USER":"$USER" /home/"$USER"
chown root:"$USER" /home/"$USER"
chmod 755 /home/"$USER"

# user rtorrent.conf config
echo "
        location /$USERMAJ {
            include scgi_params;
            scgi_pass 127.0.0.1:5001; #ou socket : unix:/home/username/.session/username.socket
            auth_basic \"seedbox\";
            auth_basic_user_file \"/etc/nginx/passwd/rutorrent_passwd_$USER\";
        }
}">> /etc/nginx/sites-enabled/rutorrent.conf

mkdir "$RUTORRENT"/conf/users/"$USER"

# config.php
cat <<'EOF' >  "$RUTORRENT"/conf/users/"$USER"/config.php
<?php
$pathToExternals = array(
    "curl"  => '/usr/bin/curl',
    "stat"  => '/usr/bin/stat',
    );
$topDirectory = '/home/@USER@';
$scgi_port = 5001;
$scgi_host = '127.0.0.1';
$XMLRPCMountPoint = '/@USERMAJ@';
EOF
sed -i "s/@USER@/$USER/g;" "$RUTORRENT"/conf/users/"$USER"/config.php
sed -i "s/@USERMAJ@/$USERMAJ/g;" "$RUTORRENT"/conf/users/"$USER"/config.php

# plugin.ini
cat <<'EOF' >  "$RUTORRENT"/conf/users/"$USER"/plugins.ini
[default]
enabled = user-defined
canChangeToolbar = yes
canChangeMenu = yes
canChangeOptions = yes
canChangeTabs = yes
canChangeColumns = yes
canChangeStatusBar = yes
canChangeCategory = yes
canBeShutdowned = yes
[ipad]
enabled = no
[httprpc]
enabled = no
[retrackers]
enabled = no
[rpc]
enabled = no
[rutracker_check]
enabled = no
[chat]
enabled = no
EOF

# script rtorrent
cat <<'EOF' >  /etc/init.d/"$USER"-rtorrent
#!/usr/bin/env bash

# Dépendance : screen, killall et rtorrent
### BEGIN INIT INFO
# Provides:          @USER@-rtorrent
# Required-Start:    $syslog $network
# Required-Stop:     $syslog $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Start-Stop rtorrent user session
### END INIT INFO

## Début configuration ##
user="@USER@"
## Fin configuration ##

rt_start() {
    su --command="screen -dmS ${user}-rtorrent rtorrent" "${user}"
}

rt_stop() {
    killall --user "${user}" screen
}

case "$1" in
start) echo "Starting rtorrent..."; rt_start
    ;;
stop) echo "Stopping rtorrent..."; rt_stop
    ;;
restart) echo "Restart rtorrent..."; rt_stop; sleep 1; rt_start
    ;;
*) echo "Usage: $0 {start|stop|restart}"; exit 1
    ;;
esac
exit 0
EOF

sed -i "s/@USER@/$USER/g;" /etc/init.d/"$USER"-rtorrent

# configuration script rtorrent
chmod +x /etc/init.d/"$USER"-rtorrent
update-rc.d "$USER"-rtorrent defaults

# démarrage de rtorrent
/etc/init.d/"$USER"-rtorrent start

# htpasswd
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd "$USER" "${PASSNGINX}"
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd_"$USER" "$USER" "${PASSNGINX}"
chmod 640 /etc/nginx/passwd/*
chown -c www-data:www-data /etc/nginx/passwd/*

echo ""
echo -e "${CBLUE}Configuration utilisateur ruTorrent${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# conf fail2ban
cat <<'EOF' >  /etc/fail2ban/filter.d/nginx-auth.conf
## FICHIER /etc/fail2ban/filter.d/nginx-auth.conf ##
[Definition]

failregex = no user/password was provided for basic authentication.*client: <HOST>
            user .* was not found in.*client: <HOST>
            user .* password mismatch.*client: <HOST>

ignoreregex =
EOF

cat <<'EOF' >  /etc/fail2ban/filter.d/nginx-badbots.conf
# Fail2Ban configuration file nginx-badbots.conf
# Author: Patrik 'Sikevux' Greco <sikevux@sikevux.se>

[Definition]

# Option: failregex
# Notes.: regex to match access attempts to setup.php
# Values: TEXT

failregex = ^<HOST> .*?"GET.*?\/setup\.php.*?" .*?

# Anti w00tw00t
            ^<HOST> .*?"GET .*w00tw00t.* 404

# try to access to directory
            ^<HOST> .*?"GET .*admin.* 403
            ^<HOST> .*?"GET .*admin.* 404
            ^<HOST> .*?"GET .*install.* 404
            ^<HOST> .*?"GET .*dbadmin.* 404
            ^<HOST> .*?"GET .*myadmin.* 404
            ^<HOST> .*?"GET .*MyAdmin.* 404
            ^<HOST> .*?"GET .*mysql.* 404
            ^<HOST> .*?"GET .*websql.* 404
            ^<HOST> .*?"GET .*webdb.* 404
            ^<HOST> .*?"GET .*webadmin.* 404
            ^<HOST> .*?"GET \/pma\/.* 404
            ^<HOST> .*?"GET .*phppath.* 404
            ^<HOST> .*?"GET .*admm.* 404
            ^<HOST> .*?"GET .*databaseadmin.* 404
            ^<HOST> .*?"GET .*mysqlmanager.* 404
            ^<HOST> .*?"GET .*phpMyAdmin.* 404
            ^<HOST> .*?"GET .*xampp.* 404
            ^<HOST> .*?"GET .*sqlmanager.* 404
            ^<HOST> .*?"GET .*wp-content.* 404
            ^<HOST> .*?"GET .*wp-login.* 404
            ^<HOST> .*?"GET .*typo3.* 404
            ^<HOST> .*?"HEAD .*manager.* 404
            ^<HOST> .*?"GET .*manager.* 404
            ^<HOST> .*?"HEAD .*blackcat.* 404
            ^<HOST> .*?"HEAD .*sprawdza.php.* 404
            ^<HOST> .*?"GET .*HNAP1.* 404
            ^<HOST> .*?"GET .*vtigercrm.* 404
            ^<HOST> .*?"GET .*cgi-bin.* 404
            ^<HOST> .*?"GET .*webdav.* 404
            ^<HOST> .*?"GET .*web-console.* 404
            ^<HOST> .*?"GET .*manager.* 404
# Option: ignoreregex
# Notes.: regex to ignore. If this regex matches, the line is ignored.
# Values: TEXT
#
ignoreregex =
EOF

cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i '93,$d' /etc/fail2ban/jail.local

echo "
[ssh]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
bantime = 600
banaction = iptables-multiport
maxretry = 5

[nginx-auth]
enabled  = true
port  = http,https
filter   = nginx-auth
logpath  = /var/log/nginx/*error.log
bantime = 600
banaction = iptables-multiport
maxretry = 10

[nginx-badbots]
enabled  = true
port  = http,https
filter = nginx-badbots
logpath = /var/log/nginx/*access.log
bantime = 600
banaction = iptables-multiport
maxretry = 5">> /etc/fail2ban/jail.local

/etc/init.d/fail2ban restart
echo ""
echo -e "${CBLUE}Configuration Fail2ban${CEND}     ${CGREEN}Done !${CEND}"
echo ""

# installation vsftpd

if [ "$SERVFTP" = "y" ] || [ "$SERVFTP" = "Y" ] || [ "$SERVFTP" = "o" ] || [ "$SERVFTP" = "O" ]; then
apt-get install -y vsftpd

mv /etc/vsftpd.conf /etc/vsftpd.bak

echo "
# Configuration générale FTP/FTPS sur port 21 #
# Faite par Meister pour mondedie.fr
#
# Mode standalone
listen=YES
#
# Connexions anonymes 
anonymous_enable=NO
#
# Connexions des utilisateurs locaux
local_enable=YES
#
# Ecriture des fichiers
write_enable=YES
#
# Masque local 022 (les fichiers ecrits auront les droits 755)
local_umask=022
#
# Ecriture de fichiers pour l'admin
anon_upload_enable=YES
#
# Creation de repertoires
anon_mkdir_write_enable=YES
#
#message sur les répertoires
dirmessage_enable=YES
#
# Utilisation de l'heure locale
use_localtime=YES
#

# Connexion sur le port 20 du serveur client  (ftp-data).
connect_from_port_20=YES
#
# Activation des logs
dual_log_enable=YES
#
# Repertoire des logs.
vsftpd_log_file=/var/log/vsftpd.log
xferlog_file=/var/log/xferlog
xferlog_std_format=YES
#
# Timeout
idle_session_timeout=600
data_connection_timeout=120
#
# Bannière FTP
ftpd_banner=Bienvenue sur votre serveur FTP.
#
# Chroot des utilisateurs locaux
chroot_local_user=YES
chroot_list_enable=YES
#
# Repertoire de chroot
chroot_list_file=/etc/vsftpd.chroot_list
secure_chroot_dir=/var/run/vsftpd/empty
#
# Fichier de config PAM
pam_service_name=vsftpd
#
#
# Configuration ssl
#
#Chemin du certificat ssl
rsa_cert_file=/etc/ssl/private/vsftpd.cert.pem
rsa_private_key_file=/etc/ssl/private/vsftpd.key.pem
#
# Activation du ssl sur le serveur
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
#
# Acceptation des différentes versions du ssl
ssl_ciphers=HIGH
ssl_tlsv1=YES
ssl_sslv2=YES
ssl_sslv3=YES
#
max_per_ip=0
pasv_min_port=0
pasv_min_port=0
download_enable=YES
guest_enable=NO
pasv_enable=YES
port_enable=YES
pasv_promiscuous=NO
port_promiscuous=NO
#">> /etc/vsftpd.conf

# récupèration certificats nginx
cp -f /etc/nginx/ssl/server.crt  /etc/ssl/private/vsftpd.cert.pem
cp -f /etc/nginx/ssl/server.key  /etc/ssl/private/vsftpd.key.pem

touch /etc/vsftpd.chroot_list
/etc/init.d/vsftpd reload

echo "
[vsftpd]
enabled = true
port = ftp
filter = vsftpd
logpath = /var/log/vsftpd.log
bantime  = 600
banaction = iptables-multiport
maxretry = 5">> /etc/fail2ban/jail.local

/etc/init.d/fail2ban restart

echo ""
echo -e "${CBLUE}Installation VsFTPd${CEND}     ${CGREEN}Done !${CEND}"
echo ""
fi

# déplacement clé 2048
cp /tmp/dhparams.pem /etc/nginx/ssl/dhparams.pem
chmod 600 /etc/nginx/ssl/dhparams.pem
service nginx restart
# Contrôle
if [ ! -f /etc/nginx/ssl/dhparams.pem ]; then
echo -e "${CBLUE}Création certificat 2048 bits${CEND}"
echo -e "${CRED}L'attente peut durer plus de 10 minutes, soyez patient !${CEND}"
cd /etc/nginx/ssl
openssl dhparam -out dhparams.pem 2048
chmod 600 dhparams.pem
service nginx restart
echo ""
echo -e "${CBLUE}Création certificat${CEND}     ${CGREEN}Done !${CEND}"
echo ""
fi

# log users
echo "maillog">> "$RUTORRENT"/histo_ess.log
echo "userlog">> "$RUTORRENT"/histo_ess.log
sed -i "s/maillog/$EMAIL/g;" "$RUTORRENT"/histo_ess.log
sed -i "s/userlog/$USER:5001/g;" "$RUTORRENT"/histo_ess.log

echo ""
echo -e "${CBLUE}Ajout de l'utilisateur terminé !${CEND}"
echo ""
echo -e "${CGREEN}Gardez bien ces informations:${CEND}"
echo -e "${CBLUE}Username: ${CEND}${CYELLOW}$USER${CEND}"
echo -e "${CBLUE}Password: ${CEND}${CYELLOW}${PASSNGINX}${CEND}"
echo -e "${CGREEN}Elles vous permettront de vous connecter sur ruTorrent,\nSeedbox-Manager et en FTP si choisi à l'installation.${CEND}"
echo ""

# ajout utilisateur supplémentaire

while :; do
echo -n -e "${CGREEN}Voulez vous ajouter un autre utilisateur (y/n): ${CEND}"
read REPONSE

if [ "$REPONSE" = "n" ]  || [ "$REPONSE" = "N" ]; then
	# fin d'installation
	echo ""
	echo -e "${CBLUE}Génération du log d'installation.${CEND}"
	cp /tmp/install.log "$RUTORRENT"/install.log
	ccze -h < "$RUTORRENT"/install.log > "$RUTORRENT"/install.html
    echo ""
	echo -n -e "${CGREEN}Voulez vous redémarrer pour finaliser votre installation (y/n): ${CEND}"
	read REBOOT

	if [ "$REBOOT" = "n" ]  || [ "$REBOOT" = "N" ]; then
		echo ""
		echo -e "${CBLUE}Le log de l'installation est visible à cette adresse:${CEND}"
		echo -e "${CYELLOW}https://$IP/rutorrent/install.html${CEND}"
		echo ""
		echo -e "${CRED}Pensez à redémarrer manuellement votre serveur avant utilisation !${CEND}"
		echo ""
		echo -e "${CBLUE}Vous pourrez ensuite vous connecter sur ruTorrent:${CEND}"
		echo -e "${CYELLOW}https://$IP/rutorrent/${CEND}"
		echo ""
		echo -e "${CBLUE}Et dans la partie \"Administration\" de Seedbox-Manager\npour ajuster certains réglages si installé:${CEND}"
		echo -e "${CYELLOW}https://$IP/seedbox-manager/${CEND}"
		echo ""
		echo ""
		echo -e "${CBLUE}           Bon download, restez en seed et à bientôt sur mondédié.fr${CEND}"
		echo -e "${CBLUE}                  Ex_Rat - http://mondedie.fr/${CEND}"
		echo ""
		break
		#exit 1
	fi

	if [ "$REBOOT" = "y" ] || [ "$REBOOT" = "Y" ] || [ "$REBOOT" = "o" ] || [ "$REBOOT" = "O" ]; then
		echo ""
		echo -e "${CBLUE}Le log de l'installation est visible à cette adresse:${CEND}"
		echo -e "${CYELLOW}https://$IP/rutorrent/install.html${CEND}"
		echo ""
		echo -e "${CBLUE}Vous pourrez ensuite vous connecter sur ruTorrent:${CEND}"
		echo -e "${CYELLOW}https://$IP/rutorrent/${CEND}"
		echo ""
		echo -e "${CBLUE}Et dans la partie \"Administration\" de Seedbox-Manager\npour ajuster certains réglages si installé:${CEND}"
		echo -e "${CYELLOW}https://$IP/seedbox-manager/${CEND}"
		echo ""
		echo ""
		echo -e "${CBLUE}           Bon download, restez en seed et à bientôt sur mondédié.fr${CEND}"
		echo -e "${CBLUE}                  Ex_Rat - http://mondedie.fr/${CEND}"
		echo ""
		reboot
		break
	fi
fi

if [ "$REPONSE" = "y" ] || [ "$REPONSE" = "Y" ] || [ "$REPONSE" = "o" ] || [ "$REPONSE" = "O" ]; then

# demande nom et mot de passe
echo ""
while :; do
echo -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): ${CEND}"
read TESTUSERSUP
if [[ "$TESTUSERSUP" =~ ^[a-z0-9]{3,}$ ]];then
	USERSUP="$TESTUSERSUP"
	break
else
	echo ""
	echo -e "${CRED}Le nom de votre utilisateur doit être en minuscule,\nde plus de 3 lettres et sans caratères spéciaux.${CEND}"
	echo ""
fi
done

echo ""
while :; do
echo -e "${CGREEN}Entrez le mot de passe pour cet utilisateur, ou appuyez\nsur \"${CEND}${CYELLOW}Entrée${CEND}${CGREEN}\" pour en générer un automatiquement: ${CEND}"
read REPPWDSUP
if [ "$REPPWDSUP" = "" ]; then
	AUTOPWDSUP=$(tr -dc "1-9a-nA-Np-zP-Z" < /dev/urandom | head -c 8)
	echo ""
    echo -e -n "${CGREEN}Voulez vous utiliser${CEND} ${CYELLOW}$AUTOPWDSUP${CEND}${CGREEN} comme mot de passe ? (y/n): ${CEND}"
        read REPONSEPWDSUP
        if [ "$REPONSEPWDSUP" = "n" ] || [ "$REPONSEPWDSUP" = "N" ]; then
		echo
        else
			PWDSUP="$AUTOPWDSUP"
			break
		fi

else
	if [[ "$REPPWDSUP" =~ ^[a-zA-Z0-9]{6,}$ ]];then
		PWDSUP="$REPPWDSUP"
       	break
	else
		echo ""
		echo -e "${CRED}Le mot de passe ne doit pas contenir de caratères\nspéciaux et faire plus de 5 chiffres ou lettres.${CEND}"
		echo ""
	fi
fi
done

# récupération 5% root sur /home/user si présent
FS=$(grep /home/"$USERSUP" /etc/fstab | cut -c 6-9)

if [ "$FS" = "" ]; then
	echo
else
    tune2fs -m 0 /dev/"$FS"
    mount -o remount /home/"$USERSUP"
fi

# variable passe nginx
PASSNGINXSUP=${PWDSUP}
echo ""

# ajout utilisateur
useradd -M -s /bin/bash "$USERSUP"

# création du mot de passe pour cet utilisateur
echo "${USERSUP}:${PWDSUP}" | chpasswd

# anti-bug /home/user déjà existant
mkdir -p /home/"$USERSUP"
chown -R "$USERSUP":"$USERSUP" /home/"$USERSUP"

# variable utilisateur majuscule
USERMAJSUP=$(echo "$USERSUP" | tr "[:lower:]" "[:upper:]")

# variable mail
EMAIL=$(sed -n "1 p" "$RUTORRENT"/histo_ess.log)

# création de dossier
su "$USERSUP" -c 'mkdir -p ~/watch ~/torrents ~/.session '

# calcul port
HISTO=$(wc -l < "$RUTORRENT"/histo_ess.log)
PORTSUP=$(( 5001+HISTO ))

# config .rtorrent.rc
cat <<'EOF' > /home/"$USERSUP"/.rtorrent.rc
scgi_port = 127.0.0.1:@PORTSUP@
encoding_list = UTF-8
port_range = 45000-65000
port_random = no
check_hash = no
directory = /home/@USERSUP@/torrents
session = /home/@USERSUP@/.session
encryption = allow_incoming, try_outgoing, enable_retry
schedule = watch_directory,1,1,"load_start=/home/@USERSUP@/watch/*.torrent"
schedule = untied_directory,5,5,"stop_untied=/home/@USERSUP@/watch/*.torrent"
schedule = espace_disque_insuffisant,1,30,close_low_diskspace=500M
use_udp_trackers = yes
dht = off
peer_exchange = no
min_peers = 40
max_peers = 100
min_peers_seed = 10
max_peers_seed = 50
max_uploads = 15
execute = {sh,-c,/usr/bin/php @RUTORRENT@/php/initplugins.php @USERSUP@ &}
EOF
sed -i "s/@USERSUP@/$USERSUP/g;" /home/"$USERSUP"/.rtorrent.rc
sed -i "s/@PORTSUP@/$PORTSUP/g;" /home/"$USERSUP"/.rtorrent.rc
sed -i "s|@RUTORRENT@|$RUTORRENT|;" /home/"$USERSUP"/.rtorrent.rc

# user rtorrent.conf config
sed -i '$d' /etc/nginx/sites-enabled/rutorrent.conf
echo "
        location /$USERMAJSUP {
            include scgi_params;
            scgi_pass 127.0.0.1:$PORTSUP; #ou socket : unix:/home/username/.session/username.socket
            auth_basic \"seedbox\";
            auth_basic_user_file \"/etc/nginx/passwd/rutorrent_passwd_$USERSUP\";
        }">> /etc/nginx/sites-enabled/rutorrent.conf
echo "}" >> /etc/nginx/sites-enabled/rutorrent.conf

mkdir "$RUTORRENT"/conf/users/"$USERSUP"

# config.php
cat <<'EOF' > "$RUTORRENT"/conf/users/"$USERSUP"/config.php
<?php
$pathToExternals = array(
    "curl"  => '/usr/bin/curl',
    "stat"  => '/usr/bin/stat',
    );
$topDirectory = '/home/@USERSUP@';
$scgi_port = @PORTSUP@;
$scgi_host = '127.0.0.1';
$XMLRPCMountPoint = '/@USERMAJSUP@';
EOF
sed -i "s/@USERSUP@/$USERSUP/g;" "$RUTORRENT"/conf/users/"$USERSUP"/config.php
sed -i "s/@USERMAJSUP@/$USERMAJSUP/g;" "$RUTORRENT"/conf/users/"$USERSUP"/config.php
sed -i "s/@PORTSUP@/$PORTSUP/g;" "$RUTORRENT"/conf/users/"$USERSUP"/config.php

# chroot user supplèmentaire
echo "Match User $USERSUP
ChrootDirectory /home/$USERSUP">> /etc/ssh/sshd_config

service ssh restart

## conf user seedbox-manager
if [ -f /var/www/seedbox-manager/public/themes/default/template/header.html ]; then
cd /var/www/seedbox-manager/conf/users
mkdir "$USERSUP"

cat <<'EOF' >  /var/www/seedbox-manager/conf/users/"$USERSUP"/config.ini
; Manager de seedbox (adapté pour le tuto de mondedie.fr)
;
; Fichier de configuration :
; yes ou no pour activer les modules
; Si vous n'avez pas de nom de domaine, indiquez l'ip (ex: http://XX.XX.XX.XX/rutorrent)

[user]
active_bloc_info = yes
user_directory = "/"
scgi_folder = "/RPC1"
theme = "default"
owner = no

[nav]
data_link = "url = ../rutorrent/, name = rutorrent"

[ftp]
active_ftp = yes
port_ftp = "21"
port_sftp = "22"

[rtorrent]
active_reboot = yes

[support]
active_support = yes
adresse_mail = "contact@mail.com"

[logout]
url_redirect = "http://mondedie.fr"

EOF
sed -i "s/\"\/\"/\"\/home\/$USERSUP\"/g;" /var/www/seedbox-manager/conf/users/"$USERSUP"/config.ini
sed -i "s/RPC1/$USERMAJSUP/g;" /var/www/seedbox-manager/conf/users/"$USERSUP"/config.ini
sed -i "s/contact@mail.com/$EMAIL/g;" /var/www/seedbox-manager/conf/users/"$USERSUP"/config.ini
chown -R www-data:www-data /var/www/seedbox-manager/conf/users
fi

# plugin.ini
cat <<'EOF' >  "$RUTORRENT"/conf/users/"$USERSUP"/plugins.ini
[default]
enabled = user-defined
canChangeToolbar = yes
canChangeMenu = yes
canChangeOptions = yes
canChangeTabs = yes
canChangeColumns = yes
canChangeStatusBar = yes
canChangeCategory = yes
canBeShutdowned = yes
[ipad]
enabled = no
[httprpc]
enabled = no
[retrackers]
enabled = no
[rpc]
enabled = no
[rutracker_check]
enabled = no
[chat]
enabled = no
EOF

# permission
chown -R www-data:www-data "$RUTORRENT"
chown -R "$USERSUP":"$USERSUP" /home/"$USERSUP"
chown root:"$USERSUP" /home/"$USERSUP"
chmod 755 /home/"$USERSUP"

# script rtorrent
cat <<'EOF' > /etc/init.d/"$USERSUP"-rtorrent
#!/usr/bin/env bash

# Dépendance : screen, killall et rtorrent
### BEGIN INIT INFO
# Provides:          @USERSUP@-rtorrent
# Required-Start:    $syslog $network
# Required-Stop:     $syslog $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Start-Stop rtorrent user session
### END INIT INFO

## Début configuration ##
user="@USERSUP@"
## Fin configuration ##

rt_start() {
    su --command="screen -dmS ${user}-rtorrent rtorrent" "${user}"
}

rt_stop() {
    killall --user "${user}" screen
}

case "$1" in
start) echo "Starting rtorrent..."; rt_start
    ;;
stop) echo "Stopping rtorrent..."; rt_stop
    ;;
restart) echo "Restart rtorrent..."; rt_stop; sleep 1; rt_start
    ;;
*) echo "Usage: $0 {start|stop|restart}"; exit 1
    ;;
esac
exit 0
EOF

sed -i "s/@USERSUP@/$USERSUP/g;" /etc/init.d/"$USERSUP"-rtorrent
chmod +x /etc/init.d/"$USERSUP"-rtorrent
update-rc.d "$USERSUP"-rtorrent defaults

service "$USERSUP"-rtorrent start

# htpasswd
htpasswd -bs /etc/nginx/passwd/rutorrent_passwd "$USERSUP" "${PASSNGINXSUP}"
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd_"$USERSUP" "$USERSUP" "${PASSNGINXSUP}"
chmod 640 /etc/nginx/passwd/*
chown -c www-data:www-data /etc/nginx/passwd/*
service nginx restart

# log users
echo "userlog">> "$RUTORRENT"/histo_ess.log
sed -i "s/userlog/$USERSUP:$PORTSUP/g;" "$RUTORRENT"/histo_ess.log

echo ""
echo -e "${CBLUE}Ajout de l'utilisateur terminé !${CEND}"

echo ""
echo -e "${CGREEN}Gardez bien ces informations:${CEND}"
echo -e "${CBLUE}Username: ${CEND}${CYELLOW}$USERSUP${CEND}"
echo -e "${CBLUE}Password: ${CEND}${CYELLOW}${PASSNGINXSUP}${CEND}"
echo -e "${CGREEN}Elles vous permettront de vous connecter sur ruTorrent,\nSeedbox-Manager et en FTP si choisi à l'installation.${CEND}"
echo ""
fi
done

else

################################################
# lancement gestion des utilisateurs ruTorrent #
################################################

clear

# Contrôle installation
if [ ! -f "$RUTORRENT"/histo_ess.log ]; then
	echo ""
	echo -e "${CRED}     Votre installation n'est pas compatible avec cette version du script.${CEND}"
	echo -e "${CRED}               Vous trouverez de l'aide sur http://mondedie.fr !${CEND}"
	echo ""
	exit 1
fi

# message d'accueil
echo ""
echo -e "${CBLUE}                  Utilitaire de gestion utilisateur ruTorrent${CEND}"
echo ""

# logo
echo -e "${CBLUE}
                                      |          |_)         _|
            __ \`__ \   _ \  __ \   _\` |  _ \  _\` | |  _ \   |    __|
            |   |   | (   | |   | (   |  __/ (   | |  __/   __| |
           _|  _|  _|\___/ _|  _|\__,_|\___|\__,_|_|\___|_)_|  _|

${CEND}"
echo ""

# mise en garde
echo -e "${CRED}         Attention, si vous avez modifié votre fichier rutorrent.conf${CEND}"
echo -e "${CRED}         depuis la fin de l'installation automatique, le script peut${CEND}"
echo -e "${CRED}         ne pas fonctionner normalement. Faites le manuellement !${CEND}"
echo ""
echo -n -e "${CGREEN}Voulez vous continuer? (y/n): ${CEND}"
read VALIDE

if [ "$VALIDE" = "n" ] || [ "$VALIDE" = "N" ]; then
	echo ""
	echo -e "${CBLUE}           Bon download, restez en seed et à bientôt sur mondédié.fr${CEND}"
	echo -e "${CBLUE}                  Ex_Rat - http://mondedie.fr/${CEND}"
	echo ""
	exit 1
fi

if [ "$VALIDE" = "y" ] || [ "$VALIDE" = "Y" ] || [ "$VALIDE" = "o" ] || [ "$VALIDE" = "O" ]; then

# Boucle ajout/suppression utilisateur
while :; do

# menu gestion multi-utilisateurs
echo ""
echo -e "${CBLUE}Choisissez une option.${CEND}"
echo -e "${CYELLOW} 1${CEND} ${CGREEN}: Ajouter un utilisateur${CEND}"
echo -e "${CYELLOW} 2${CEND} ${CGREEN}: Supprimer un utilisateur${CEND}"
echo -e "${CYELLOW} 3${CEND} ${CGREEN}: Modifier un mot de passe${CEND}"
echo -e "${CYELLOW} 4${CEND} ${CGREEN}: Sortir${CEND}"
echo -n -e "${CBLUE}Numéro: ${CEND}"
read OPTION

case $OPTION in
1)

# demande nom et mot de passe
while :; do
echo -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): ${CEND}"
read TESTUSER
if [[ "$TESTUSER" =~ ^[a-z0-9]{3,}$ ]];then
	USER="$TESTUSER"
	break
else
	echo ""
	echo -e "${CRED}Le nom de votre utilisateur doit être en minuscule,\nde plus de 3 lettres et sans caratères spéciaux.${CEND}"
	echo ""
fi
done

echo ""
while :; do
echo -e "${CGREEN}Entrez le mot de passe pour cet utilisateur, ou appuyez\nsur \"${CEND}${CYELLOW}Entrée${CEND}${CGREEN}\" pour en générer un automatiquement: ${CEND}"
read REPPWD
if [ "$REPPWD" = "" ]; then
	AUTOPWD=$(tr -dc "1-9a-nA-Np-zP-Z" < /dev/urandom | head -c 8)
	echo ""
    echo -e -n "${CGREEN}Voulez vous utiliser${CEND} ${CYELLOW}$AUTOPWD${CEND}${CGREEN} comme mot de passe ? (y/n): ${CEND}"
        read REPONSEPWD
        if [ "$REPONSEPWD" = "n" ] || [ "$REPONSEPWD" = "N" ]; then
		echo
        else
			PWD="$AUTOPWD"
			break
		fi

else
	if [[ "$REPPWD" =~ ^[a-zA-Z0-9]{6,}$ ]];then
		PWD="$REPPWD"
       	break
	else
		echo ""
		echo -e "${CRED}Le mot de passe ne doit pas contenir de caratères\nspéciaux et faire plus de 5 chiffres ou lettres.${CEND}"
		echo ""
	fi
fi
done
echo ""

# récupération 5% root sur /home/user si présent
FS=$(grep /home/"$USER" /etc/fstab | cut -c 6-9)

if [ "$FS" = "" ]; then
	echo
else
    tune2fs -m 0 /dev/"$FS"
    mount -o remount /home/"$USER"
	echo ""
fi

# variable email (rétro compatible)
TESTMAIL=$(sed -n "1 p" "$RUTORRENT"/histo_ess.log)
if [[ "$TESTMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]*$ ]];then
        EMAIL="$TESTMAIL"
else
        EMAIL=contact@exemple.com
fi

# variable passe nginx
PASSNGINX=${PWD}
echo ""

# ajout utilisateur
useradd -M -s /bin/bash "$USER"

# création du mot de passe pour cet utilisateur
echo "${USER}:${PWD}" | chpasswd

# anti-bug /home/user déjà existant
mkdir -p /home/"$USER"
chown -R "$USER":"$USER" /home/"$USER"

# variable utilisateur majuscule
USERMAJ=$(echo "$USER" | tr "[:lower:]" "[:upper:]")

# récupération IP serveur
IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}' | head -1)
if [ "$IP" = "" ]; then
	IP=$(wget -qO- ipv4.icanhazip.com)
fi

su "$USER" -c 'mkdir -p ~/watch ~/torrents ~/.session '

# calcul port
HISTO=$(wc -l < "$RUTORRENT"/histo_ess.log)
PORT=$(( 5001+HISTO ))

# config .rtorrent.rc
cat <<'EOF' > /home/"$USER"/.rtorrent.rc
scgi_port = 127.0.0.1:@PORT@
encoding_list = UTF-8
port_range = 45000-65000
port_random = no
check_hash = no
directory = /home/@USER@/torrents
session = /home/@USER@/.session
encryption = allow_incoming, try_outgoing, enable_retry
schedule = watch_directory,1,1,"load_start=/home/@USER@/watch/*.torrent"
schedule = untied_directory,5,5,"stop_untied=/home/@USER@/watch/*.torrent"
schedule = espace_disque_insuffisant,1,30,close_low_diskspace=500M
use_udp_trackers = yes
dht = off
peer_exchange = no
min_peers = 40
max_peers = 100
min_peers_seed = 10
max_peers_seed = 50
max_uploads = 15
execute = {sh,-c,/usr/bin/php @RUTORRENT@/php/initplugins.php @USER@ &}
EOF
sed -i "s/@USER@/$USER/g;" /home/"$USER"/.rtorrent.rc
sed -i "s/@PORT@/$PORT/g;" /home/"$USER"/.rtorrent.rc
sed -i "s|@RUTORRENT@|$RUTORRENT|;" /home/"$USER"/.rtorrent.rc

# user rtorrent.conf config
sed -i '$d' /etc/nginx/sites-enabled/rutorrent.conf
echo "
        location /$USERMAJ {
            include scgi_params;
            scgi_pass 127.0.0.1:$PORT; #ou socket : unix:/home/username/.session/username.socket
            auth_basic \"seedbox\";
            auth_basic_user_file \"/etc/nginx/passwd/rutorrent_passwd_$USER\";
        }">> /etc/nginx/sites-enabled/rutorrent.conf
echo "}" >> /etc/nginx/sites-enabled/rutorrent.conf

mkdir "$RUTORRENT"/conf/users/"$USER"

# config.php
cat <<'EOF' > "$RUTORRENT"/conf/users/"$USER"/config.php
<?php
$pathToExternals = array(
    "curl"  => '/usr/bin/curl',
    "stat"  => '/usr/bin/stat',
    );
$topDirectory = '/home/@USER@';
$scgi_port = @PORT@;
$scgi_host = '127.0.0.1';
$XMLRPCMountPoint = '/@USERMAJ@';
EOF
sed -i "s/@USER@/$USER/g;" "$RUTORRENT"/conf/users/"$USER"/config.php
sed -i "s/@USERMAJ@/$USERMAJ/g;" "$RUTORRENT"/conf/users/"$USER"/config.php
sed -i "s/@PORT@/$PORT/g;" "$RUTORRENT"/conf/users/"$USER"/config.php

# plugin.ini
cat <<'EOF' >  "$RUTORRENT"/conf/users/"$USER"/plugins.ini
[default]
enabled = user-defined
canChangeToolbar = yes
canChangeMenu = yes
canChangeOptions = yes
canChangeTabs = yes
canChangeColumns = yes
canChangeStatusBar = yes
canChangeCategory = yes
canBeShutdowned = yes
[ipad]
enabled = no
[httprpc]
enabled = no
[retrackers]
enabled = no
[rpc]
enabled = no
[rutracker_check]
enabled = no
[chat]
enabled = no
EOF

# chroot user supplémentaire
echo "Match User $USER
ChrootDirectory /home/$USER">> /etc/ssh/sshd_config

service ssh restart

# permission
chown -R www-data:www-data "$RUTORRENT"
chown -R "$USER":"$USER" /home/"$USER"
chown root:"$USER" /home/"$USER"
chmod 755 /home/"$USER"

# script rtorrent
cat <<'EOF' > /etc/init.d/"$USER"-rtorrent
#!/usr/bin/env bash

# Dépendance : screen, killall et rtorrent
### BEGIN INIT INFO
# Provides:          @USER@-rtorrent
# Required-Start:    $syslog $network
# Required-Stop:     $syslog $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Start-Stop rtorrent user session
### END INIT INFO

## Début configuration ##
user="@USER@"
## Fin configuration ##

rt_start() {
    su --command="screen -dmS ${user}-rtorrent rtorrent" "${user}"
}

rt_stop() {
    killall --user "${user}" screen
}

case "$1" in
start) echo "Starting rtorrent..."; rt_start
    ;;
stop) echo "Stopping rtorrent..."; rt_stop
    ;;
restart) echo "Restart rtorrent..."; rt_stop; sleep 1; rt_start
    ;;
*) echo "Usage: $0 {start|stop|restart}"; exit 1
    ;;
esac
exit 0
EOF

sed -i "s/@USER@/$USER/g;" /etc/init.d/"$USER"-rtorrent
chmod +x /etc/init.d/"$USER"-rtorrent
update-rc.d "$USER"-rtorrent defaults

service "$USER"-rtorrent start

# htpasswd
htpasswd -bs /etc/nginx/passwd/rutorrent_passwd "$USER" "${PASSNGINX}"
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd_"$USER" "$USER" "${PASSNGINX}"
chmod 640 /etc/nginx/passwd/*
chown -c www-data:www-data /etc/nginx/passwd/*
service nginx restart

# seedbox-manager conf user
if [ -f /var/www/seedbox-manager/public/themes/default/template/header.html ]; then

cd /var/www/seedbox-manager/conf/users
mkdir "$USER"

cat <<'EOF' >  /var/www/seedbox-manager/conf/users/"$USER"/config.ini
; Manager de seedbox (adapté pour le tuto de mondedie.fr)
;
; Fichier de configuration :
; yes ou no pour activer les modules
; Si vous n'avez pas de nom de domaine, indiquez l'ip (ex: http://XX.XX.XX.XX/rutorrent)

[user]
active_bloc_info = yes
user_directory = "/"
scgi_folder = "/RPC1"
theme = "default"
owner = no

[nav]
data_link = "url = ../rutorrent/, name = rutorrent"

[ftp]
active_ftp = yes
port_ftp = "21"
port_sftp = "22"

[rtorrent]
active_reboot = yes

[support]
active_support = yes
adresse_mail = "contact@mail.com"

[logout]
url_redirect = "http://mondedie.fr"

EOF
sed -i "s/\"\/\"/\"\/home\/$USER\"/g;" /var/www/seedbox-manager/conf/users/"$USER"/config.ini
sed -i "s/RPC1/$USERMAJ/g;" /var/www/seedbox-manager/conf/users/"$USER"/config.ini
sed -i "s/contact@mail.com/$EMAIL/g;" /var/www/seedbox-manager/conf/users/"$USER"/config.ini

chown -R www-data:www-data /var/www/seedbox-manager/conf/users
fi

# log users
echo "userlog">> "$RUTORRENT"/histo_ess.log
sed -i "s/userlog/$USER:$PORT/g;" "$RUTORRENT"/histo_ess.log

echo ""
echo -e "${CBLUE}Ajout de l'utilisateur terminé !${CEND}"

echo ""
echo -e "${CGREEN}Gardez bien ces informations:${CEND}"
echo -e "${CBLUE}Username: ${CEND}${CYELLOW}$USER${CEND}"
echo -e "${CBLUE}Password: ${CEND}${CYELLOW}${PASSNGINX}${CEND}"
echo -e "${CGREEN}Elles vous permettront de vous connecter sur ruTorrent,\nSeedbox-Manager et en FTP si vous possédez ces options.${CEND}"
echo ""
;;

# suppression utilisateur
2)

echo ""
echo -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): ${CEND}"
read USER
echo -n -e "${CGREEN}Voulez vous vraiment supprimer l'utilisateur ${CEND}${CYELLOW}$USER${CEDN}${CGREEN} (y/n): ${CEND}"
read SUPPR

if [ "$SUPPR" = "n" ]  || [ "$SUPPR" = "N" ]; then
	echo

else
	echo ""
	echo -e "${CBLUE}Suppression de l'utilisateur.${CEND}"
	echo ""

	# variable utilisateur majuscule
	USERMAJ=$(echo "$USER" | tr "[:lower:]" "[:upper:]")
	echo -e "$USERMAJ"

	# crontab (pour rétro-compatibilité)
	crontab -l > /tmp/rmuser
	sed -i "s/* \* \* \* \* if ! ( ps -U $USER | grep rtorrent > \/dev\/null ); then \/etc\/init.d\/$USER-rtorrent start; fi > \/dev\/null 2>&1//g;" /tmp/rmuser
	crontab /tmp/rmuser
	rm /tmp/rmuser

	# stop user
	/etc/init.d/"$USER"-rtorrent stop
	killall --user "$USER" rtorrent
	killall --user "$USER" screen

	# suppression script
	rm /etc/init.d/"$USER"-rtorrent
	update-rc.d "$USER"-rtorrent remove

	# suppression conf rutorrent
	rm -R "$RUTORRENT"/conf/users/"$USER"
	rm -R "$RUTORRENT"/share/users/"$USER"

	# suppression pass
	sed -i "/^$USER/d" /etc/nginx/passwd/rutorrent_passwd
	rm /etc/nginx/passwd/rutorrent_passwd_"$USER"

	# suppression nginx
	sed -i '/location \/'"$USERMAJ"'/,/}/d' /etc/nginx/sites-enabled/rutorrent.conf
	service nginx restart

	# suppression seebbox-manager
	if [ -f /var/www/seedbox-manager/public/themes/default/template/header.html ]; then
	rm -R /var/www/seedbox-manager/conf/users/"$USER"
	fi

	# suppression user
	deluser "$USER" --remove-home

	echo ""
	echo -e "${CBLUE}L'utilisateur${CEND} ${CYELLOW}$USER${CEND} ${CBLUE}a bien été supprimé.${CEND}"
	fi
;;

# modification mot de passe utilisateur
3)

echo ""
echo -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): ${CEND}"
read USER
echo ""
while :; do
echo -e "${CGREEN}Entrez le nouveau mot de passe pour cet utilisateur,\nou appuyez sur \"${CEND}${CYELLOW}Entrée${CEND}${CGREEN}\" pour en générer un automatiquement: ${CEND}"
read REPPWD
if [ "$REPPWD" = "" ]; then
	AUTOPWD=$(tr -dc "1-9a-nA-Np-zP-Z" < /dev/urandom | head -c 8)
	echo ""
    echo -e -n "${CGREEN}Voulez vous utiliser${CEND} ${CYELLOW}$AUTOPWD${CEND}${CGREEN} comme mot de passe ? (y/n): ${CEND}"
        read REPONSEPWD
        if [ "$REPONSEPWD" = "n" ]  || [ "$REPONSEPWD" = "N" ]; then
		echo
        else
			PWD="$AUTOPWD"
			break
		fi

else
	if [[ "$REPPWD" =~ ^[a-zA-Z0-9]{6,}$ ]];then
		PWD="$REPPWD"
       	break
	else
		echo ""
		echo -e "${CRED}Le mot de passe ne doit pas contenir de caratères\nspéciaux et faire plus de 5 chiffres ou lettres.${CEND}"
		echo ""
	fi
fi
done

echo ""
echo -e "${CBLUE}Modification du mot de passe de l'utilisateur.${CEND}"
echo ""

# variable passe nginx
PASSNGINX=${PWD}
echo ""

# modification du mot de passe pour cet utilisateur
echo "${USER}:${PWD}" | chpasswd

# htpasswd
htpasswd -bs /etc/nginx/passwd/rutorrent_passwd "$USER" "${PASSNGINX}"
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd_"$USER" "$USER" "${PASSNGINX}"
chmod 640 /etc/nginx/passwd/*
chown -c www-data:www-data /etc/nginx/passwd/*
service nginx restart

echo ""
echo -e "${CBLUE}Le mot de passe utilisateur de${CEND} ${CYELLOW}$USER${CEND} ${CBLUE}a bien été modifié.${CEND}"
echo
echo -e "${CGREEN}Gardez bien ces informations:${CEND}"
echo -e "${CBLUE}Username: ${CEND}${CYELLOW}$USER${CEND}"
echo -e "${CBLUE}Password: ${CEND}${CYELLOW}${PASSNGINX}${CEND}"
echo -e "${CGREEN}Elles vous permettront de vous connecter sur ruTorrent,\nSeedbox-Manager et en FTP si vous possédez cette option.${CEND}"
echo ""
;;

# sortir gestion utilisateurs
4)
echo ""
echo -n -e "${CGREEN}Voulez vous redémarrer pour finaliser la gestion utilisateur (y/n): ${CEND}"
read REBOOT

if [ "$REBOOT" = "n" ]  || [ "$REBOOT" = "N" ]; then
	echo ""
	echo -e "${CRED}Penser à redémarrer manuellement votre serveur avant utilisation !${CEND}"
	echo ""
	echo -e "${CBLUE}           Bon download, restez en seed et à bientôt sur mondédié.fr${CEND}"
	echo -e "${CBLUE}                  Ex_Rat - http://mondedie.fr/${CEND}"
	echo ""
	exit 1
fi

if [ "$REBOOT" = "y" ] || [ "$REBOOT" = "Y" ] || [ "$REBOOT" = "o" ] || [ "$REBOOT" = "O" ]; then
	echo ""			
	echo -e "${CBLUE}           Bon download, restez en seed et à bientôt sur mondédié.fr${CEND}"
	echo -e "${CBLUE}                  Ex_Rat - http://mondedie.fr/${CEND}"
	echo ""
	reboot
fi

break
;;

*)
echo -e "${CRED} Option invalide${CEND}"
;;
esac
done
fi
fi
