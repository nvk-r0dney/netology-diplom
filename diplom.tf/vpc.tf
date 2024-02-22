resource "yandex_vpc_network" "cloud-network" {
  name      = var.vpc_name
  folder_id = var.folder_id
}

resource "yandex_vpc_subnet" "vpc-subnet" {
  name           = var.subnet_name
  zone           = var.subnet_zone
  network_id     = yandex_vpc_network.cloud-network.id
  v4_cidr_blocks = var.cidr_block
}
