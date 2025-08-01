#!/bin/bash

# cdn-upcheck/do
# by jore

# the purpose of this script is to run as a bi-hourly cron that extracts all references to CDN video streaming for project site and checks both the video files and metadata for uptime, availability, and correctness at the remote end
# files that are inaccessible or incorrect trigger email alerts and logging




### SET UP ENVIRONMENT ###

  # turn on debugging
  ##set -o xtrace

  # stop everything when any command exits with non-zero status
  set -o errexit

  # carry exit codes of a pipeline through to the end of the line
  set -o pipefail

  # get the full path to wherever this script resides, without trailing slash
  fullpath_and_name="$(readlink --canonicalize "${0}")"
  wd="$(dirname "${fullpath_and_name}")"
  # name of this file only: ${0##*/}
  # name with path ${0}
  # fullpath and name: ${fullpath_and_name}
  # path to this file only ${wd}

  # set the path as working directory, and if for some reason that fails, stop here
  cd "${wd}" || exit 1

  # folder name for storing session data inside (will be created/cleaned)
  data='.data'
  # if the data folder doesn't exist, create it and set permissions
  if [[ ! -e "${data}" ]]; then
    mkdir -p "${wd}/${data}" && chmod 700 "${wd}/${data}"
  fi 


  # folder name for where we get config settings
  conf_dir='.conf'

  # set e-mail address to send alerts to
  notify="$( < "${conf_dir}/.notify")"

  # set CDN link that is prepended to identifiers to make valid URLs, without trailing slash (used only in e-mail notifications) and outside our domain's DNS zone for failsafe
  # this should be a non-whitelabel name of the CDN provider so there's a failsafe zone to work with, e.g. https://upstreamhost.com
  cdn_origin_url="$( < "${conf_dir}/.cdn_origin_url")"
  # set the cdn-upcheck's domain's failsafe CDN URL *** without trailing slash ***
  # this should be the same URL that is used in the CMS to refer to content, e.g. https://cdn.cmsdomain.com
  cdn_url="$( < "${conf_dir}/.cdn_url")"

  # set up mysqldump
  mysqldump_db="$( < "${conf_dir}/.mysqldump_db")"
  mysqldump_user="$( < "${conf_dir}/.mysqldump_user")"
  mysqldump_pw="$( < "${conf_dir}/.mysqldump_pw")"

  # set up CDN domain API
  cdn_prefix="$( < "${conf_dir}/.cdn_prefix")" # this should be the prefix used in all DNS records for the cdn-upcheck zone, i.e. [cdn] part of cdnXXXXXX.cdn-upcheckdomain.tld
  cdn_domain="$( < "${conf_dir}/.cdn_domain")" # this should be the domain for the cdn-upcheck zone, i.e. [domain.com] part of cdnXXXXXX.cdn-upcheckdomain.tld
  cdn_acc_email="$( < "${conf_dir}/.cdn_acc_email")"
  cdn_api_key="$( < "${conf_dir}/.cdn_api_key")"
  cdn_origin_prefix="$( < "${conf_dir}/.cdn_origin_prefix")" # this should be the upstream CDN providers non-whitelabel CDN prefix, i.e. [foo] part of fooXXXXXX.region.upstreamhost.com
  cdn_origin_domain="$( < "${conf_dir}/.cdn_origin_domain")" # this should be the domain for the non-whitelabel CDN provider, i.e. [region.upstreamhost.com] part of fooXXXXXX.region.upstreamhost.com

  # set globals for curl, like useragent, etc
  curlconf="${wd}/${conf_dir}/curl.conf"

  # set stopwatch to keep track of total run time, starting from now
  start=$(date +%s)

  # set current hour (I) minute (M) second (S) timestamp to append to txt files to make them unique
  # e.g. .210812010001-mp4-matches
  timestamp_format='+%g%m%d%H%M%S'
  timestamp=$(date ${timestamp_format})

  # set time interval in minutes for when database refresh should happen, also used for garbage collection
  # e.g. refresh database and clear old temporary files after 720 minutes (12 hours)
  refreshtime="$( < "${conf_dir}/.refreshtime")"

  # set up check stream status notification formatting, also used in email notifications
    ok='[ OK ]'
  redo='[REDO]'
  fail='[FAIL]'
  warn='[WARN]'


  # define HTTP error codes we may like to iterate, if need be, in e-mail logs
  # 4xx:
    http_400="Bad Request."
    http_401="Unauthorised."
    http_403="Forbidden."
    http_405="Method Not Allowed."
    http_406="Not an acceptable request."
    http_408="The server timed out waiting for the request."
    http_409="Conflict."
    http_410="Gone. The resource has been intentionally removed/purged."
    http_414="URI too long."
    http_423="Locked."
    http_426="Upgrade Required."
    http_429="Too many requests."
    http_444="nginx: Blackholed."
    http_494="Request too large."
    http_495="SSL certificate error."
    http_496="Missing SSL certificate."
    http_497="HTTP request sent to HTTPS port for HTTPS request."
  # 5xx:
    http_500="Unspecific general internal server error."
    http_502="Bad Gateway."
    http_503="Server unavailable."
    http_504="Gateway Timeout."
    http_508="Infinite loop."
    http_509="High bandwidth."
    http_520="Empty, unknown, or unexpected response from webserver."
    http_521="Cloudflare: Remote server is down."
    http_522="Cloudflare: Connection timeout."
    http_523="Cloudflare: Origin unreachable."
    http_524="Cloudflare: Timeout."
    http_525="Cloudflare: Could not negotiate SSL handshake with origin."
    http_526="Invalid SSL certificate."
    http_530="Origin DNS error."


  # check we have non-empty config settings available before continuing
    check_var_names=(
      notify
      cdn_origin_url
      cdn_url
      mysqldump_db
      mysqldump_user
      mysqldump_pw
      cdn_prefix
      cdn_domain
      cdn_acc_email
      cdn_api_key
      cdn_origin_prefix
      cdn_origin_domain
      refreshtime
    )
    for var_name in "${check_var_names[@]}"; do
      if [[ -z "${!var_name}" ]]; then
        echo "Configuration setting(s) not set properly: check ${conf_dir}/.${var_name}"
        var_unset=true
      fi
    done
    if [[ -n "${var_unset}" ]]; then
      echo "Stopping."
      exit 1
    fi


  # START TRAP FOR EMERGENCY GARBAGE COLLECTION
  # set up a trap for garbage collection that will run on aborts or fails
  # cleans up any temporary files from the failed session (current timestamp)
  trap emergency_cleanup SIGINT SIGTERM






### FUNCTIONS ###

