locals {
  hashcmd 	= "${var.cmdp1} ${var.hashmode} ${var.cmdp2}"
}

data "http" "myip" {
  url = "https://ipinfo.io/ip"
}

# create and run a cracking instance
provider "aws" {
  profile	= "default"
  region	= "eu-west-2"
}

resource "aws_security_group" "rook_security" {
  description	= "Allow inbound SSH."
  
  egress {
    from_port	= 0
    to_port	= 0
    protocol	= "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port	= 22
    to_port	= 22
    protocol	= "tcp"
    cidr_blocks	= ["${var.whitelistip}", "${chomp(data.http.myip.body)}/32"]
  }
}

resource "aws_instance" "rook-cracking" {
  ami			= "${var.ami}"
  instance_type		= "${var.itype}"
  key_name		= "${var.identity}"
  security_groups	= ["${aws_security_group.rook_security.name}"]
   
  ebs_block_device {
    device_name	= "/dev/xvdb"
    volume_size = 50
    volume_type = "gp2"
    snapshot_id = "${var.snapid}"
  }

  connection {
    type	= "ssh"
    host	= "${aws_instance.rook-cracking.public_ip}"
    user	= "ubuntu"
    private_key = "${file("${var.sshkeyfile}")}"
  }
  
  provisioner "file" {
    source	= "files/blacklist-nouveau.conf"
    destination	= "/tmp/blacklist-nouveau.conf"
  }

  provisioner "file" {
    source	= "files/nouveau-kms.conf"
    destination	= "/tmp/nouveau-kms.conf"
  }
  
  provisioner "file" {
    source	= "files/hashes.txt"
    destination	= "/tmp/hashes.txt"
  }

  provisioner "remote-exec" {
    inline = [
    "sudo apt update",
    "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\"",
    "sudo DEBIAN_FRONTEND=noninteractive apt install -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" build-essential linux-headers-aws-lts-20.04 gcc screen linux-image-extra-virtual git make nvidia-driver-495 nvidia-opencl-dev",
    "sudo apt update && sudo apt upgrade -y && sudo apt install build-essential -yq",
    "sudo cp /tmp/blacklist-nouveau.conf /etc/modprobe.d/.",
    "sudo cp /tmp/nouveau-kms.conf /etc/modprobe.d/.",
    "sudo cp /tmp/hashes.txt /opt/.",
    "sudo update-initramfs -u",
    "sudo reboot &",
    ]
    # sshd process may exit before the reboot completes, preventing it from
    # returning the scripts exit status
    # allow_missing_exit_status = true
    # Option doesn't appear to be working currently...
  }

  provisioner "remote-exec" {
    # new remote exec to connect back after restart
    inline = [
    "sudo wget -P /opt/ ${var.hashcat}",
    "sudo mkdir /opt/hashcat/",
    "sudo tar -xvf /opt/hashcat-6.2.5.tar.gz -C /opt/",
    "cd /opt/hashcat-5.1.0 && sudo make",
    "sudo mkdir /words/",
    "sudo mount /dev/xvdb /words/",
    "sudo chown -R ubuntu:ubuntu /words/",
    "sudo chown -R ubuntu:ubuntu /opt/hashcat-6.2.5/",
    "${local.hashcmd}",
    "sudo shutdown -P +600",
    "sleep 1",
    ]
  }
}

resource "null_resource" "local" {
  provisioner "local-exec" {
    command = "echo ssh -i ${var.sshkeyfile} ubuntu@${aws_instance.rook-cracking.public_ip}"
  }
}
