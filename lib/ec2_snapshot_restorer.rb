require 'fog'
require 'open-uri'

$: << File.dirname(__FILE__)

DEBUG=false

def log what
  puts what if DEBUG
end
# 
class SnapshotRestorer
  attr_accessor :snaps
  def initialize(aki, sak)
    @compute = Fog::Compute.new({:provider => 'AWS', :aws_access_key_id => aki, :aws_secret_access_key => sak})
    @snaps = []
    @volumes = []
  end
  def find_snapshots(instance_id, kind = 'snapshot')
    log "Looking for snapshots for #{instance_id}"
    volume_map = []
    snapshots = {}

    tags = @compute.tags.all(:key => 'instance_id', :value => instance_id)

    max_date = nil
    tags.each do |tag|
      snap = @compute.snapshots.get(tag.resource_id)
      t =  snap.tags

      # Ignore in progress snapshots
      if instance_id == t['instance_id'] && 
          snap.state == 'completed' &&
          t['kind'] == kind
        max_date = t['date'] if !max_date || max_date < t['date']
        log "#{snap.inspect} is valid"
        snapshots[t['date']] ||= []
        snapshots[t['date']] << snap
      end
    end
    snapshots['LATEST'] = snapshots[max_date] if snapshots[max_date]
    return snapshots
  end
  def prepare_volumes(dest_instance)
    @snaps.each do | resource_id |
      snap = @compute.snapshots.get(resource_id)
      # Snap have the following tags
      # application
      # device
      # instance_id
      # date
      # kind

      t =  snap.tags
      volume = @compute.volumes.new :snapshot_id => snap.id, :size => snap.volume_size, :availability_zone => 'us-east-1c'
      volume.save
      volume.reload
      @compute.create_tags(volume.id, { "application" => t['application'],
        "sdevice" => t['device'],
        "date" => t['date'],
        "kind" => t['kind'],
        "sinstance" => t['instance_id'],
        "dinstance" =>  dest_instance})
      
      @volumes << volume
    end
    def rattach_volumes(base_device = nil)
      dest = base_device
      if !dest
        dest = @volumes.map{ |v| v.tags['sdevice']}.min
      end
      dest = dest.dup

      @volumes.each do |vol|
        vol.reload
        puts "Attaching #{vol.id} to #{dest} on #{vol.tags['dinstance']}"
        @compute.attach_volume(vol.tags['dinstance'], vol.id, dest)
        dest.next!
      end
    end
  end
end

if __FILE__ == $0
  require 'trollop'
  require 'ec2_instance_identifier'
  require 'pp'
  opts = Trollop::options do
    opt :hostname, "Hostname tag to use to find the instance", :type => :string, :required => true
    opt :access_key_id, "Access Key Id for AWS", :type => :string, :required => true
    opt :secret_access_key, "Secret Access Key for AWS", :type => :string, :required => true
    opt :date, "Date to restore, use LATEST to take latest data", :type => :string
    opt :type, "Snapshot type to restore, defaults to snapshot", :type => :string, :default => 'snapshot'
    opt :target, "Creates volume ready for mounting on instance id. Use special value SELF to restore here", :type => :string
    opt :first_device, "First device to attach to (default is to use source first device) /dev/sdx", :type => :string
  end
    
  finder = EC2InstanceIdentifier.new(opts[:access_key_id], opts[:secret_access_key])
  instance_identifier = finder.get_instance(opts[:hostname]).id
  s = SnapshotRestorer.new(opts[:access_key_id], opts[:secret_access_key])

  # Find this instance snapshots
  snaps = s.find_snapshots(instance_identifier, opts[:type])

  if ! opts[:date] || !snaps.has_key?(opts[:date])
    puts "We have found the following snapshot's dates:"
    snaps.each do |k,v|
      puts "- #{k} (#{v.length} volume snapshots)"
    end
  else
    puts "Snapshot taken at #{opts[:date]}"
    snaps[opts[:date]].each do |snapshot|
      puts "- #{snapshot.id}, #{snapshot.volume_size}GB - #{snapshot.tags['device']}"
    end
    if opts[:target]
      s.snaps = snaps[opts[:date]].map{ |s| s.id }
      target = opts[:target]
      target = open("http://169.254.169.254/latest/meta-data/instance-id").read if target == "SELF"
      puts "Preparing volumes for instance #{target}"
      s.prepare_volumes(target)
      # Need to clone, because trollop freeze the variable
      s.rattach_volumes(opts[:first_device])
    end
  end

end