rendertimer(){
  # convert seconds to Days, Hours, Minutes, Seconds
  # thanks to ideas by Nikolay Sidorov and https://www.shellscript.sh/tips/hms/
  local parts seconds D H M S D_tag H_tag M_tag S_tag
  seconds=${1:-0}
  # all days
  D=$((seconds / 60 / 60 / 24))
  # all hours
  H=$((seconds / 60 / 60))
  H=$((H % 24))
  # all minutes
  M=$((seconds / 60))
  M=$((M % 60))
  # all seconds
  S=$((seconds % 60))

  # set up "x day(s), x hour(s), x minute(s) and x second(s)" language
  if [[ "$D" -eq "1" ]]; then D_tag="day"; else D_tag="days"; fi
  if [[ "$H" -eq "1" ]]; then H_tag="hour"; else H_tag="hours"; fi
  if [[ "$M" -eq "1" ]]; then M_tag="minute"; else M_tag="minutes"; fi
  if [[ "$S" -eq "1" ]]; then S_tag="second"; else S_tag="seconds"; fi

  # put parts from above that exist into an array for sentence formatting
  parts=()
  if [[ "$D" -gt "0" ]]; then parts+=("$D $D_tag"); fi
  if [[ "$H" -gt "0" ]]; then parts+=("$H $H_tag"); fi
  if [[ "$M" -gt "0" ]]; then parts+=("$M $M_tag"); fi
  if [[ "$S" -gt "0" ]]; then parts+=("$S $S_tag"); fi

  # construct the sentence
  result=""
  lengthofparts=${#parts[@]}
  for (( currentpart = 0; currentpart < lengthofparts; currentpart++ )); do
    result+="${parts[$currentpart]}"
    # if current part is not the last portion of the sentence, append a comma
    if [[ "$currentpart" -ne $((lengthofparts-1)) ]]; then result+=", "; fi
    # if current part will be the last part of the sentence, say 'and'
    if [[ "$currentpart" -eq $((lengthofparts-2)) ]]; then result+="and "; fi
  done
  echo "${result}"
}


dumpdatabase() {
  # dump only the contents of the _postmeta table, matching a query looking for fields containing '.mp4'
  mysqldump -t -u "${mysqldump_user}" -p"${mysqldump_pw}" "${mysqldump_db}" _postmeta --where="meta_value LIKE '%.mp4%' AND meta_key LIKE 'tm_video_file' OR meta_key LIKE 'tm_video_code'" > "${wd}/${data}/.dump.sql"
}


extractmetadata_engine(){
  # $1 is filename to read from
  # $2 is filename to write to

  # set up a counter to work with how many lines we're dealing with, if we need it
  local totallines counter
  totallines="$(wc -l < "${1}")"
  counter=1

  # create lockfile for the big initial extraction and refreshes (i.e. when using "${wd}/${data}/.xml-urls")
  # put lockfiles in /run/lock as that's cleared on server reboots for any total crash handling
  if [[ "${2}" == "${wd}/${data}/.xml-urls" ]]; then
    # create a lockfile that denotes this session only. this is used later to test if we're running the metadata extraction in this instance
    lockfile="$(mktemp /run/lock/.cdn-upcheck-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.lock)"
    # create a persistent lockfile for use by other concurrently running instances to check with
    touch "/run/lock/.cdn-upcheck-metadata.lock"
  fi

  # notify what we're doing
  printf 'Building check list...'

  # set stopwatch to keep track of how long extraction process takes, starting from now
  extraction_start=$(date +%s)

  # now read each line to build each URL for each identifier that points to its corresponding 'cdnXXXXXX.cdn-upcheckdomain.tld' domain, discerned from /metadata JSON output which we parse to find .server and .dir (path)
  while read -r line; do
    # there's a new link on each line
    link="${line}"

    # extract the identifier from the last part of each line
    grabXML="${link##*/}"
    grabID="${grabXML%_meta.xml}"
    # if we cannot grab the identifier, set this to something useless so we don't have an empty string
    if [[ -n "${grabID}" ]]; then
      identifier="${grabID}"
    else
      identifier="EMPTY"
    fi

    # wait a random short moment before each request to /metadata, up to ~3 seconds, to avoid flooding resource
    intwait="$(((RANDOM % 2)+1)).$(((RANDOM % 999)+1))s"; sleep "$intwait";

    # fetch metadata from /metadata JSON and save it to temp file for further parsing
    curl --config "${curlconf}" --silent "${cdn_origin_url}/metadata/${identifier}" > "${wd}/${data}/.${timestamp}-${identifier}-jq-metadata-tmp" || true
    # test if `curl` output starts with an { as expected, if not, the site is down or we have JSON error, so fall back to cdn.cmsdomain.com default
      if read -r -n1 char < "${wd}/${data}/.${timestamp}-${identifier}-jq-metadata-tmp"; [[ $char = "{" ]]; then
        # yes, metadata starts with { but now check if the metadata returned is empty, i.e. {}
        if read -r -n2 char < "${wd}/${data}/.${timestamp}-${identifier}-jq-metadata-tmp"; [[ $char = "{}" ]]; then
          # metadata is empty, use failsafe URL
          echo "${cdn_url}/download/${identifier}/${identifier}_meta.xml" >> "${2}"
          printf "\n%s" "  metadata empty: ${cdn_url}/download/${identifier}/${identifier}_meta.xml"
        else
          # metadata file isn't {} so try parse stuff now
          # parse to extract server name and dir, use `tr` to trim empty lines and blank space
          # send jq STDERR to /dev/null so its output is not captured in the string and tested against later
          # snip unwanted spaces, tabs, new lines, and cartridge returns using `tr`
          server="$("${wd}/.inc/jq" --raw-output ".server" "${wd}/${data}/.${timestamp}-${identifier}-jq-metadata-tmp" 2> /dev/null | tr --delete " \t\n\r" || true)"
          dir="$("${wd}/.inc/jq" --raw-output ".dir" "${wd}/${data}/.${timestamp}-${identifier}-jq-metadata-tmp" 2> /dev/null | tr --delete " \t\n\r" || true)"
          # check that jq extraction worked okay
          if [[ "${server}" == 'null' || "${dir}" == 'null' ]]; then
            # `jq` returned empty extraction so build a failsafe URL
            echo "${cdn_url}/download/${identifier}/${identifier}_meta.xml" >> "${2}"
            printf "\n%s" "  metadata null: ${cdn_url}/download/${identifier}/${identifier}_meta.xml"
          elif [[ -n "${server}" && -n "${dir}" ]]; then
            # a server name and dir is available, so build the CDN URL
            # build server ID CDN url by replacing upstream CDN structure with local CDN to end up with cdnXXXXXX.cdn-upcheckdomain.tld URLs
            build_cdnurl="$(sed "s@${cdn_origin_prefix}\([0-9]\{6\}\)\.${cdn_origin_domain}/@${cdn_prefix}\1.${cdn_domain}/@" <<< "${server}${dir}" || true)"
            # if we get a CDN URL build it, otherwise fall back to failsafe URL cdn.cmsdomain.com
            if [[ -n "${build_cdnurl}" ]]; then
              # build line which should now look something like https://cdn123456.cdn-upcheckdomain.tld/IDENTIFIER/ITENTIFIER_meta.xml
              echo "https://${build_cdnurl}/${identifier}_meta.xml" >> "${2}"
            else
              # build_cdnurl was empty so build a failsafe URL
              echo "${cdn_url}/download/${identifier}/${identifier}_meta.xml" >> "${2}"
              printf "\n%s" "  metadata none: ${cdn_url}/download/${identifier}/${identifier}_meta.xml"
            fi
          else
            # `jq` returned empty extraction so build a failsafe URL
            echo "${cdn_url}/download/${identifier}/${identifier}_meta.xml" >> "${2}"
            printf "\n%s" "  metadata failed: ${cdn_url}/download/${identifier}/${identifier}_meta.xml"
          fi
        # done working with metadata that isn't empty {}
        fi
      else
        # metadata returned is empty, fall back on cdn.cmsdomain.com default as failsafe
        echo "${cdn_url}/download/${identifier}/${identifier}_meta.xml" >> "${2}"
        printf "\n%s" "  metadata invalid: ${cdn_url}/download/${identifier}/${identifier}_meta.xml"
      fi

  # on to the next identifier, advance the count
  counter=$((counter +1))

  # clean up temporary file
  rm --force "${wd}/${data}/.${timestamp}-${identifier}-jq-metadata-tmp"

  # we're done when we've reached the end of the file
  done < "${1}"
  printf ' done.\n'

  # extraction now finished, stop timer and display results
  extraction_end=$(date +%s)
  duration=$((extraction_end-extraction_start))
  howlong="$(rendertimer $duration)"
  printf 'Building check list took %s.\n\n\n' "${howlong}"

  # ensure lockfiles are removed on big long first extractions or refreshes
  if [[ "${2}" == "${wd}/${data}/.xml-urls" ]]; then
    # remove persistent lock
    rm --force "/run/lock/.cdn-upcheck-metadata.lock"
    # remove lock from this session
    rm --force "${lockfile}"
  fi
}


extractmetadata() {
  # first ensure we have a clean slate!
  find "${wd}/${data}/" -maxdepth 1 -name ".identifier-*" -type f -delete
  find "${wd}/${data}/" -maxdepth 1 -name ".mp4-*" -type f -delete
  find "${wd}/${data}/" -maxdepth 1 -name ".xml-*" -type f -delete

  # run `ack` on the database dump to extract all references to content hosted at cdn.cmsdomain.com with or without HTTPS
  printf 'Extracting CDN filenames... '
    # extract all CDN lines ending with an MP4 file
    "${wd}/.inc/ack" --nofilter --output='$&' "https??://${cdn_url##*//}/download/\S+?.mp4" "${wd}/${data}/.dump.sql" > "${wd}/${data}/.mp4-matches"
    # `sort` .mp4-matches list to remove duplicates, as the extraction may contain duplicate data from Wordpress post revisions not yet cleaned from the database
    # this list also includes draft posts if lines CDN match as `mysql` query from database dump doesn't distinguish post status from _postmeta table.
    sort --unique "${wd}/${data}/.mp4-matches" > "${wd}/${data}/.mp4-matches-sorted"
  printf 'done.\n'

  printf 'Extracting CDN identifiers... '
    # extract identifiers from the list we build and sort for uniqueness above
    "${wd}/.inc/ack" --nofilter --output='$&' "https??://${cdn_url##*//}/download/\S+?/" "${wd}/${data}/.mp4-matches-sorted" > "${wd}/${data}/.identifier-matches"
    sort --unique "${wd}/${data}/.identifier-matches" > "${wd}/${data}/.identifier-matches-sorted"
  printf 'done.\n'

  # extract the identifier part of URLs
  printf 'Building list of identifiers... '
    # now use the sorted and unique identifier list to extract a list of just the identifiers
    "${wd}/.inc/ack" --nofilter --output='$&' "(?<=/download/).*(?=\/)" "${wd}/${data}/.identifier-matches-sorted" > "${wd}/${data}/.identifier-matches-list"
    # wash identifiers-temp file through `sort` with --unique to ensure duplicates that are referenced from playlists/series are removed
    sort --unique "${wd}/${data}/.identifier-matches-list" > "${wd}/${data}/.identifier-matches-list-sorted"
  printf 'done.\n'

  # build the check list
  extractmetadata_engine "${wd}/${data}/.identifier-matches-list-sorted" "${wd}/${data}/.xml-urls"

  # also ensure this list is unqiue and sorted
  sort --unique "${wd}/${data}/.xml-urls" > "${wd}/${data}/.xml-urls-sorted"

  # use two lists (.xml-urls-sorted and .mp4-matches-sorted) to build a new list of what each identifiers MP4 files are. use required later to check if an identifier's MP4 files exist/are available
  # `awk` solution thanks to @SasaKanjuh, comments added
  # must use -F for field separator for older version /usr/bin/mawk on target system
  awk -F '/' ' {
    # get each identifier
    identifier = $(NF - 1)

    # if we are going through the XML URLs (the first list), i.e. NR == FNR
    if (NR == FNR) {
      # strip off the last portion of the URL line from the last slash / until the end
      sub("/[^/]*$", "")
      # assign the first portion of the URL line to an array under each specific identifier
      first_portion[identifier] = $0
    }

    # if we are in the second list then get the first portion of the line using common identifier, and append the last portion taken from above
    else print first_portion[identifier] "/" $NF
  }' "${wd}/${data}/.xml-urls-sorted" "${wd}/${data}/.mp4-matches-sorted" > "${wd}/${data}/.mp4-urls"

  # sort this list to ensure it's still clean, no duplicates
  sort --unique "${wd}/${data}/.mp4-urls" > "${wd}/${data}/.mp4-urls-sorted"
}


