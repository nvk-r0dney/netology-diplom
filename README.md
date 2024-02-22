# Дипломная работа по курсу DevOPS-инженер

<br />

## Выполнил студент группы DevOPS-25 - Кирилл Шаповалов

<br />

### Структура репозитория


1. Каталог <a href="./diplom.tf/">diplom.tf</a> содержит все манифесты Terraform по созданию инфраструктуры в Yandex.Cloud, внутри находится Readme с версиями используемых провайдеров, версией самого Terraform, а также с описанием всех переменных.
2. В каталоге <a href="./ansible-playbook/">ansible-playbook</a> находится Playbook, выполняющий всю подготовительную работу на `Kubernetes Nodes` для установки и инициализации самого кластера. `Inventory-file`, а также `Groupvars-file`, являются динамическими и создаются при создании инфраструктуры с помощью Terraform. Внутри находится Readme с описанием.
3. Каталог <a href="./kubernetes/">kubernetes</a> содержит все манифесты Kubernetes для деплоя разных приложений в кластер.
4. В каталоге <a href="./diplom-app/">diplom-app</a> находится тестовое приложение, написанное на фреймворке Django, которое будет собираться в Docker-Image для последующего деплоя в кластер Kubernetes.

<br />

### Введение

В современных условиях IT-мира в России по-прежнему преобладает использование `Self-Hosted Kubernetes Cluster`, так как такое решение удовлетворяет требованиям различных служб безопасности внутри компаний, поскольку обеспечивает наилучшую сохранность персональных данных и коммерческой тайны. Потому для написания данного дипломного проекта я заранее выбрал, что буду использовать самостоятельную установку Kubernetes-кластера, не используя Managed Service for Kubernetes от облачного провайдера.

Вся инфраструктура создается с помощью Terraform, state-файл хранится в S3 бакете с возможностью блокировки с помощью Yandex DynamoDB. Хранение state файла также можно организовать внутри корпоративного Gitlab и подключать по HTTP. Более детально я рассмотрю создание инфраструктуры в соответствующем разделе.

Далее всю подготовку виртуальных машин осуществляет Ansible Playbook, написанный мной ранее для выполнения домашних заданий, который я немного модернизировал для дипломного проекта (например, подключил динамически создаваемый Inventory, добавил редактирование файла `/etc/hosts` на каждой ноде кластера).

Инициализацию кластера я выполняю самостоятельно и в ручном режиме с обязательным указанием параметра `--v=5`, поскольку для меня важно видеть что происходит в процессе инициализации кластера с выводом в консоль этапов инициализации. Для полной автоматизации можно использовать такое решение, как kubespray, но я предпочитаю осуществлять инициализацию вручную.

В качестве собственного приложения буду использовать небольшую галерею изображений, созданную с помощью фреймворка Django в процессе его изучения, соберу Docker Image, который будет храниться в локальном Gitlab Container Registry, и будет использоваться при деплое в Kubernetes кластер.

Автоматизация сборки, деплоя приложения, настройки кластера и создания инфраструктуры будет осуществлена с помощью локальной Gitlab CI/CD.

<br />

### Предварительная подготовка

При подготовке проекта были использованы локально установленные пакеты: 

<img src="./images/00-local-packages.png" width="800px" height="auto" />

<br />

### Подготовка инфраструктуры на базе облачного провайдера Yandex.Cloud

Для хранения state-файла создано S3 хранилище в Yandex.Cloud:

<img src="./images/01-yandex-s3-bucket.png" width="800px" height="auto" />

Для блокировки state-файла используется Yandex DynamoDB:

<img src="./images/02-yandex-dynamodb.png" width="800px" height="auto" />

Проверка, что в БД реально пишется блокировка файла состояний:

<img src="./images/03-lock-hash-in-ydb.png" width="800px" height="auto" />

<br />

Теперь рассмотрим структуру проекта по созданию инфраструктуры.

Манифест `provider.tf` описывает параметры провайдера, также здесь описано какой backend использовать для хранения tfstate файла и каким образом осуществлять его блокировку.

<details><summary>provider.tf</summary>

```terraform
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">=0.107.0"

  backend "s3" {
    endpoints = {
      s3       = "https://storage.yandexcloud.net"
      dynamodb = "https://docapi.serverless.yandexcloud.net/ru-central1/b1gqm95h91idg2ffi5la/etne4c7rs7nm1h1uh5f6"
    }
    bucket                      = "net-s3-tfstate"
    region                      = "ru-central1"
    key                         = "terraform.tfstate"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true

    dynamodb_table = "lock-table"
  }
}

provider "yandex" {
  token     = var.token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.default_zone
}
```

</details>

<br />

Для дипломного проекта я создал отдельную vpc с отдельной подсетью, для этого используется манифест `vpc.tf`

<details><summary>vpc.tf</summary>

```terraform
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

```

</details>

Все параметры для создания сети и подсети задаются в файле `vpc.auto.tfvars`.

Манифест `instances.tf` динамически создает заданное количество нод будущего кластера. С помощью конструкции `for_each` можно создать как одну машину, так и 10, и больше.

<details><summary>instances.tf</summary>

```terraform
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
```

</details>

Параметры для создания инстансов задаются в файле `instances.auto.tfvars`. 

