rm -rf /tmp/backup/*
mkdir -p /tmp/backup/ready
mkdir -p /tmp/backup/remote
mkdir -p /tmp/backup/raw
dd if=/dev/urandom of=/tmp/backup/raw/dump.out bs=$((1024**2)) count=3
#dd if=/dev/zero of=/tmp/backup/raw/dump.out bs=$((1024**2)) count=3
ruby genmsg.rb /tmp/backup/raw/dump.out > /tmp/backup/ready/dump.msg.json
mkdir -p /tmp/backup/
mkdir -p /tmp/backup/processing
mkdir -p /tmp/backup/complete