buildfiles() {
  # copy the lists created since last refreshtime for use in this session
  cp "${wd}/${data}/.identifier-matches-list-sorted" "${wd}/${data}/.${timestamp}-identifier-matches-list-sorted"
  cp "${wd}/${data}/.xml-urls-sorted" "${wd}/${data}/.${timestamp}-xml-urls-sorted"
  cp "${wd}/${data}/.mp4-urls-sorted" "${wd}/${data}/.${timestamp}-mp4-urls-sorted"

  # reshuffle checking list for this session
  # $timestamp-xml-urls-shuf is the file that is sent to the first pass
  shuf "${wd}/${data}/.${timestamp}-xml-urls-sorted" > "${wd}/${data}/.${timestamp}-xml-urls-shuf"
}


buildCDNrefreshlist(){
  # this function is used in the second pass of checkstream ONLY
  # log the CDN ID of this identifier in a list of CDN domains to refresh so we can try to update DNS for this failed host
  # $id contains the server number that needs refreshing, i.e. 123456. use it to build cdn123456.cdn-upcheckdomain.tld and add that to the list for refreshing
  # != "-EMPTY" is used to check against because that's the placeholder for a CDN ID that is served by cdn.cmsdomain.com not cdn123456.cdn-upcheckdomain.tld
  # i.e. if the current CDN is a 'blank' then don't write anything
  if [[ -n "${id}" ]] && [[ "${id}" != "-EMPTY" ]]; then
    echo "${cdn_origin_prefix}${id}.${cdn_origin_domain}" >> "${wd}/${data}/.${timestamp}-cdns-to-refresh"
  fi
}


