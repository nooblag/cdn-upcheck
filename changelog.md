# Changelog

## 3.1.16 - 2021/12/24
 * add the start of lockfile to notification when aborting from duplicate build check list

---
 
## 3.1.15 - 2021/12/14
 * improve 404 handling in 1st pass checkstream to try links again later (reduce false email alerts and also refresh metadata)

---

## 3.1.14 - 2021/12/13
 * fix stray cURL output in 2nd pass checkstream for 302 returned status.

---

## 3.1.13 - 2021/11/04
 * increase short sleep times throughout to ease off timeouts at remote end

---

## 3.1.12 - 2021/11/04
 * increase sleep time to ~10 seconds during MP4 file check in first pass of checkstream to ease off timeouts at remote end

---

## 3.1.11 - 2021/11/03
 * improve `curl` settings and error handling throughout to suppress messages in checkstream

---

## 3.1.10 - 2021/10/30
 * improve use of `find` to clear out old files in temporary file storage by excluding current session's timestamp and removing files older than 7 days, rather than double of `$refreshtime`

---

## 3.1.9 - 2021/10/25
 * improve cURL 000 `$failState` output in first and second passes of the checkstream so cURL's stdout never interrupts the checkstream but its `$errorCode` is still usable.

---

## 3.1.8 - 2021/10/10
 * improve status messages in if conditions when handling/building check URL strings in `extractmetadata_engine()`

---

## 3.1.7 - 2021/09/23
 * add null check to `jq` output in `extractmetadata_engine()`
 * restore pretty `${cdnid}` empty handling

---

## 3.1.6 - 2021/09/21
 * put error message before the link in MP4 file check, in HTTP 200 response 1st checkstream
 * modify `${cdnid}` empty handling temporarily.

---

## 3.1.5 - 2021/09/12
 * remove development output line left behind in `extractmetadata_engine()`

---

## 3.1.4 - 2021/09/12
 * improve metadata handling in `extractmetadata_engine()` for edge case where metadata is valid, but `jq` cannot find a server name

---

## 3.1.3 - 2021/09/12
 * fix bug in HTTP 200 status `if` conditions to catch rare failure with `grep` if remote endpoint is down or XML data is not fetched as expected
 * improve cleanup of temporary files for this section also
 * improve var handling for getting identifiers and also references to `$cdn_url` and `$cdnurl` made the latter `$build_cdnurl` to more easily distinguish it from the `$cdn_url` var which is a config setting

---

## 3.1.2 - 2021/09/05
 * improve failed status info inside MP4 checking for a HTTP 200 response in the first pass: render a verbose error message

---

## 3.1.1 - 2021/08/14
 * improve quoting throughout in a couple of places where old copy/paste slipped through commit
 * fix bug in refreshing build timestamp, ditto
 * convert tabs to spaces throughout

---

## 3.1 - 2021/08/14
 * changed the last check list filename
 * remove unnecessary `shuf` when extracting identifiers, as the XML list is used now, and is shuffled for each unique session with `buildfiles()` instead
 * fixed bug where clean slate was not ensured in `extractmetadata()` as `*` was inside quotes for filename so it was not interpreted as wildcard (and hence files not removed), but these lines improved by replacing `rm` with `find` anyway
 * subtly improved use of `rm` and `find` throughout
 * improve garbage collection with better regex in `cleanup()`

---

## 3.0.4 - 2021/08/13
 * refactor `extractmetadata()` and `buildfiles()` to move `awk` building of `.mp4-urls` which was unnecessary every time script runs, it's needed at extraction time
 * move `$refreshtime` to a variable in `.conf/` rather than hardcoded

---

## 3.0.3 - 2021/08/12
 * improve `if` conditions formatting throughout
 * determine and use dynamic paths for `${wd}` rather than hardcoding
 * improve quoting throughout

---

## 3.0.2 - 2021/08/11
 * improve build checking and move data store to working directory rather than data directory
 * improve usage of timestamps throughout
 * modify changelog formatting of versions
 * updated some comments throughout
 * extend `$refreshtime` to 725 minutes (12 hours, 5 minutes) instead of every 6 hours
 * improved garbage collection and re-enabled
 * improve ensuring the clean slate in `extractmetadata()`

