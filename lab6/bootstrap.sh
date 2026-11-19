#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=180 install -y docker.io curl
systemctl enable --now docker

install -d -m 0755 /opt/lab6
printf '%s\n' '<html lang="pl"><title>Lab 6</title><h1>Lab 6: Nginx na Azure VM</h1></html>' > /opt/lab6/index.html

if docker container inspect lab6-web >/dev/null 2>&1; then
  docker rm -f lab6-web
fi

docker run --detach --name lab6-web --restart unless-stopped \
  --publish 127.0.0.1:8080:80 \
  --volume /opt/lab6/index.html:/usr/share/nginx/html/index.html:ro \
  nginx:stable-alpine

curl -fsS --retry 10 --retry-connrefused http://127.0.0.1:8080/
