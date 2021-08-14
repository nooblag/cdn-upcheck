# cdn-upcheck/do

The purpose of this script is to run as a bi-hourly cronjob that extracts all references to CDN video streaming for project site and checks both the video files and metadata for uptime, availability, and correctness at the remote end.

Video files that are inaccessible or incorrect trigger email alerts and logging.

## Crontab example

The script is envisioned to be invoked at least once every hour.

To make each scheduled start time more readable in cron emails that are delivered, we pass the start time to the script in `${1}` but it is not used anywhere else except for the email subject line.

Example crontab, with further comments:

```
MAILTO='emailaddress@cmsdomain.com'

# cdn-upcheck script to check through MP4s hosted on CDN
  # CDN is in UTC -7 timezone so peak-times on servers there are likely to be from 3pm to midnight their time, which is roughly 8am to 5pm our time (UTC+10/11).
  # each check (of currently ~850 identifiers) takes ~2 hours to complete (~7 identifiers per minute).
  # running two checks every hour means approx ~14 identifiers checked per minute.
  # each unique identifier should be checked at least once inside each hourly range, but up to twice or three times at most inside the same hour (uncertain because of `shuf` randomisation).
  # the actual check window could be a few seconds up to one or two hours each identifier is checked in 24hr period, both because of `shuf` but also because database refreshes occur every 360 minutes (6 hrs
  # which takes 20-30 minutes itself.

  # midnight here, 7am at CDN
    00 00 * * * bash /home/jore/cdn-upcheck/do 12am
    30 00 * * * bash /home/jore/cdn-upcheck/do 12:30am
  #  1am,  8am CDN
    00 01 * * * bash /home/jore/cdn-upcheck/do 1am
    30 01 * * * bash /home/jore/cdn-upcheck/do 1:30am
  #  2am,  9am CDN
    00 02 * * * bash /home/jore/cdn-upcheck/do 2am
    30 02 * * * bash /home/jore/cdn-upcheck/do 2:30am
  #  3am, 10am CDN
    00 03 * * * bash /home/jore/cdn-upcheck/do 3am
    30 03 * * * bash /home/jore/cdn-upcheck/do 3:30am
  #  4am, 11am CDN
    00 04 * * * bash /home/jore/cdn-upcheck/do 4am
    30 04 * * * bash /home/jore/cdn-upcheck/do 4:30am
  #  5am, noon CDN
    00 05 * * * bash /home/jore/cdn-upcheck/do 5am
    30 05 * * * bash /home/jore/cdn-upcheck/do 5:30am
  #  6am,  1pm CDN
    00 06 * * * bash /home/jore/cdn-upcheck/do 6am
    30 06 * * * bash /home/jore/cdn-upcheck/do 6:30am
  #  7am,  2pm CDN, coming into peak
    00 07 * * * bash /home/jore/cdn-upcheck/do 7am
    30 07 * * * bash /home/jore/cdn-upcheck/do 7:30am
  #  8am,  3pm CDN, PEAK
    00 08 * * * bash /home/jore/cdn-upcheck/do 8am
    30 08 * * * bash /home/jore/cdn-upcheck/do 8:30am
  #  9am,  4pm CDN, PEAK
    00 09 * * * bash /home/jore/cdn-upcheck/do 9am
    30 09 * * * bash /home/jore/cdn-upcheck/do 9:30am
  # 10am,  5pm CDN, PEAK
    00 10 * * * bash /home/jore/cdn-upcheck/do 10am
    30 10 * * * bash /home/jore/cdn-upcheck/do 10:30am
  # 11am,  6pm CDN, PEAK
    00 11 * * * bash /home/jore/cdn-upcheck/do 11am
    30 11 * * * bash /home/jore/cdn-upcheck/do 11:30am
  # noon,  7pm CDN, PEAK
    00 12 * * * bash /home/jore/cdn-upcheck/do 12pm
    30 12 * * * bash /home/jore/cdn-upcheck/do 12:30pm
  #  1pm,  8pm CDN, PEAK
    00 13 * * * bash /home/jore/cdn-upcheck/do 1pm
    30 13 * * * bash /home/jore/cdn-upcheck/do 1:30pm
  #  2pm,  9pm CDN, PEAK
    00 14 * * * bash /home/jore/cdn-upcheck/do 2pm
    30 14 * * * bash /home/jore/cdn-upcheck/do 2:30pm
  #  3pm, 10pm CDN, PEAK
    00 15 * * * bash /home/jore/cdn-upcheck/do 3pm
    30 15 * * * bash /home/jore/cdn-upcheck/do 3:30pm
  #  4pm, 11pm CDN, PEAK
    00 16 * * * bash /home/jore/cdn-upcheck/do 4pm
    30 16 * * * bash /home/jore/cdn-upcheck/do 4:30pm
  #  5pm, midnight at CDN, coming out of peak
    00 17 * * * bash /home/jore/cdn-upcheck/do 5pm
    30 17 * * * bash /home/jore/cdn-upcheck/do 5:30pm
  #  6pm,  1am CDN
    00 18 * * * bash /home/jore/cdn-upcheck/do 6pm
    30 18 * * * bash /home/jore/cdn-upcheck/do 6:30pm
  #  7pm,  2am CDN
    00 19 * * * bash /home/jore/cdn-upcheck/do 7pm
    30 19 * * * bash /home/jore/cdn-upcheck/do 7:30pm
  #  8pm,  3am CDN
    00 20 * * * bash /home/jore/cdn-upcheck/do 8pm
    30 20 * * * bash /home/jore/cdn-upcheck/do 8:30pm
  #  9pm,  4am CDN
    00 21 * * * bash /home/jore/cdn-upcheck/do 9pm
    30 21 * * * bash /home/jore/cdn-upcheck/do 9:30pm
  # 10pm,  5am CDN
    00 22 * * * bash /home/jore/cdn-upcheck/do 10pm
    30 22 * * * bash /home/jore/cdn-upcheck/do 10:30pm
  # 11pm,  6am CDN
    00 23 * * * bash /home/jore/cdn-upcheck/do 11pm
    30 23 * * * bash /home/jore/cdn-upcheck/do 11:30pm
```

