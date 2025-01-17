# Base Image
ARG nominatim_version=4.3.1
FROM ubuntu:20.04 as base
ARG nominatim_version

# Avoid prompts with apt
ENV DEBIAN_FRONTEND=noninteractive

# Install basic tools, cmake from default repos and official kitware repos, and other dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y cmake gcc make apt-transport-https ca-certificates gnupg software-properties-common wget apt-utils && \
    wget -qO - https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ focal main" > /etc/apt/sources.list.d/kitware.list && \
    apt-get update && \
    apt-get install -y cmake gcc make && \
    apt-get install -y -qq --no-install-recommends build-essential cmake g++ nlohmann-json3-dev liblua5.2-dev libboost-dev libboost-system-dev libboost-filesystem-dev libexpat1-dev zlib1g-dev libxml2-dev libbz2-dev libpq-dev libgeos-dev libgeos++-dev libproj-dev postgresql-server-dev-all php curl

# Install Python 3.7 and set it as default
RUN apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y python3.7 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.7 1

# Build Nominatim
RUN cd /srv && \
    curl -k --silent -L http://www.nominatim.org/release/Nominatim-${nominatim_version}.tar.bz2 -o v${nominatim_version}.tar.bz2 && \
    tar xf v${nominatim_version}.tar.bz2 && \
    rm v${nominatim_version}.tar.bz2 && \
    mv Nominatim-${nominatim_version} nominatim && \
    cd nominatim && mkdir build && cd build && cmake .. && make

# Final Image
FROM ubuntu:20.04

ARG nominatim_version
LABEL maintainer="Peter Evans <mail@peterevans.dev>" \
      org.opencontainers.image.title="nominatim-k8s" \
      org.opencontainers.image.description="Nominatim for Kubernetes on Google Container Engine (GKE)." \
      org.opencontainers.image.authors="Peter Evans <mail@peterevans.dev>" \
      org.opencontainers.image.url="https://github.com/peter-evans/nominatim-k8s" \
      org.opencontainers.image.vendor="https://peterevans.dev" \
      org.opencontainers.image.licenses="MIT" \
      app.tag="nominatim${nominatim_version}"

# Avoid prompts with apt
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages and PostgreSQL repository
RUN apt-get -y update && \
    apt-get install -y --no-install-recommends wget gnupg software-properties-common && \
    echo 'deb http://apt.postgresql.org/pub/repos/apt/ focal-pgdg main' > /etc/apt/sources.list.d/pgdg.list && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get -y update && \
    apt-get install -y --no-install-recommends locales postgresql-server-dev-14 postgresql-14-postgis-3 postgresql-contrib-14 apache2 php php-pgsql libapache2-mod-php libboost-filesystem-dev php-pear php-db php-intl python3-dev python3-psycopg2 curl ca-certificates sudo && \
    locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 && apt-get clean && rm -rf /var/lib/apt/lists/* && rm -rf /tmp/* /var/tmp/*

# Copy the application from the builder image
COPY --from=base /srv/nominatim /srv/nominatim

# Configure Nominatim and Apache
COPY local.php /srv/nominatim/build/settings/local.php
COPY nominatim.conf /etc/apache2/sites-enabled/000-default.conf

# Allow remote connections to PostgreSQL
RUN echo "host all  all    0.0.0.0/0  trust" >> /etc/postgresql/14/main/pg_hba.conf && \
    echo "listen_addresses='*'" >> /etc/postgresql/14/main/postgresql.conf

# Set the entrypoint
COPY docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 5432 8080
