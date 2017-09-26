#!/bin/sh

# Setup local development Script for OSX
# To execute: save and `chmod +x ./local-devel-env.sh` then `sudo ./local-devel-env.sh.sh`

# cat $(brew --prefix)/etc/my.cnf
# cat $(brew --prefix)/etc/dnsmasq.conf
# cat ~/.bash_profile
# cat $(brew --prefix)/etc/php/7.1/php-fpm.d/www.conf

# brew services restart php71
# brew services restart nginx
# brew services restart dnsmasq

DEFAULT_USER=$USER
DEFAULT_GROUP='staff'
DEFAULT_FOLDER="/Users/$DEFAULT_USER/sites"

echo "*********************************************"
read -p "Input the user php will run as or press enter for current user [$DEFAULT_USER]: " PHP_USER
PHP_USER="${PHP_USER:-$DEFAULT_USER}"
read -p "Input the group php will run as or press enter for standard group [$DEFAULT_GROUP]: " PHP_GROUP
PHP_GROUP="${PHP_GROUP:-$DEFAULT_GROUP}"
read -p "Input the folder which will be web root or press enter for suggested folder [$DEFAULT_FOLDER]: " WEB_FOLDER
WEB_FOLDER="${WEB_FOLDER:-$DEFAULT_FOLDER}"

echo "*** Enter your password for sudo ***"
sudo chgrp "$DEFAULT_GROUP" /usr/local
sudo chmod g+w /usr/local

if ! [ -d /usr/local/bin  ]
then
  mkdir "/usr/local/bin"
fi

echo "Installing composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
PROFILE_INCLUDE='alias composer="php /usr/local/bin/composer.phar"'
FILE="/Users/$DEFAULT_USER/.bash_profile"
if ! [ -f  ]
then
  touch "$FILE"
fi
if grep -Fxq 'alias composer=' "$FILE"
then
  sed -i '' 's/alias composer=/'"${PROFILE_INCLUDE}"'/' "$FILE"
else
  echo "$PROFILE_INCLUDE" >> "$FILE"
fi

echo "Installing drush..."
composer global require drush/drush:8
PROFILE_INCLUDE='export PATH="$HOME/.composer/vendor/bin:$PATH"'
if ! grep -Fxq "$PROFILE_INCLUDE" "$FILE"
then
  echo "$PROFILE_INCLUDE" >> "$FILE"
fi

source "$FILE"

echo "Installing Homebrew..."
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

echo "installing   MySQL..."
brew install -v mysql
cat > $(brew --prefix)/etc/my.cnf <<'EOF'
# Default Homebrew MySQL server config
[mysqld]
# Only allow connections from localhost
bind-address = 127.0.0.1
# Echo & Co. changes
max_allowed_packet = 1073741824
default-storage-engine = innodb
innodb_buffer_pool_size = 1G
innodb_log_file_size = 100M
#innodb_flush_method = fdatasync
innodb_file_per_table = 1
innodb_log_buffer_size = 10M
innodb_flush_log_at_trx_commit = 0
innodb_thread_concurrency = 32
EOF
brew tap homebrew/services

echo "Installing DNSMasq..."
brew install -v dnsmasq
cat > $(brew --prefix)/etc/dnsmasq.conf <<'EOF'
address=/.dev/127.0.0.1
listen-address=127.0.0.1
port=35353
EOF

echo "*** Enter your password for sudo ***"
if ! [ -d "/etc/resolver" ]
then
  sudo mkdir -v "/etc/resolver"
fi
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/dev
echo "port 35353" | sudo tee -a /etc/resolver/dev

echo "Install PHP..."
brew tap homebrew/dupes && \
brew tap homebrew/php && \
brew install php71
sed -i '' 's/user = .*/user = '"${PHP_USER}"'/' $(brew --prefix)/etc/php/7.1/php-fpm.d/www.conf
sed -i '' 's/group = .*/group = '"${PHP_GROUP}"'/' $(brew --prefix)/etc/php/7.1/php-fpm.d/www.conf

echo "Installing XDebug"
brew install homebrew/php/php71-xdebug

echo "Creating ext-xdebug.ini"
cat > $(brew --prefix)/etc/php/7.1/ext-xdebug.ini <<'EOF'
[xdebug]
zend_extension="/usr/local/opt/php71-xdebug/xdebug.so"
xdebug.remote_port = 9001
xdebug.remote_enable = 1
xdebug.remote_connect_back = 1
xdebug.idekey = "docker"
xdebug.remote_log="/usr/local/var/log/xdebug.log"
xdebug.profiler_enable_trigger = 1
xdebug.trace_enable_trigger = 1
xdebug.max_nesting_level = 1000
EOF

