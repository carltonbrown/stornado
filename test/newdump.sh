DUMPNAME=$(date +%Y%m%d%H%M%S).dump.out
DUMPFILE=/tmp/backup/raw/${DUMPNAME}
dd if=/dev/urandom of=${DUMPFILE} bs=$((1024**2)) count=3
#dd if=/dev/zero of=/tmp/backup/raw/dump.out bs=$((1024**2)) count=3
ruby genmsg.rb ${DUMPFILE} > /tmp/backup/ready/${DUMPNAME}.msg.json
echo "Wrote dump ${DUMPFILE}" to /tmp/backup/ready/${DUMPNAME}.msg.json
