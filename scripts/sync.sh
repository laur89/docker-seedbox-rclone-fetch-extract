#!/usr/bin/env bash

#####################################
readonly SELF="${0##*/}"
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"  # location of this script
JOB_ID="sync-$$"
#####################################

is_upstream_removed() {
    local local_node remote_node
    local_node="${1%/}"

    for remote_node in "${REMOTE_NODES[@]}"; do
        [[ "$remote_node" == "$local_node" ]] && return 1
    done

    return 0  # no match, hence asset has been removed on remote
}


#### ENTRY
source /common.sh || { echo -e "    ERROR: failed to import /common.sh"; exit 1; }

_prepare_locking
exlock_now || { info "unable to obtain lock: $?"; exit 0; }

validate_config_common
check_connection || fail "no internets"

REMOTE_NODES=()
INCLUDES=()
RCLONE_FLAGS=(
  --config "$RCLONE_CONF"
  --fast-list
  --bwlimit 15M
  --use-mmap
  --transfers 10
)

if [[ -n "${RCLONE_OPTS[*]}" ]]; then
    IFS=' ' read -ra rclone_opts <<< "$RCLONE_OPTS"
    RCLONE_FLAGS+=("${rclone_opts[@]}")   # allow extending w/ user-provided opts
fi

# non-empty $DEST_INITIAL suggests issues during previous run(s):
is_dir_empty "$DEST_INITIAL" || err "expected DEST_INITIAL dir [$DEST_INITIAL] to be empty, but it's not"

# first list the remote source dir contents:
remote_nodes="$(rclone lsf --log-file "$LOG_ROOT/rclone-lsf.log" \
    "${RCLONE_FLAGS[@]}" -- "$REMOTE:$SRC_DIR")" || fail "lsf failed w/ $?"  # TODO: pushover!
readarray -t remote_nodes <<< "$remote_nodes"

# ...then verify which assets we haven't already downloaded-processed:
for f in "${remote_nodes[@]}"; do
    REMOTE_NODES+=("${f%/}")  # note we remove possible trailing slash
    [[ -e "$DEST_FINAL/${f%/}" ]] && continue  # already been processed
    INCLUDES+=('--include')
    [[ "$f" == */ ]] && INCLUDES+=("/${f}**") || INCLUDES+=("/$f")
done

# ...nuke assets that are already removed on the remote:
if [[ -z "$SKIP_LOCAL_RM" ]]; then
    while IFS= read -r -d $'\0' f; do
        if is_upstream_removed "$f"; then
            rm -rf -- "$DEST_FINAL/$f" \
                    && info "removed [$DEST_FINAL/$f] whose remote counterpart is gone" \
                    || err "[rm -rf $DEST_FINAL/$f] failed w/ $?"
        fi
    done< <(find -L "$DEST_FINAL" -mindepth 1 -maxdepth 1 -printf '%f\0')
fi

# pull new assets:
if [[ "${#INCLUDES[@]}" -gt 0 ]]; then
    rclone copy --log-file "$LOG_ROOT/rclone-copy.log" "${RCLONE_FLAGS[@]}" \
        "$REMOTE:$SRC_DIR" "$DEST_INITIAL" "${INCLUDES[@]}" || fail "copy failed w/ $?"  # TODO: pushover!
fi

# process assets.
# note we work on _all_ nodes in $DEST_INITIAL, not only ones
# that were pulled during this execution; this is essentially
# for retrying previous failures:
while IFS= read -r -d $'\0' i; do
    if [[ -z "$SKIP_EXTRACT" ]]; then
        extract.sh "$i" || { err "[$i] extraction failed"; continue; }  # TODO: pushover!
    fi
    mv -- "$i" "$DEST_FINAL/" || { err "[mv $i $DEST_FINAL/] failed w/ $?"; continue; }  # TODO: pushover!
done < <(find -L "$DEST_INITIAL" -mindepth 1 -maxdepth 1 -print0)

exit 0
