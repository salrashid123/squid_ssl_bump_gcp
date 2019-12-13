FROM debian:9
RUN apt-get -y update
RUN apt-get install -y curl supervisor git openssl build-essential libssl-dev wget python-pip vim sudo
RUN mkdir -p /var/log/supervisor
RUN adduser root sudo
WORKDIR /apps/

RUN wget -O - http://www.squid-cache.org/Versions/v4/squid-4.9.tar.gz | tar zxfv - \
    && CPU=$(( `nproc --all`-1 )) \
    && cd /apps/squid-4.9/ \
    && ./configure --prefix=/apps/squid --enable-icap-client --enable-ssl --with-openssl --enable-ssl-crtd  \
    && make -j$CPU \
    && make install \
    && cd /apps \
    && rm -rf /apps/squid-4.9

RUN mkdir -p  /apps/squid/var/lib/
RUN /apps/squid/libexec/security_file_certgen -c -s /apps/squid/var/lib/ssl_db -M 1MB

RUN chown -R nobody /apps/



