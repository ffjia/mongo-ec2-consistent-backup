# Mongo consistent backup over RAID EBS disks on EC2 instance

Suite of tools to backup and manage snapshots of MongoDB data set to EC2 Snapshots.

## Lock and Snapshot: mongo_lock_and_snapshot.rb

### Usage

Snapshot a list of devices on a given instance on ec2.

```shell
/root/bin/mongo-ec2-consistent-backup/bin# ruby lock_and_snapshot -a ACCESS_KEY -s 'SECRET_KEY' -d "/dev/sdc,/dev/sdb" -h host -r us-east-1 -l 7 >> /tmp/mongo_backup.log 2>&1
```

* --access-key-id, -a :   Access Key Id for AWS
* --secret-access-key, -s :   Secret Access Key for AWS
* --devices, -d :   Devices to snapshot, comma separated
* --type, -t :   Snapshot type, to choose among test,snapshot,daily,weekly,monthly,yearly (default: snapshot)
* --help, -h:   Show this message

### Usage with IAM

If you use IAM for your authentication in EC2, here is a probably up to date list of the permissions you need to grant:

```
  "ec2:CreateSnapshot",
  "ec2:DeleteSnapshot",
  "ec2:DescribeSnapshots",
  "ec2:CreateTags",
  "ec2:DescribeTags",
  "ec2:DescribeVolumes",
  "ec2:DescribeInstances",
  "ec2:AttachVolume",
  "ec2:CreateVolume"
```
