export AWS_ACCESS_KEY_ID="SCWDGPTYWZWMB0M18F67"
export AWS_SECRET_ACCESS_KEY="877b6ff2-ae1b-4183-965d-1a4c2fb9f827"

#!/bin/bash

export PASSPHRASE=""

export AWS_ACCESS_KEY_ID="SCWYRMRP1D7XY229N6YB"
export AWS_SECRET_ACCESS_KEY="2bef7f33-3617-446a-ad9a-d2067c4cec85"

# Variables
BUCKET_URL="s3://gewisfiles01-retrieval/$(date +%Y)"
RESTORE_DIR="/cygdrive/d/duplicity_restore"
ARCHIVE_DIR="/cygdrive/d/duplicity"
GPG_KEY="89865D00"
S3_ENDPOINT="https://s3.nl-ams.scw.cloud"
S3_REGION="nl-ams"

# Restore command
duplicity \
  restore \
  --s3-use-glacier \
  --s3-endpoint-url "$S3_ENDPOINT" \
  --s3-region-name "$S3_REGION" \
  --archive-dir "$ARCHIVE_DIR" \
  --name backup-gewisfiles01-retrieval \
  --encrypt-key "$GPG_KEY" \
  --sign-key "$GPG_KEY" \
  "$BUCKET_URL" \
  "$RESTORE_DIR" 2>&1 | tee restore-log.txt