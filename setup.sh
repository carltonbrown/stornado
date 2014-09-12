rm -rf /tmp/backup/*
mkdir -p /tmp/backup/ready
mkdir -p /tmp/backup/remote
mkdir -p /tmp/backup/raw
cp dump.msg.json /tmp/backup/ready
dd if=/dev/zero of=/tmp/backup/raw/dump.out bs=$((1024**2)) count=50
mkdir -p /tmp/backup/
mkdir -p /tmp/backup/processing
mkdir -p /tmp/backup/complete
