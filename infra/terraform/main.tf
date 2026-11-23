terraform {
  required_version = ">= 1.12.0, < 2.0.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.29"
    }
  }
  backend "oci" {}
}

variable "tenancy_ocid" { type = string }
variable "compartment_ocid" { type = string }
variable "user_ocid" { type = string }
variable "fingerprint" { type = string }
variable "private_key_path" { type = string }
variable "region" { type = string }
variable "ssh_public_key" {
  type      = string
  sensitive = true
}
variable "ssh_source_cidr" { type = string }
variable "admin_ssh_cidr" {
  type    = string
  default = ""
  validation {
    condition     = var.admin_ssh_cidr == "" || (can(cidrhost(var.admin_ssh_cidr, 0)) && endswith(var.admin_ssh_cidr, "/32"))
    error_message = "La IP opcional de acceso SSH debe ser una dirección individual con /32."
  }
}
variable "availability_domain" {
  type    = string
  default = ""
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

data "oci_identity_availability_domains" "current" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.E5.Flex"
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals { tags = { project = "TrifoBet", managed_by = "Terraform" } }

resource "oci_core_vcn" "app" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.86.0.0/16"]
  display_name   = "trifobet-vcn"
  dns_label      = "trifobet"
  freeform_tags  = local.tags
}

resource "oci_core_internet_gateway" "app" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.app.id
  display_name   = "trifobet-internet"
  enabled        = true
  freeform_tags  = local.tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.app.id
  display_name   = "trifobet-public-route"
  freeform_tags  = local.tags
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.app.id
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.app.id
  display_name   = "trifobet-web-ingress"
  freeform_tags  = local.tags
  ingress_security_rules {
    protocol = "6"
    source   = var.ssh_source_cidr
    tcp_options {
      min = 22
      max = 22
    }
  }
  dynamic "ingress_security_rules" {
    for_each = var.admin_ssh_cidr == "" ? [] : [var.admin_ssh_cidr]
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        min = 22
        max = 22
      }
    }
  }
  dynamic "ingress_security_rules" {
    for_each = [80, 443]
    content {
      protocol = "6"
      source   = "0.0.0.0/0"
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.app.id
  cidr_block                 = "10.86.1.0/24"
  display_name               = "trifobet-public-subnet"
  dns_label                  = "publica"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = local.tags
}

resource "oci_core_instance" "app" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain != "" ? var.availability_domain : data.oci_identity_availability_domains.current.availability_domains[0].name
  display_name        = "trifobet-ubuntu-2404"
  shape               = "VM.Standard.E5.Flex"
  freeform_tags       = local.tags
  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }
  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = 50
  }
  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = "trifobet"
  }
  metadata = { ssh_authorized_keys = trimspace(var.ssh_public_key) }
  lifecycle {
    ignore_changes = [source_details[0].source_id]
    precondition {
      condition     = length(data.oci_core_images.ubuntu.images) > 0
      error_message = "OCI no encontró Ubuntu 24.04 compatible con E5.Flex."
    }
  }
}

output "public_ip" { value = oci_core_instance.app.public_ip }
output "instance_id" { value = oci_core_instance.app.id }