---

## 3.0.1 - 2021/08/11
 * add facility to check last build date and notify the user about changes at runtime
 * replace `echo` with `printf` line at start

---

## 3.0 - 2021/08/11
 * add `git` tracking and sync with github

---

## 2.1.4 - 2021/08/11
 * refactor `buildfiles()` to ensure MP4 URLs sorted list is always populated

---

## 2.1.3 - 2021/07/26
 * improve `301` and `302` handling when checking MP4 files in first pass after a `200` response for `$httpStatus`

---

## 2.1.2 - 2021/07/25
 * fix bug in `ack` line with new vars where regex fails with variables, replace with shell expansion of `${cdn_url##*//}` instead, where `*//` means everything after the first //

---

## 2.1.1 - 2021/07/25
 * improve fetching metadata throughout to use .conf variables
 * improve `sed` usage throughout to use variables instead of hardcoded (thanks to @SasaKanjuh)
 * add `$cdn_prefix` var to .conf
 * add `$cdn_url` and `$cdn_origin_url` vars to .conf
 * refactor uses of piping `echo` to `grep` `sed` and `awk` to instead using STDIN `<<<` throughout

---

## 2.1 - 2021/07/24
 * add `$cdn_origin_domain` and `$cdn_origin_domain` to config params
 * refactor `buildCDNrefreshlist()` to use above params
 * improve `$timestamp` to include full date, not just time
 * temporarily suspend the usage of `cleanup()`

---

## 2.0.3 - 2021/07/24
 * refactored `buildCDNrefreshlist()`
 * removed unnecessary metadata extraction from `buildCDNrefreshlist()` and rolled back to using `$id` (server ID) to write the list instead

---

## 2.0.2 - 2021/07/21
 * fix bug in "Refreshing CDN DNS" where getting a "does not resolve" DNS response in the second check pass trips `buildCDNrefreshlist()` *and*  `$cdnurl` ends up empty because metadata extraction fails (due to DNS not resolving) before `buildCDNrefreshlist()`  even runs

---

## 2.0.1 - 2021/07/19
 * improved exit code handling for `checkconfigvars()`

---

## 2.0 - 2021/06/26
 * major restructure
   * removed hard-coded settings throughout and replaced them with `.conf/`
   * cleaned up bundled binaries `ack` and `jq` and put them in `.inc/`
   * separated changelog comments from the script header into this now individual file
 * general code clean up

---

## 1.36.14 - 2021/06/23
 * improve `$cdnurl` extraction handling in `extractmetadata_engine()` and `buildCDNrefreshlist()` to avoid using empty strings in edge cases where remote server returns a non-empty metadata response, but the extraction doesn't return something expected

---

## 1.36.13 - 2021/06/23
 * modify `xtrace` for check stream

---

## 1.36.12 - 2021/06/16
 * improve exit status handling on `curl` throughout

---

## 1.36.11 - 2021/06/15
 * improve handling of 403 and 404 errors in check stream

---

## 1.36.10 - 2021/06/12
 * fix bug in `curl` exit status handling for 000 HTTP status errors

---

## 1.36.9 - 2021/06/12
 * improve indentation throughout

---

## 1.36.8 - 2021/05/30
 * improve quoting throughout

---

## 1.36.7 - 2021/05/15
 * improve DNS refresh condition: more reliable to check if string is empty rather than testing exit code to proceed
 * improve quoting on subshell variables throughout

---

## 1.36.6 - 2021/05/15
 * fix bugs throughout when using `grep` or `awk` to extract ID: always exit with `true` even if there is no ID match so we don't `errexit`

---

## 1.36.5 - 2021/05/15
 * fix bug in `emergencycleanup()` where data directory not being cleaned properly on `SIGINT`

---

## 1.36.4 - 2021/05/04
 * improve reportbacks in the check stream for files: clarify `[WARN]` instead of `[REDO]` if we're not actually redoing

---

## 1.36.3 - 2021/05/03
 * improve `diff` checking with `set -o errexit` environment as when `diff` finds a match it returns a non-zero exit status which stops everything unnecessarily

