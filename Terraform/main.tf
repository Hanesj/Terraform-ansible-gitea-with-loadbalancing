variable "password" {}
variable "user_name" {}
variable "tenant_name" {}


variable "az_list" {
  description = "List of Availability Zones available in your OpenStack cluster"
  type = list
  default = ["sto1", "sto2", "sto3"]
}

terraform {
  required_providers {
        openstack = {
            source = "terraform-provider-openstack/openstack"
        }
    }
}
provider "openstack" {
  use_octavia = true
  user_name = var.user_name
  tenant_name = var.tenant_name
  password = var.password
  auth_url = "https://ops.elastx.cloud:5000/v3"
}
resource "openstack_networking_router_v2" "router" {
  name = "hs-router"
  admin_state_up = "true"
  external_network_id = "600b8501-78cb-4155-9c9f-23dfcba88828"
}
resource "openstack_compute_keypair_v2" "hs-keypair2" {
  name = "hs-keypair2"
  public_key = file("./id_rsa.pub")
}
resource "openstack_compute_secgroup_v2" "ssh_sg" {
  name = "hs-ssh-sg"
  description = "ssh security group"
  rule {
    from_port = 22
    to_port = 22
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
}
resource "openstack_networking_secgroup_v2" "lb_sg" {
  name = "LB SECGROUP"
  description = "Security group for lb"
}
resource "openstack_networking_secgroup_rule_v2" "lb_sg_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.lb_sg.id
  
}
resource "openstack_networking_secgroup_v2" "bastionen" {
  name        = "bastionen"
  description = "Security group for bastion"
}

resource "openstack_networking_secgroup_rule_v2" "bastions_trust" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastionen.id
}

