#!/bin/bash
set -e

if [ -z "$TINC_MASTERS" ]; then
  echo Invalid TINC_MASTERS environment variable
  exit 1
fi

if [ -z "$TINC_NET" ]; then
  echo Invalid TINC_NET environment variable
  exit 1
fi

FIRST_TINC=$(echo $TINC_MASTERS | cut -d' ' -f1)

host="$1"
node_name="$2"
node_ip="$3"

usage(){
  echo "$0 <host> <node-name> <node-ip>"
}

if [ -z "$host" ]; then
  echo Missing host name or ip
  usage
  exit 1
fi

if [ -z "$node_name" ]; then
  echo Missing node name
  usage
  exit 1
fi

if [ -z "$node_ip" ]; then
  echo Missing node ip
  usage
  exit 1
fi

echo Testing host reachability...
ping -W1 -c3 $host >/dev/null 2>&1 || {
  echo "Host $host did not reply to ping. Aborting."
  exit 1
}

echo Testing duplicated IPs...
ping -W1 -c3 $node_ip >/dev/null 2>&1 && {
  echo "A host already responds to the IP $node_ip. Aborting"
  exit 1
}

echo "Testing root access..."
ssh -o ConnectTimeout=3 root@$host true || {
  echo SSH to the host as root failed. Aborting.
  exit 1
}

echo "Testing /dev/net/tun presence..."
ssh -o ConnectTimeout=3 root@$host test -c /dev/net/tun || {
  echo "/dev/net/tun char device not detected (container?). Aborting."
  exit 1
}

echo "Testing tinc master reachability..."
ssh -o ConnectTimeout=3 root@$FIRST_TINC true || {
  echo SSH to the tinc master failed. Aborting.
  exit 1
}

cp -r template tmp
trap "rm -rf tmp" EXIT
scp root@$FIRST_TINC:/etc/tinc/$TINC_NET/hosts/* tmp/etc/tinc/$TINC_NET/hosts/

sed -i s/@@NODE_NAME@@/$node_name/ tmp/etc/tinc/$TINC_NET/tinc.conf
sed -i s/@@NODE_IP@@/$node_ip/ tmp/etc/tinc/$TINC_NET/tinc-up
sed -i s/@@NODE_IP@@/$node_ip/ tmp/etc/tinc/$TINC_NET/tinc-up
echo | tincd -K -c tmp/etc/tinc/$TINC_NET $tmpdir
echo "Subnet = $node_ip/32" > tmp/etc/tinc/$TINC_NET/hosts/$node_name.new
cat tmp/etc/tinc/$TINC_NET/hosts/$node_name >> tmp/etc/tinc/$TINC_NET/hosts/$node_name.new
mv tmp/etc/tinc/$TINC_NET/hosts/$node_name.new tmp/etc/tinc/$TINC_NET/hosts/$node_name
wait

ssh root@$host apt-get install -y -f tinc
ssh root@$host rm -rf /etc/tinc/$TINC_NET
scp -r tmp/etc/tinc/$TINC_NET root@$host:/etc/tinc/
ssh root@$host "chown root:root -R /etc/tinc/$TINC_NET"
ssh root@$host "service tinc start || service tinc restart"
ssh root@$host "grep -q $TINC_NET /etc/tinc/nets.boot || echo $TINC_NET >> /etc/tinc/nets.boot"
for tm in $TINC_MASTERS; do
  scp tmp/etc/tinc/$TINC_NET/hosts/$node_name root@$tm:/etc/tinc/$TINC_NET/hosts/
done

echo Adding the node to /etc/hosts
echo $node_ip $node_name | sudo tee -a /etc/hosts

echo Done!
