rm -rf /tmp/backup/*
mkdir -p /tmp/backup/ready
mkdir -p /tmp/backup/remote
mkdir -p /tmp/backup/raw
bash newdump.sh
mkdir -p /tmp/backup/
mkdir -p /tmp/backup/processing
mkdir -p /tmp/backup/complete