Базовая конфигурация машин осуществляется с помощью `cloud-config` файла, в котором задается имя пользователя по умолчанию, хеш его пароля, добавляется публичная часть ssh-ключа, а также задаются пакеты, которые должны быть установлены на этапе конфигурирования машин. Синтаксис файла ниже.

<details><summary>cloud-init.yml</summary>

```yml
#cloud-config

users:
  - name: admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: sudo
    lock_passwd: false
    # password - netology-diplom
    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
    ssh_authorized_keys:
      - ${ssh_public_key}
package_update: true
package_upgrade: false
packages:
  - vim
  - yum-utils
  - curl
  - git
  - wget
```

</details>

<br />

Манифест `data.tf` содержит набор датасурсов, используемых в проекте. Тут указано какой образ использовать для создания виртуальных машин, а также какой ssh-ключ брать и откуда. Прятать публичную часть ключа за переменные или Vault не вижу особого смысла, публичная часть она на то и публичная, чтобы предоставить ее куда-либо, без компрометации приватной части ключа.

<details><summary>data.tf</summary>

```terraform
data "yandex_compute_image" "vm-image" {
  family = var.image_family
}

data "template_file" "cloudinit" {
  template = file("./cloud-init.yml")
  vars = {
    ssh_public_key = file("./key.pub")
  }
}

```

</details>

<br />

Ну а манифест `main.tf` позволяет динамически создавать файл inventory для Ansible, а так же файл group_vars, содержащий локальные адреса нод будущего кластера.

<details><summary>main.tf</summary>

```terraform
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
```

</details>

Используя модуль `local_file` и разные файлы-шаблоны Terraform получает определенные данные созданных виртуальных машин и записывает их в итоговый файл на выходе.

Шаблоны файлов ниже:

* шаблон inventory файла

```
---
all:
  hosts:
    %{~ for i in kube-nodes ~}
    ${i["name"]}:
      ansible_host: ${i["network_interface"][0]["nat_ip_address"]}
    %{~ endfor ~}  
  vars:
    ansible_user: admin
```

* шаблон group_vars файла

```
---
local_ip:
  %{~ for i in local-adresses ~}
  - ${i["network_interface"][0]["ip_address"]}  ${i["name"]}
  %{~ endfor ~}
```

Значения переменных для доступа к самому облаку объявлены в файле `personal.auto.tfvars`, который в репозиторий не попадает благодаря тому, что имя этого файла содержится в файле `.gitignore`. На этапе автоматизации с помощью CI/CD эти переменные нужно будет выносить в переменные проекта либо использовать стороннее хранилище секретов, например Hashicorp Vault.

Необходимо убедиться, что команды Terraform будут выполняться без каких-либо дополнительных действий.

<details><summary>Результат выполнения команды <b>terraform plan</b></summary>

