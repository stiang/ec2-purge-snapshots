# ec2-purge-snapshots

## What is it?

A Ruby script that lets you purge (delete) AWS EC2 snapshots
according to rules you set up. 

For example, you can specify that you want to keep every snapshot 
for 48 hours, then one per day for two weeks, then one per week 
for four weeks, and finally one per month for two years.

## Usage

    Usage: ./ec2-purge-snapshots.rb [options]

    Deletes ALL snapshots (for the volumes specified) that do not
    match the rules below. Rules are applied in the following order:

        hours -> days -> weeks -> months

    MANDATORY options:
        -v, --volumes VOL1,VOL2,...      Comma-separated list (no spaces) of volume-ids,
                                         or 'all' for all volumes

    MANDATORY rules:
        -h, --hours HOURS                The number of hours to keep ALL snapshots
        -d, --days DAYS                  The number of days to keep ONE snapshot per day
        -w, --weeks WEEKS                The number of weeks to keep ONE snapshot per week
        -m, --months MONTHS              The number of months to keep ONE snapshot per month

    OPTIONAL options:
        -a, --access-key-file FILENAME   The path to a file containing the AWS access key to use,
                                         otherwise use the value of $AWS_ACCESS_KEY
        -e, --secret-key-file FILENAME   The path to a file containing the AWS secret key to use,
                                         otherwise use the value of $AWS_SECRET_KEY
        -n, --noop                       Don't actually delete, but print what would be done
        -q, --quiet                      Print deletions only
        -s, --silent                     Print summary only
            --no-summary                 Don't print summary
        -x, --extremely-silent           Don't print anything unless something goes wrong
        -u, --url URL                    The Amazon EC2 region URL (default is US East 1)
            --help                       Show this message

## Known issues
* If you have many snapshots the script will eventually return the AWS error RequestLimitExceeded. Not sure how to fix this, since there is no information given about which limit is exceeded - maybe just add a slight delay between each API call?

## Contribute
Please fork and add pull requests if you would like to improve this package.

## Author
[Stian Grytøyr][1]

[1]: http://stian.grytoyr.net/about/
