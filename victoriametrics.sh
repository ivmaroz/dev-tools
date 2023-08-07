#!/bin/bash

set -e

########################################################################################################################

echo "Create VictoriaMetrics system group"
if ! getent passwd victoriametrics >/dev/null; then
  sudo groupadd --system victoriametrics
  sudo useradd -s /sbin/nologin --system -g victoriametrics victoriametrics
fi

########################################################################################################################

echo "Create data & configs directories"

if [ ! -d /var/lib/victoriametrics ]; then
  sudo mkdir -p /var/lib/victoriametrics
  sudo chown victoriametrics:victoriametrics /var/lib/victoriametrics
fi

sudo mkdir -pv /etc/victoriametrics

########################################################################################################################

echo "Update required files"

for COMMAND in jq wget curl vim; do
  if ! command -v "$COMMAND" &>/dev/null; then
    sudo apt update
    sudo apt -y install jq wget curl vim
    break
  fi
done

########################################################################################################################

VERSION=$(curl -s https://api.github.com/repos/VictoriaMetrics/VictoriaMetrics/releases/latest | jq -r '.tag_name' | sed 's/^v//')

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OS="darwin"
else
  echo "Unknown OS"
  exit 1
fi

ARCHITECTURE=""
case $(uname -m) in
i386) ARCHITECTURE="386" ;;
i686) ARCHITECTURE="386" ;;
x86_64) ARCHITECTURE="amd64" ;;
arm) dpkg --print-architecture | grep -q "arm64" && ARCHITECTURE="arm64" || ARCHITECTURE="arm" ;;
esac

########################################################################################################################

echo "Download VictoriaMetrics files"

if [ -d /tmp/victoriametrics ]; then
  sudo rm -rf /tmp/victoriametrics
fi
mkdir -p /tmp/victoriametrics

wget "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${VERSION}/victoria-metrics-${OS}-${ARCHITECTURE}-v${VERSION}.tar.gz" \
  -O /tmp/victoriametrics/victoriametrics.tar.gz

cd /tmp/victoriametrics/
tar -xf victoriametrics.tar.gz

########################################################################################################################

if [ ! -f /usr/local/bin/victoria-metrics ] || [ "$(shasum -a256 victoria-metrics-prod | awk '{ print $1 }')" != "$(shasum -a256 /usr/local/bin/victoria-metrics | awk '{ print $1 }')" ]; then
  sudo mv -v victoria-metrics-prod /usr/local/bin/victoria-metrics
  UPDATED=1
else
  UPDATED=0
fi

if [ ! -f /etc/victoriametrics/victoriametrics.yml ]; then

  sudo tee /etc/victoriametrics/victoriametrics.yml <<EOF
# my global config
global:
  scrape_interval: 15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  # The job name is added as a label \`job=<job_name>\` to any timeseries scraped from this config.
  - job_name: "victoriametrics"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
      - targets: ["localhost:8428"]

EOF

fi

########################################################################################################################

if [ ! -f /etc/systemd/system/victoriametrics.service ]; then

  sudo tee /etc/systemd/system/victoriametrics.service <<EOF
[Unit]
Description=VictoriaMetrics
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=victoriametrics
Group=victoriametrics
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/local/bin/victoria-metrics \\
  -storageDataPath /var/lib/victoriametrics \\
  -retentionPeriod 1 \\
  -promscrape.config=/etc/victoriametrics/victoriametrics.yml \\
  -promscrape.config.strictParse=false

SyslogIdentifier=victoriametrics
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl start victoriametrics.service
  sudo systemctl enable victoriametrics.service

else

  if [[ $UPDATED -eq 1 ]]; then
    sudo systemctl restart victoriametrics.service
  fi
fi

########################################################################################################################

rm -rf /tmp/victoriametrics