```bash
rodney@arch-home: /home/rodney/learning/kirill-shapovalov-netologydiplom/diplom.tf git:(main) ✗ 
➜   terraform plan 
Acquiring state lock. This may take a few moments...
data.template_file.cloudinit: Reading...
data.template_file.cloudinit: Read complete after 0s [id=7dada99b1a5900b0a2447da452bf65e7ab31407994f179670fbb86b1b29b58eb]
data.yandex_compute_image.vm-image: Reading...
data.yandex_compute_image.vm-image: Read complete after 1s [id=fd8aptfr48hdvlflumbe]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.ansible-inventory will be created
  + resource "local_file" "ansible-inventory" {
      + content              = (known after apply)
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "../ansible-playbook/inventory/hosts.yml"
      + id                   = (known after apply)
    }

  # local_file.local-address will be created
  + resource "local_file" "local-address" {
      + content              = (known after apply)
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "../ansible-playbook/group_vars/all/local_ip.yml"
      + id                   = (known after apply)
    }

  # yandex_compute_instance.kube-node["0"] will be created
  + resource "yandex_compute_instance" "kube-node" {
      + allow_stopping_for_update = true
      + created_at                = (known after apply)
      + folder_id                 = (known after apply)
      + fqdn                      = (known after apply)
      + gpu_cluster_id            = (known after apply)
      + hostname                  = "k8s-node-01"
      + id                        = (known after apply)
      + maintenance_grace_period  = (known after apply)
      + maintenance_policy        = (known after apply)
      + metadata                  = {
          + "serial-port-enable" = "1"
          + "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        }
      + name                      = "k8s-node-01"
      + network_acceleration_type = "standard"
      + platform_id               = "standard-v1"
      + service_account_id        = (known after apply)
      + status                    = (known after apply)
      + zone                      = "ru-central1-a"

      + boot_disk {
          + auto_delete = true
          + device_name = (known after apply)
          + disk_id     = (known after apply)
          + mode        = (known after apply)

          + initialize_params {
              + block_size  = (known after apply)
              + description = (known after apply)
              + image_id    = "fd8aptfr48hdvlflumbe"
              + name        = (known after apply)
              + size        = 20
              + snapshot_id = (known after apply)
              + type        = "network-ssd"
            }
        }

      + network_interface {
          + index              = (known after apply)
          + ip_address         = (known after apply)
          + ipv4               = true
          + ipv6               = (known after apply)
          + ipv6_address       = (known after apply)
          + mac_address        = (known after apply)
          + nat                = true
          + nat_ip_address     = (known after apply)
          + nat_ip_version     = (known after apply)
          + security_group_ids = (known after apply)
          + subnet_id          = (known after apply)
        }

      + resources {
          + core_fraction = 20
          + cores         = 4
          + memory        = 8
        }

      + scheduling_policy {
          + preemptible = true
        }
    }

  # yandex_compute_instance.kube-node["1"] will be created
  + resource "yandex_compute_instance" "kube-node" {
      + allow_stopping_for_update = true
      + created_at                = (known after apply)
      + folder_id                 = (known after apply)
      + fqdn                      = (known after apply)
      + gpu_cluster_id            = (known after apply)
      + hostname                  = "k8s-node-02"
      + id                        = (known after apply)
      + maintenance_grace_period  = (known after apply)
      + maintenance_policy        = (known after apply)
      + metadata                  = {
          + "serial-port-enable" = "1"
          + "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        }
      + name                      = "k8s-node-02"
      + network_acceleration_type = "standard"
      + platform_id               = "standard-v1"
      + service_account_id        = (known after apply)
      + status                    = (known after apply)
      + zone                      = "ru-central1-a"

      + boot_disk {
          + auto_delete = true
          + device_name = (known after apply)
          + disk_id     = (known after apply)
          + mode        = (known after apply)

          + initialize_params {
              + block_size  = (known after apply)
              + description = (known after apply)
              + image_id    = "fd8aptfr48hdvlflumbe"
              + name        = (known after apply)
              + size        = 20
              + snapshot_id = (known after apply)
              + type        = "network-ssd"
            }
        }

      + network_interface {
          + index              = (known after apply)
          + ip_address         = (known after apply)
          + ipv4               = true
          + ipv6               = (known after apply)
          + ipv6_address       = (known after apply)
          + mac_address        = (known after apply)
          + nat                = true
          + nat_ip_address     = (known after apply)
          + nat_ip_version     = (known after apply)
          + security_group_ids = (known after apply)
          + subnet_id          = (known after apply)
        }

      + resources {
          + core_fraction = 20
          + cores         = 4
          + memory        = 8
        }

      + scheduling_policy {
          + preemptible = true
        }
    }

  # yandex_compute_instance.kube-node["2"] will be created
  + resource "yandex_compute_instance" "kube-node" {
      + allow_stopping_for_update = true
      + created_at                = (known after apply)
      + folder_id                 = (known after apply)
      + fqdn                      = (known after apply)
      + gpu_cluster_id            = (known after apply)
      + hostname                  = "k8s-node-03"
      + id                        = (known after apply)
      + maintenance_grace_period  = (known after apply)
      + maintenance_policy        = (known after apply)
      + metadata                  = {
          + "serial-port-enable" = "1"
          + "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        }
      + name                      = "k8s-node-03"
      + network_acceleration_type = "standard"
      + platform_id               = "standard-v1"
      + service_account_id        = (known after apply)
      + status                    = (known after apply)
      + zone                      = "ru-central1-a"

      + boot_disk {
          + auto_delete = true
          + device_name = (known after apply)
          + disk_id     = (known after apply)
          + mode        = (known after apply)

          + initialize_params {
              + block_size  = (known after apply)
              + description = (known after apply)
              + image_id    = "fd8aptfr48hdvlflumbe"
              + name        = (known after apply)
              + size        = 20
              + snapshot_id = (known after apply)
              + type        = "network-ssd"
            }
        }

      + network_interface {
          + index              = (known after apply)
          + ip_address         = (known after apply)
          + ipv4               = true
          + ipv6               = (known after apply)
          + ipv6_address       = (known after apply)
          + mac_address        = (known after apply)
          + nat                = true
          + nat_ip_address     = (known after apply)
          + nat_ip_version     = (known after apply)
          + security_group_ids = (known after apply)
          + subnet_id          = (known after apply)
        }

      + resources {
          + core_fraction = 20
          + cores         = 4
          + memory        = 8
        }

      + scheduling_policy {
          + preemptible = true
        }
    }

  # yandex_vpc_network.cloud-network will be created
  + resource "yandex_vpc_network" "cloud-network" {
      + created_at                = (known after apply)
      + default_security_group_id = (known after apply)
      + folder_id                 = "b1gab8fuc9s78vrid6au"
      + id                        = (known after apply)
      + labels                    = (known after apply)
      + name                      = "diplom-network"
      + subnet_ids                = (known after apply)
    }

  # yandex_vpc_subnet.vpc-subnet will be created
  + resource "yandex_vpc_subnet" "vpc-subnet" {
      + created_at     = (known after apply)
      + folder_id      = (known after apply)
      + id             = (known after apply)
      + labels         = (known after apply)
      + name           = "public"
      + network_id     = (known after apply)
      + v4_cidr_blocks = [
          + "192.168.10.0/24",
        ]
      + v6_cidr_blocks = (known after apply)
      + zone           = "ru-central1-a"
    }

Plan: 7 to add, 0 to change, 0 to destroy.

─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't guarantee to take exactly these actions if you run "terraform apply" now.
```

</details>

<br />

<details><summary>Результат выполнения команды <b>terraform apply</b></summary>

