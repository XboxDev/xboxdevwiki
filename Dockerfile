FROM php:5.6-apache-jessie

RUN docker-php-ext-install mysqli

RUN mv /etc/apache2/mods-available/rewrite.load /etc/apache2/mods-enabled/
COPY apache2/ports.conf /etc/apache2/ports.conf
COPY apache2/sites-enabled/ /etc/apache2/sites-enabled/
COPY --chown=www-data:www-data mediawiki /opt/bitnami/apps/mediawiki

ARG WG_SECRET_KEY
ARG WG_DB_PASSWORD
ENV WG_SECRET_KEY=${WG_SECRET_KEY}
ENV WG_DB_PASSWORD=${WG_DB_PASSWORD}