## Config

Config files are expected in `.config/` with the following layout:

### .cdn_acc_email
The email address to use to interact with CDN API, e.g. admin@cdn-upcheckdomain.tld

### .cdn_api_key
The API key to use to interact with CDN API

### .cdn_domain
The CDN base FQDN to use to interact with CDN API, e.g. `cdn-upcheckdomain.tld`

### .cdn_origin_domain
The *domain* for the non-whitelabel CDN provider, e.g. the `region.upstreamhost.com` part of `fooXXXXXX.region.upstreamhost.com`

### .cdn_origin_prefix
The upstream CDN provider's non-whitelabel CDN *prefix*, e.g. `foo` part of `fooXXXXXX.region.upstreamhost.com`

### .cdn_origin_url
The non-whitelabel URL of the CDN provider so there's a fail-safe zone to work with for DNS, e.g. `https://upstreamhost.com`

### .cdn_prefix
The prefix used in all DNS records for the cdn-upcheck zone, e.g. the `cdn` part of `cdnXXXXXX.cdn-upcheckdomain.tld`

### .cdn_url
This should be the same URL that is used in the CMS to refer to content, e.g. `https://cdn.cmsdomain.com`

### .mysqldump_db
The name of the database that the CMS domain uses, to pass to `mysqldump`.

### .mysqldump_pw
The password for the user of the database that the CMS domain uses, to pass to `mysqldump`.

### .mysqldump_user
The username of the database that the CMS domain uses, to pass to `mysqldump`.

### .notify
The email address to use to send alerts to. Should ideally be the same address used in the `$MAILTO` var of crontab.

### .refreshtime
The time in minutes that a fresh database dump should happen. This var is also used to calculate which files to clean in `cleanup()`.
