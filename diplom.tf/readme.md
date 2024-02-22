<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >=0.107.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.4.1 |
| <a name="provider_template"></a> [template](#provider\_template) | 2.2.0 |
| <a name="provider_yandex"></a> [yandex](#provider\_yandex) | 0.108.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [local_file.ansible-inventory](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.local-address](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [yandex_compute_instance.kube-node](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/compute_instance) | resource |
| [yandex_vpc_network.cloud-network](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_network) | resource |
| [yandex_vpc_subnet.vpc-subnet](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/vpc_subnet) | resource |
| [template_file.cloudinit](https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/file) | data source |
| [yandex_compute_image.vm-image](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/data-sources/compute_image) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | Yandex.Cloud VPC subnet cidr block in A zone | `tuple([string])` | n/a | yes |
| <a name="input_cloud_id"></a> [cloud\_id](#input\_cloud\_id) | Yandex.Cloud ID | `string` | n/a | yes |
| <a name="input_default_zone"></a> [default\_zone](#input\_default\_zone) | Yandex.Cloud default zone | `string` | n/a | yes |
| <a name="input_folder_id"></a> [folder\_id](#input\_folder\_id) | Yandex.Cloud MyDefault folder ID | `string` | n/a | yes |
| <a name="input_hdd_size"></a> [hdd\_size](#input\_hdd\_size) | Instance disk size in GB | `number` | n/a | yes |
| <a name="input_hdd_type"></a> [hdd\_type](#input\_hdd\_type) | Disk type for Kubernetes instance | `string` | n/a | yes |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | Hostname for Kubernetes Node | <pre>list(object({<br>    hostname = string<br>  }))</pre> | n/a | yes |
| <a name="input_image_family"></a> [image\_family](#input\_image\_family) | OS family for instance | `string` | n/a | yes |
| <a name="input_network_nat"></a> [network\_nat](#input\_network\_nat) | Enable NAT on Kubernetes instance | `bool` | `true` | no |
| <a name="input_platform"></a> [platform](#input\_platform) | Platform type in Yandex.Cloud | `string` | n/a | yes |
| <a name="input_preemptible"></a> [preemptible](#input\_preemptible) | Set instance preemptible or not | `bool` | `true` | no |
| <a name="input_ram_size"></a> [ram\_size](#input\_ram\_size) | Instance RAM size in GB | `number` | n/a | yes |
| <a name="input_serial_port"></a> [serial\_port](#input\_serial\_port) | Enable Serial port on Kubernetes instance | `number` | `1` | no |
| <a name="input_stop_to_update"></a> [stop\_to\_update](#input\_stop\_to\_update) | Allow stop instance for updates | `bool` | `true` | no |
| <a name="input_subnet_name"></a> [subnet\_name](#input\_subnet\_name) | Yandex.Cloud VPC subnet name in A zone | `string` | n/a | yes |
| <a name="input_subnet_zone"></a> [subnet\_zone](#input\_subnet\_zone) | Yandex.Cloud VPC subnet in A zone | `string` | n/a | yes |
| <a name="input_token"></a> [token](#input\_token) | OAuth-token | `string` | n/a | yes |
| <a name="input_vcpu_cores"></a> [vcpu\_cores](#input\_vcpu\_cores) | vCPU resources for Kubernetes instance | `number` | n/a | yes |
| <a name="input_vcpu_fraction"></a> [vcpu\_fraction](#input\_vcpu\_fraction) | Instance vCPU fraction in Yandex.Cloud | `number` | n/a | yes |
| <a name="input_vpc_name"></a> [vpc\_name](#input\_vpc\_name) | Yandex.Cloud Diplom VPC | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->