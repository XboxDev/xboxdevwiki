FROM php:5.6-apache-jessie

RUN apt-get update && apt-get install -y python imagemagick

RUN docker-php-ext-install mysqli

RUN mv /etc/apache2/mods-available/rewrite.load /etc/apache2/mods-enabled/
COPY apache2/ports.conf /etc/apache2/ports.conf
COPY apache2/sites-enabled/ /etc/apache2/sites-enabled/
COPY --chown=www-data:www-data mediawiki /opt/bitnami/apps/mediawiki

ARG WG_SECRET_KEY
ARG WG_DB_PASSWORD
ARG GCS_ACCESS_KEY
ARG GCS_SECRET_KEY
ENV WG_SECRET_KEY=${WG_SECRET_KEY}
ENV WG_DB_PASSWORD=${WG_DB_PASSWORD}
ENV GCS_ACCESS_KEY=${GCS_ACCESS_KEY}
ENV GCS_SECRET_KEY=${GCS_SECRET_KEY}