```bash
rodney@arch-home: /home/rodney/learning/kirill-shapovalov-netologydiplom/diplom.tf git:(main) ✗ 
➜   terraform apply       
data.template_file.cloudinit: Reading...
data.template_file.cloudinit: Read complete after 0s [id=7dada99b1a5900b0a2447da452bf65e7ab31407994f179670fbb86b1b29b58eb]
data.yandex_compute_image.vm-image: Reading...
data.yandex_compute_image.vm-image: Read complete after 1s [id=fd8aptfr48hdvlflumbe]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # local_file.ansible-inventory will be created
  + resource "local_file" "ansible-inventory" {
      + content              = (known after apply)
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "../ansible-playbook/inventory/hosts.yml"
      + id                   = (known after apply)
    }

  # local_file.local-address will be created
  + resource "local_file" "local-address" {
      + content              = (known after apply)
      + content_base64sha256 = (known after apply)
      + content_base64sha512 = (known after apply)
      + content_md5          = (known after apply)
      + content_sha1         = (known after apply)
      + content_sha256       = (known after apply)
      + content_sha512       = (known after apply)
      + directory_permission = "0777"
      + file_permission      = "0777"
      + filename             = "../ansible-playbook/group_vars/all/local_ip.yml"
      + id                   = (known after apply)
    }

  # yandex_compute_instance.kube-node["0"] will be created
  + resource "yandex_compute_instance" "kube-node" {
      + allow_stopping_for_update = true
      + created_at                = (known after apply)
      + folder_id                 = (known after apply)
      + fqdn                      = (known after apply)
      + gpu_cluster_id            = (known after apply)
      + hostname                  = "k8s-node-01"
      + id                        = (known after apply)
      + maintenance_grace_period  = (known after apply)
      + maintenance_policy        = (known after apply)
      + metadata                  = {
          + "serial-port-enable" = "1"
          + "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        }
      + name                      = "k8s-node-01"
      + network_acceleration_type = "standard"
      + platform_id               = "standard-v1"
      + service_account_id        = (known after apply)
      + status                    = (known after apply)
      + zone                      = "ru-central1-a"

      + boot_disk {
          + auto_delete = true
          + device_name = (known after apply)
          + disk_id     = (known after apply)
          + mode        = (known after apply)

          + initialize_params {
              + block_size  = (known after apply)
              + description = (known after apply)
              + image_id    = "fd8aptfr48hdvlflumbe"
              + name        = (known after apply)
              + size        = 20
              + snapshot_id = (known after apply)
              + type        = "network-ssd"
            }
        }

      + network_interface {
          + index              = (known after apply)
          + ip_address         = (known after apply)
          + ipv4               = true
          + ipv6               = (known after apply)
          + ipv6_address       = (known after apply)
          + mac_address        = (known after apply)
          + nat                = true
          + nat_ip_address     = (known after apply)
          + nat_ip_version     = (known after apply)
          + security_group_ids = (known after apply)
          + subnet_id          = (known after apply)
        }

      + resources {
          + core_fraction = 20
          + cores         = 4
          + memory        = 8
        }

      + scheduling_policy {
          + preemptible = true
        }
    }

  # yandex_compute_instance.kube-node["1"] will be created
  + resource "yandex_compute_instance" "kube-node" {
      + allow_stopping_for_update = true
      + created_at                = (known after apply)
      + folder_id                 = (known after apply)
      + fqdn                      = (known after apply)
      + gpu_cluster_id            = (known after apply)
      + hostname                  = "k8s-node-02"
      + id                        = (known after apply)
      + maintenance_grace_period  = (known after apply)
      + maintenance_policy        = (known after apply)
      + metadata                  = {
          + "serial-port-enable" = "1"
          + "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        }
      + name                      = "k8s-node-02"
      + network_acceleration_type = "standard"
      + platform_id               = "standard-v1"
      + service_account_id        = (known after apply)
      + status                    = (known after apply)
      + zone                      = "ru-central1-a"

      + boot_disk {
          + auto_delete = true
          + device_name = (known after apply)
          + disk_id     = (known after apply)
          + mode        = (known after apply)

          + initialize_params {
              + block_size  = (known after apply)
              + description = (known after apply)
              + image_id    = "fd8aptfr48hdvlflumbe"
              + name        = (known after apply)
              + size        = 20
              + snapshot_id = (known after apply)
              + type        = "network-ssd"
            }
        }

      + network_interface {
          + index              = (known after apply)
          + ip_address         = (known after apply)
          + ipv4               = true
          + ipv6               = (known after apply)
          + ipv6_address       = (known after apply)
          + mac_address        = (known after apply)
          + nat                = true
          + nat_ip_address     = (known after apply)
          + nat_ip_version     = (known after apply)
          + security_group_ids = (known after apply)
          + subnet_id          = (known after apply)
        }

      + resources {
          + core_fraction = 20
          + cores         = 4
          + memory        = 8
        }

      + scheduling_policy {
          + preemptible = true
        }
    }

  # yandex_compute_instance.kube-node["2"] will be created
  + resource "yandex_compute_instance" "kube-node" {
      + allow_stopping_for_update = true
      + created_at                = (known after apply)
      + folder_id                 = (known after apply)
      + fqdn                      = (known after apply)
      + gpu_cluster_id            = (known after apply)
      + hostname                  = "k8s-node-03"
      + id                        = (known after apply)
      + maintenance_grace_period  = (known after apply)
      + maintenance_policy        = (known after apply)
      + metadata                  = {
          + "serial-port-enable" = "1"
          + "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        }
      + name                      = "k8s-node-03"
      + network_acceleration_type = "standard"
      + platform_id               = "standard-v1"
      + service_account_id        = (known after apply)
      + status                    = (known after apply)
      + zone                      = "ru-central1-a"

      + boot_disk {
          + auto_delete = true
          + device_name = (known after apply)
          + disk_id     = (known after apply)
          + mode        = (known after apply)

          + initialize_params {
              + block_size  = (known after apply)
              + description = (known after apply)
              + image_id    = "fd8aptfr48hdvlflumbe"
              + name        = (known after apply)
              + size        = 20
              + snapshot_id = (known after apply)
              + type        = "network-ssd"
            }
        }

      + network_interface {
          + index              = (known after apply)
          + ip_address         = (known after apply)
          + ipv4               = true
          + ipv6               = (known after apply)
          + ipv6_address       = (known after apply)
          + mac_address        = (known after apply)
          + nat                = true
          + nat_ip_address     = (known after apply)
          + nat_ip_version     = (known after apply)
          + security_group_ids = (known after apply)
          + subnet_id          = (known after apply)
        }

      + resources {
          + core_fraction = 20
          + cores         = 4
          + memory        = 8
        }

      + scheduling_policy {
          + preemptible = true
        }
    }

  # yandex_vpc_network.cloud-network will be created
  + resource "yandex_vpc_network" "cloud-network" {
      + created_at                = (known after apply)
      + default_security_group_id = (known after apply)
      + folder_id                 = "b1gab8fuc9s78vrid6au"
      + id                        = (known after apply)
      + labels                    = (known after apply)
      + name                      = "diplom-network"
      + subnet_ids                = (known after apply)
    }

  # yandex_vpc_subnet.vpc-subnet will be created
  + resource "yandex_vpc_subnet" "vpc-subnet" {
      + created_at     = (known after apply)
      + folder_id      = (known after apply)
      + id             = (known after apply)
      + labels         = (known after apply)
      + name           = "public"
      + network_id     = (known after apply)
      + v4_cidr_blocks = [
          + "192.168.10.0/24",
        ]
      + v6_cidr_blocks = (known after apply)
      + zone           = "ru-central1-a"
    }

Plan: 7 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

yandex_vpc_network.cloud-network: Creating...
yandex_vpc_network.cloud-network: Creation complete after 4s [id=enpcbmbsdf2fte3nksus]
yandex_vpc_subnet.vpc-subnet: Creating...
yandex_vpc_subnet.vpc-subnet: Creation complete after 0s [id=e9biu29uda5nk2ds9267]
yandex_compute_instance.kube-node["2"]: Creating...
yandex_compute_instance.kube-node["1"]: Creating...
yandex_compute_instance.kube-node["0"]: Creating...
yandex_compute_instance.kube-node["2"]: Still creating... [10s elapsed]
yandex_compute_instance.kube-node["1"]: Still creating... [10s elapsed]
yandex_compute_instance.kube-node["0"]: Still creating... [10s elapsed]
yandex_compute_instance.kube-node["1"]: Still creating... [20s elapsed]
yandex_compute_instance.kube-node["2"]: Still creating... [20s elapsed]
yandex_compute_instance.kube-node["0"]: Still creating... [20s elapsed]
yandex_compute_instance.kube-node["2"]: Still creating... [30s elapsed]
yandex_compute_instance.kube-node["1"]: Still creating... [30s elapsed]
yandex_compute_instance.kube-node["0"]: Still creating... [30s elapsed]
yandex_compute_instance.kube-node["0"]: Creation complete after 31s [id=fhm7ge0kaj4ehteell84]
yandex_compute_instance.kube-node["1"]: Creation complete after 35s [id=fhmd254ti1ve9fer4sfu]
yandex_compute_instance.kube-node["2"]: Creation complete after 38s [id=fhm21gp5hscbenqkb5oe]
local_file.ansible-inventory: Creating...
local_file.local-address: Creating...
local_file.ansible-inventory: Creation complete after 0s [id=0636557ffce5d790bacb805764b68ffdcb4bc010]
local_file.local-address: Creation complete after 0s [id=70783904d03169065aadd905fda70b7ceee3b4b7]

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

</details>

<br />

<details><summary>Результат выполнения команды <b>terraform destroy</b></summary>

```bash
rodney@arch-home: /home/rodney/learning/kirill-shapovalov-netologydiplom/diplom.tf git:(main) ✗ 
➜   terraform destroy
data.template_file.cloudinit: Reading...
data.template_file.cloudinit: Read complete after 0s [id=7dada99b1a5900b0a2447da452bf65e7ab31407994f179670fbb86b1b29b58eb]
yandex_vpc_network.cloud-network: Refreshing state... [id=enpcbmbsdf2fte3nksus]
data.yandex_compute_image.vm-image: Reading...
data.yandex_compute_image.vm-image: Read complete after 1s [id=fd8aptfr48hdvlflumbe]
yandex_vpc_subnet.vpc-subnet: Refreshing state... [id=e9biu29uda5nk2ds9267]
yandex_compute_instance.kube-node["1"]: Refreshing state... [id=fhmd254ti1ve9fer4sfu]
yandex_compute_instance.kube-node["2"]: Refreshing state... [id=fhm21gp5hscbenqkb5oe]
yandex_compute_instance.kube-node["0"]: Refreshing state... [id=fhm7ge0kaj4ehteell84]
local_file.ansible-inventory: Refreshing state... [id=0636557ffce5d790bacb805764b68ffdcb4bc010]
local_file.local-address: Refreshing state... [id=70783904d03169065aadd905fda70b7ceee3b4b7]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  # local_file.ansible-inventory will be destroyed
  - resource "local_file" "ansible-inventory" {
      - content              = <<-EOT
            ---
            all:
              hosts:
                k8s-node-01:
                  ansible_host: 158.160.121.191
                k8s-node-02:
                  ansible_host: 62.84.115.190
                k8s-node-03:
                  ansible_host: 51.250.10.89
              vars:
                ansible_user: admin
        EOT -> null
      - content_base64sha256 = "u6Fs6QE5Q/zCpTEMOLyk4nl93HwOV9puWcRJj/y6sbI=" -> null
      - content_base64sha512 = "mvwihMMJomvOVJx/vZl7kzZhUMZW/cZzli+BdhjJK8sqx1PZXpP5eVfD24R9VWRlpqb57PrKv2dgKrLUZhK69A==" -> null
      - content_md5          = "5a029cc679e7c11afcf2f56f4f7cbf0d" -> null
      - content_sha1         = "0636557ffce5d790bacb805764b68ffdcb4bc010" -> null
      - content_sha256       = "bba16ce9013943fcc2a5310c38bca4e2797ddc7c0e57da6e59c4498ffcbab1b2" -> null
      - content_sha512       = "9afc2284c309a26bce549c7fbd997b93366150c656fdc673962f817618c92bcb2ac753d95e93f97957c3db847d556465a6a6f9ecfacabf67602ab2d46612baf4" -> null
      - directory_permission = "0777" -> null
      - file_permission      = "0777" -> null
      - filename             = "../ansible-playbook/inventory/hosts.yml" -> null
      - id                   = "0636557ffce5d790bacb805764b68ffdcb4bc010" -> null
    }

  # local_file.local-address will be destroyed
  - resource "local_file" "local-address" {
      - content              = <<-EOT
            ---
            local_ip:
              - 192.168.10.3  k8s-node-01
              - 192.168.10.15  k8s-node-02
              - 192.168.10.26  k8s-node-03
        EOT -> null
      - content_base64sha256 = "bYlR/X4llYqf5ZdfHXwAWL74SiRq8opO5FOQiKTiEZU=" -> null
      - content_base64sha512 = "QDnPDblJXmyGvNR46FpK8g1TfoLO2Lt5cyYflG9BjBbrAhfnp2XMMHxOCZvLv0YHeITEgp6RUM+gEmeBHlIqIQ==" -> null
      - content_md5          = "e38ab4e4df6377400ca4973efc7676c5" -> null
      - content_sha1         = "70783904d03169065aadd905fda70b7ceee3b4b7" -> null
      - content_sha256       = "6d8951fd7e25958a9fe5975f1d7c0058bef84a246af28a4ee4539088a4e21195" -> null
      - content_sha512       = "4039cf0db9495e6c86bcd478e85a4af20d537e82ced8bb7973261f946f418c16eb0217e7a765cc307c4e099bcbbf46077884c4829e9150cfa01267811e522a21" -> null
      - directory_permission = "0777" -> null
      - file_permission      = "0777" -> null
      - filename             = "../ansible-playbook/group_vars/all/local_ip.yml" -> null
      - id                   = "70783904d03169065aadd905fda70b7ceee3b4b7" -> null
    }

  # yandex_compute_instance.kube-node["0"] will be destroyed
  - resource "yandex_compute_instance" "kube-node" {
      - allow_stopping_for_update = true -> null
      - created_at                = "2024-02-22T14:54:51Z" -> null
      - folder_id                 = "b1gab8fuc9s78vrid6au" -> null
      - fqdn                      = "k8s-node-01.ru-central1.internal" -> null
      - hostname                  = "k8s-node-01" -> null
      - id                        = "fhm7ge0kaj4ehteell84" -> null
      - labels                    = {} -> null
      - metadata                  = {
          - "serial-port-enable" = "1"
          - "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        } -> null
      - name                      = "k8s-node-01" -> null
      - network_acceleration_type = "standard" -> null
      - platform_id               = "standard-v1" -> null
      - status                    = "running" -> null
      - zone                      = "ru-central1-a" -> null

      - boot_disk {
          - auto_delete = true -> null
          - device_name = "fhml6jqgdv8csumj8b8s" -> null
          - disk_id     = "fhml6jqgdv8csumj8b8s" -> null
          - mode        = "READ_WRITE" -> null

          - initialize_params {
              - block_size = 4096 -> null
              - image_id   = "fd8aptfr48hdvlflumbe" -> null
              - size       = 20 -> null
              - type       = "network-ssd" -> null
            }
        }

      - metadata_options {
          - aws_v1_http_endpoint = 1 -> null
          - aws_v1_http_token    = 2 -> null
          - gce_http_endpoint    = 1 -> null
          - gce_http_token       = 1 -> null
        }

      - network_interface {
          - index              = 0 -> null
          - ip_address         = "192.168.10.3" -> null
          - ipv4               = true -> null
          - ipv6               = false -> null
          - mac_address        = "d0:0d:78:38:14:54" -> null
          - nat                = true -> null
          - nat_ip_address     = "158.160.121.191" -> null
          - nat_ip_version     = "IPV4" -> null
          - security_group_ids = [] -> null
          - subnet_id          = "e9biu29uda5nk2ds9267" -> null
        }

      - placement_policy {
          - host_affinity_rules       = [] -> null
          - placement_group_partition = 0 -> null
        }

      - resources {
          - core_fraction = 20 -> null
          - cores         = 4 -> null
          - gpus          = 0 -> null
          - memory        = 8 -> null
        }

      - scheduling_policy {
          - preemptible = true -> null
        }
    }

  # yandex_compute_instance.kube-node["1"] will be destroyed
  - resource "yandex_compute_instance" "kube-node" {
      - allow_stopping_for_update = true -> null
      - created_at                = "2024-02-22T14:54:51Z" -> null
      - folder_id                 = "b1gab8fuc9s78vrid6au" -> null
      - fqdn                      = "k8s-node-02.ru-central1.internal" -> null
      - hostname                  = "k8s-node-02" -> null
      - id                        = "fhmd254ti1ve9fer4sfu" -> null
      - labels                    = {} -> null
      - metadata                  = {
          - "serial-port-enable" = "1"
          - "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        } -> null
      - name                      = "k8s-node-02" -> null
      - network_acceleration_type = "standard" -> null
      - platform_id               = "standard-v1" -> null
      - status                    = "running" -> null
      - zone                      = "ru-central1-a" -> null

      - boot_disk {
          - auto_delete = true -> null
          - device_name = "fhms1hu7p3pe3m6vd413" -> null
          - disk_id     = "fhms1hu7p3pe3m6vd413" -> null
          - mode        = "READ_WRITE" -> null

          - initialize_params {
              - block_size = 4096 -> null
              - image_id   = "fd8aptfr48hdvlflumbe" -> null
              - size       = 20 -> null
              - type       = "network-ssd" -> null
            }
        }

      - metadata_options {
          - aws_v1_http_endpoint = 1 -> null
          - aws_v1_http_token    = 2 -> null
          - gce_http_endpoint    = 1 -> null
          - gce_http_token       = 1 -> null
        }

      - network_interface {
          - index              = 0 -> null
          - ip_address         = "192.168.10.15" -> null
          - ipv4               = true -> null
          - ipv6               = false -> null
          - mac_address        = "d0:0d:d1:14:9d:90" -> null
          - nat                = true -> null
          - nat_ip_address     = "62.84.115.190" -> null
          - nat_ip_version     = "IPV4" -> null
          - security_group_ids = [] -> null
          - subnet_id          = "e9biu29uda5nk2ds9267" -> null
        }

      - placement_policy {
          - host_affinity_rules       = [] -> null
          - placement_group_partition = 0 -> null
        }

      - resources {
          - core_fraction = 20 -> null
          - cores         = 4 -> null
          - gpus          = 0 -> null
          - memory        = 8 -> null
        }

      - scheduling_policy {
          - preemptible = true -> null
        }
    }

  # yandex_compute_instance.kube-node["2"] will be destroyed
  - resource "yandex_compute_instance" "kube-node" {
      - allow_stopping_for_update = true -> null
      - created_at                = "2024-02-22T14:54:51Z" -> null
      - folder_id                 = "b1gab8fuc9s78vrid6au" -> null
      - fqdn                      = "k8s-node-03.ru-central1.internal" -> null
      - hostname                  = "k8s-node-03" -> null
      - id                        = "fhm21gp5hscbenqkb5oe" -> null
      - labels                    = {} -> null
      - metadata                  = {
          - "serial-port-enable" = "1"
          - "user-data"          = <<-EOT
                #cloud-config
                
                users:
                  - name: admin
                    sudo: ALL=(ALL) NOPASSWD:ALL
                    shell: /bin/bash
                    groups: sudo
                    lock_passwd: false
                    # password - netology-diplom
                    passwd: $6$rounds=4096$MO/C34ZjgPaA44/M$KCt8tGEsbTomnLx6/W9KlR55JJo0Bhn5aLtzse3fa5UVvFhmo4C6wzitdPRv10rtWBY0yL/zZXQqKJhMMFpEs/
                    ssh_authorized_keys:
                      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJpYQT/m1O5e6S0I3H/lGHgzN/JYD2DzLksszQ4/GxD rodney@arch-home
                
                package_update: true
                package_upgrade: false
                packages:
                  - vim
                  - yum-utils
                  - curl
                  - git
                  - wget
            EOT
        } -> null
      - name                      = "k8s-node-03" -> null
      - network_acceleration_type = "standard" -> null
      - platform_id               = "standard-v1" -> null
      - status                    = "running" -> null
      - zone                      = "ru-central1-a" -> null

      - boot_disk {
          - auto_delete = true -> null
          - device_name = "fhmm9uljelsetquua0i2" -> null
          - disk_id     = "fhmm9uljelsetquua0i2" -> null
          - mode        = "READ_WRITE" -> null

          - initialize_params {
              - block_size = 4096 -> null
              - image_id   = "fd8aptfr48hdvlflumbe" -> null
              - size       = 20 -> null
              - type       = "network-ssd" -> null
            }
        }

      - metadata_options {
          - aws_v1_http_endpoint = 1 -> null
          - aws_v1_http_token    = 2 -> null
          - gce_http_endpoint    = 1 -> null
          - gce_http_token       = 1 -> null
        }

      - network_interface {
          - index              = 0 -> null
          - ip_address         = "192.168.10.26" -> null
          - ipv4               = true -> null
          - ipv6               = false -> null
          - mac_address        = "d0:0d:20:c3:25:8f" -> null
          - nat                = true -> null
          - nat_ip_address     = "51.250.10.89" -> null
          - nat_ip_version     = "IPV4" -> null
          - security_group_ids = [] -> null
          - subnet_id          = "e9biu29uda5nk2ds9267" -> null
        }

      - placement_policy {
          - host_affinity_rules       = [] -> null
          - placement_group_partition = 0 -> null
        }

      - resources {
          - core_fraction = 20 -> null
          - cores         = 4 -> null
          - gpus          = 0 -> null
          - memory        = 8 -> null
        }

      - scheduling_policy {
          - preemptible = true -> null
        }
    }

  # yandex_vpc_network.cloud-network will be destroyed
  - resource "yandex_vpc_network" "cloud-network" {
      - created_at                = "2024-02-22T14:54:46Z" -> null
      - default_security_group_id = "enp684trksk1a1m6mqvs" -> null
      - folder_id                 = "b1gab8fuc9s78vrid6au" -> null
      - id                        = "enpcbmbsdf2fte3nksus" -> null
      - labels                    = {} -> null
      - name                      = "diplom-network" -> null
      - subnet_ids                = [
          - "e9biu29uda5nk2ds9267",
        ] -> null
    }

  # yandex_vpc_subnet.vpc-subnet will be destroyed
  - resource "yandex_vpc_subnet" "vpc-subnet" {
      - created_at     = "2024-02-22T14:54:50Z" -> null
      - folder_id      = "b1gab8fuc9s78vrid6au" -> null
      - id             = "e9biu29uda5nk2ds9267" -> null
      - labels         = {} -> null
      - name           = "public" -> null
      - network_id     = "enpcbmbsdf2fte3nksus" -> null
      - v4_cidr_blocks = [
          - "192.168.10.0/24",
        ] -> null
      - v6_cidr_blocks = [] -> null
      - zone           = "ru-central1-a" -> null
    }

Plan: 0 to add, 0 to change, 7 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

local_file.ansible-inventory: Destroying... [id=0636557ffce5d790bacb805764b68ffdcb4bc010]
local_file.local-address: Destroying... [id=70783904d03169065aadd905fda70b7ceee3b4b7]
local_file.ansible-inventory: Destruction complete after 0s
local_file.local-address: Destruction complete after 0s
yandex_compute_instance.kube-node["2"]: Destroying... [id=fhm21gp5hscbenqkb5oe]
yandex_compute_instance.kube-node["0"]: Destroying... [id=fhm7ge0kaj4ehteell84]
yandex_compute_instance.kube-node["1"]: Destroying... [id=fhmd254ti1ve9fer4sfu]
yandex_compute_instance.kube-node["1"]: Still destroying... [id=fhmd254ti1ve9fer4sfu, 10s elapsed]
yandex_compute_instance.kube-node["2"]: Still destroying... [id=fhm21gp5hscbenqkb5oe, 10s elapsed]
yandex_compute_instance.kube-node["0"]: Still destroying... [id=fhm7ge0kaj4ehteell84, 10s elapsed]
yandex_compute_instance.kube-node["0"]: Still destroying... [id=fhm7ge0kaj4ehteell84, 20s elapsed]
yandex_compute_instance.kube-node["2"]: Still destroying... [id=fhm21gp5hscbenqkb5oe, 20s elapsed]
yandex_compute_instance.kube-node["1"]: Still destroying... [id=fhmd254ti1ve9fer4sfu, 20s elapsed]
yandex_compute_instance.kube-node["1"]: Still destroying... [id=fhmd254ti1ve9fer4sfu, 30s elapsed]
yandex_compute_instance.kube-node["0"]: Still destroying... [id=fhm7ge0kaj4ehteell84, 30s elapsed]
yandex_compute_instance.kube-node["2"]: Still destroying... [id=fhm21gp5hscbenqkb5oe, 30s elapsed]
yandex_compute_instance.kube-node["0"]: Destruction complete after 35s
yandex_compute_instance.kube-node["2"]: Still destroying... [id=fhm21gp5hscbenqkb5oe, 40s elapsed]
yandex_compute_instance.kube-node["1"]: Still destroying... [id=fhmd254ti1ve9fer4sfu, 40s elapsed]
yandex_compute_instance.kube-node["1"]: Destruction complete after 42s
yandex_compute_instance.kube-node["2"]: Destruction complete after 49s
yandex_vpc_subnet.vpc-subnet: Destroying... [id=e9biu29uda5nk2ds9267]
yandex_vpc_subnet.vpc-subnet: Destruction complete after 3s
yandex_vpc_network.cloud-network: Destroying... [id=enpcbmbsdf2fte3nksus]
yandex_vpc_network.cloud-network: Destruction complete after 1s

Destroy complete! Resources: 7 destroyed.
```
</details>

<br />

Все команды Terraform выполняются без каких либо дополнительных действий. Можно приступать к настройкам нод кластера и последующей инициализации самого Kubernetes-кластера.

### Запустить и сконфигурировать Kubernetes кластер