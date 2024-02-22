hostname = [
  {
    hostname = "k8s-node-01"
  },
  {
    hostname = "k8s-node-02"
  },
  {
    hostname = "k8s-node-03"
  },
]
platform       = "standard-v1"
stop_to_update = true
vcpu_cores     = 4
vcpu_fraction  = 20
ram_size       = 8
hdd_type       = "network-ssd"
hdd_size       = 20
preemptible    = true
serial_port    = 1
network_nat    = true
image_family   = "centos-7"