echo "Installing Nginx..."
brew tap homebrew/nginx && \
brew install nginx
mkdir -p $(brew --prefix)/etc/nginx/sites-available && \
mkdir -p $(brew --prefix)/etc/nginx/sites-enabled && \
mkdir -p $(brew --prefix)/etc/nginx/conf.d && \
mkdir -p $(brew --prefix)/etc/nginx/ssl
echo "Removing default nginx.conf"
FILE="$(brew --prefix)/etc/nginx/nginx.conf"
if [ -f "$FILE" ]
then
  rm "$FILE"
fi

echo "Creating new nginx.conf"
cat > "$FILE" <<'EOF'
worker_processes auto;
events {
  worker_connections  1024;
}
http {
  include             mime.types;
  default_type        application/octet-stream;
  log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
  access_log /usr/local/var/log/nginx/access.log;
  error_log /usr/local/var/log/nginx/error.log;
  keepalive_timeout   65;
  index index.html index.php;
  include /usr/local/etc/nginx/sites-enabled/*;
}
EOF

if ! [ -d "$WEB_FOLDER" ]
then
  sudo mkdir "$WEB_FOLDER"
  sudo chown "$PHP_USER" "$WEB_FOLDER"
  sudo chgrp "$PHP_GROUP" "$WEB_FOLDER"
fi

LOCAL_FOLDER="$WEB_FOLDER/local"
if ! [ -d "$LOCAL_FOLDER" ]
then
  sudo mkdir "$LOCAL_FOLDER"
  sudo chown "$PHP_USER" "$LOCAL_FOLDER"
  sudo chgrp "$PHP_GROUP" "$LOCAL_FOLDER"
fi

LOCAL_FOLDER="$LOCAL_FOLDER/drupal"
if ! [ -d "$LOCAL_FOLDER" ]
then
  sudo mkdir "$LOCAL_FOLDER"
  sudo chown "$PHP_USER" "$LOCAL_FOLDER"
  sudo chgrp "$PHP_GROUP" "$LOCAL_FOLDER"
fi

echo "Creating test index.php"
cat > "${LOCAL_FOLDER}/index.php" << 'EOF'
<?php
phpinfo();
EOF

echo "Creating php-fpm.conf"
cat > $(brew --prefix)/etc/nginx/php-fpm.conf <<'EOF'
fastcgi_pass   127.0.0.1:9000;
#fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;

# regex to split $uri to $fastcgi_script_name and $fastcgi_path
fastcgi_split_path_info ^(.+\.php)(/.+)$;

# Check that the PHP script exists before passing it
try_files $fastcgi_script_name =404;

# Bypass the fact that try_files resets $fastcgi_path_info. See: http://trac.nginx.org/nginx/ticket/321
set $path_info $fastcgi_path_info;
fastcgi_param PATH_INFO $path_info;
fastcgi_index index.php;
include fastcgi.conf;
EOF

echo "Creating drupal.conf"
cat > $(brew --prefix)/etc/nginx/drupal.conf <<'EOF'
# Drupal include, adapted from https://raw.github.com/perusio/drupal-with-nginx
index index.php;

## The 'default' location.
location / {
    location ~ ^/sites/default/files/ {
      try_files $uri @rewrite;
    }

    ## If accessing an image generated by imagecache, serve it directly if
    ## available, if not relay the request to Drupal to (re)generate the
    ## image.
    location ~* /imagecache/ {
        access_log off;
        expires 30d;
        try_files $uri @rewrite;
    }

    ## Drupal 7 generated image handling, i.e., imagecache in core. See:
    ## https://drupal.org/node/371374.
    location ~* /files/styles/ {
        access_log off;
        expires 30d;
        try_files $uri @rewrite;
    }

    ## Regular private file serving (i.e. handled by Drupal).
    location ^~ /system/files/ {
        ## For not signaling a 404 in the error log whenever the
        ## system/files directory is accessed add the line below.
        ## Note that the 404 is the intended behavior.
        log_not_found off;
        access_log off;
        expires 30d;
        try_files $uri @rewrite;
    }

    location ^~ /system/redis/ {
        ## For not signaling a 404 in the error log whenever the
        ## system/files directory is accessed add the line below.
        ## Note that the 404 is the intended behavior.
        log_not_found off;
        access_log off;
        expires 30d;
        try_files $uri @rewrite;
    }

    # Google verification code.
    location ~ ^/google.*\.html$ {
      try_files $uri @rewrite;
    }

    ## All static files will be served directly.
    location ~* ^.+\.(?:txt|css|js|jpe?g|gif|htc|ico|png|html|xml)$ {
        access_log off;
        log_not_found off;
        expires 30d;
        ## No need to bleed constant updates. Send the all shebang in one
        ## fell swoop.
        tcp_nodelay off;
        ## Set the OS file cache.
        #open_file_cache max=3000 inactive=120s;
        #open_file_cache_valid 45s;
        #open_file_cache_min_uses 2;
        open_file_cache_errors off;
    }

    ## PDFs and powerpoint files handling.
    location ~* ^.+\.(?:pdf|pptx?)$ {
        expires 30d;
        ## No need to bleed constant updates. Send the all shebang in one
        ## fell swoop.
        tcp_nodelay off;
    }

    ## Replicate the Apache <FilesMatch> directive of Drupal standard
    ## .htaccess. Disable access to any code files. Return a 404 to curtail
    ## information disclosure. Hide also the text files.
    location ~* ^(?:.+\.(?:htaccess|make|txt|engine|inc|info|install|module|profile|po|sh|.*sql|theme|tpl(?:\.php)?|xtmpl)|code-style\.pl|/Entries.*|/Repository|/Root|/Tag|/Template)$ {
        return 404;
    }

    try_files $uri @rewrite;
}

########### Security measures ##########

location = /sites/all/libraries/ckfinder/core/connector/php/connector.php {
    include php-fpm.conf;
}

location = /index.php {
    include php-fpm.conf;
    ## This enables a fallback for whenever the 'default' upstream fails.
}

location @rewrite {
    # Some modules enforce no slash (/) at the end of the URL
    # Else this rewrite block wouldn't be needed (GlobalRedirect)
    rewrite ^/(.*)$ /index.php?q=$1;
}

## Disallow access to .git directory: return 404 as not to disclose
## information.
location ~ /.git {
    return 404;
}

## Disallow access to patches directory.
location ~ /patches {
    return 404;
}

## Disallow access to drush backup directory.
location = /backup {
    return 404;
}

## Disable access logs for robots.txt.
location = /robots.txt {
    access_log off;
}

## RSS feed support.
location = /rss.xml {
    try_files $uri @rewrite;
}

## XML Sitemap support.
location = /sitemap.xml {
    try_files $uri @rewrite;
}

## Support for favicon. Return a 204 (No Content) if the favicon
## doesn't exist.
location = /favicon.ico {
    try_files /favicon.ico =204;
}

## Any other attempt to access PHP files returns a 404.
location ~* ^.+\.php$ {
    return 404;
}
EOF

echo "Creating default.conf for nginx"
cat > $(brew --prefix)/etc/nginx/sites-available/default.conf <<'EOF'
server {
  listen 80 default_server;
  index index.php;
  set $basepath "/var/www/html";

  set $domain $host;

  # check one name domain for simple application
  if ($domain ~ "^(.[^.]*)\.dev$") {
    set $domain $1;
    set $rootpath "${domain}/drupal";
    set $servername "${domain}.dev";
  }

  # check multi name domain to multi application
  #if ($domain ~ "^(.*)\.(.[^.]*)\.dev$") {
  #  set $subdomain $1;
  #  set $domain $2;
  #  set $rootpath "${domain}/${subdomain}/www/";
  #  set $servername "${subdomain}.${domain}.dev";
  #}

  server_name $servername;

  access_log "/usr/local/var/log/nginx/${servername}.access.log";
  error_log "/usr/local/var/log/nginx/dev.error.log";

  root $basepath/$rootpath;

  include drupal.conf;
}
EOF
sed -i '' 's|/var/www/html|'"${WEB_FOLDER}"'|g' $(brew --prefix)/etc/nginx/sites-available/default.conf

FILE=$(brew --prefix)/etc/nginx/sites-enabled/default.conf
if ! [ -f "$FILE" ]
then
  ln -s $(brew --prefix)/etc/nginx/sites-available/default.conf  "$FILE"
fi

echo "Restarting services ..."
brew services restart php71
sudo brew services restart nginx
brew services restart dnsmasq
brew services restart mysql
