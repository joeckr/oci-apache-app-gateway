ARG VERSION=8.5
ARG REGISTRY=docker.io/library
FROM $REGISTRY/php:$VERSION-apache-trixie

RUN rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/partial && \
    apt-get -o APT::Sandbox::User=root update && \
    apt-get -o APT::Sandbox::User=root -o Dpkg::Options::=--force-not-root upgrade -y && \
    apt-get -o APT::Sandbox::User=root -o Dpkg::Options::=--force-not-root --no-install-recommends install -y libapache2-mod-auth-openidc=2.4.* apache2-utils=2.4.* && \
    apt-get -o APT::Sandbox::User=root clean && \
    rm -rf /var/lib/apt/lists/*

RUN a2enmod rewrite && \
    a2enmod auth_openidc

COPY ./src/ports.conf /etc/apache2/ports.conf

RUN rm -rf /var/www/html && \
    mkdir -p /var/www/html && \
    chgrp -R 0 /var/www/html && \
    chmod -R g+rwX /var/www/html

COPY ./src/index.html /var/www/html/index.html

RUN chgrp -R 0 /etc/apache2/conf-enabled/ && \
    chmod -R g+rwX /etc/apache2/conf-enabled/

EXPOSE 8080

COPY ./src/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh && \
    chown 0:0 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD [ "apache2-foreground" ]
