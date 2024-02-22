resource "yandex_compute_instance" "kube-node" {
  for_each = { for key, value in var.hostname : key => value }

  name        = each.value.hostname
  hostname    = each.value.hostname
  platform_id = var.platform
  zone        = var.default_zone

  resources {
    cores         = var.vcpu_cores
    core_fraction = var.vcpu_fraction
    memory        = var.ram_size
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.vm-image.id
      type     = var.hdd_type
      size     = var.hdd_size
    }
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.vpc-subnet.id
    nat       = var.network_nat
  }

  metadata = {
    serial-port-enable = var.serial_port
    user-data          = data.template_file.cloudinit.rendered
  }

  allow_stopping_for_update = var.stop_to_update
}

