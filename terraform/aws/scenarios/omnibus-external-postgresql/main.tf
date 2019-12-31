module "chef_server" {
  source = "../../modules/aws_instance"

  aws_profile       = "${var.aws_profile}"
  aws_region        = "${var.aws_region}"
  aws_vpc_name      = "${var.aws_vpc_name}"
  aws_department    = "${var.aws_department}"
  aws_contact       = "${var.aws_contact}"
  aws_ssh_key_id    = "${var.aws_ssh_key_id}"
  aws_instance_type = "${var.aws_instance_type}"
  enable_ipv6       = "${var.enable_ipv6}"
  platform          = "${var.platform}"
  build_prefix      = "${var.build_prefix}"
  name              = "chef_server-${var.scenario}-${var.enable_ipv6 ? "ipv6" : "ipv4"}-${var.platform}"
}

module "postgresql" {
  source = "../../modules/aws_instance"

  aws_profile       = "${var.aws_profile}"
  aws_region        = "${var.aws_region}"
  aws_vpc_name      = "${var.aws_vpc_name}"
  aws_department    = "${var.aws_department}"
  aws_contact       = "${var.aws_contact}"
  aws_ssh_key_id    = "${var.aws_ssh_key_id}"
  aws_instance_type = "${var.aws_instance_type}"
  enable_ipv6       = "${var.enable_ipv6}"
  platform          = "ubuntu-16.04"
  build_prefix      = "${var.build_prefix}"
  name              = "postgresql-${var.scenario}-${var.enable_ipv6 ? "ipv6" : "ipv4"}-${var.platform}"
}

# generate static hosts configuration
data "template_file" "hosts_config" {
  template = "${file("${path.module}/templates/hosts.tpl")}"

  vars {
    chef_server_ip = "${var.enable_ipv6 == true ? module.chef_server.public_ipv6_address : module.chef_server.private_ipv4_address}"
    postgresql_ip  = "${var.enable_ipv6 == true ? module.postgresql.public_ipv6_address : module.postgresql.private_ipv4_address}"
  }
}

# generate chef_server.rb configuration
data "template_file" "chef_server_rb" {
  template = "${file("${path.module}/templates/chef-server.rb.tpl")}"

  vars {
    postgresql_ip = "${var.enable_ipv6 == true ? module.postgresql.public_ipv6_address : module.postgresql.private_ipv4_address}"
  }
}

# update postgres server
resource "null_resource" "postgresql_config" {
  # provide some connection info
  connection {
    type = "ssh"
    user = "${module.postgresql.ssh_username}"
    host = "${module.postgresql.public_ipv4_dns}"
  }

  provisioner "file" {
    content     = "${data.template_file.hosts_config.rendered}"
    destination = "/tmp/hosts"
  }

  provisioner "remote-exec" {
    inline = [
      "set -evx",
      "sudo chown root:root /tmp/hosts",
      "sudo mv /tmp/hosts /etc/hosts",
      "sleep 30",
      "echo 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' | sudo tee /etc/apt/sources.list.d/pgdg.list",
      "wget --quiet https://www.postgresql.org/media/keys/ACCC4CF8.asc",
      "sudo apt-key add ACCC4CF8.asc",
      "sudo apt-get update",
      "sudo apt-get install -y ssl-cert sysstat postgresql-9.6",
      "echo 'host    all             all            ${var.enable_ipv6 == true ? module.chef_server.public_ipv6_address : module.chef_server.private_ipv4_address}/${var.enable_ipv6 == "true" ? 64 : 32}         md5' | sudo tee -a /etc/postgresql/9.6/main/pg_hba.conf",
      "echo \"listen_addresses='*'\" | sudo tee -a /etc/postgresql/9.6/main/postgresql.conf",
      "sudo systemctl restart postgresql",
      "sudo -u postgres psql -c \"CREATE USER bofh SUPERUSER ENCRYPTED PASSWORD 'i1uvd3v0ps';\"",
    ]
  }
}

# update chef server
resource "null_resource" "chef_server_config" {
  depends_on = ["null_resource.postgresql_config"]

  # provide some connection info
  connection {
    type = "ssh"
    user = "${module.chef_server.ssh_username}"
    host = "${module.chef_server.public_ipv4_dns}"
  }

  provisioner "file" {
    content     = "${data.template_file.hosts_config.rendered}"
    destination = "/tmp/hosts"
  }

  provisioner "file" {
    content     = "${data.template_file.chef_server_rb.rendered}"
    destination = "/tmp/chef-server.rb"
  }

  provisioner "file" {
    source      = "${path.module}/../../../common/files/dhparam.pem"
    destination = "/tmp/dhparam.pem"
  }

  # install chef-server
  provisioner "remote-exec" {
    inline = [
      "set -evx",
      "echo -e '\nBEGIN INSTALL CHEF SERVER\n'",
      "sudo chown root:root /tmp/hosts",
      "sudo mv /tmp/hosts /etc/hosts",
      "curl -vo /tmp/${replace(var.upgrade_version_url, "/^.*\\//", "")} ${var.upgrade_version_url}",
      "sudo ${replace(var.upgrade_version_url, "rpm", "") != var.upgrade_version_url ? "rpm -U" : "dpkg -iEG"} /tmp/${replace(var.upgrade_version_url, "/^.*\\//", "")}",
      "sudo chown root:root /tmp/chef-server.rb",
      "sudo chown root:root /tmp/dhparam.pem",
      "sudo mv /tmp/chef-server.rb /etc/opscode",
      "sudo mv /tmp/dhparam.pem /etc/opscode",
      "sudo chef-server-ctl reconfigure --chef-license=accept",
      "sleep 120",
      "echo -e '\nEND INSTALL CHEF SERVER\n'",
    ]
  }

  # add user + organization
  provisioner "remote-exec" {
    script = "${path.module}/../../../common/files/add_user.sh"
  }
}

resource "null_resource" "chef_server_test" {
  depends_on = ["null_resource.chef_server_config"]

  connection {
    type = "ssh"
    user = "${module.chef_server.ssh_username}"
    host = "${module.chef_server.public_ipv4_dns}"
  }

  # run smoke test
  provisioner "remote-exec" {
    script = "${path.module}/../../../common/files/test_chef_server-smoke.sh"
  }

  # install push jobs addon
  provisioner "remote-exec" {
    script = "${path.module}/../../../common/files/install_addon_push_jobs.sh"
  }

  # test push jobs addon
  provisioner "remote-exec" {
    script = "${path.module}/../../../common/files/test_addon_push_jobs.sh"
  }

  # install chef manage addon
  provisioner "remote-exec" {
    script = "${path.module}/../../../common/files/install_addon_chef_manage.sh"
  }

  # run pedant test
  provisioner "remote-exec" {
    script = "${path.module}/../../../common/files/test_chef_server-pedant.sh"
  }

  # run psql test
  provisioner "remote-exec" {
    script = "${path.module}/../../../common/files/test_psql.sh"
  }

  # run gather-logs test
  provisioner "remote-exec" {
    script = "${path.module}/../../../common/files/test_gather_logs.sh"
  }
}
