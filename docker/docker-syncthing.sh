# https://github.com/linuxserver/docker-syncthing
docker create \
  --name=syncthing \
  -v /docker/syncthing/config:/config \
  -v /docker/syncthing/data:/data \
  -e PGID=0 -e PUID=0 \
  -p 8384:8384 -p 22000:22000 -p 21027:21027/udp \
  linuxserver/syncthing