checkstream(){
  # use this function in any check loop to print the current check info line
  # renders as: TIME     COUNT    CDN-ID     STATUS  HTTP IDENTIFIER  MESSAGE SPACE   URL (on error)
  #             h:MM:SS  x of xx  cdn123456  [ OK ]  200  id_FooBar   Error message.  https://cdnlink/if/needed"
  #             %s       %d of $d  %s         %s      %s   %s          %s              %s
  # $1 is OK or FAIL status, $2 is error message if needed, $3 is current CDN link (https://cdn123456/identifier/...)
  printf '%s %*d of %d  %s\t%s  %s  %s  %s  %s\n' "$(checkstream_timestamp)" $((${#totallines}+1)) "$counter" "$totallines" "${cdnid}" "${1}" "${httpStatus}" "${identifier}" "${2}" "${3}"
}


checkstream_timestamp(){
  # returns the current date and time for use in checkstreams and email alerts
  # e = day of week (space padded), b = month in 3 letters, k = hour in 24hr time (space padded), then Minutes Seconds
  date '+%e-%b %k:%M:%S'
}


cleanup(){
  printf '\nCleaning up this session... '
    # clean up this session's temporary files
    find "${wd}/${data}/" -maxdepth 1 -name ".${timestamp}*" -type f -delete
  printf 'done.\n'
  printf 'Cleaning up temporary data storage... '
    # clear temporary files that have not been accessed for more than 7 days
    # this handles cleanup in situations where cron is disrupted or a prior script aborts or fails for whatever reason
    # find how long the timestamp var is, e.g. 12 chars ${#timestamp}, and use to build a regex line with `find` to go looking for old timestamped files and delete them
    find_regex=".*\.[0-9]{${#timestamp}}.*"
    # the `find` below with above $find_regex should expand to something like '.*\.[0-9]{12}.*' where 12 is the length of the timestamps
    # should not evaluate any files from this session as part of this cleanup by passing this session's timestamp into -not -iname
    # prefer selecting by -atime rather than -amin because `find` says -amin calculates "from the beginning of today rather than from 24 hours ago" and that may cause problems in the overlay of days with hourly cron? not sure
    # -atime +n = file was last accessed n*24 hours ago. "`find` figures out how many 24-hour periods ago the file was last accessed" (see `man time`)
    # so final line should evaluate files in temp dir only, that are not from current session, that have a timestamp, and that have not been accessed for more than 7x24-hour periods. matches are deleted
    find "${wd}/${data}/" -maxdepth 1 -not -iname ".${timestamp}*" -regextype posix-extended -regex "${find_regex}" -atime +7 -type f -delete
  printf 'done.\n'
}


emergency_cleanup(){
  printf '\n\nEmergency cleanup... '
    # clear this failed session's temporary files
    find "${wd}/${data}/" -maxdepth 1 -name ".${timestamp}*" -type f -delete

    # if the metadata extraction is running inside this instance during fail (i.e. lock file has been set with current timestamp)
    if [[ -n "${lockfile}" ]] && [[ -f "${lockfile}" ]]; then
      # clear out the entire data folder for all checks so next check can start fresh
      # use safety measures (i.e. ${string:?}) on variables to prevent `rm` wiping out everything from root (/) if $wd or $data is empty for an unforseen reason (https://github.com/koalaman/shellcheck/wiki/SC2115)
      rm --recursive --force "${wd:?}/${data:?}/"
      # also clean up this session's file lock
      rm --force "${lockfile}"
    fi

    # ensure file lock from any instance is removed regardless of what happened this time
    rm --force "/run/lock/.cdn-upcheck-metadata.lock"
  printf 'done.\n'

  # stop all currently running checks on emergency fail
    # use ${fullpath_and_name} to retrieve the name of this file to pass to `pkill` to send the end process signal we want
    # SIGINT is essentially CTRL + C
    # SIGTERM gracefully kills the process whereas SIGKILL kills the process immediately
    # SIGTERM signal can be handled, ignored and blocked but SIGKILL cannot be handled or blocked
    # SIGTERM doesn’t kill the child processes, SIGKILL kills the child processes as well
      echo "Stopping all concurrent running checks."
      # kill all currently running instances this script
      # --full for searching in the full command line of running processes, --signal SIGTERM for 'terminate' signal, --echo display list of what was killed
      # pattern .* catches none or any paths before the name of this script, in the situations where this script is invoked "outside its path"
      pkill --full --echo --signal SIGKILL "bash .*${0##*/}"
      # `pkill` obviously kills this at above line, so if successful, lines from now on are never executed

  # stop here with exit status 1 for fail if we get there for any reason
  exit 1
}


cdn-upcheck() {
  # consolodated and common flow for all checking and handling
  # this function assumes $filename has been set, as that is what list is used to iterate checks on

  # determine if this invocation is the 1st or 2nd pass
  # if pass is not set for whatever reason, assume 1st pass conditions so we don't have an empty string
  if [[ -z "${pass}" ]]; then
    pass=1
  else
    pass="${1}" # first argument
  fi

  # read each line from $filename, -r ignores slashes so we don't read them as escape characters
  while read -r line; do
    link="${line}"
    # extract portion from end of the line to find identifier (https://unix.stackexchange.com/questions/626432)
    grabXML="${link##*/}"
    grabID="${grabXML%_meta.xml}"
    # if we cannot grab the identifier, set this to something useless so we don't have an empty string
      if [[ -n "$grabID" ]]; then
        identifier="${grabID}"
      else
        identifier="EMPTY"
      fi

    # extract the current server number from the URL
    # use `awk` to get the subdomain(s) part of the CDN URL and then `grep` only the part with 6 digits as the ID
    # add `true` to always exit successfully even if we don't get an ID match
    id="$(awk -F '/' '{print $3}' <<< "${link}" | grep --only-matching '[0-9]\{6\}' || true)"
    # if we cannot grab the CDN ID, then just set it to use a dummy so we don't have an empty string
    if [[ -n "${id}" ]]; then
      cdnid="${cdn_prefix}${id}"
    else
      id="-EMPTY"
      cdnid="         " # add 'padding' for empty chars to keep check stream pretty
    fi


    # now actually do the checking

    # sleep a little bit before each test, up to ~3 seconds
    intwait="$(((RANDOM % 2)+1)).$(((RANDOM % 999)+1))s"; sleep "$intwait";

    # use `curl` to check the upload link
      # over-ride link to test logic for specific HTTP error codes using httpbin.org
      ##link=http://httpbin.org/status/404
      # --location to follow redirects, --output to set output/write file to nothing, --silent removes the progress meter, --head makes a HEAD HTTP request instead of GET, --write-out prints the required status code
      httpStatus="$(curl --config "${curlconf}" --header 'upcheck:true' --location --output /dev/null --silent --head --write-out '%{http_code}' "${link}" 2> /dev/null || true)"
        # over-ride httpStatus for testing    
        ##httpStatus="522"



    # logic that does things depending on status returned

    if [[ "${httpStatus}" == 200 ]]; then
      # sleep a little bit before next `curl` request, up to ~3 seconds
      intwait="$(((RANDOM % 2)+1)).$(((RANDOM % 999)+1))s"; sleep "$intwait";
      # identifier seems ok, so now grab metadata to see if it has been marked as high bandwidth
      curl --config "${curlconf}" --header 'upcheck:true' --location --silent --output "${wd}/${data}/.${timestamp}-${identifier}-xml-data-tmp" "${link}" || true
        # check XML data was fetched OK
        if [[ -s "${wd}/${data}/.${timestamp}-${identifier}-xml-data-tmp" ]]; then
          # XML content exists, now `grep` it to check if identifier has been marked as high bandwidth
          if grep -q "<collection>highbandwidth</collection>" "${wd}/${data}/.${timestamp}-${identifier}-xml-data-tmp"; then
            # yep, it's been marked
            checkstream "${fail}" "High bandwidth." "${link}"
            # send e-mail about high bandwidth removal right away
            printf '%s has been marked as high bandwidth.\n\n' "${cdn_origin_url}/details/${identifier}" | mail -s "cdn-upcheck [High Bandwidth] ${identifier}" "${notify}"
            # clean up temporary file now that we're done
            rm --force "${wd}/${data}/.${timestamp}-${identifier}-xml-data-tmp"
          else
            # it's not marked as high bandwidth, we're all good
            checkstream "${ok}"

            # now that metadata is confirmed to be good, check the MP4 file(s) for current identifier also exist and are available too, as we expect
            # use `ack` to search list of MP4 matches extracted from database dump for files that reference the current identifier
            # build list of files that begin with http or https and end with .mp4
            if [[ "${pass}" == 2 ]]; then
              # use the latest list that has been medtadata refreshed, otherwise, use the main list created at the start of this session
              mp4checklist_tomatch="${wd}/${data}/.${timestamp}-renewed-mp4-urls-sorted"
              mp4checklist="${wd}/${data}/.${timestamp}-${identifier}-renewed-mp4-checklist"
            else
              # use main list
              mp4checklist_tomatch="${wd}/${data}/.${timestamp}-mp4-urls-sorted"
              mp4checklist="${wd}/${data}/.${timestamp}-${identifier}-mp4-checklist"
            fi
            
            # build the checklist
            "${wd}/.inc/ack" --nofilter --output='$&' "https??://.*/${identifier}/.*\.mp4" "${mp4checklist_tomatch}" > "${mp4checklist}"

            # check the file(s) exist
              while read -r mp4url; do
                # sleep a little bit before each test, up to ~5 seconds
                intwait="$(((RANDOM % 4)+1)).$(((RANDOM % 999)+1))s"; sleep "$intwait";
                # check the status of the current URL
                mp4Status="$(curl --config "${curlconf}" --header 'upcheck:true' --location --output /dev/null --silent --head --write-out '%{http_code}' "${mp4url}" 2> /dev/null || true)"

                # if http_code is empty due to a timeout or other remote failure, say so
                if [[ -z "${mp4Status}" ]]; then
                  mp4Status="   " # pad with 3 spaces to stay column aligned
                  # on 1st pass
                  if [[ "${pass}" == 1 ]]; then
                    # report warning in checkstream
                    printf '\t\t\t\t\t\t\t%s  %s  %s\n' "${redo}" "${mp4Status}" "HTTP status code empty. Remote timeout? ${mp4url}"
                    # add current identifier to 2nd pass check
                    echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
                  fi
                  # on 2nd pass
                  if [[ "${pass}" == 2 ]]; then
                    # report failure in checkstream
                    printf '\t\t\t\t\t\t\t%s  %s  %s\n' "${warn}" "${mp4Status}" "HTTP status code empty. Remote timeout? ${mp4url}"
                    # add current failure to errors-range e-mail report
                    ##checkstream "${fail}" "HTTP status code empty. Remote timeout?" "${mp4url}" >> "${wd}/${data}/.${timestamp}-errors-else"
                  fi

                # if 200 then file is OK
                elif [[ "${mp4Status}" == 200 ]]; then
                  ##printf '\t\t\t\t%s\t%s\n' "${ok}" "${mp4url}"
                  # the metadata is good, the files are good so do nothing successfully using `true`
                  true

                # if 301 or 302 then mention a warning
                elif [[ "${mp4Status}" == 301 || "${mp4Status}" == 302 ]]; then
                  printf '\t\t\t\t\t\t\t%s  %s  %s\n' "${warn}" "${mp4Status}" "MP4 redirected: ${mp4url}"

                # if 404, report a failure in the check stream, but confirm it in a 2nd pass before sending an email alert
                elif [[ "${mp4Status}" == 404 ]]; then
                  # on 1st pass
                  if [[ "${pass}" == 1 ]]; then
                    # report redo in checkstream
                    printf '\t\t\t\t\t\t\t%s  %s  %s\n' "${redo}" "${mp4Status}" "File not found: ${mp4url}"
                    # add current identifier to 2nd pass check
                    echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
                  fi
                  # on 2nd pass
                  if [[ "${pass}" == 2 ]]; then
                    # report redo in checkstream
                    printf '\t\t\t\t\t\t\t%s  %s  %s\n' "${fail}" "${mp4Status}" "File not found: ${mp4url}"
                    # send email alert right now
                    printf '%s file could not be found.\n\n%s\n' "${mp4url}" "${cdn_origin_url}/details/${identifier}" | mail -s "cdn-upcheck [404 MP4 File] ${identifier}" "${notify}"
                  fi

                # if any other error, then report failure in the check stream
                else
                  mp4StatusInfo="http_${mp4Status}"
                  # on 1st pass
                  if [[ "${pass}" == 1 ]]; then
                    # report warning in checkstream
                    printf '\t\t\t\t\t\t\t%s  %s  %s\n' "${redo}" "${mp4Status}" "Problem checking MP4 file: ${!mp4StatusInfo} ${mp4url}"
                    # add current identifier to 2nd pass check
                    echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
                  fi
                  # on 2nd pass
                  if [[ "${pass}" == 2 ]]; then
                    # report failure in check stream
                    printf '\t\t\t\t\t\t\t%s  %s  %s\n' "${fail}" "${mp4Status}" "Problem checking MP4 file: ${!mp4StatusInfo} ${mp4url}"
                    # add current failure to errors-range e-mail report
                    checkstream "${fail}" "Problem checking MP4 file: ${!mp4StatusInfo}" "${mp4url}" >> "${wd}/${data}/.${timestamp}-errors-else"
                  fi
                fi

              # finished making the check list
              done < "${mp4checklist}"
              # clean up temporary file now that we're done
              rm --force "${mp4checklist}"
              rm --force "${wd}/${data}/.${timestamp}-${identifier}-xml-data-tmp"
            fi
        else
          # failed to get XML data
          # on 1st pass
          if [[ "${pass}" == 1 ]]; then
            checkstream "${redo}" "XML file empty." "${link}"
            # log the link to try it again later
            echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
          fi
          # on 2nd pass
          if [[ "${pass}" == 2 ]]; then
            checkstream "${fail}" "XML file empty." "${link}"
          fi
        fi



    elif [[ "${httpStatus}" == 000 ]]; then
      # sleep a little bit before next `curl` request, up to ~3 seconds
      intwait="$(((RANDOM % 2)+1)).$(((RANDOM % 999)+1))s"; sleep "$intwait";
      # 000 could mean lots of things. connection refused, SSL fail, unable to resolve DNS, etc. run `curl` again to try again and also find out a little more based on its exit code
      # use 2>&1 to redirect curl's output of both STDOUT and STDERR to the $failState variable and catch curl's exitcode
      failState=$(curl --config "${curlconf}" --header 'upcheck:true' --show-error --silent --location "${link}" > /dev/null 2>&1) exitCode=$? || true
      # over-ride exitCode for testing
      ##exitCode="99"

      # parse different actions depending on type of error. common ones are:
      if [[ $exitCode == 0 ]]; then
        # 0 is paradoxically all fine, proceed as usual, i.e. do nothing now
        checkstream "${ok}" "curl returned 0 as an exitcode, but otherwise OK."

      elif [[ $exitCode == 6 ]]; then
        # 6 is couldn't resolve host
          # on 1st pass
          if [[ "${pass}" == 1 ]]; then
            checkstream "${redo}" "Couldn't resolve host." "${link}"
            # log the link to try it again later
            echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
          fi
          # on 2nd pass
          if [[ "${pass}" == 2 ]]; then
            checkstream "${fail}" "Couldn't resolve host." "${link}"
            # log this identifier in list of 000 fails to send bulk at end
            echo "${cdn_origin_url}/details/${identifier}" >> "${wd}/${data}/.${timestamp}-errors-000-6"
            # trigger update CDN DNS for this item
            buildCDNrefreshlist
          fi


      elif [[ $exitCode == 7 ]]; then
        # 7 is connection refused
          # on 1st pass
          if [[ "${pass}" == 1 ]]; then
            checkstream "${redo}" "Connection Refused." "${link}"
            # log the link to try it again later
            echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
          fi
          # on 2nd pass
          if [[ "${pass}" == 2 ]]; then
            checkstream "${fail}" "Connection Refused." "${link}"
            # log this identifier in list of 000 fails to send bulk at end
            echo "${cdn_origin_url}/details/${identifier}" >> "${wd}/${data}/.${timestamp}-errors-000-7"
          fi


      else
        # error could be all sorts of other things, and can add more tests here, but for now we'll catch all
          # on 1st pass
            if [[ "${pass}" == 1 ]]; then
              checkstream "${redo}" "${exitCode}: ${failState}" "${link}"
            # log the link to try it again later
            echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
            fi
            # on 2nd pass
            if [[ "${pass}" == 2 ]]; then
              checkstream "${fail}" "${exitCode}: ${failState}" "${link}"
              # log this identifier in list of 000 fails
              checkstream "${fail}" "${exitCode}: ${failState}" "${link}" >> "${wd}/${data}/.${timestamp}-errors-000"
            fi
      fi




    elif [[ "${httpStatus}" == 302 ]]; then
      # 302 temporary redirects are probably okay, but identifier again at the end just to be sure it's still up (hopefully 200) by the time we get there
          # on 1st pass
            if [[ "${pass}" == 1 ]]; then
              checkstream "${redo}" "Redirected." "${link}"
              # log the link to try it again later
              echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
            fi
            # on 2nd pass
            if [[ "${pass}" == 2 ]]; then
              # check out where identifier is being redirected to by running `curl` on it again
              # sleep a little bit before next `curl` request, up to ~3 seconds
              intwait="$(((RANDOM % 2)+1)).$(((RANDOM % 999)+1))s"; sleep "$intwait";
              redirectEnd="$(curl --config "${curlconf}" --header 'upcheck:true' --show-error --silent --location --output /dev/null --write-out "%{url_effective}" --head "${link}" 2> /dev/null || true)"
              # if `curl` output returns normal metadata file, then assume the upload is OK
              # build that string to check it, does it end in /items/IDENTIFIER/IDENTIFIER_meta.xml
              expectedEndFile="$(sed 's#.*#items/&/&_meta.xml#' <<< "${identifier}")"
              if [[ "$redirectEnd" == *"$expectedEndFile" ]]; then
                checkstream "${ok}" "302 redirect, but destination result is OK."
              else
                checkstream "${fail}" "302 redirected to somewhere unexpected." "${link}"
                # write this error to log file
                checkstream "${fail}" "302 redirected to somewhere unexpected." "${link}" >> "${wd}/${data}/.${timestamp}-errors-302"
              fi
            fi




    elif [[ "${httpStatus}" == 403 ]]; then
      # 403, item is currently forbidden. being taken down right now?
        # on 1st pass
        if [[ "${pass}" == 1 ]]; then
          checkstream "${redo}" "${link}"
          # log the link to try it again later
          echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
        fi
        # on 2nd pass
        if [[ "${pass}" == 2 ]]; then
          checkstream "${fail}" "${link}"
          # send an e-mail about removal right away
          printf '%s may be removed.\n\n%s reported 403 error after rechecking.' "${cdn_origin_url}/details/${identifier}" "${link}" | mail -s "cdn-upcheck [403] ${identifier}" "${notify}"
        fi




    elif [[ "${httpStatus}" == 404 ]]; then
      # 404, has been removed
        # on 1st pass
        if [[ "${pass}" == 1 ]]; then
          checkstream "${redo}" "${link}"
          # log the link to try it again later
          echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
        fi
        # on 2nd pass
        if [[ "${pass}" == 2 ]]; then
          checkstream "${fail}" "${link}"
          # send an e-mail about removal right away
          printf '%s may be removed.\n\n%s reported 404 error after rechecking.' "${cdn_origin_url}/details/${identifier}" "${link}" | mail -s "cdn-upcheck [404] ${identifier}" "${notify}"
        fi



      elif [[ "${httpStatus}" == 521 || "${httpStatus}" == 523 || "${httpStatus}" == 530 ]]; then
        # 521 Cloudflare says the web server is down
        # 523 Cloudflare says origin unreachable
        # 530 origin DNS error
        httpStatusInfo="http_${httpStatus}"
          # on 1st pass
          if [[ "${pass}" == 1 ]]; then
            checkstream "${redo}" "${!httpStatusInfo}" "${link}"
            # log the link to try it again later
            echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
          fi
          # on 2nd pass
          if [[ "${pass}" == 2 ]]; then
            # alert about failure
            checkstream "${fail}" "${!httpStatusInfo}" "${link}"
            # write this fail to log
            checkstream "${fail}" "${!httpStatusInfo}" "${link}" >> "${wd}/${data}/.${timestamp}-errors-else"
            # trigger update CDN DNS for this item
            buildCDNrefreshlist
          fi



    else
      # catch codes not defined above
      # first, build variable of what the HTTP code is to import its literal message later using ${!var}
      httpStatusInfo="http_${httpStatus}"
        # on 1st pass
          if [[ "${pass}" == 1 ]]; then
            # problem could be temporary so warn about this identifier now, but recheck at the end
            # do this to avoid unnecessary e-mail alerts if something is only temporarily down
            checkstream "${redo}" "${!httpStatusInfo}" "${link}"
            # log the link to try it again later
            echo "${link}" >> "${wd}/${data}/.${timestamp}-links-tryagain"
          fi
          # on 2nd pass
          if [[ "${pass}" == 2 ]]; then
            # this must be long downtime. let's alert and if we have a message defined above that matches the current error, show that to explain what we know
            checkstream "${fail}" "${!httpStatusInfo}" "${link}"
            # write this fail to log
            checkstream "${fail}" "${!httpStatusInfo}" "${link}" >> "${wd}/${data}/.${timestamp}-errors-else"
          fi
    fi
  # we're done, now on to the next identifier so increase the loop count
  counter=$((counter +1))
  done < "${filename}"
}





### RUNTIME GUTS ###

# write the title
printf "Checking CDN uploads.\n\n"


# build version notification
  # find the "build date and time" of this file and if it's been changed since we last know, notify user
  if [[ -s "${wd}/.build" ]]; then
    # the .build storage file exists and it's not empty so assume it's useful
    last_build_date="$( < "${wd}/.build")"
    current_build="$(date --reference="${fullpath_and_name}" ${timestamp_format})"
    # test if build date and time has changed
    if [[ "${last_build_date}" != "${current_build}" ]]; then
      # build has changed since script last run, notify user about using this last new build
      printf 'Using new build: %s\n\n' "${current_build}"
      # update .build file
      date --reference="${fullpath_and_name}" ${timestamp_format} > "${wd}/.build"
    fi
  else
    # .build not yet known, so find out
    # get the modification date and time using `date --reference` of this script's path and name, and write that to a file
    date --reference="${fullpath_and_name}" ${timestamp_format} > "${wd}/.build"
    chmod 600 "${wd}/.build"
    current_build="$( < "${wd}/.build")"
    printf 'Using new build: %s\n\n' "${current_build}"
  fi


# lock file handling
  # check if persistent lockfile exists for metadata extraction and if prior script is busy then stop everything/skip this check
  if [[ -f "/run/lock/.cdn-upcheck-metadata.lock" ]]; then
    # find time lockfile was modified; %l %M %P format renders as 9:30pm for example
    lockfiletime="$(date --reference="/run/lock/.cdn-upcheck-metadata.lock" +%l:%M%P)"
    # remove leading space from the date output using parameter expansion (https://wiki.bash-hackers.org/syntax/pe)
    removeleadingspace="${lockfiletime%%[^[:blank:]]*}"
    lockfiletime="${lockfiletime#"${removeleadingspace}"}"
    echo "*** ABORT *** Building check list still running from ${lockfiletime}. Stopping."
    cleanup
    exit 1
  fi


# `mysqldump` current database to extract MP4 links from. if that fails, we crash gracefully by invoking emergency_cleanup()
# only do one dump per day to lighten server load, instead of unnecessarily refresh every hour
  # first check to see if dump.sql exists (if file is larger than zero bytes)
  if [[ -s "${wd}/${data}/.dump.sql" ]]; then
    # check to see how old the file is, if it's less than ${refreshtime} minutes, use it
    # the find command must be quoted in case the file in question contains spaces or special characters.
    if [[ "$(find "${wd}/${data}/.dump.sql" -mmin -"${refreshtime}")" ]]; then
      # use it
      printf 'Database dump is fresh enough, using it.\n\n'
      buildfiles || emergency_cleanup
    else
      printf 'Updating database dump...'
      dumpdatabase || emergency_cleanup
      printf 'done.\n'
      extractmetadata || emergency_cleanup
      buildfiles || emergency_cleanup
    fi
  # database dump doesn't exist, so create it
  else
    printf 'Dumping database... '
    dumpdatabase || emergency_cleanup
    printf 'done.\n'
    extractmetadata || emergency_cleanup
    buildfiles || emergency_cleanup
  fi



# tell us how many uploads we'll be checking
  filename="${wd}/${data}/.${timestamp}-xml-urls-shuf"
  # count how many lines in file, we assume this is how many uploads we'll be checking
  totallines="$(wc --lines < "${filename}")"
  printf 'Checking %s uploads.\n\n' "$totallines"

# set up a loop counter for progress reporting
counter=1



# if need be (if identifiers-checked.dat exists and is not empty), compare identifiers we have now with what was checked last time and if any have changed, notify what they are
  if [[ -s "${wd}/${data}/last-checked.list" ]]; then
  # what's been removed since last time?
  # use OR pipe (|| true) for `diff` to return zero exit status since a match with diff returns a non-zero exit status, and with `set -o errexit` it stops everything unnecessarily
  idsremoved="$(diff --suppress-common-lines --changed-group-format='%<' --unchanged-group-format='' "${wd}/${data}/last-checked.list" "${wd}/${data}/.${timestamp}-identifier-matches-list-sorted" || true)"
    if [[ -n "${idsremoved}" ]]; then
      printf '*** Uploads REMOVED since last refresh:\n'
      printf '%s\n' "${idsremoved}"
      printf '\n'
    fi
  # which IDs are new?
  idsnew="$(diff --suppress-common-lines --changed-group-format='%>' --unchanged-group-format='' "${wd}/${data}/last-checked.list" "${wd}/${data}/.${timestamp}-identifier-matches-list-sorted" || true)"
    if [[ -n "${idsnew}" ]]; then
      printf '*** Uploads added since last refresh:\n'
      printf '%s\n' "${idsnew}"
      printf '\n'
    fi
  fi

  # update the list of identifiers for this test next time
  # use -s test to only deal with files greater than zero bytes
  if [[ -s "${wd}/${data}/.${timestamp}-identifier-matches-list-sorted" ]]; then
    mv -f "${wd}/${data}/.${timestamp}-identifier-matches-list-sorted" "${wd}/${data}/last-checked.list"
  fi




# to ease load on remote servers, sleep a random amount before we begin checks, at least 10 seconds, up to 4 minutes
intwait="$(((RANDOM % 240)+10))"
wait="$(rendertimer "$intwait")"
printf '\n\nWaiting %s before we begin... ' "${wait}"
  sleep "$intwait"
printf 'done.\n'

# write the date and time now
starttime="$(date '+%l:%M:%S %P')"
# remove leading space from the date output using parameter expansion (https://wiki.bash-hackers.org/syntax/pe)
removeleadingspace="${starttime%%[^[:blank:]]*}"
starttime="${starttime#"${removeleadingspace}"}"
printf '\nStarting check now, at %s.\n\n\n' "${starttime}"




# now actually do the checking.
# FIRST PASS
cdn-upcheck 1
printf '\nFinished checking %s uploads.\n\n\n' "$totallines"


# SECOND PASS IF NEED BE
# if we had any errors during the first pass to try again (i.e. 302, 405-5xx+), check these links again now.
# double check metadata is correct as an identifier may have moved server. if the item is still down, send an e-mail alert at the end of this check.

  # see if log file is not empty (-s). if it's got entries, keep going, otherwise skip this 2nd pass
  if [[ -s "${wd}/${data}/.${timestamp}-links-tryagain" ]]; then
      filename="${wd}/${data}/.${timestamp}-links-tryagain"
      # count how many lines in this error file, we assume this is how many files
      totallines="$(wc --lines < "${filename}")"
      printf '*** Try again error(s) detected. ***\n\n'
      # reset loop counter for files
      counter=1

      # since we may have had problems with DNS not resolving in the first pass, rebuild the check list before continuing with this second pass
      extractmetadata_engine "${wd}/${data}/.${timestamp}-links-tryagain" "${wd}/${data}/.${timestamp}-renewed-xml-urls"
      
      # now that CDN URLs may have changed, find and replace prior metadata list file with updated entries using `awk`, thanks @tshiono (https://stackoverflow.com/questions/65862573)
      # this is done to save and detected changes right away so the lists are always fresh and not stale for the next check cron
      # the NR==FNR { BLOCK1; next } { BLOCK2 } syntax is a common idiom to switch the processing individually for each file. as the `NR==FNR` condition meets only for the 1st file in the argument list and `next` statement skips the following block, BLOCK1 processes the file "toupdate.txt" only. similarly BLOCK2 processes the file "masterlist.txt" only.
      awk 'NR==FNR {
        # if the function `match($0, pattern)` succeeds, it sets the `awk` variable `RSTART` to the start position of the matched substring out of $0, the current record read from the file, then sets the variable `RLENGTH` to the length of the matched substring
        # now we can extract the matched substring such as "/f_SomeName/f_SomeName_user.xml" by using the `substr()` function.
        if (match($0, "/[^/]+/[^/]*\\.xml$")) {
          # assign the array `map` so that the substring (the unique part) is mapped to the portion of the URL in ".xml-urls-sorted" list that we want to update
          map[substr($0, RSTART, RLENGTH)] = $0
        }
        next
        }{
        # if the value corresponding to the key is found in the array `map`, then the record ($0) is replaced with the value of the array indexed by the key.
        if (match($0, "/[^/]+/[^/]*\\.xml$")) {
          full_path = map[substr($0, RSTART, RLENGTH)]
          if (full_path != "") {
            $0 = full_path
          }
        }
        print
      }' "${wd}/${data}/.${timestamp}-renewed-xml-urls" "${wd}/${data}/.${timestamp}-xml-urls-sorted" > "${wd}/${data}/.xml-urls-sorted"

      # also do similar to above to write changes to what each identifier's MP4 files are in the main lists
      # `awk` solution thanks to @SasaKanjuh, comments added
      # must use -F for field separator for older version /usr/bin/mawk on target system
      awk -F '/' ' {
        # get each identifier
        identifier = $(NF - 1)

        # if we are going through the XML URLs (the first list), i.e. NR == FNR
        if (NR == FNR) {
          # strip off the last portion of the URL line from the last slash / until the end
          sub("/[^/]*$", "")
          # assign the first portion of the URL line to an array under each specific identifier
          first_portion[identifier] = $0
        }

        # if we are in the second list then get the first portion of the line using common identifier, and append the last portion taken from above
        else print first_portion[identifier] "/" $NF
      }' "${wd}/${data}/.xml-urls-sorted" "${wd}/${data}/.mp4-matches-sorted" > "${wd}/${data}/.mp4-urls"

      # sort this list to ensure it's still clean, no duplicates
      sort --unique "${wd}/${data}/.mp4-urls" > "${wd}/${data}/.mp4-urls-sorted"
      # create a new list MP4 files reference list to use for 2nd pass checking
      cp "${wd}/${data}/.mp4-urls-sorted" "${wd}/${data}/.${timestamp}-renewed-mp4-urls-sorted"


      # now re-check from renewed list
      filename="${wd}/${data}/.${timestamp}-renewed-xml-urls"
      printf 'Re-checking %s identifiers.\n\n' "$totallines"
      # run 2nd pass
      cdn-upcheck 2
    printf '\nFinished re-checking %s uploads.\n\n\n' "$totallines"
  fi



  # if encountered any 000 "couldn't resolve host errors" try to refresh DNS now
  if [[ -s "${wd}/${data}/.${timestamp}-cdns-to-refresh" ]]; then
    filename="${wd}/${data}/.${timestamp}-cdns-to-refresh"
    # count how many lines in this error file, we assume this is how many items require DNS refresh
    totallines="$(wc --lines < "${filename}")"
    printf '*** Possible DNS failure(s) detected. ***\n\n'

    printf 'Refreshing CDN DNS.\n'
      # set stopwatch to keep track of how long DNS update process takes, starting from now
      dns_update_start="$(date +%s)"
      printf 'Fetching CDN zone... '
      ZONE="$(curl --silent --location --proxy GET "https://api.cloudflare.com/client/v4/zones?name=${cdn_domain}&status=active" \
        -H "X-Auth-Email: ${cdn_acc_email}" \
        -H "X-Auth-Key: ${cdn_api_key}" \
        -H "Content-Type: application/json" | "${wd}/.inc/jq" -r .result[0].id || true)"
      if [[ $ZONE == "null" ]]; then
        printf 'FAILED. Is the account e-mail and API key correct for the %s account?\n\n\n' "${cdn_domain}"
      else
        printf 'done.\n\n'
        # found zone OK, so now try to refresh
          while read -r line; do
            # there's a new link on each line
            url="${line}"
            #extract the server number from the URL
            # add `true` to always exit successfully even if we don't get an ID match
            id="$(grep --only-matching '[0-9]\{6\}' <<< "${url}" || true)"
              if [[ -n "${id}" ]]; then
                # extracted server ID successfully
                # now use `host` to check if the upstream CDN server we're iterating returns an IP, which shows it has DNS (exists)
                ip="$(host "${url}" | "${wd}/.inc/ack" --output='$&' "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" || true)"
                  if [[ -n "${ip}" ]]; then
                    # `host` returned an IP for upstream CDN server, it exists, so increase count and notify user
                    printf '%s %s.%s  ->  %s' "$(checkstream_timestamp)" "${cdn_prefix}${id}" "${cdn_domain}" "${ip}"

                    # our website's subdomain we want to build, mapped with upstream CDN server
                    cdn_sub_domain="${cdn_prefix}${id}.${cdn_domain}" # cdnXXXXXX.cdn-upcheckdomain.tld
                    cdn_record_data="${ip}" # IP Address

                      # now write our DNS to cloudflare zone
                      # sleep one second first, so as to not overwhelm API (we get 1,200 requests per 5 min)
                      sleep 1
                      # fetch record data
                      RECORD="$(curl --silent --location --proxy GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?name=${cdn_sub_domain}" \
                        -H "X-Auth-Email: ${cdn_acc_email}" \
                        -H "X-Auth-Key: ${cdn_api_key}" \
                        -H "Content-Type: application/json" | "${wd}/.inc/jq" -r .result[0].id || true)"
                      # sleep another short moment
                      intwait="0.$(((RANDOM % 899)+100))s"; sleep "$intwait";
                      # write record data
                      if [[ "${#RECORD}" -le 10 ]]; then
                        RECORD="$(curl --silent --location --proxy POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
                        -H "X-Auth-Email: ${cdn_acc_email}" \
                        -H "X-Auth-Key: ${cdn_api_key}" \
                        -H "Content-Type: application/json" \
                        --data '{"type":"A","name":"'${cdn_sub_domain}'","content":"'${cdn_record_data}'","ttl":1,"proxied":true}' | "${wd}/.inc/jq" -r .result.id || true)"
                      fi
                      # sleep another short moment
                      intwait="0.$(((RANDOM % 899)+100))s"; sleep "$intwait";
                      # update the record
                      RESULT="$(curl --silent --location --proxy PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${RECORD}" \
                      -H "X-Auth-Email: ${cdn_acc_email}" \
                      -H "X-Auth-Key: ${cdn_api_key}" \
                      -H "Content-Type: application/json" \
                      --data '{"type":"A","name":"'${cdn_sub_domain}'","content":"'${cdn_record_data}'","ttl":1,"proxied":true}' || true)"
                      ##echo "${RESULT}"
                      if [[ "${RESULT}" != *"success\":true"* ]] && [[ "${RESULT}" != *"A record with those settings already exists."* ]] ; then
                        printf '  %s\n' "${fail}"
                      else
                        printf '  %s\n' "${ok}"
                      fi
                  else
                    # getting IP failed, but tell us what we're dealing with
                    printf '%s %s.%s    *** not found ***\n' "$(checkstream_timestamp)" "${cdn_prefix}${id}" "${cdn_domain}"
                  fi
              else
                # id extraction failed, but tell us what we're dealing with
                printf '%s\n' "CDN server ID extraction failed. ID was blank."
              fi
          # we're done when we've reached the end of the file
          done < "${filename}"
        # update now finished, stop timer
        dns_update_end="$(date +%s)"
        duration="$((dns_update_end-dns_update_start))"
        howlong="$(rendertimer $duration)"
        printf '\nRefreshing CDN DNS took %s.\n\n\n' "${howlong}"
      fi
  fi



