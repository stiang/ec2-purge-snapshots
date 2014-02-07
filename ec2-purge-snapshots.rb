#!/usr/bin/env ruby

# -----------------------------------------------------
# Author:  Stian Grytoyr <stian (at) grytoyr (dot) net> 
# Created: September 2010
# License: Apache License 2.0
# -----------------------------------------------------

require 'optparse'
require 'rubygems'
require 'date'

def purge_snapshots(ec2, options, vol, vol_snaps, volume_counts)
  newest = vol_snaps.last
  prev_start_date = nil
  delete_count    = 0
  keep_count      = 0

  vol_snaps.each do |snap|
    snap_date = Time.parse(snap['startTime']).localtime
    snap_Date = Date.parse(snap_date.to_s)
    snap_age = ((NOW.to_i - snap_date.to_i).to_f / HOUR.to_f).to_i
    # Hourly 
    if snap_age > options[:hours]
      # Daily 
      if snap_age <= START_WEEKS_AFTER
        type_str       = "day"
        start_date_str = snap_date.strftime("%Y-%m-%d")
        start_date     = Time.parse("#{start_date_str}")
      else
        # Weekly 
        if snap_age <= START_MONTHS_AFTER
          type_str       = "week"
          week_day       = snap_date.strftime("%w").to_i
          start_date     = Time.at(snap_date.to_i - (week_day * DAY))
          start_date_str = start_date.strftime("%Y-%m-%d")
        else
          # Monthly 
          type_str = "month"
          start_date_str = snap_date.strftime("%Y-%m")
          start_date     = Time.parse("#{start_date_str}-01")
        end
      end
      if start_date_str != prev_start_date && snap_Date > DELETE_BEFORE_DATE
        # Keep
        prev_start_date = start_date_str
        msg =  "Keeping #{snap['snapshotId']}: #{snap_date}, #{(snap_age.to_f / 24.to_f).to_i} "
        msg += "days old - #{type_str} of #{start_date_str}" 
        puts msg unless options[:quiet] 
        keep_count += 1
      else
        # Never delete the newest snapshot
        if snap['snapshotId'] == newest['snapshotId']
          msg =  "Keeping #{snap['snapshotId']}: #{snap_date}, #{snap_age} hours old - "
          msg += "will never delete newest snapshot" 
          puts msg unless options[:quiet]
          keep_count += 1
        else
          # Delete it
          not_really_str = options[:noop] ? "(not really) " : ""
          msg = "- Deleting #{not_really_str}#{snap['snapshotId']}: #{snap_date}, "
          msg += "#{(snap_age.to_f / 24.to_f).to_i} days old" 
          puts msg unless options[:silent]
          begin
            ec2.delete_snapshot(:snapshot_id => snap['snapshotId']) unless options[:noop]
          rescue AWS::Error => e
            puts e
          else
            delete_count += 1
            sleep [delete_count, 20].min * 0.05
          end
        end
      end
    else
      msg =  "Keeping #{snap['snapshotId']}: #{snap_date}, #{snap_age} hours old - "
      msg += "#{options[:hours]}-hour threshold"
      puts msg unless options[:quiet]
      keep_count += 1
    end
  end
  volume_counts[vol] = [delete_count, keep_count]
end

NOW  = Time.now
HOUR = 3600
DAY  = 86400

if ARGV[0] == "-h" and not ARGV[1]
  puts "Must specify volumes and rules."
  puts "#{$0} --help for usage info."
  exit 20
end

options = {}
filter_tags = []
opts_parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  opts.separator ""
  opts.separator "Deletes ALL snapshots (for the volumes specified) that do not"
  opts.separator "match the rules below. Rules are applied in the following order:"
  opts.separator ""
  opts.separator "    hours -> days -> weeks -> months"
  opts.separator ""
  opts.separator "MANDATORY options (one of -v or -t must be used):"
  opts.on("-v", "--volumes VOL1,VOL2,...", Array, "Comma-separated list (no spaces) of volume-ids,", 
                                                  "or 'all' for all volumes") do |v|
    options[:volumes] = v
  end
  opts.on("-t", "--tag key=value", "Tag to use to filter the snapshot. May specify multiple.") do |tag|
    tagParts = tag.split('=')
    filter_tags << tagParts
  end
  opts.separator ""
  opts.separator "MANDATORY rules:"
  opts.on("-h", "--hours HOURS", "The number of hours to keep ALL snapshots") do |hours|
    options[:hours] = hours.to_i
  end
  opts.on("-d", "--days DAYS", "The number of days to keep ONE snapshot per day") do |days|
    options[:days] = days.to_i
  end
  opts.on("-w", "--weeks WEEKS", "The number of weeks to keep ONE snapshot per week") do |weeks|
    options[:weeks] = weeks.to_i
  end
  opts.on("-m", "--months MONTHS", "The number of months to keep ONE snapshot per month") do |months|
    options[:months] = months.to_i
  end
  opts.separator ""
  opts.separator "OPTIONAL options:"
  opts.on("-a", "--access-key-file FILENAME", "The path to a file containing the AWS access key to use,", 
                                              "otherwise use the value of $AWS_ACCESS_KEY") do |afile|
    options[:access_file] = afile
  end
  opts.on("-e", "--secret-key-file FILENAME", "The path to a file containing the AWS secret key to use,", 
                                              "otherwise use the value of $AWS_SECRET_KEY") do |sfile|
    options[:secret_file] = sfile
  end
  opts.on("-n", "--noop", "Don't actually delete, but print what would be done") do |n|
    options[:noop] = true
  end
  opts.on("-q", "--quiet", "Print deletions only") do |q|
    options[:quiet] = true
  end
  opts.on("-s", "--silent", "Print summary only") do |q|
    options[:quiet] = true
    options[:silent] = true
  end
  opts.on("--no-summary", "Don't print summary") do |q|
    options[:no_summary] = true
  end
  opts.on("-x", "--extremely-silent", "Don't print anything unless something goes wrong") do |q|
    options[:quiet] = true
    options[:silent] = true
    options[:xsilent] = true
  end
  opts.on("-u", "--url URL", "The Amazon EC2 region URL (default is US East 1)") do |url|
    options[:url] = url
  end
  opts.on_tail("--help", "Show this message") do
    puts opts
    exit
  end
