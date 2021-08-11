# cdn-upcheck/do

the purpose of this script is to run as a bi-hourly cron that extracts all references to CDN video streaming for project site and checks both the video files and metadata for uptime, availability, and correctness at the remote end

files that are inaccessible or incorrect trigger email alerts and logging