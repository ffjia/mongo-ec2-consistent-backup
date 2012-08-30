require 'fog'
require 'open-uri'

# This class is responsible of the snapshoting of given disks to EC2
# EC2 related permissions in IAM
# Sid": "Stmt1344254048404",
#      "Action": [
#        "ec2:CreateSnapshot",
#        "ec2:DeleteSnapshot",
#        "ec2:DescribeSnapshots",
#        "ec2:CreateTags",
#        "ec2:DescribeTags",
#        "ec2:DescribeVolumes"
#      ],
#      "Effect": "Allow",
#      "Resource": [
#        "*"
#      ]
#

class NoSuchVolumeException < Exception
  def initialize(instance, volume, details)
    @instance, @volume, @details = instance, volume, details
  end
  def to_s
    "Unable to locate volume \"#{@volume}\" on #{@instance}\nKnow volumes for this instance are:\n#{@details.inspect}"
  end
end

class EC2VolumeSnapshoter
  # Kind of snapshot and their expiration in days
  KINDS = { 'test' => 1,
    'snapshot' => 0,
    'daily' => 7,
    'weekly' => 31,
    'monthly' => 300,
    'yearly' => 0}

  attr_reader :instance_id, :prefix
  # Need access_key_id, secret_access_key and instance_id
  # If not provided, attempt to fetch current instance_id
  def initialize(aki, sak, region, prefix, instance_id = open("http://169.254.169.254/latest/meta-data/instance-id").read)

    @instance_id = instance_id
    @prefix = prefix

    @compute = Fog::Compute.new({:provider => 'AWS', :aws_access_key_id => aki, :aws_secret_access_key => sak, :region => region })
  end
  # Snapshots the list of devices
  # devices is an array of device attached to the instance (/dev/foo)
  # name if the name of the snapshot
  def snapshot_devices(devices, prefix, limit = 0, name = "#{instance_id}")
    log "Snapshot limit set to #{limit} (0 means never purge)"
    ts = DateTime.now.strftime("%Y-%m-%d-%H-%M").to_s
    name = "#{prefix} " + name
    volumes = {}
    devices.each do |device|
      volumes[device] = find_volume_for_device(device)
    end
    sn = []
    volumes.each do |device, volume|
      log "Creating volume snapshot for #{device} on instance #{instance_id}"
      snapshot = volume.snapshots.new
      snapshot.description = name+": #{device}"
      snapshot.save
      sn << snapshot
      snapshot.reload

      @compute.tags.create(:resource_id => snapshot.id, :key =>"device", :value => device)
      @compute.tags.create(:resource_id => snapshot.id, :key =>"instance_id", :value =>instance_id)
      @compute.tags.create(:resource_id => snapshot.id, :key =>"date", :value => ts)
    end

    # DO NOT need to wait for creating EBS snapshot
    #log "Waiting for snapshots to complete."
    #sn.each do |s|
    #  begin
    #    sleep(3)
    #    s.reload
    #  end while s.state == 'nil' || s.state == 'pending'
    #end

    if limit != 0
      # populate data structure with updated information
      snapshots = list_snapshots(devices)
      nsnaps = snapshots.keys.length
      if nsnaps-limit > 0
        dates = snapshots.keys.sort
        puts dates.inspect
        extra_snapshots = dates[0..-(limit+1)]
        remaining_snapshots = dates[-limit..-1]
        extra_snapshots.each do |date|
          snapshots[date].each do |snap|
            log "Destroying #{snap.description} #{snap.id}"
            snap.destroy
         end
        end
      end
    end
  end

  # List snapshots for a set of device
  require 'pp'
  def list_snapshots(devices)
    volume_map = []
    snapshots = {}

    tags = @compute.tags.all(:key => 'instance_id', :value => instance_id)
    tags.each do |tag|
      snap = @compute.snapshots.get(tag.resource_id)
      t =  snap.tags

      if devices.include?(t['device']) &&
        instance_id == t['instance_id'] &&
        snapshots[t['date']] ||= []
        snapshots[t['date']] << snap
      end
    end

    # take out incomplete backups
    snapshots.delete_if{ |date, snaps| snaps.length != devices.length }
    snapshots
  end

  def find_volume_for_device(device)
    my = []
    @compute.volumes.all().each do |volume|
      if volume.server_id == @instance_id
        my << volume
        if volume.device == device
          return volume
        end
      end
    end
    raise NoSuchVolumeException.new(@instance_id, device, my)
  end
end

if __FILE__ == $0
  require 'trollop'
  require 'pp'

  opts = Trollop::options do
    opt :access_key_id, "Access Key Id for AWS", :type => :string, :required => true
    opt :secret_access_key, "Secret Access Key for AWS", :type => :string, :required => true
    opt :instance_id, "Instance identifier", :type => :string, :required => true
    opt :find_volume_for, "Show information for device path (mount point)", :type => :string
    opt :snapshot, "Snapshot device path (mount point)", :type => :string
    opt :snapshot_type, "Kind of snapshot (any of #{EC2VolumeSnapshoter::KINDS.keys.join(", ")})", :default => 'test'

  end

  evs = EC2VolumeSnapshoter.new(opts[:access_key_id], opts[:secret_access_key], opts[:instance_id])
  if opts[:find_volume_for]
    pp evs.find_volume_for_device(opts[:find_volume_for])
  end
  if opts[:snapshot]
    evs.snapshot_devices([opts[:snapshot]])
  end
end
