# Check-ServerDiskSpace
Pulls list of servers from AD and scans all disks for low free space then emails a report.

Example 1: Retuen a list of disks from all servers with less then 5 percent free disk space.
`Check-ServerDiskSpace -Percent 5`

## Optional Parameters ##
```
-Percent
If free disk space percentage is less than this number, the disk will be flagged as having low free space.
Default value: 10
```
