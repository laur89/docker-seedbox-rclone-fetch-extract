# Seedbox data fetcher & extractor

Dockerised service periodically pulling data from a remote seedbox & extracting
archived files. 

## Running/configuration

### Required environment variables

- `REMOTE`: your configured rclone remote
- `SRC_DIR`: path to the source directory on your remote to pull data from
- `DEST_FINAL`: path to the mounted directory in container to finally move pulled
   data to; note this would be the directory monitored by your \*arr services  et al

### Optional environment variables

- `DEST_INITIAL`: path to the mounted dir in container where rclone initially downloads
   data to; if not defined, then a directory is created inside `$DEST_FINAL`; it's 
   highly recommended you define this. also make sure it lies on the same filesystem
   as `DEST_FINAL`, so `mv` command is atomic;
- `CRON_PATTERN`: cron pattern to be used to execute the syncing script; defaults to every 5 min
  (eg `*/10 *` to execute every 10 minutes);
- `SKIP_EXTRACT`: set this to any non-empty value to skip archived file extraction;
- `RCLONE_OPTS`: space-separated additional options to be passed to all `rclone` commands;
  useful eg if you want to override the `--bwlimit` option (defaults to 15M);
- `PGID`: user id;
- `PUID`: group id;

### Required mountpoints & files

- you need to provide valid mountpoint to your defined `DEST_FINAL` (& `DEST_INITIAL`
  if env var was defined)
- mount point to configuration root dir at `/config` also needs to be provided;
- valid rclone config file `rclone.conf` needs to be present in `/config` mount dir;
  this conf needs to define the remote set by `REMOTE` env var;


Note at the container startup it immediately tries updating the records, and
container will halt on any error; this is for sanity check to make sure you
don't launch the service with invalid settings. Downside is the container can't
be started without Internet connection.


## Example docker command:

	docker run -d \
		--name seedbox-fetcher \
		-e REMOTE=seedbox \
		-e SRC_DIR=files/complete \
		-e DEST_FINAL=/data/complete \
		-e DEST_INITIAL=/data/tmp \
		-e UID=1003 \
		-v /data/downloads/torrent-complete:/data/complete \
		-v /data/downloads/torrent-rclone-tmp:/data/tmp \
		-v /data/configs/seedbox-fetcher:/config \
		layr/seedbox-rclone-fetcher-extractor
