####################################
### -------- Cloud Vars -------- ###
####################################

variable "token" {
  type        = string
  description = "OAuth-token"
}

variable "cloud_id" {
  type        = string
  description = "Yandex.Cloud ID"
}

variable "folder_id" {
  type        = string
  description = "Yandex.Cloud MyDefault folder ID"
}

variable "default_zone" {
  type        = string
  description = "Yandex.Cloud default zone"
}

####################################
### --------- VPC Vars --------- ###
####################################

variable "vpc_name" {
  type        = string
  description = "Yandex.Cloud Diplom VPC"
}

variable "subnet_zone" {
  type        = string
  description = "Yandex.Cloud VPC subnet in A zone"
}

variable "subnet_name" {
  type        = string
  description = "Yandex.Cloud VPC subnet name in A zone"
}

variable "cidr_block" {
  type        = tuple([string])
  description = "Yandex.Cloud VPC subnet cidr block in A zone"
}


####################################
### ------ Instance Vars ------- ###
####################################

variable "hostname" {
  type = list(object({
    hostname = string
  }))
  description = "Hostname for Kubernetes Node"
}

variable "platform" {
  type        = string
  description = "Platform type in Yandex.Cloud"
}

variable "stop_to_update" {
  type        = bool
  description = "Allow stop instance for updates"
  default     = true
}

variable "vcpu_cores" {
  type        = number
  description = "vCPU resources for Kubernetes instance"
}

variable "vcpu_fraction" {
  type        = number
  description = "Instance vCPU fraction in Yandex.Cloud"
}

variable "ram_size" {
  type        = number
  description = "Instance RAM size in GB"
}

variable "hdd_type" {
  type        = string
  description = "Disk type for Kubernetes instance"
}

variable "hdd_size" {
  type        = number
  description = "Instance disk size in GB"
}

variable "preemptible" {
  type        = bool
  description = "Set instance preemptible or not"
  default     = true
}

variable "serial_port" {
  type        = number
  description = "Enable Serial port on Kubernetes instance"
  default     = 1
}

variable "network_nat" {
  type        = bool
  description = "Enable NAT on Kubernetes instance"
  default     = true
}

variable "image_family" {
  type        = string
  description = "OS family for instance"
}