---

## 1.36.2 - 2021/04/29
 * improve `emergency_cleanup()` trap to `pkill` all currently running instances so next scheduled cron can attempt to start from scratch with fresh data
 * improve `${timestamp}` handling throughout
 * improve file lock handling throughout so there's a specifically unique file lock denoting this specific session running

---

## 1.36.1 - 2021/04/27
 * improve handling of temporary files with `curl` throughout
 * improve garbage collection and emergency cleanup to clear lock file on SIGINT SIGTERM SIGKILL
& ensure we stop everything on exit with `set -e`

---

## 1.36 - 2021/04/27
 * add a `trap` that runs on aborts or exits so that garbage collection of current temp files from this check (timestamped files) always runs and that file locks are handled/checked

---

## 1.35 - 2021/04/27
 * introduce file lock when extracting metadata for the first time, as when the process takes longer than 30 minutes, we run into problems with the next cron starting with incomplete data (lists are still being generated)

---

## 1.34.7 - 2021/04/26
 * improve subshell quoting throughout
 * improve and standardise comments inside `awk` scripts throughout
 * improve output of `extractmetadata_engine()` to include what we're up to at each iteration so we have some output while this is running in a shell rather than cron (so we can see what script is doing/is up to)

---

## 1.34.6 - 2021/04/26
 * improve `awk` lines to have uniform field delimiter syntax: `-F '/'`

---

## 1.34.5 - 2021/04/25
 * improve handling of temporary files: move everything to `${data}` folder and update all inputs/outputs to there instead of with this script and its binary dependencies (i.e. easier cleanup during development and testing)

---

## 1.34.4 - 2021/04/25
 * improve `mysqldump` query to narrow the returned values to only `'meta_key'` values that have data in `'tm_video_file'` or `'tm_video_code'` which is where our MP4 files sit (in custom fields)

---

## 1.34.3 - 2021/04/25
 * improve the use of `rm` throughout for better safety so we're not deleting beyond expected scope in some cases with temporary files!

---

## 1.34.2 - 2021/04/25
 * improve `ack` and `jq` calls throughout to include full path using `${wd}` so we always use enclosed bundled binaries for these

---

## 1.34.1 - 2021/04/25
 * improve `ack` query to extract CDN references

---

## 1.34 - 2021/04/25
 * overhaul checking to confirm the existence of MP4 files, not just confirming the metadata. this covers edge cases where an identifier exists and is accessible, but the MP4 file has been removed or is not available for whatever reason

---

## 1.33 - 2021/04/24
 * introduce garbage collection to `buildfiles()`

---

## 1.32.8 - 2021/04/24
 * improve handling of temporary files in `buildfiles()`

---

## 1.32.7 - 2021/04/24
 * improve `read` throughout to ensure better use of `-r` consistently

---

