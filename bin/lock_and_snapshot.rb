#!/usr/bin/env ruby
# Lock a set of disk via the mongo lock command and snapshot them to the cloud

require 'rubygems'
require 'trollop'

$: << File.join("..", File.dirname(__FILE__), "lib")
require 'ec2-consistent-backup'

opts = Trollop::options do
  opt :port, "Mongo port to connect to", :default => 27017
  opt :access_key_id, "Access Key Id for AWS", :type => :string, :required => true
  opt :secret_access_key, "Secret Access Key for AWS", :type => :string, :required => true
  opt :devices, "Devices to snapshot, comma separated", :type => :string, :required => true
  opt :hostname, "Hostname to look for. Should resolve to a local EC2 Ip", :type => :string, :required => true
end

# find instance id by
#  - resolving name to ip
#  - looking in EC2 for server
# Lock Mongo
# Snapshot
# Unlock

aki = opts[:access_key_id]
sak = opts[:secret_access_key]

identifier = EC2InstanceIdentifier.new(aki, sak)
instance = identifier.get_instance(opts[:hostname])

locker = MongoHelper::DataLocker.new(opts[:port], opts[:hostname])

locker.lock
begin
  snapshoter = EC2VolumeSnapshoter.new(aki, sak, instance.id)
  snapshoter.snapshot_devices(opts[:devices].split(/,/))
rescue Exception => e
  require "pp"
  puts e.inspect  
  pp e.backtrace
ensure
  locker.unlock
end