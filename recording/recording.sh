set -eu

PROGNAME="$(basename $0)"

DEFAULT_BASE_URL=${MIRAKC_REC_BASE_URL:-http://localhost:40772}
DEFAULT_FOLDER=${MIRAKC_REC_FOLDER:-}

JSON=
BASE_URL=$DEFAULT_BASE_URL
FOLDER=$DEFAULT_FOLDER

help() {
    cat <<EOF >&2
USAGE:
  $PROGNAME [options] [list]
  $PROGNAME [options] add <program-id>
  $PROGNAME [options] delete <program-id>
  $PROGNAME [options] show <program-id>
  $PROGNAME [options] clear
  $PROGNAME [options] clear-all
  $PROGNAME [options] start <program-id>
  $PROGNAME [options] stop <program-id>
  $PROGNAME -h | --help | help

OPTIONS:
  -h, --help
    Show the help.

  -j, --json
    Output JSON.

  -b, --base-url <BASE_URL> [default: '$DEFAULT_BASE_URL']
    A base URL of mirakc to use.

  --folder <FOLDER> [default: '$DEFAULT_FOLDER']
    The name (or relative path) of a folder to store recording files.

COMMANDS:
  list (default command)
    List recording schedules.

  add
    Add a recording schedule with the "manual" tag.

  delete
    Delete a recording schedule.

  show
    Show a recording schedule.

  clear
    Clear recording schedules added using this script.

  clear-all
    Clear all recording schedules.

  start
    Start recording with the "manual" tag.

  stop
    Stop a recording without deleting its recording schedule.

NOTE:
  It's recommended to create a shell script named mirakc-rec like below:

    #!/bin/sh
    export MIRAKC_REC_BASE_URL=http://your-mirakc:40772
    sh /path/to/mirakc/contrib/search/search.sh "\$@"
EOF
    exit 0
}

make_json() {
  PROGRAM_ID=$1
  PROGRAM=$(curl "$BASE_URL/api/programs/$PROGRAM_ID" -sG)
  DATE=$(echo "$PROGRAM" | jq -Mr '.startAt / 1000 | strflocaltime("%Y%m%d%H%M")')
  if [ -n "$FOLDER" ]
  then
    CONTENT_PATH="$FOLDER/${DATE}_${PROGRAM_ID}.m2ts"
  else
    CONTENT_PATH="${DATE}_${PROGRAM_ID}.m2ts"
  fi
  cat <<EOF | jq -Mc '.'
{
  "programId": $PROGRAM_ID,
  "options": {
    "contentPath": "$CONTENT_PATH"
  },
  "tags": ["manual"]
}
EOF
}

list() {
  curl "$BASE_URL/api/recording/schedules" -sG
}

add() {
  curl "$BASE_URL/api/recording/schedules" -s \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "$(make_json $1)"
}

delete() {
  curl "$BASE_URL/api/recording/schedules/$1" -s \
    -X DELETE \
    -H 'Content-Type: application/json'
}

show() {
  curl "$BASE_URL/api/recording/schedules/$1" -sG
}

clear() {
  curl "$BASE_URL/api/recording/schedules?tag=manual" -s -X DELETE
}

clear_all() {
  curl "$BASE_URL/api/recording/schedules" -s -X DELETE
}

start() {
  curl "$BASE_URL/api/recording/recorders" -s \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "$(make_json $1)"
}

stop() {
  curl "$BASE_URL/api/recording/recorders/$1" -s \
    -X DELETE \
    -H 'Content-Type: application/json'
}

render() {
  START_FMT='(.program.startAt / 1000 | strflocaltime("%Y-%m-%d %H:%M"))'
  # If no duration is specified, show startAt.
  END_FMT='((.program.startAt + (.program.duration // 0)) / 1000 | strflocaltime("%Y-%m-%d %H:%M"))'
  DURATION_FMT='((.program.duration // 0) / 60000)'
  # First, we put a placeholder string <SERVICE> into a TSV string. And then we
  # replace it with an actual service name in `replace_services`.
  SERVICE_FMT='"<SERVICE>"'
  TAGS_FMT='(.tags | join(" "))'
  FILTER="[.program.id, .state, $START_FMT, $END_FMT, $DURATION_FMT, .program.name, $SERVICE_FMT, $TAGS_FMT]"
  LABELS='ID\tSTATE\tSTART\tEND\tMINS\tTITLE\tSERVICE\tTAGS'

  TYP=$1

  RES=$(cat)
  if [ "$JSON" = 1 ]
  then
    RES=$(echo "$RES" | jq -Mc '.')
  else
    if [ "$TYP" = 'list' ]
    then
      RES=$(echo "$RES" | jq -r ".[] | $FILTER | @tsv")
    else
      RES=$(echo "$RES" | jq -r ". | $FILTER | @tsv")
    fi
    RES=$(echo "$RES" | replace_services)
    RES=$(echo "$RES" | sed -e "1i $LABELS")
    RES=$(echo "$RES" | column -s$'\t' -t)
  fi
  echo "$RES"
}

replace_services() {
  SERVICES=$(curl "$BASE_URL/api/services" -sG)
  while read -r TSV
  do
    if [ -z "$TSV" ]
    then
      continue
    fi
    ID=$(echo "$TSV" | cut -f 1)
    SERVICE_ID=$(expr $ID / 100000)
    SERVICE=$(echo "$SERVICES" | jq -r ".[] | select(.id == $SERVICE_ID) | .name")
    echo "$TSV" | sed "s/<SERVICE>/$SERVICE/"
  done
}

prepare_replace_services() {
  export -f replace_services
}

while [ $# -gt 0 ]
do
  case "$1" in
    '-h' | '--help')
      help
      ;;
    '-j' | '--json')
      JSON=1
      shift
      ;;
    '-b' | '--base-url')
      BASE_URL="$2"
      shift 2
      ;;
    '--folder')
      FOLDER="$2"
      shift 2
      ;;
    'list')
      list | render 'list'
      exit 0
      ;;
    'add')
      add $2 | render ''
      exit 0
      ;;
    'delete')
      delete $2
      exit 0
      ;;
    'show')
      show $2 | render ''
      exit 0
      ;;
    'clear')
      clear
      exit 0
      ;;
    'clear-all')
      clear_all
      exit 0
      ;;
    'start')
      start $2
      exit 0
      ;;
    'stop')
      stop $2
      exit 0
      ;;
    *)
      help
      ;;
  esac
done

# default command
list | render 'list'