## 1.32.6 - 2021/04/24
 * improve handling of mail commands: get rid of [useless](https://github.com/koalaman/shellcheck/wiki/SC2002) `cat` and use `STDIN`

---

## 1.32.5 - 2021/04/24
 * further improve escaping on some variables throughout, including subshell commands

---

## 1.32.4 - 2021/04/24
 * fix usage of `$((..))` instead of [deprecated](https://github.com/koalaman/shellcheck/wiki/SC2007) `$[..]` throughout

---

## 1.32.3 - 2021/04/24
 * fix line formatting for time before the first pass starts

---

## 1.32.2 - 2021/04/24
 * improve escaping on some variables throughout

---

## 1.32.1 - 2021/04/24
 * improve all `printf` lines to [not use variables in the format string](https://github.com/koalaman/shellcheck/wiki/SC2059)

---

## 1.32 - 2021/04/24
 * overhaul check stream output: replace with a function for uniform use throughout and easier future changes

---

## 1.31 - 2021/04/24
 * overhaul check stream counter: replace `if` conditions with better and more simple `printf` line solution thanks to [@anubhava](https://stackoverflow.com/questions/67224543)

---

## 1.30.1 - 2021/04/22
 * fix line formatting for time before check stream begins

---

## 1.30 - 2021/04/22
 * add current time to check stream to show what was checked, when

---

## 1.29.1 - 2021/04/21
 * improve `rendertimer()` to handle Days, Hours, Minutes, Seconds
 * and also begin using [semantic versioning](https://semver.org/) for better tracking of changes and include the date of changes!

---

## 1.29
 * add `rendertimer()` to write out readable times in Hours, Minutes, Seconds - inspired by `hms` thanks to https://www.shellscript.sh/tips/hms/

---

## 1.28
 * improve handling of 521 523 530 errors in second pass check to trip updating DNS for those errors

---

## 1.27
 * add metadata extraction functions to reduce duplicate code throughout

---

## 1.26
 * fix bug in check stream where `${cdnurl}` contains an empty CDN ID if `extractmetadata()` fails to find the CDN ID

---

## 1.25
 * improve `mysqldump` query to reduce scope of database dump to only specific tables and only specific fields of that table, and then increase database refresh time from 12 hours to every 6 hours

---

## 1.24
 * improve `diff` data handling of metadata: update/save the data as soon as we detect differences with identifiers, instead of after checks were complete to prevent duplicate notifications using older data

---

## 1.23
 * improve metadata and DNS update handling to check for rare case where metadata returned is empty (remote end is offline or the fetch fails) and hence we have empty strings for the updates which causes problems

---

## 1.22
 * improve the check stream output to include the current CDN server ID as well as identifier, rather than solely identifier without more context

---

## 1.21
 * improve 'REDO' and 'FAIL' error reporting in the check stream

---

## 1.20
 * add DNS updating to identifiers that return 000 "couldn't resolve host" to sync if upstream server IPs have changed

---

## 1.19
 * add timer to metadata extraction process and notify how long that process took by itself

---

## 1.18
 * improve handling of situation where identifier has moved server (on failures, check and rewrite XML URLs list at the end)

---

## 1.17
 * improve checking identifiers: check `cdnXXXXXX.DOMAIN.TLD` URLs not `cdn.DOMAIN.TLD` ones, so as to also check CDN DNS is correct while we're at it; also improve some string handling throughout (more robust quoting) and add some basic functions for repeat actions

---

## 1.16
 * improve 404 error handling for e-mail notifications

---

## 1.15
 * improve regex in `ack` for line 78 "extracting CDN references" to catch edge cases where file does not end in `.mp4`

---

## 1.14
 * add `curl` handling for `000 error (6)` which is DNS fail

---

## 1.13
 * add variables to handle credentials in commands for database name and login rather than hardcoding throughout

---

## 1.12
 * add `shuf` to shuffle lines in mp4-identifiers-sorted, so items are checked in random order each time

---

## 1.11
 * fix bug in sending 'catch-all' e-mails in the check stream

---

## 1.10
 * improve handling of `mysqldump`: only do one dump per 12hrs to lighten server load, instead of unnecessarily refreshing every hour

---

##  1.9
 * improve handling of temporary data files: insert runtime timestamp to filenames (i.e. `.HHMMSS-mp4-identifiers-temp`) so that a current script running does not affect a script starting within the same hour as files are cleaned/removed at startup

---

##  1.8
 * improve handling of 5xx errors: try them all again later, and also provide better output if still return 5xx at end of checks to include Cloudflare error information such as SSL failures, timeouts, etc

---

##  1.7
 * add handling of 302 (temporary) redirects, as this is probably okay and not an error

---

##  1.6
 * improve handling of 5xx errors so it triggers less e-mail alerts

---

##  1.5
 * improve handling of cURL 000 status, as some error codes aren't problematic errors in this context (https://curl.haxx.se/libcurl/c/libcurl-errors.html)

---

##  1.4
 * improve checking loop and formatting for cron e-mails, add date and time stamps for better tracking

---

##  1.3
 * add notification on which identifiers are new/deleted since last check using `diff`

---

##  1.2
 * add exits on critical points of failure (set working dir, `mysqldump`, etc) with `||`

---

## 1.1
 * revise handling of HTTP 5xx errors---recheck them at the end

---

## 1.0
 * initial
