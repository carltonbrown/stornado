rm -rf ${BAKNADO_DIR}/*
mkdir -p ${BAKNADO_DIR}/ready
mkdir -p ${BAKNADO_DIR}/remote
mkdir -p ${BAKNADO_DIR}/raw
bash newdump.sh
mkdir -p ${BAKNADO_DIR}/
mkdir -p ${BAKNADO_DIR}/processing
mkdir -p ${BAKNADO_DIR}/complete
