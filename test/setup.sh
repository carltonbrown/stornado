set -e
if [[ ! $BAKNADO_DIR ]]; 
  echo "Baknado dir not set."  
  exit 1
fi

rm -rf --preserve-root ${BAKNADO_DIR}/*
mkdir -p ${BAKNADO_DIR}/ready
mkdir -p ${BAKNADO_DIR}/remote
mkdir -p ${BAKNADO_DIR}/raw
bash newdump.sh
mkdir -p ${BAKNADO_DIR}/
mkdir -p ${BAKNADO_DIR}/processing
mkdir -p ${BAKNADO_DIR}/complete
