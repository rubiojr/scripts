#!/bin/bash
#/ Usage: paperless.sh [volumes-dir]
#/
#/ Paperless installer using a single Docker container.
#/
#/ https://github.com/danielquinn/paperless
#/
set -e

# Paperless data and media will be stored here so it can
# be easily backed up and restored.
VOLUMES_PATH=${1:-$HOME/docker/paperless}

# Supported OCR languages
PAPERLESS_OCR_LANGUAGES=${PAPERLESS_OCR_LANGUAGES:-"spa eng"}

# Paperless encrypts using GPG.
# This will be the password
echo "Setting up Paperless"
echo -n "Encryption password: "
read -s GPG_KEY 
echo

if [ -z "$GPG_KEY" ]; then
  echo "Invalid encryption password."
  exit 1
fi

mkdir -p $VOLUMES_PATH/media/documents/{thumbnails,originals} $VOLUMES_PATH/consume
chmod a+rw $VOLUMES_PATH/consume
echo "Starting the container"
docker run -d -e PAPERLESS_PASSPHRASE=$GPG_KEY -e "PAPERLESS_OCR_LANGUAGES=$PAPERLESS_OCR_LANGUAGES" -it \
           --name paperless \
           -v $VOLUMES_PATH/data:/usr/src/paperless/data \
           -v $VOLUMES_PATH/media:/usr/src/paperless/media \
           -v $VOLUMES_PATH/consume:/consume \
           -v $VOLUMES_PATH/export:/export \
           -p 8000:8000 pitkley/paperless runserver 0.0.0.0:8000 >/dev/null

echo "Container post-start tasks"
docker exec -it paperless python manage.py migrate > /dev/null
docker exec -it paperless chown paperless:paperless -R /usr/src/paperless/data

echo "Creating admin user"
docker exec -it paperless python manage.py createsuperuser

echo "Paperless is now ready, waiting for documents..."
docker exec -it paperless python manage.py document_consumer
