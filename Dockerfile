FROM alpine:3.4
MAINTAINER otofu <otofu.xxx+docker@gmail.com>

# 環境変数の定義
ENV HTTPD_PREFIX /usr/local/apache2
ENV PATH $HTTPD_PREFIX/bin:$PATH

ENV HTTPD_VERSION 2.4.23
ENV HTTPD_SHA1 5101be34ac4a509b245adb70a56690a84fcc4e7f
ENV HTTPD_GPG_KEY A93D62ECC3C8EA12DB220EC934EA76E6791485A8
ENV HTTPD_BZ2_URL https://www.apache.org/dyn/closer.cgi?action=download&filename=httpd/httpd-$HTTPD_VERSION.tar.bz2
ENV HTTPD_ASC_URL https://www.apache.org/dist/httpd/httpd-$HTTPD_VERSION.tar.bz2.asc

ENV PHPIZE_DEPS autoconf file g++ gcc libc-dev make pkgconf re2c
ENV PHP_INI_DIR /usr/local/etc/php
ENV PHP_GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7
ENV PHP_VERSION 5.3.29
ENV PHP_URL="https://secure.php.net/get/php-${PHP_VERSION}.tar.xz/from/this/mirror"
ENV PHP_ASC_URL="https://secure.php.net/get/php-${PHP_VERSION}.tar.xz.asc/from/this/mirror"
ENV PHP_SHA256="8438c2f14ab8f3d6cd2495aa37de7b559e33b610f9ab264f0c61b531bf0c262d"
ENV PHP_MD5="dcff9c881fe436708c141cfc56358075"

# 必要なユーザ・グループ、パッケージ、ディレクトリの作成
RUN set -x \
    && addgroup -g 82 -S www-data && adduser -u 82 -D -S -G www-data www-data \
    && mkdir -p "$HTTPD_PREFIX" chown www-data:www-data "$HTTPD_PREFIX" \
    && mkdir -p $PHP_INI_DIR/conf.d \
    && mkdir -p /usr/local/apache2/conf/other \
    && mkdir -p /var/www/html && chown -R www-data:www-data /var/www \
    && apk --update add --no-cache --virtual .persistent-deps ca-certificates curl tar xz

# 設定ファイルのコピー
COPY ./usr /usr

WORKDIR $HTTPD_PREFIX
RUN set -x \
# Apache、PHPのビルドに必要なパッケージのインストール.
  && runDeps='apr-dev apr-util-dev perl' \
  && apk --update add --no-cache --virtual .build-deps \
      $PHPIZE_DEPS $runDeps \
      ca-certificates \
      curl-dev \
      gnupg \
      libedit-dev \
      libjpeg-turbo-dev \
      libpng-dev \
      libxml2-dev \
      mariadb-dev \
      openssl \
      openssl-dev \
      pcre-dev \
      sqlite-dev \
  \
# Apacheのビルド.
  && wget -O httpd.tar.bz2 "$HTTPD_BZ2_URL" \
  && echo "$HTTPD_SHA1 *httpd.tar.bz2" | sha1sum -c - \
  && wget -O httpd.tar.bz2.asc "$HTTPD_ASC_URL" \
  && export GNUPGHOME="$(mktemp -d)" \
  && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys $HTTPD_GPG_KEY \
  && gpg --batch --verify httpd.tar.bz2.asc httpd.tar.bz2 \
  && rm -r "$GNUPGHOME" httpd.tar.bz2.asc \
  && mkdir -p src \
  && tar -xvf httpd.tar.bz2 -C src --strip-components=1 \
  && rm httpd.tar.bz2 \
  && cd src \
  && ./configure \
    --prefix="$HTTPD_PREFIX" \
    --enable-mods-shared=reallyall \
    --with-mpm=prefork \
  && make -j"$(getconf _NPROCESSORS_ONLN)" \
  && make install \
  && cd .. \
  && rm -r src \
  && sed -ri \
    -e 's!^(\s*CustomLog)\s+\S+!\1 /proc/self/fd/1!g' \
    -e 's!^(\s*ErrorLog)\s+\S+!\1 /proc/self/fd/2!g' \
    -e 's/#LoadModule rewrite_module/LoadModule rewrite_module/' \
    -e 's/#LoadModule vhost_alias_module/LoadModule vhost_alias_module/' \
    -e 's/#LoadModule expires_module/LoadModule expires_module/' \
    -e '$ a IncludeOptional conf/other/*.conf' \
    "$HTTPD_PREFIX/conf/httpd.conf" \
  && runDeps="$runDeps $( \
    scanelf --needed --nobanner --recursive /usr/local \
      | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
      | sort -u \
      | xargs -r apk info --installed \
      | sort -u \
  )" \
  \
# PHPのビルド.
  && mkdir -p /usr/src \
  && cd /usr/src \
  && wget -O php.tar.xz "$PHP_URL" \
  && echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c - \
  && echo "$PHP_MD5 *php.tar.xz" | md5sum -c - \
  && wget -O php.tar.xz.asc "$PHP_ASC_URL" \
  && export GNUPGHOME="$(mktemp -d)" \
  && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys $PHP_GPG_KEYS \
  && gpg --batch --verify php.tar.xz.asc php.tar.xz \
  && rm -r "$GNUPGHOME" \
  && docker-php-source extract \
  && cd /usr/src/php \
  && ./configure \
    --with-apxs2="/usr/local/apache2/bin/apxs" \
    --with-config-file-path="$PHP_INI_DIR" \
    --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
    --disable-cgi \
    --enable-ftp \
    --enable-mbstring \
    --enable-mysqlnd \
    --with-curl \
    --with-libedit \
    --with-openssl \
    --with-zlib \
    --enable-maintainer-zts \
  && make -j "$(getconf _NPROCESSORS_ONLN)" \
  && make install \
  && { find /usr/local/bin /usr/local/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; } \
  && make clean \
  && docker-php-source delete \
  && docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
  && docker-php-ext-install gd mbstring mysqli pdo pdo_mysql zip \
  && pecl install uploadprogress && docker-php-ext-enable uploadprogress \
  && pecl install zendopcache \
  && runDeps="$runDeps $( \
    scanelf --needed --nobanner --recursive /usr/local \
      | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
      | sort -u \
      | xargs -r apk info --installed \
      | sort -u \
  )" \
  \
# Apache、PHPの実行に必要なパッケージをインストール.
  && apk del --purge .build-deps \
  && apk add --virtual .httpd-rundeps $runDeps

# ssmtpのインストール・設定
RUN apk --update add --no-cache ssmtp && \
    sed -i -e 's/mailhub=mail/mailhub=mailcatcher.l:1025/' \
    -e '$ a FromLineOverride=YES' \
    /etc/ssmtp/ssmtp.conf

EXPOSE 80

CMD ["httpd-foreground"]