end
opts_parser.parse!

ENV["EC2_URL"] = options[:url] if options[:url]

# HACK: Had to move this here so it would pick up the environment variable EC2_URL, 
# which is set after the options are parsed. Is there a better way to do this?
require 'AWS'       # sudo gem install amazon-ec2

# Check for mandatory options/rules
if (options[:volumes].nil? and filter_tags.empty?) or options[:hours].nil? or options[:days].nil? or 
                             options[:weeks].nil? or options[:months].nil?
  puts opts_parser.help
  exit 1
end
  
START_WEEKS_AFTER = options[:hours] + (options[:days] * 24)
START_MONTHS_AFTER = START_WEEKS_AFTER + (options[:weeks] * 24 * 7)
DELETE_BEFORE_DATE = Date.parse((Time.at(NOW.to_i - (START_MONTHS_AFTER * HOUR))).to_s) << options[:months]

aws_access_key = options[:access_file] ? File.read(options[:access_file]).strip : ENV['AWS_ACCESS_KEY']
aws_secret_key = options[:secret_file] ? File.read(options[:secret_file]).strip : ENV['AWS_SECRET_KEY']

# Check that the AWS credentials are somewhat sensible
if aws_access_key and aws_access_key != '' and aws_secret_key and aws_secret_key != ''
  ec2 = AWS::EC2::Base.new(:access_key_id => aws_access_key, :secret_access_key => aws_secret_key)
  snapshots = []
  snapshots_set = ec2.describe_snapshots(:owner => "self")
  if snapshots_set and snapshots_set.snapshotSet and 
                       snapshots_set.snapshotSet.item and not 
                       snapshots_set.snapshotSet.item.empty?
    snapshots = snapshots_set.snapshotSet.item.find_all {|s| s['status'] == "completed"}
  end

  # Make sure we have some snapshots to work with
  unless snapshots.empty?
    volume_counts   = {}
    if filter_tags.empty? 
      if options[:volumes].size == 1 and options[:volumes][0] == "all"
        volumes = snapshots.collect {|s| s['volumeId']}.uniq
      else
        volumes = options[:volumes]
      end
  
      volumes.each do |vol|
        # Find snapshots for this volume and sort them by date (oldest first)
        vol_snaps = snapshots.find_all {|s| s['volumeId'] == vol}.sort_by {|v| v['startTime']}
        puts "---- VOLUME #{vol} (#{vol_snaps.size} snapshots) ---" unless options[:quiet]
  
        purge_snapshots ec2, options, vol, vol_snaps, volume_counts  
          
      end      
    else
      vol_snaps = snapshots_set.snapshotSet.item.find_all {|s| s['status'] == "completed" && !s['tagSet'].nil? && filter_tags.all? {|f| s['tagSet'].item.detect {|t| t['key']==f[0] && t['value']==f[1]}} }.sort_by {|v| v['startTime']}
      tag_id = filter_tags.collect{|f| "#{f[0]}=#{f[1]}"}.join(", ")  
      purge_snapshots ec2, options, tag_id, vol_snaps, {}
    end
    if not options[:xsilent] and not options[:no_summary]
        puts ""
        puts "SUMMARY:"
        puts ""
        volume_counts.each do |vol, counts|
          puts "#{vol}:"
          puts "  deleted: #{counts[0]}"
          puts "  kept:    #{counts[1]}"
          puts ""
        end
      end
  else
    puts "No snapshots found, exiting."
    exit 2
  end

else
  puts "No AWS access/secret keys specified, aborting."
  puts "#{$0} --help for more info"
  puts ""
  exit 2
end
