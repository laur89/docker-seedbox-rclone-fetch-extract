#!/usr/bin/env bash

#####################################
readonly SELF="${0##*/}"
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"  # location of this script
JOB_ID="sync-$$"
#####################################

is_upstream_removed() {
    local local_node remote_node
    local_node="$1"

    for remote_node in "${REMOTE_NODES[@]}"; do
        [[ "$remote_node" == "$local_node" ]] && return 1
    done

    return 0  # no match, hence asset has been removed on remote
}


#### ENTRY
source /common.sh || { echo -e "    ERROR: failed to import /common.sh"; exit 1; }

_prepare_locking
exlock_now || { info "unable to obtain lock: $?"; exit 0; }

check_connection || fail "no internets"

[[ -f "$ENV_ROOT/pre-parse.sh" ]] && source "$ENV_ROOT/pre-parse.sh"

REMOTE_NODES=()
ADD_FILTER=()
TO_DOWNLOAD_LIST=()

if [[ -n "${RCLONE_FLAGS[*]}" ]]; then
    IFS="$SEPARATOR" read -ra RCLONE_FLAGS <<< "$RCLONE_FLAGS"
else  # no rclone flags provided, define our set of defaults;
    # note if your seedbox had an nvme or a dedicated disk plan, then there
    # would be no need for bwlimit
    RCLONE_FLAGS=(
      --config "$RCLONE_CONF"
      --fast-list
      --bwlimit 20M
      --use-mmap
      --transfers 10
    )
fi

if [[ -n "${RCLONE_OPTS[*]}" ]]; then
    IFS="$SEPARATOR" read -ra rclone_opts <<< "$RCLONE_OPTS"
    RCLONE_FLAGS+=("${rclone_opts[@]}")   # allow extending w/ user-provided opts
fi

[[ -f "$ENV_ROOT/post-parse.sh" ]] && source "$ENV_ROOT/post-parse.sh"
validate_config_common  # check after post-parse.sh sourcing to make sure nothing's been hecked up

# non-empty $DEST_INITIAL suggests issues during previous run(s):
find -L "$DEST_INITIAL" -mindepth "$DEPTH" -maxdepth "$DEPTH" -print -quit | grep -q . && err "expected DEST_INITIAL dir [$DEST_INITIAL] to be empty at depth=$DEPTH, but it's not"

# move assets _to_ remote (.torrent files to watchdir):
if [[ -d "$WATCHDIR_SRC" ]] && ! is_dir_empty "$WATCHDIR_SRC"; then
    rclone move --log-file "$LOG_ROOT/rclone-move.log" "${RCLONE_FLAGS[@]}" \
            "$WATCHDIR_SRC" "$REMOTE:$WATCHDIR_DEST" || err "rclone move from [$WATCHDIR_SRC] to [$WATCHDIR_DEST] failed w/ $?"  # TODO: pushover! but do _not_ fail out here
fi

# first list the remote source dir contents:
remote_nodes="$(rclone lsf --log-file "$LOG_ROOT/rclone-lsf.log" \
    "${RCLONE_FLAGS[@]}" --max-depth "$DEPTH" -- "$REMOTE:$SRC_DIR")" || fail "rclone lsf failed w/ $?"  # TODO: pushover!
readarray -t remote_nodes <<< "$remote_nodes"

# ...then verify which assets we haven't already downloaded-processed, and compile
# them into rclone '--filter' options:
for f in "${remote_nodes[@]}"; do
    unset paths
    readarray -d / paths < <(printf '%s' "${f//$'\n'}")  # process-substitution via printf is to prevent trailing newline that's produced by bash here-string (<<<)
    [[ "${#paths[@]}" -ne "$DEPTH" ]] && continue

    REMOTE_NODES+=("${f%/}")  # note we remove possible trailing slash; this way we can compare values to local nodes verbatim
    [[ -e "$DEST_FINAL/${f%/}" ]] && continue  # already been processed
    TO_DOWNLOAD_LIST+=("$f")
    ADD_FILTER+=('--filter')
    f_escaped="$(sed 's/[.\*^$()+?{}|]/\\&/g;s/[][]/\\&/g' <<< "$f")"
    [[ "$f_escaped" == */ ]] && ADD_FILTER+=("+ /${f_escaped}**") || ADD_FILTER+=("+ /$f_escaped")
done

# ...nuke assets that are already removed on the remote:
if [[ -z "$SKIP_LOCAL_RM" ]]; then
    while IFS= read -r -d $'\0' f; do
        if is_upstream_removed "${f##"${DEST_FINAL}/"}"; then
            rm -rf -- "$f" \
                    && info "removed [$f] whose remote counterpart is gone" \
                    || err "[rm -rf $f] failed w/ $?"
        fi
    done< <(find -L "$DEST_FINAL" -mindepth "$DEPTH" -maxdepth "$DEPTH" -print0)
fi

# pull new assets:
if [[ "${#TO_DOWNLOAD_LIST[@]}" -gt 0 ]]; then
    [[ "${#TO_DOWNLOAD_LIST[@]}" -gt 1 ]] && s=s
    info "going to copy following ${#TO_DOWNLOAD_LIST[@]} node${s} from remote:"
    unset s

    for i in "${TO_DOWNLOAD_LIST[@]}"; do
        info "  > $i"
    done

    rclone copy --log-file "$LOG_ROOT/rclone-copy.log" "${RCLONE_FLAGS[@]}" \
        "$REMOTE:$SRC_DIR" "$DEST_INITIAL" "${ADD_FILTER[@]}" --filter '- *' || fail "rclone copy failed w/ $?"  # TODO: pushover!
fi

# process assets.
# note we work on _all_ nodes in $DEST_INITIAL, not only ones
# that were pulled during this execution; this is essentially
# for retrying previous failures:
while IFS= read -r -d $'\0' f; do
    f_relative="${f##"${DEST_INITIAL}/"}"
    dest_dir="$(dirname -- "$DEST_FINAL/$f_relative")"

    if [[ -z "$SKIP_EXTRACT" && ! -e "$DEST_FINAL/$SKIP_EXTRACT_MARKER_FILE" && ! -e "$dest_dir/$SKIP_EXTRACT_MARKER_FILE" ]]; then
        extract.sh "$f" || { err "[$f] extraction failed"; continue; }  # TODO: pushover!
    fi

    if [[ -e "$DEST_FINAL/$f_relative" ]]; then
        err "[$DEST_FINAL/$f_relative] already exists; cannot move [$f] into $dest_dir/"  # TODO: pushover!
        continue
    else
        if [[ "$DEPTH" -gt 1 ]]; then
            [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir" || { err "[mkdir -p $dest_dir] failed w/ $?"; continue; }  # TODO: pushover!
        fi
        mv -- "$f" "$dest_dir/" || { err "[mv $f $dest_dir/] failed w/ $?"; continue; }  # TODO: pushover!
    fi
done< <(find -L "$DEST_INITIAL" -mindepth "$DEPTH" -maxdepth "$DEPTH" -print0)

exit 0
