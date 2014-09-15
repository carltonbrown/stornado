DUMPNAME=$(date +%Y%m%d%H%M%S).dump.out
DUMPFILE=${BAKNADO_DIR}/raw/${DUMPNAME}
dd if=/dev/urandom of=${DUMPFILE} bs=$((1024**2)) count=3
ruby genmsg.rb ${DUMPFILE} > ${BAKNADO_DIR}/ready/${DUMPNAME}.msg.json
echo "Wrote dump message ${DUMPFILE}" to ${BAKNADO_DIR}/ready/${DUMPNAME}.msg.json