# finished tests. now send bulk e-mail alerts and do other handling, if needed

  # 000 http status
    # send e-mail about failures to connect (error code 6)
      # check if log file exists and is not empty (-s)
      if [[ -s "${wd}/${data}/.${timestamp}-errors-000-6" ]]; then
        # prepend a little note to the log before e-mailing it
        printf '%s\n\n%s' "Here is a list of identifiers that did not resolve DNS during rechecking:" "$(cat "${wd}/${data}/.${timestamp}-errors-000-6")" > "${wd}/${data}/.${timestamp}-errors-000-6"
        # email it
        printf 'Could not resolve some hosts, sending e-mail log... '
        mail -s "cdn-upcheck [DNS Failures]" "${notify}" < "${wd}/${data}/.${timestamp}-errors-000-6"
        printf 'done.\n'
      fi

    # send e-mail about connection fails (error code 7)
      # check if log file exists and is not empty (-s)
      if [[ -s "${wd}/${data}/.${timestamp}-errors-000-7" ]]; then
        # prepend a little note to the log before e-mailing it
        printf '%s\n\n%s' "Here is a list of identifiers that failed to connect for an uptime test recheck:" "$(cat "${wd}/${data}/.${timestamp}-errors-000-7")" > "${wd}/${data}/.${timestamp}-errors-000-7"
        # email it
        printf 'Connection(s) refused, sending e-mail log... '
        mail -s "cdn-upcheck [Failed Connections]" "${notify}" < "${wd}/${data}/.${timestamp}-errors-000-7"
        printf 'done.\n'
      fi

    # send e-mail about unknown failures returned with 000 http code but specific `curl` error
      # check if log file exists and is not empty (-s)
      if [[ -s "${wd}/${data}/.${timestamp}-errors-000" ]]; then
        # prepend a little note to the log before e-mailing it
        printf '%s\n\n%s' "Here is a list of identifiers that returned some kind of zero status code during rechecking:" "$(cat "${wd}/${data}/.${timestamp}-errors-000")" > "${wd}/${data}/.${timestamp}-errors-000"
        # email it
        printf 'Zero status returned, sending e-mail log... '
        mail -s "cdn-upcheck [Zero Status Failures]" "${notify}" < "${wd}/${data}/.${timestamp}-errors-000"
        printf 'done.\n'
      fi


  # send e-mail about failed 302 redirects
    # check if log file exists and is not empty (-s)
    if [[ -s "${wd}/${data}/.${timestamp}-errors-302" ]]; then
      # prepend a little note to the log before e-mailing it
      printf '%s\n\n%s' "Here is a list of identifiers that returned 302 redirects to somewhere unexpected:" "$(cat "${wd}/${data}/.${timestamp}-errors-302")" > "${wd}/${data}/.${timestamp}-errors-302"
      # email it
      printf 'Unexpected redirect error(s) returned, sending e-mail log... '
      mail -s "cdn-upcheck [302 Redirect Errors]" "${notify}" < "${wd}/${data}/.${timestamp}-errors-302"
      printf 'done.\n'
    fi    


  # send e-mail about all other failures from the catch-all
    # check if log file exists and is not empty (-s)
    if [[ -s "${wd}/${data}/.${timestamp}-errors-else" ]]; then
      # prepend a little note to the log before e-mailing it
      printf '%s\n\n%s' "Here is a list of identifiers or files that failed an uptime test during rechecking:" "$(cat "${wd}/${data}/.${timestamp}-errors-else")" > "${wd}/${data}/.${timestamp}-errors-else"
      # email it
      printf 'Catch-all-rule error(s) returned, sending e-mail log... '
      mail -s "cdn-upcheck [Catch-all Failures]" "${notify}" < "${wd}/${data}/.${timestamp}-errors-else"
      printf 'done.\n'
    fi


# now cleanup temporary files, run the function for it
cleanup

printf "\n\n\nChecking CDN uploads completed.\n"

# stop timer and display total runtime
end=$(date +%s)
duration=$((end-start))
howlong="$(rendertimer $duration)"
printf '\nTotal runtime was %s.\n\n\n' "${howlong}"
