#!/bin/bash
export PASSPHRASE=""

export AWS_ACCESS_KEY_ID="SCWDGPTYWZWMB0M18F67"
export AWS_SECRET_ACCESS_KEY="877b6ff2-ae1b-4183-965d-1a4c2fb9f827"

duplicity \
	incr \
	--full-if-older-than "4M" \
	--asynchronous-upload \
	--s3-use-glacier \
	--s3-endpoint-url "https://s3.nl-ams.scw.cloud" \
	--s3-region-name "nl-ams" \
	--volsize 1000 \
	--archive-dir /cygdrive/d/duplicity \
	--exclude-filelist "/home/SYSTEM/dontBackupDatas.txt" \
	--name backup-gewisfiles01-datas \
	--encrypt-key="89865D00" \
	--sign-key="89865D00" \
	/cygdrive/d/datas s3://gewisfiles01-datas/$(date +%Y)-Q$(date +%q) 2>&1 | tee backup-datas.txt

sleep 1m

export AWS_ACCESS_KEY_ID="SCWMGTJ5BR36DZFCHVXB"
export AWS_SECRET_ACCESS_KEY="5c93d28e-cb6a-4beb-92c7-6a5e9b0b79bd"

duplicity \
	incr \
	--full-if-older-than "4M" \
	--asynchronous-upload \
	--s3-use-glacier \
	--s3-endpoint-url "https://s3.nl-ams.scw.cloud" \
	--s3-region-name "nl-ams" \
	--volsize 750 \
	--archive-dir /cygdrive/d/duplicity \
	--name backup-gewisfiles01-homes \
	--encrypt-key="89865D00" \
	--sign-key="89865D00" \
	/cygdrive/d/homes s3://gewisfiles01-homes/$(date +%Y)-Q$(date +%q) 2>&1 | tee backup-homes.txt
	
sleep 1m
	
export AWS_ACCESS_KEY_ID="SCW15K36RFGZD1Y1JTGS"
export AWS_SECRET_ACCESS_KEY="c37d935e-90df-4340-88ef-02f15192cf0f"
	
# Note that the photo backup is not signed because a 25GB signature file needs to be uploaded every time	

duplicity \
	incr \
	--full-if-older-than "1Y" \
	--asynchronous-upload \
	--s3-use-glacier \
	--s3-endpoint-url "https://s3.nl-ams.scw.cloud" \
	--s3-region-name "nl-ams" \
	--volsize 1000 \
	--archive-dir /cygdrive/d/duplicity \
	--name backup-gewisfiles01-photos \
	--s3-multipart-chunk-size 100 \
	--encrypt-key="89865D00" \
	/cygdrive/d/datas/Photos s3://gewisfiles01-photos/$(date +%Y)-Q$(date +%q) 2>&1 | tee backup-photos.txt

sleep 1m

export AWS_ACCESS_KEY_ID="SCWYRMRP1D7XY229N6YB"
export AWS_SECRET_ACCESS_KEY="2bef7f33-3617-446a-ad9a-d2067c4cec85"

duplicity \
	incr \
	--full-if-older-than "2Y" \
	--asynchronous-upload \
	--s3-use-glacier \
	--s3-endpoint-url "https://s3.nl-ams.scw.cloud" \
	--s3-region-name "nl-ams" \
	--volsize 1000 \
	--archive-dir /cygdrive/d/duplicity \
	--exclude-filelist "/home/SYSTEM/dontBackupMP3.txt" \
	--name backup-gewisfiles01-mp3 \
	--encrypt-key="89865D00" \
	--sign-key="89865D00" \
	/cygdrive/d/datas/MP3 s3://gewisfiles01-mp3/$(date +%Y) 2>&1 | tee backup-mp3.txt
