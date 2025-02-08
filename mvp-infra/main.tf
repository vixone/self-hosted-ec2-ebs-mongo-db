provider "aws" {
  region = "us-east-1"
}

# Get current account info (used later if needed)
data "aws_caller_identity" "current" {}

# Fetch a free-tier eligible Ubuntu AMI (Ubuntu 20.04 LTS)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Use your local public key for SSH access.
resource "aws_key_pair" "default" {
  key_name   = "mvp-demo-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Security group allowing SSH, HTTP (port 8080 for the Go wrapper), and MongoDB (port 27017).
resource "aws_security_group" "instance_sg" {
  name        = "mvp-demo-sg"
  description = "Security group for MVP demo instance"

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow HTTP (Go Wrapper Service)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow MongoDB"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#############################
# IAM Role for the EC2 instance
#############################
resource "aws_iam_role" "ec2_role" {
  name = "mvp-demo-ec2-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "mvp-demo-instance-profile"
  role = aws_iam_role.ec2_role.name
}

#############################
# IAM Role for DLM (for automated snapshots)
#############################
resource "aws_iam_role" "dlm_role" {
  name = "mvp-demo-dlm-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "dlm.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "dlm_policy" {
  name        = "mvp-demo-dlm-policy"
  description = "Policy to allow DLM to manage EBS snapshots"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:DescribeSnapshots",
        "ec2:DescribeVolumes"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "dlm_policy_attach" {
  role       = aws_iam_role.dlm_role.name
  policy_arn = aws_iam_policy.dlm_policy.arn
}

#############################
# EC2 Instance (Free-tier eligible)
#############################
resource "aws_instance" "mvp_demo" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t2.micro"
  key_name             = aws_key_pair.default.key_name
  security_groups      = [aws_security_group.instance_sg.name]
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  root_block_device {
    volume_size = 8
    volume_type = "gp2"
  }

  # User data: install Docker, format & mount the attached EBS volume, and run Docker containers.
  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Update and install Docker
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker

              # Wait until /dev/sdf (the extra EBS volume) is attached.
              while [ ! -e /dev/sdf ]; do
                echo "Waiting for /dev/sdf to be attached..."
                sleep 2
              done

              MOUNTPOINT="/mnt/ebs"
              mkdir -p $MOUNTPOINT

              # Check if a filesystem exists; if not, create an ext4 filesystem.
              if [ "$(file -s /dev/sdf | awk '{print $2}')" = "data" ]; then
                mkfs -t ext4 /dev/sdf
              fi

              mount /dev/sdf $MOUNTPOINT
              echo "/dev/sdf $MOUNTPOINT ext4 defaults,nofail 0 2" >> /etc/fstab
              chown -R ubuntu:ubuntu $MOUNTPOINT

              # Launch MongoDB container (data stored on the mounted volume).
              docker run -d --name mongodb -p 27017:27017 -v $MOUNTPOINT:/data/db mongo:latest

              # Launch the Go wrapper container.
              docker run -d --name go-wrapper -p 8080:8080 --link mongodb:mongodb your-dockerhub-username/go-wrapper:latest
              EOF

  tags = {
    Name = "MVP-Demo-Instance"
  }
}

#############################
# Separate EBS Volume for Data (30 GB, gp3)
#############################
resource "aws_ebs_volume" "mvp_demo_volume" {
  availability_zone = aws_instance.mvp_demo.availability_zone
  size              = 30
  type              = "gp3"
  tags = {
    Name     = "mvp-demo-ebs-volume"
    Snapshot = "true"   # This tag is used to target the volume in the DLM policy.
  }
}

# Attach the EBS volume to the instance on /dev/sdf.
resource "aws_volume_attachment" "mvp_demo_attachment" {
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.mvp_demo_volume.id
  instance_id  = aws_instance.mvp_demo.id
  force_detach = true
}

#############################
# DLM Policy for Automated Snapshots
#############################
resource "aws_dlm_lifecycle_policy" "ebs_snapshot_policy" {
  description        = "Daily snapshot policy for EBS volumes"
  state              = "ENABLED"
  execution_role_arn = aws_iam_role.dlm_role.arn

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      Snapshot = "true"
    }

    schedules {
      name = "DailySnapshots"
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["02:00"]  # Snapshot daily at 2 AM.
      }
      retain_rule {
        count = 7
      }
      copy_tags = true
    }
  }
  tags = {
    Name = "MVP-Demo-DLM"
  }
}

