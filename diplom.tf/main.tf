resource "local_file" "ansible-inventory" {
  content = templatefile("${path.module}/hosts.tftpl",
    {
      kube-nodes = yandex_compute_instance.kube-node
    }
  )
  filename = "../ansible-playbook/inventory/hosts.yml"
}

resource "local_file" "local-address" {
  content = templatefile("${path.module}/local-node-ip-vars.tftpl",
    {
      local-adresses = yandex_compute_instance.kube-node
    }
  )
  filename = "../ansible-playbook/group_vars/all/local_ip.yml"
}
