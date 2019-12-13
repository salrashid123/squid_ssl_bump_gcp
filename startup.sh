#! /bin/bash    
# apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -qq wget curl supervisor git openssl python-pip build-essential libssl-dev wget python-pip vim python-setuptools inotify-tools google-cloud-sdk

apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -qq wget curl supervisor git openssl python-pip build-essential libssl-dev wget python-pip vim python-setuptools inotify-tools google-cloud-sdk

mkdir -p /var/log/supervisor
mkdir /apps/
cd /apps/

export PROJECTID=$(curl -s http://metadata.google.internal/computeMetadata/v1/project/project-id -H "Metadata-Flavor: Google")

/usr/bin/gsutil cp   gs://$PROJECTID-squid-src/squid.tar .
tar xf squid.tar
rm squid.tar

# wget -O - http://www.squid-cache.org/Versions/v4/squid-4.9.tar.gz | tar zxfv - \
#     && CPU=$(( `nproc --all` )) \
#     && cd /apps/squid-4.9/ \
#     && ./configure --prefix=/apps/squid --enable-icap-client --enable-ssl --with-openssl --enable-ssl-crtd  \
#     && make -j$CPU \
#     && make install \
#     && cd /apps \
#     && rm -rf /apps/squid-4.9

chown -R nobody /apps/
mkdir -p  /apps/squid/var/lib/
/apps/squid/libexec/security_file_certgen -c -s /apps/squid/var/lib/ssl_db -M 1MB

cd /apps
git clone https://github.com/netom/pyicap
cd /apps/pyicap
./setup.py install

cd /
export HOME=/root


curl -O "https://repo.stackdriver.com/stack-install.sh"
bash stack-install.sh --write-gcm
service stackdriver-agent restart

cat <<EOF >   /etc/default/google-fluentd
export no_proxy=169.254.169.254 
EOF

curl -sSO https://dl.google.com/cloudagents/install-logging-agent.sh
bash install-logging-agent.sh


mkdir /data
cd /data
cat <<EOF > /apps/resync.sh
#!/bin/sh
export PROJECTID=$(curl -s http://metadata.google.internal/computeMetadata/v1/project/project-id -H "Metadata-Flavor: Google")
/usr/bin/gsutil -m rsync   -d -r  gs://$PROJECTID-squid-src/data/ /data/
EOF
chmod u+x /apps/resync.sh

/apps/resync.sh

sed -E 's/(-+(BEGIN|END) RSA PRIVATE KEY-+) *| +/\1\n/g' <<< `gcloud beta secrets versions access 1 --secret squid` > /data/certs/CA_key.pem


cat <<EOF > /etc/google-fluentd/config.d/squid.conf
<source>
  @type tail
  path /apps/squid/var/logs/access.log
  format /^(?<date>[^ ]+)\s+(?<duration>.*) (?<client address>.*) (?<result code>.*) (?<bytes>.*) (?<request method>.*) (?<url>.*) (?<rfc931>.*) (?<hierarchy code>.*) (?<type>.*)$/
  pos_file /var/log/td-agent/squid-access.log.pos
  tag squid
</source>

<filter squid.**>
  @type record_transformer
  @log_level debug
</filter>

<match squid.**>
  @type google_cloud
  use_metadata_service true
  @log_level debug
</match>
EOF

cat <<EOF > /etc/supervisor/supervisord.conf
[supervisord]
nodaemon=true

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[unix_http_server]
file=/run/supervisord.sock

[supervisorctl]
serverurl=unix:///run/supervisord.sock

[program:squid3]
command=/apps/squid/sbin/squid  -NsY -f /data/squid.conf.https_proxy
stdout_events_enabled=true
stderr_events_enabled=true

[program:icap_filter]
command=/usr/bin/python /data/pyicap/filter.py
stdout_events_enabled=true
stderr_events_enabled=true
EOF


service supervisor restart
service google-fluentd restart

cat <<EOF > /apps/monitorfile.sh
#!/bin/sh
while true; do
  inotifywait -e modify /data/pyicap/filter_list.txt
  /usr/bin/supervisorctl -c  /etc/supervisor/supervisord.conf restart icap_filter  
done
EOF

chmod u+x /apps/monitorfile.sh
/apps/monitorfile.sh &

crontab -l > mycron
echo "*/5 * * * * /bin/bash /apps/resync.sh" >> mycron
crontab mycron
