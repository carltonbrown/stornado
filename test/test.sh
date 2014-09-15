export BAKNADO_DIR=/var/tmp/baknado
export BAKNADO_CHUNK_SIZE=$((1024**2))
bash setup.sh
ruby -I../lib ../bin/baknado
