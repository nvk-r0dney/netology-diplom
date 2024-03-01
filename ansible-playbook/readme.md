# Playbook 

### Description

Данный Playbook конфигурирует ноды для будущего Kubernetes кластера. Устанавливает необходимые пакеты, выполняет необходимые команды, копирует необходимые конфигурационные файлы по шаблону.

### Plays

1. **Prepare nodes**

На данном этапе выполняется предварительная конфигурация нод, для каждой ноды устанавливается значение hostname, а также заполняется файл `/etc/hosts` - в него записываются локальные адреса нод кластера с их именами.

2. **Install containerd.io**

На данном этапе выполняется установка основного движка контейнеризации Kubernetes - containerd.io. Здесь для начала удаляются старые версии приложений, если таковые имелись, после чего добавляется репозиторий Docker, и осуществляется установка самого пакета containerd.io.

3. **Prepare to install Kubernetes**

На данном этапе выполняется подготовка к установке пакетов Kubernetes. Добавляется репозиторий Kubernetes, копируется конфигурационный файл, выполняются необходимые команды.

4. **Install Kubernetes**

Данный Play устанавливает пакеты kubeadm, kubeinit и kubelet на ноды кластера.

### Tasks

1. **Prepare nodes | Config hostname** - устанавливает `hostname` для каждой ноды в соответствии с именем, данным на этапе создания ВМ.
2. **Prepare nodes | Set DNS nodes values** - записывает в `/etc/hosts` локальные адреса нод кластера и их имена, которые берет из динамического файла group_vars.
3. **Install containerd.io | Remove previous versions** - удаляет предыдущие версии пакетов.
4. **Install containerd.io | Add Docker repo** - добавляет официальный репозиторий Docker.
5. **Install containerd.io | Install package** - устанавливает пакет containerd.io.
6. **Install containerd.io | Remove containerd config file** - удаляет файл `/etc/containerd/config.toml`, поскольку если этого не сделать - kubeadm init упадет с ошибкой.
7. **Prepare to install Kubernetes | Add Kube repo** - добавление официального репозитория Kubernetes.
8. **Prepare to install Kubernetes | Add Kubernetes config-file** - добавление конфигурационного файла Kubernetes из шаблона Jinja.
9. **Prepare to install Kubernetes | Exec commands** - выполнение набора необходимых команд, без которых инициализация кластера будет невозможна (например, swapoff -a). Весь список команд взят из официальной документации.
10. **Install Kubernetes | Install packages** - установка пакетов kubeadm, kubeinit и kubelet на ноды кластера.

### Handlers

1. **Start containerd.io daemon** - запускает сервис containerd.io на нодах кластера.
2. **Restart containerd.io daemon** - перезапускает сервис containerd.io после удаления конфигурационного файла `/etc/containerd/config.toml`.
3. **Start kubelet service** - запускает сервис kubelet.