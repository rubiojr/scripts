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

node_name="$1"
node_ip="$2"

usage(){
  echo "$0 <node-name> <node-ip>"
}

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

echo Testing duplicated IPs...
ping -W1 -c3 $node_ip >/dev/null 2>&1 && {
  echo "A host already responds to the IP $node_ip. Aborting"
  exit 1
}

echo "Testing tinc master reachability..."
ssh -o ConnectTimeout=3 root@$FIRST_TINC true || {
  echo SSH to the tinc master failed. Aborting.
  exit 1
}

if [ -d tmp ]; then
  echo "tmp directory already exists, aborting."
  exit 1
fi

cp -r template tmp
scp root@$FIRST_TINC:/etc/tinc/$TINC_NET/hosts/* tmp/etc/tinc/$TINC_NET/hosts/

sed -i s/@@NODE_NAME@@/$node_name/ tmp/etc/tinc/$TINC_NET/tinc.conf
sed -i s/@@NODE_IP@@/$node_ip/ tmp/etc/tinc/$TINC_NET/tinc-up
sed -i s/@@NODE_IP@@/$node_ip/ tmp/etc/tinc/$TINC_NET/tinc-up
echo | tincd -K -c tmp/etc/tinc/$TINC_NET $tmpdir
echo "Subnet = $node_ip/32" > tmp/etc/tinc/$TINC_NET/hosts/$node_name.new
cat tmp/etc/tinc/$TINC_NET/hosts/$node_name >> tmp/etc/tinc/$TINC_NET/hosts/$node_name.new
mv tmp/etc/tinc/$TINC_NET/hosts/$node_name.new tmp/etc/tinc/$TINC_NET/hosts/$node_name
wait

cp install.sh.in.tmpl install.sh.in
cat >> install.sh.in <<EOF
  if [ ! -c /dev/net/tun ]; then
    echo "Aborting. /dev/net/tun support not found so tincd won't work."
    exit 1
  fi

  echo "Installing tinc..."
  apt-get install -y -f tinc
  rm -rf /etc/tinc/$TINC_NET
  cp -r tmp/etc/tinc/$TINC_NET /etc/tinc/
  chown root:root -R /etc/tinc/$TINC_NET
  grep -q $TINC_NET /etc/tinc/nets.boot || echo $TINC_NET >> /etc/tinc/nets.boot
  service tinc start || service tinc restart
EOF
echo "exit 0" >> install.sh.in

tar czf $node_name.tar.gz tmp
make-installer.sh $node_name.tar.gz 
rm -f install.sh.in $node_name.tar.gz 
mv install.sh $node_name-dascitizen.sh

for tm in $TINC_MASTERS; do
  scp tmp/etc/tinc/$TINC_NET/hosts/$node_name root@$tm:/etc/tinc/$TINC_NET/hosts/
done

rm -rf tmp
echo Adding the node to /etc/hosts
echo $node_ip $node_name | sudo tee -a /etc/hosts

echo Done!
