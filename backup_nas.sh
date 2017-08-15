#!/bin/bash
# This file is part of resynclinkdest.
#
# resynclinkdest is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# resynclinkdest is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with resynclinkdest.  If not, see <http://www.gnu.org/licenses/>.

BACKUP_HOST="boke.lan"
LATEST_LINKNAME="latest"

# Non-empty to make verbose
DEBUG=""
# Non-empty to dry-run
DRY=""
####
test $# -eq 0 && exit 0
BACKUP_URL="${BACKUP_HOST}:"
DATE="$(date "+%Y-%m-%d")"
HIST_DEST_URL="${BACKUP_URL}${DATE}"
NOHIST_DEST_URL="${BACKUP_URL}nohist"
RSYNC_ARGS="--archive --relative --sparse --one-file-system --remote-option=--fake-super"
RSYNC="rsync"
test -n "$DEBUG" && RSYNC="$RSYNC --info=progress2"
test -n "$DRY"  && RSYNC="$RSYNC --dry-run"

test_port()
{
  ssh -o ConnectTimeout=1 "$BACKUP_HOST" exit 2> /dev/null
  return $?
}

test_port
if [ $? != 0 ]; then
  ip route list | sed "s/.*\<dev\s\(\S\+\)\s.*/\1/" | sort | uniq | while IFS= read -r IFACE; do
    etherwake -i "$IFACE" "$BACKUP_HOST"
  done
  for COUNT in $(seq 60); do
    test_port && break
  done
fi

test "$(ssh "$BACKUP_HOST" readlink "${LATEST_LINKNAME}")" != "${DATE}"
CAN_LINK_DEST=$?

set -e
for HOME_DIR in "$@"; do
  HIST_DIR="${HOME_DIR}/.backup_nas/"
  if [ -d "$HIST_DIR" ]; then
    find "$HIST_DIR" -type l -print0 | while IFS= read -r -d '' SOURCE_LINK; do
      SOURCE_PATH="$(readlink -nf "$SOURCE_LINK")"
      test -z "$SOURCE_PATH" && continue
      test -n "$DEBUG" && echo "${SOURCE_PATH}/ ${HIST_DEST_URL}/"
      if [ $CAN_LINK_DEST -eq 0 ] ; then
        $RSYNC $RSYNC_ARGS --link-dest="../${LATEST_LINKNAME}" "${SOURCE_PATH}/" "${HIST_DEST_URL}/"
      else
        $RSYNC $RSYNC_ARGS "${SOURCE_PATH}/" "${HIST_DEST_URL}/"
      fi
    done
  fi

  NOHIST_DIR="${HOME_DIR}/.backup_nas_nohist/"
  if [ -d "$NOHIST_DIR" ]; then
    find "$NOHIST_DIR" -type l -print0 | while IFS= read -r -d '' SOURCE_LINK; do
      SOURCE_PATH="$(readlink -nf "$SOURCE_LINK")"
      test -z "$SOURCE_PATH" && continue
      test -n "$DEBUG" && echo "${SOURCE_PATH}/ ${NOHIST_DEST_URL}/"
      $RSYNC $RSYNC_ARGS "${SOURCE_PATH}/" "${NOHIST_DEST_URL}/"
    done
  fi
done

# If something was created on this run, create a symlink locally, and upload it.
if [ $CAN_LINK_DEST -eq 0 ]; then
  if rsync "$HIST_DEST_URL" > /dev/null 2>&1; then
    TEMP_DIR="$(mktemp -d)"
    NEW_LINK="${TEMP_DIR}/${LATEST_LINKNAME}"
    ln -s "$DATE" "$NEW_LINK"
    $RSYNC -l "$NEW_LINK" "$BACKUP_URL"
    rm -r "$TEMP_DIR"
  fi
fi