resource "openstack_compute_secgroup_v2" "web_sg" {
  name = "hs-web-sg"
  description = "web security group"
  rule {
    from_port = 80
    to_port = 80
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
  rule {
    from_port = 3000
    to_port= 3000
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
  rule {
    from_port = 3306
    to_port= 3306
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
  rule {
    from_port = 443
    to_port = 443
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
}
#Kunna pinga till maskiner
resource "openstack_compute_secgroup_v2" "ping_sg" {
    name= "hs-ping-sg"
    description = "Ping security group"
    rule {
        from_port = -1
        to_port = -1
        ip_protocol = "icmp"
        cidr = "0.0.0.0/0"
  }
}
#Nätverk

resource "openstack_networking_network_v2" "web_net" {
  name = "hs-web-net"
  admin_state_up = "true"

}
#Skapa subnät
resource "openstack_networking_subnet_v2" "web_subnet" {
  name = "hs-web-subnet"
  network_id = openstack_networking_network_v2.web_net.id
  cidr = "10.10.10.0/24"
  ip_version = 4
  enable_dhcp = "true"
  dns_nameservers = ["8.8.8.8","8.8.4.4"]
}
resource "openstack_networking_router_interface_v2" "web-ext-interface" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.web_subnet.id
}

#Servergrupp

resource "openstack_compute_servergroup_v2" "web_srvgrp" {
  name = "hs-web-srvgrp"
  policies = ["soft-anti-affinity"]
}
# Gitea instans
resource "openstack_compute_instance_v2" "gitea" {
  name = "hs-web-gitea"
  availability_zone = "sto1"
  image_name = "ubuntu-22.04-server-latest"
  flavor_name = "v1-c1-m1-d20"
  network  { 
    uuid = openstack_networking_network_v2.web_net.id
  }
  key_pair = openstack_compute_keypair_v2.hs-keypair2.name
  scheduler_hints {
    group = openstack_compute_servergroup_v2.web_srvgrp.id
  }
  security_groups = ["${openstack_compute_secgroup_v2.ssh_sg.name}","${openstack_compute_secgroup_v2.web_sg.name}","${openstack_compute_secgroup_v2.ping_sg.name}","${openstack_networking_secgroup_v2.bastionen.name}"]
  depends_on = [openstack_networking_subnet_v2.web_subnet]
}
#Databas instans
resource "openstack_compute_instance_v2" "db" {
  name = "hs-web-db"
  availability_zone = "sto2"
  image_name = "ubuntu-22.04-server-latest"
  flavor_name = "v1-c1-m1-d20"
  network  { 
    uuid = openstack_networking_network_v2.web_net.id
  }
  key_pair = openstack_compute_keypair_v2.hs-keypair2.name
  scheduler_hints {
    group = openstack_compute_servergroup_v2.web_srvgrp.id
  }
  security_groups = ["${openstack_compute_secgroup_v2.ssh_sg.name}","${openstack_compute_secgroup_v2.web_sg.name}","${openstack_compute_secgroup_v2.ping_sg.name}","${openstack_networking_secgroup_v2.bastionen.name}"]
  depends_on = [openstack_networking_subnet_v2.web_subnet]
}

#Bastion

resource "openstack_compute_instance_v2" "bastion" {
  name = "hs-bastion"
  availability_zone = "sto1"
  image_name = "ubuntu-22.04-server-latest"
  flavor_name = "v1-c1-m1-d20"
  network  { 
    uuid = openstack_networking_network_v2.web_net.id
  }
  key_pair = openstack_compute_keypair_v2.hs-keypair2.name
  scheduler_hints {
    group = openstack_compute_servergroup_v2.web_srvgrp.id
  }
  security_groups = ["${openstack_compute_secgroup_v2.ssh_sg.name}","${openstack_compute_secgroup_v2.web_sg.name}","${openstack_compute_secgroup_v2.ping_sg.name}","${openstack_networking_secgroup_v2.bastionen.name}"]
  depends_on = [openstack_networking_subnet_v2.web_subnet]
}
#Få flytande IP för bastionen
resource "openstack_networking_floatingip_v2" "bastion" {
  pool = "elx-public1"
}
#Associera den flytande IP:n till bastionen
resource "openstack_compute_floatingip_associate_v2" "bastion_fip" {
  floating_ip = openstack_networking_floatingip_v2.bastion.address
  instance_id = openstack_compute_instance_v2.bastion.id
}

#Load balancer

resource "openstack_lb_loadbalancer_v2" "lb_1" {
  name = "Load balancer"
  vip_subnet_id = openstack_networking_subnet_v2.web_subnet.id
  security_group_ids = [openstack_networking_secgroup_v2.lb_sg.id]
  depends_on = [openstack_compute_instance_v2.gitea]
  
}
resource "openstack_lb_listener_v2" "listener1" {
    protocol = "HTTP"
    protocol_port = 80
    loadbalancer_id = openstack_lb_loadbalancer_v2.lb_1.id
    insert_headers = {
      X-Forwarded-For = "true"
  }
  depends_on = [
    openstack_lb_loadbalancer_v2.lb_1
  ]
}
resource "openstack_lb_pool_v2" "pool1" {
  
    protocol = "HTTP"
    #ROUND_ROBIN om man har mer än 1 server
    lb_method = "ROUND_ROBIN"
    listener_id = openstack_lb_listener_v2.listener1.id
    depends_on = [
      openstack_lb_listener_v2.listener1
    ]    
}

resource "openstack_lb_member_v2" "member" {
  address = openstack_compute_instance_v2.gitea.access_ip_v4
  protocol_port = 3000
  pool_id = openstack_lb_pool_v2.pool1.id
  subnet_id = openstack_networking_subnet_v2.web_subnet.id
   
}

resource "openstack_networking_floatingip_v2" "lbfip" {
    pool = "elx-public1"
}
resource "openstack_networking_floatingip_associate_v2" "lbafip" {
    floating_ip = openstack_networking_floatingip_v2.lbfip.address
    port_id = openstack_lb_loadbalancer_v2.lb_1.vip_port_id
}
#Lite outputs av IP:addresser när det det är färdigkört
output "lb" {
  value = openstack_networking_floatingip_v2.lbfip.address
}
output "bastion" {
  value = openstack_networking_floatingip_v2.bastion.address
}
output "gitealocalip" {
  value = openstack_compute_instance_v2.gitea.access_ip_v4
}
output "dblocalip" {
  value = openstack_compute_instance_v2.db.access_ip_v4
}
#Skapa config fil för ssh
resource "local_file" "config" {
  content = <<EOT
  Host *
  ForwardAgent yes

  Host bastion
  Hostname ${openstack_networking_floatingip_v2.bastion.address}
  User ubuntu
  Port 22 
  Identityfile ~/.ssh/id_rsa

  Host gitea
  Hostname ${openstack_compute_instance_v2.gitea.access_ip_v4}
  User ubuntu
  ProxyJump bastion

  Host db
  Hostname ${openstack_compute_instance_v2.db.access_ip_v4}
  User ubuntu
  ProxyJump bastion
  EOT
  filename = "./config"
}
#Lastbalanserare IP
resource "local_file" "lbip" {
  content = "LB: ${openstack_networking_floatingip_v2.lbfip.address}"
  filename = "./lbip.txt"
  
}
#INI fil för giteas förinstallation
resource "local_file" "ini" {
  content = <<EOT
APP_NAME = Gitea: Git with a cup of tea
RUN_USER = git
RUN_MODE = prod

[database]
DB_TYPE  = mysql
HOST     = ${openstack_compute_instance_v2.db.access_ip_v4}
NAME     = giteadb
USER     = gitea
PASSWD   = gitea
SCHEMA   =
SSL_MODE = disable
CHARSET  = utf8
PATH     = /var/lib/gitea/data/gitea.db
LOG_SQL  = false

[repository]
ROOT = /var/lib/gitea/data/gitea-repositories

[server]
SSH_DOMAIN       = ${openstack_compute_instance_v2.gitea.access_ip_v4}
DOMAIN           = ${openstack_compute_instance_v2.gitea.access_ip_v4}
HTTP_PORT        = 3000
ROOT_URL         = http://localhost:3000/
DISABLE_SSH      = false
SSH_PORT         = 22
LFS_START_SERVER = true
LFS_CONTENT_PATH = /var/lib/gitea/data/lfs
LFS_JWT_SECRET   = mXrrF9Ltapld1rKU7X3SZJ-L_5v94AT-0frlEGrgyfQ
OFFLINE_MODE     = false

[mailer]
ENABLED = false

[service]
REGISTER_EMAIL_CONFIRM            = false
ENABLE_NOTIFY_MAIL                = false
DISABLE_REGISTRATION              = false
ALLOW_ONLY_EXTERNAL_REGISTRATION  = false
ENABLE_CAPTCHA                    = false
REQUIRE_SIGNIN_VIEW               = false
DEFAULT_KEEP_EMAIL_PRIVATE        = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = true
DEFAULT_ENABLE_TIMETRACKING       = true
NO_REPLY_ADDRESS                  = noreply.localhost

[picture]
DISABLE_GRAVATAR        = false
ENABLE_FEDERATED_AVATAR = true

[openid]
ENABLE_OPENID_SIGNIN = true
ENABLE_OPENID_SIGNUP = true

[session]
PROVIDER = file

[log]
MODE      = console
LEVEL     = info
ROOT_PATH = /var/lib/gitea/log
ROUTER    = console

[security]
INSTALL_LOCK       = true
INTERNAL_TOKEN     = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuYmYiOjE2Nzc1ODg2NTV9.FUAMYSc9j6DrVkQvrsbw_Ohigi9xpau4C0hmfsdaYOY
PASSWORD_HASH_ALGO = pbkdf2

EOT
filename = "./app.ini"
  
}

