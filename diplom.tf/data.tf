data "yandex_compute_image" "vm-image" {
  family = var.image_family
}

data "template_file" "cloudinit" {
  template = file("./cloud-init.yml")
  vars = {
    ssh_public_key = file("./key.pub")
  }
}
