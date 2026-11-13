# Demo: OpenTofu + Proxmox + Ansible

This demo goes from an empty Proxmox VE host to a running, monitored web server, using Infrastructure as Code:

1. **OpenTofu** with the [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) provider.
2. **Build an Ubuntu 24.04 LTS template** from the official cloud image, using OpenTofu.
3. **Deploy a new VM** as a **linked clone** of the template from step 2. cloud-init sets the static IP, the user and the SSH key.
4. **Install nginx with Ansible** on the new VM. OpenTofu writes the Ansible inventory for you.
5. **Monitor nginx the SRE way** with Prometheus and Grafana on a second VM: the four **golden signals**, an **SLO** with an **error budget**, and **alerts**.

```
┌──────────────────┐    ┌──────────────────────┐    ┌──────────────────┐    ┌────────────────┐
│ Ubuntu cloud img │ ─▶ │ 01-template (tofu)   │ ─▶ │ 02-instance      │ ─▶ │ Ansible        │
│ noble .qcow2     │    │ VM 9000 → template   │    │ linked → web-01  │    │ nginx.yml      │
└──────────────────┘    └──────────────────────┘    │          mon-01  │    │ monitoring.yml │
                                                    │ + inventory.ini  │    └────────────────┘
                                                    └──────────────────┘
```

What runs where after `make all`:

```
          your laptop                       web-01 (group: web)                  mon-01 (group: monitoring)
  ┌────────────────────────┐   HTTP   ┌──────────────────────────────┐ scrape ┌────────────────────────────┐
  │ browser / make load    │ ───────▶ │ nginx :80                    │ ◀───── │ Prometheus :9090           │
  │                        │          │  ├ nginxlog-exporter :4040   │        │  ├ rules: SLIs + alerts    │
  │ browser ───────────────┼──────────┼──┤ nginx-exporter    :9113   │        │  └ node-exporter :9100     │
  │   Grafana / Prometheus │          │  └ node-exporter     :9100   │        │ Grafana :3000 (dashboard)  │
  └────────────────────────┘          └──────────────────────────────┘        └────────────────────────────┘
```

**Versions used** (all 5 steps tested end to end on this setup):

| Component | Version |
|---|---|
| Proxmox VE | 8.4.21 |
| OpenTofu | 1.13.9 |
| bpg/proxmox | 0.122.0 |
| ansible-core | 2.21.6 |
| Prometheus (Ubuntu package) | 2.45.3 |
| Grafana | 13.3.1 |
| node-exporter / nginx-exporter | 1.7.0 / 1.1.0 |
| prometheus-nginxlog-exporter | 1.11.0 |

## Project layout

```
.
├── Makefile                      # make setup / template / instance / nginx / monitoring / load
├── requirements.txt              # Python deps (ansible-core) for .venv
├── bin/tofu                      # (gitignored) created by `make tofu-install`
├── .venv/                        # (gitignored) created by `make venv`
├── .ssh/id_ed25519               # (gitignored) demo SSH key created by `make ssh-key`
├── .secrets/                     # (gitignored) generated Grafana admin password
├── scripts/
│   ├── loadgen.py                # test traffic for the dashboard (make load)
│   └── gen_dashboard.py          # generates the Grafana dashboard JSON
├── tofu/
│   ├── 01-template/              # Steps 1-2: provider + Ubuntu 24.04 template
│   │   ├── versions.tf           #   bpg/proxmox provider
│   │   ├── variables.tf
│   │   ├── main.tf               #   download cloud image + VM (template = true)
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── 02-instance/              # Step 3: clone VMs from the template
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf               #   clone + cloud-init + write ansible/inventory.ini
│       ├── outputs.tf
│       ├── templates/inventory.tftpl
│       └── terraform.tfvars.example
└── ansible/
    ├── ansible.cfg
    ├── nginx.yml                 # Step 4: nginx + demo endpoints (/health, /error, /slow)
    ├── monitoring.yml            # Step 5: exporters, Prometheus, Grafana
    ├── templates/                #   index.html, nginx site, prometheus.yml (from the inventory)
    └── files/
        ├── nginx-monitoring.conf #   timed access log + stub_status
        ├── nginxlog-exporter.yml
        ├── prometheus/golden-signals.rules.yml   # SLIs (recording rules) + alerts
        └── grafana/              #   data source, dashboard provider, golden-signals.json
```

**Why two separate OpenTofu states?** In real life you build a template once and many VMs are cloned from it. Keeping them apart means destroying the VMs never deletes the template.

---

## Prerequisites

### On your workstation

You only need `python3` (with `python3-venv`), `curl`, `unzip`, `make` and `ssh-keygen`.
You don't install OpenTofu or Ansible yourself, and you don't need an SSH key: `make setup` creates all of them inside the project folder.

```bash
sudo apt install -y python3-venv curl unzip make openssh-client   # Ubuntu / WSL

make setup
```

| Tool | Installed to | Make target | Notes |
|---|---|---|---|
| OpenTofu | `./bin/tofu` | `make tofu-install` | Downloads the release binary from GitHub and verifies its SHA256. Choose another version with `make tofu-install TOFU_VERSION=x.y.z`. |
| Ansible (ansible-core) | `./.venv` | `make venv` | Installs [requirements.txt](requirements.txt). |
| SSH key | `./.ssh/id_ed25519` | `make ssh-key` | A new key just for this demo, so the keys in your `~/.ssh` are never used or replaced. It is only created if it doesn't exist yet. |

<details>
<summary>What <code>make setup</code> runs</summary>

```bash
# make tofu-install: download OpenTofu, verify the checksum, unpack into ./bin
mkdir -p bin/.download
curl -fsSL -o bin/.download/tofu_1.13.9_linux_amd64.zip \
  https://github.com/opentofu/opentofu/releases/download/v1.13.9/tofu_1.13.9_linux_amd64.zip
curl -fsSL -o bin/.download/SHA256SUMS \
  https://github.com/opentofu/opentofu/releases/download/v1.13.9/tofu_1.13.9_SHA256SUMS
cd bin/.download && grep " tofu_1.13.9_linux_amd64.zip$" SHA256SUMS | sha256sum -c - && cd ../..
unzip -o -q bin/.download/tofu_1.13.9_linux_amd64.zip tofu -d bin
chmod +x bin/tofu
rm -f bin/.download/tofu_1.13.9_linux_amd64.zip bin/.download/SHA256SUMS
rmdir bin/.download

# make venv: Python virtual environment with Ansible
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt

# make ssh-key: demo SSH key (skipped if .ssh/id_ed25519 already exists)
mkdir -p .ssh && chmod 700 .ssh
ssh-keygen -t ed25519 -N "" -C "opentofu-proxmox-demo" -f .ssh/id_ed25519

# make versions
bin/tofu version
.venv/bin/ansible --version
```

The file names use your OS and CPU (`linux_amd64`, `linux_arm64`, `darwin_arm64`, ...).

</details>

`bin/`, `.venv/` and `.ssh/` are in `.gitignore`. `make clean-tools` removes `bin/` and `.venv/`. It keeps the SSH key, because the VMs still trust it.

To run the commands yourself instead of through `make`, activate the environment first:

```bash
source .venv/bin/activate
export PATH="$PWD/bin:$PATH"
```

### On Proxmox VE (8.4 or newer)

- **Storage `local` must allow the content type `import`.** It is not enabled by default. The cloud image is stored there and imported as a disk through the API, so OpenTofu **does not need SSH access** to the Proxmox node.

  ```bash
  # Run on the Proxmox shell. Keep the content types you already have
  # (check them in Datacenter → Storage, or with `cat /etc/pve/storage.cfg`).
  pvesm set local --content backup,iso,vztmpl,import
  ```

  Or in the UI: Datacenter → Storage → local → Edit → Content → add **Import**.
- **Storage `local-lvm`** (or another storage that supports linked clones, such as LVM-thin, ZFS or Ceph) holds the VM disks. It needs very little free space: the template is about 2 GB and each linked clone starts at almost 0.
- **Internet access on the Proxmox node.** The node downloads the image from `cloud-images.ubuntu.com` itself.
- **A network bridge** (`vmbr0`) and free IP addresses on that subnet for the VMs.

#### Create an API token for OpenTofu

Run these commands as root on the Proxmox shell:

```bash
# 1) Create a user for OpenTofu
pveum user add tofu@pve --comment "OpenTofu automation"

# 2) Create a least-privilege role with only what this demo needs
pveum role add TofuDemo -privs "\
Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,\
SDN.Audit,SDN.Use,\
Sys.Audit,Sys.Modify,\
VM.Allocate,VM.Audit,VM.Clone,VM.PowerMgmt,\
VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,\
VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options"

# 3) Give the role to the user on path "/" (it propagates to all nodes, storages and VMs)
pveum aclmod / -user tofu@pve -role TofuDemo

# 4) Create the token (--privsep 0 = the token uses the user's permissions directly)
pveum user token add tofu@pve tofu --privsep 0
```

The last command prints `full-tokenid` and `value`. **The `value` is shown only once.** Join the two parts like this:

```
tofu@pve!tofu=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

##### What each privilege is used for

| Privilege | Used for |
|---|---|
| `Datastore.AllocateTemplate` | Downloading the cloud image into storage `local` (`proxmox_download_file`) |
| `Datastore.Allocate` | Deleting the image file from storage on `tofu destroy` or when the resource is replaced |
| `Sys.Audit`, `Sys.Modify` | Required on the node by the Proxmox `download-url` API; also used to read node info |
| `Datastore.AllocateSpace` | Creating the VM disk and the cloud-init drive on `local-lvm` |
| `Datastore.Audit` | Listing storages and their contents |
| `SDN.Use`, `SDN.Audit` | Attaching VMs to bridge `vmbr0`. Without them, Proxmox hides the bridge and you get "interface not found". |
| `VM.Allocate` | Creating and deleting VMs, and converting a VM into a template |
| `VM.Clone` | Cloning VMs from the template (02-instance) |
| `VM.Audit` | Reading VM config and status (`tofu plan` / refresh) |
| `VM.PowerMgmt` | Starting and stopping VMs |
| `VM.Config.Disk` | Importing the cloud image as a disk and resizing disks |
| `VM.Config.CDROM` | Adding the cloud-init drive (it is a CD-ROM type drive) |
| `VM.Config.Cloudinit` | Setting user, SSH key, IP and DNS through cloud-init |
| `VM.Config.CPU`, `VM.Config.Memory` | Setting CPU and RAM |
| `VM.Config.Network` | Adding the network device |
| `VM.Config.HWType` | Setting machine type `q35`, SCSI controller, serial port and VGA |
| `VM.Config.Options` | Setting name, description, tags, on_boot and OS type |

##### Notes on permissions

- **Works on PVE 8 and 9.** Some privileges changed in PVE 9 (for example, `VM.Monitor` was removed). If a role names a privilege that doesn't exist, `pveum role add` fails right away, so the list above only uses privileges that exist in both versions.
- **A privilege is missing?** An error like `403 Permission check failed (/path, Privilege.Name)` tells you exactly which one. Add it with:
  `pveum role modify TofuDemo -append 1 -privs "Privilege.Name"`
- **Features this demo doesn't use** need extra privileges if you add them:
  - resource pools → `Pool.Allocate`
  - reading the IP through qemu-guest-agent on PVE 9 → `VM.GuestAgent.Audit`
  - migrating VMs → `VM.Migrate`
- **Narrower scope.** Instead of giving the role on `/`, you can give it on specific paths only:
  - `/nodes/pve` for `Sys.*`
  - `/storage/local` and `/storage/local-lvm` for `Datastore.*`
  - `/sdn/zones/localnetwork` for `SDN.*`
  - `/vms` for `VM.*`

  This is safer but takes more commands.
- **Lab shortcut.** For a quick test you can use `pveum aclmod / -user tofu@pve -role Administrator`. Never do this in production.
- **Why `--privsep 0`?** A token created with `--privsep 1` (the default in `pveum` and in the UI) only gets the **intersection** of the user's permissions and the token's own permissions. You must then give the role to **both** the user and the token. If only one side has it, the token can do nothing at all:

  ```bash
  pveum aclmod / -user  tofu@pve        -role TofuDemo
  pveum aclmod / -token 'tofu@pve!tofu' -role TofuDemo
  ```

  To check what the token can really do: `pveum user token permissions tofu@pve tofu --path /storage/local`

---

## Quick start

```bash
# 0) Install tofu + ansible inside the project
make setup

# 1) Create your config files
cp tofu/01-template/terraform.tfvars.example tofu/01-template/terraform.tfvars
cp tofu/02-instance/terraform.tfvars.example tofu/02-instance/terraform.tfvars
# Edit endpoint, api_token, node_name, storage, bridge, IP and gateway to match your environment

# 2) Run every step
make all
```

`make all` is the same as `make template`, then `make instance`, then `make nginx`, then `make monitoring`. Run `make help` to see every target. The commands behind each target are shown in the sections below.

When it finishes, open `http://<VM_IP>/` to see the page that Ansible deployed.

If you'd rather not keep the token in a file, use an environment variable instead:
`export TF_VAR_proxmox_api_token='tofu@pve!tofu=...'`

---

## Step by step

### Steps 1-2: Build the Ubuntu 24.04 template

```bash
make template
```

`make template` runs:

```bash
cd tofu/01-template
../../bin/tofu init -upgrade
../../bin/tofu apply -auto-approve
```

To review the changes before applying, run the steps yourself:

```bash
cd tofu/01-template
../../bin/tofu init
../../bin/tofu plan     # show what will be created
../../bin/tofu apply    # asks "yes" before it changes anything
```

What happens ([main.tf](tofu/01-template/main.tf)):

1. `proxmox_download_file` tells Proxmox to download the Ubuntu cloud image and save it as `local:import/noble-server-cloudimg-amd64.qcow2`. The Proxmox node downloads it directly; the file never passes through your machine.
2. `proxmox_virtual_environment_vm` creates VM ID `9000` and imports the image as disk `scsi0` with `import_from`. This uses only the API, with no SSH. It then:
   - adds a cloud-init drive on **`sata0`**. The default `ide2` doesn't work with some Ubuntu cloud images, such as 22.04; SATA works for all of them.
   - sets up a serial console (`serial0`), which Ubuntu cloud images expect
   - sets `template = true` to turn the VM into a template

The template disk is only **5 GB**. The image itself is about 3.5 GB, so this is close to the minimum. `local-lvm` is thin-provisioned, so only blocks that are actually written use space.

Example output (about 1-2 minutes; most of it is downloading the ~600 MB image):

```
proxmox_download_file.ubuntu_noble: Creation complete after 34s [id=local:import/noble-server-cloudimg-amd64.qcow2]
proxmox_virtual_environment_vm.ubuntu_template: Creation complete after 39s [id=9000]
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

template_name  = "ubuntu-2404-template"
template_node  = "pve"
template_vm_id = 9000
```

To check it, look in the Proxmox UI: `ubuntu-2404-template` (ID 9000) shows a template icon. Or use the shell:

```bash
qm config 9000 | grep -E 'template|scsi0|sata0|serial0|vga'
# template: 1
# scsi0: local-lvm:base-9000-disk-0,...,size=5G,ssd=1
# sata0: local-lvm:vm-9000-cloudinit,media=cdrom
# serial0: socket
# vga: memory=16,type=serial0
```

> **VM ID already taken?** If another VM already uses ID `9000`, change `template_vm_id` in `tofu/01-template/terraform.tfvars`. **Also set the same `template_vm_id` in `tofu/02-instance/terraform.tfvars`.**

### Step 3: Deploy a VM from the template

```bash
make instance
```

`make instance` runs (it first runs `make ssh-key` if the key doesn't exist):

```bash
cd tofu/02-instance
../../bin/tofu init -upgrade
../../bin/tofu apply -auto-approve
```

What happens ([main.tf](tofu/02-instance/main.tf)):

- A **linked clone** of the template is made for each entry in `var.instances`: `web-01` (group `web`) and `mon-01` (group `monitoring`). It takes only a few seconds.
  - A linked clone doesn't copy the disk. Its disk is a thin snapshot of the template's disk and only stores the blocks that change.
  - For a full, independent copy, set `full_clone = true`.
  - While linked clones exist, the template can't be deleted. `make destroy` removes the VMs first for this reason.
- CPU and RAM are set. The disk keeps the template's 5 GB unless the instance sets `disk_size`. `mon-01` uses 10 GB, because Grafana alone takes about 2 GB.
- cloud-init configures:
  - a static IP, gateway and DNS
  - user `ubuntu` with your SSH public key
- `ansible/inventory.ini` is written automatically from [inventory.tftpl](tofu/02-instance/templates/inventory.tftpl), with one Ansible group per `group` value:

  ```ini
  [monitoring]
  mon-01 ansible_host=192.168.1.102

  [web]
  web-01 ansible_host=192.168.1.101

  [all:vars]
  ansible_user=ubuntu
  ansible_ssh_private_key_file=/path/to/project/.ssh/id_ed25519
  ```

Example output:

```
proxmox_virtual_environment_vm.vm["mon-01"]: Creation complete after 5s [id=202]
proxmox_virtual_environment_vm.vm["web-01"]: Creation complete after 5s [id=201]
local_file.ansible_inventory: Creation complete after 0s [id=...]
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

instances = {
  "mon-01" = "192.168.1.102"
  "web-01" = "192.168.1.101"
}
urls = {
  "mon-01 grafana"    = "http://192.168.1.102:3000/"
  "mon-01 prometheus" = "http://192.168.1.102:9090/"
  "web-01"            = "http://192.168.1.101/"
}
```

To check that it really is a linked clone, read the clone task log in the Proxmox UI (VM 9000 → Task History). It says `create linked clone of drive scsi0`.

To log in to the VM, use the project key:

```bash
ssh -i .ssh/id_ed25519 ubuntu@192.168.1.101
```

For more VMs, add entries to `instances` and run `tofu apply` again. `group`, `cores`, `memory` and `disk_size` are optional (default group: `web`). A new `web-*` VM is picked up by monitoring automatically the next time you run `make monitoring`:

```hcl
instances = {
  "web-01" = { vm_id = 201, ip_cidr = "192.168.1.101/24", group = "web" }
  "mon-01" = { vm_id = 202, ip_cidr = "192.168.1.102/24", group = "monitoring", disk_size = 10 }
  "web-02" = { vm_id = 203, ip_cidr = "192.168.1.103/24", group = "web" }
}
```

### Step 4: Install nginx with Ansible

```bash
make ping     # check that Ansible can reach the VMs
make nginx    # run the playbook
```

These run:

```bash
cd ansible
../.venv/bin/ansible all -m ping          # make ping
../.venv/bin/ansible-playbook nginx.yml   # make nginx
```

Ansible reads [ansible.cfg](ansible/ansible.cfg) from the `ansible/` folder, which points to the generated `inventory.ini`. That's why the commands run from inside that folder.

The playbook ([nginx.yml](ansible/nginx.yml)) runs these steps in order:

1. Wait until SSH is ready.
2. Wait for `cloud-init` to finish, so it doesn't fight over the apt lock on first boot. Exit code 2 ("degraded done") also counts as success: it only means there were deprecation warnings in the user-data that Proxmox generates.
3. Install `nginx`.
4. Deploy an `index.html` page from a template. The page shows the hostname, IP and OS.
5. Deploy the site config with three **demo endpoints** used in step 5:

   | Path | Returns | Used to show |
   |---|---|---|
   | `/health` | `200 ok` (not logged) | health checks |
   | `/error` | `500` every time | the **Errors** signal and the error budget |
   | `/slow` | a 6 KB file sent at 4 KB/s (~1-1.5 s) | the **Latency** signal |

6. Check the config with `nginx -t`, then reload nginx (only if something changed).
7. Make sure nginx is running and starts on boot.
8. Send HTTP requests from your machine to confirm `/` and `/health` return 200 and `/error` returns 500.

Expected result (a second run shows `changed=0`, because the playbook is idempotent):

```
PLAY RECAP *********************************************************************
web-01  : ok=11   changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

To check it yourself:

```bash
curl http://192.168.1.101/
```

### Step 5: Monitor nginx with the golden signals

```bash
make monitoring
```

`make monitoring` runs:

```bash
cd ansible
../.venv/bin/ansible-playbook monitoring.yml
```

#### SRE in 1 minute

**Site Reliability Engineering (SRE)** treats reliability as something you measure and set a target for. A few words you'll see on the dashboard:

| Term | Meaning | In this demo |
|---|---|---|
| **Golden signals** | The 4 numbers that tell you if a user-facing service is healthy (from Google's SRE book) | Latency, Traffic, Errors, Saturation |
| **SLI** (indicator) | A measurement of how good the service is, usually a ratio of good events / all events | % of requests that are not 5xx; % of requests faster than 500 ms |
| **SLO** (objective) | The target for an SLI | 99% of requests succeed, p95 latency < 500 ms |
| **Error budget** | How much failure the SLO allows: 100% - SLO | 1% of requests may fail. When it's used up, stop shipping risky changes and fix reliability |
| **Burn rate** | How fast the error budget is being used. 1 = exactly on budget | Burn rate 14.4 would empty a 30-day budget in about 2 days, so it pages someone |
| **p95 / p99** | Percentile: 95% (or 99%) of requests were faster than this | Averages hide slow requests; percentiles show what the unluckiest users feel |

#### The four golden signals, and where each number comes from

| Signal | Question | Metric | Exporter (on web-01) |
|---|---|---|---|
| **Latency** | How long do requests take? | `nginx_http_response_time_seconds_hist_bucket` (histogram → p50/p95/p99) | [nginxlog-exporter](https://github.com/martin-helmich/prometheus-nginxlog-exporter) reads `$request_time` from a second access log |
| **Traffic** | How much demand is there? | `nginx_http_response_count_total` (requests/s), `nginx_connections_active` | nginxlog-exporter, nginx-exporter (`stub_status`) |
| **Errors** | How many requests fail? | `nginx_http_response_count_total{status=~"5.."}` / all requests | nginxlog-exporter |
| **Saturation** | How "full" is the server? | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes` | node-exporter (on every VM) |

nginx's built-in `stub_status` only counts connections and requests. It knows nothing about latency or status codes. That's why the playbook adds a **second access log with `$request_time`** ([nginx-monitoring.conf](ansible/files/nginx-monitoring.conf)) and runs nginxlog-exporter to turn it into metrics.

#### What the playbook does

1. **All VMs:** grow the root partition if `disk_size` was raised, then install **node-exporter** (`:9100`).
2. **web-01:**
   - Add the timed access log and a `stub_status` endpoint that only listens on `127.0.0.1:8080`.
   - Install **nginx-exporter** (`:9113`).
   - Install **nginxlog-exporter** (`:4040`). The `.deb` is checked against the release's SHA256 checksum. It runs as an unprivileged systemd `DynamicUser` in the `adm` group, so it can read the nginx logs.
3. **mon-01:**
   - Install **Prometheus**. Its [prometheus.yml](ansible/templates/prometheus.yml.j2) is generated from the inventory, so new web VMs are scraped automatically. It keeps 7 days of data and loads the [golden-signals rules](ansible/files/prometheus/golden-signals.rules.yml). Both files are checked with `promtool` before they're installed.
   - Install **Grafana** from the official apt repo, with the Prometheus data source and the **Nginx Golden Signals** dashboard provisioned as code.
4. **Check:** wait until every Prometheus scrape target is `up`.

Open the URLs from `tofu output urls`:

| URL | What you see |
|---|---|
| `http://<mon-01>:3000/` | Grafana, opens straight on the **Nginx Golden Signals** dashboard (anonymous, read-only) |
| `http://<mon-01>:9090/targets` | Prometheus: every scrape target should be `UP` |
| `http://<mon-01>:9090/alerts` | Prometheus: the golden-signal alerts and their state |

Log in to Grafana as `admin` (to edit things) with the password in `.secrets/grafana-admin-password`. Ansible generates it on your machine the first time; it's gitignored.

#### The dashboard

| Row | Panels |
|---|---|
| **SLO overview** | Availability (SLI, 1h) · Error budget left · p95 latency · Traffic (req/s) · Firing alerts |
| **Latency** | p50 / p95 / p99 with the 500 ms SLO line · share of requests faster than 500 ms |
| **Traffic** | requests/s by status code · active connections |
| **Errors** | 5xx ratio with the 1% budget line · 4xx and 5xx per second |
| **Saturation** | CPU busy · memory used · root disk used (per VM, with alert lines) |

The dashboard JSON is generated by [scripts/gen_dashboard.py](scripts/gen_dashboard.py). To change the dashboard, edit the script, regenerate the JSON, and run `make monitoring` again:

```bash
python3 scripts/gen_dashboard.py ansible/files/grafana/golden-signals.json
```

#### Alerts

| Alert | Fires when | Signal |
|---|---|---|
| `NginxDown` | an nginx exporter can't be scraped, or nginx stops answering, for 1 min | Errors |
| `HighErrorRate` | more than 5% of requests are 5xx for 2 min | Errors |
| `ErrorBudgetBurnFast` | the error ratio is above 14.4% in **both** the 5 min and 1 h windows (multi-window burn rate) | Errors / SLO |
| `HighLatencyP95` | p95 latency is above 500 ms for 2 min | Latency |
| `HighCpu` / `LowMemory` / `DiskAlmostFull` | CPU > 80%, memory > 90%, root disk > 85% for 5 min | Saturation |

The alerts show up in Prometheus and in the "Firing alerts" panel. To get notified by email, Slack and so on, add Alertmanager. It isn't part of this demo, to keep it small.

#### Try it: break things on purpose

Send traffic from your laptop and watch the dashboard. Leave each mode running for a few minutes, because the windows are 1-5 minutes.

```bash
make load                  # healthy traffic: ~95% 200, a few 404s
make load MODE=errors      # ~20% of requests get a 500 -> error ratio up, error budget burns, alerts fire
make load MODE=slow        # ~30% of requests take ~1 s -> p95 latency crosses the 500 ms SLO
make load MODE=normal RPS=50 DURATION=120
```

`make load` runs [scripts/loadgen.py](scripts/loadgen.py), which uses only the Python standard library and sends traffic to every host in the `[web]` group:

```bash
python3 scripts/loadgen.py --mode errors --rps 20 --duration 300
```

What happened when we tested it on the lab (20 requests/s):

| Test | Load generator result | What Prometheus / Grafana showed |
|---|---|---|
| `make load MODE=errors DURATION=240` | `200=3624  404=248  500=928` (19% errors) | 5xx ratio ~19%, error budget left 0%. `ErrorBudgetBurnFast` fired after ~1 min, `HighErrorRate` after ~2 min |
| `make load MODE=slow DURATION=210` | `200=4200` | p95 latency ~2 s, `HighLatencyP95` fired |

> **Why does p95 show ~2 s when `/slow` takes ~1.1 s?** Prometheus estimates percentiles from histogram **buckets**. Our buckets are `…, 0.5, 1, 2.5, …` seconds, so a request of 1.1 s falls in the 1-2.5 s bucket, and `histogram_quantile()` assumes it could be anywhere inside it. A percentile is only as precise as the buckets around it, so pick buckets close to your SLO threshold (we have one at exactly 0.5 s).

When the load stops, the alerts resolve by themselves within a few minutes. The 1-hour availability and error budget panels take up to an hour to recover, because they look at the whole hour.

---

## Clean up

```bash
make destroy            # delete the VMs first, then the template
# or
make destroy-instance   # delete only the VMs and keep the template for later
```

These run:

```bash
# make destroy-instance
cd tofu/02-instance && ../../bin/tofu destroy -auto-approve && cd ../..

# make destroy-template
cd tofu/01-template && ../../bin/tofu destroy -auto-approve && cd ../..

# make destroy = destroy-instance, then destroy-template

# make clean-tools: remove the local tools (keeps .ssh/)
rm -rf ./bin ./.venv
```

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `401 authentication failure` | The token has the wrong format. It must be `user@realm!tokenid=secret`. |
| `403 Permission check failed (/path, Priv)` | **If the role already has that privilege:** the token is probably `privsep 1` and the role is given to only the user or only the token. Give it to both. **If the role doesn't have it:** add it to the role (see [Notes on permissions](#notes-on-permissions)). |
| Image download is slow or times out | The Proxmox node can't reach the internet, or the link is slow. Increase `upload_timeout`. |
| `storage 'local' does not support content-type 'import'` | Enable content type **import** on storage `local` (see Prerequisites). |
| `unable to authenticate user "" over SSH` | This happens when the disk uses `file_id`, because the provider then imports over SSH. Use `import_from` with content type `import` instead; this repo already does. |
| cloud-init settings (IP, user, SSH key) are ignored | The cloud-init drive is on `ide2`. Some Ubuntu cloud images (e.g. 22.04) don't read it there. Use `interface = "sata0"` in the `initialization` block, as this repo does. |
| Ansible fails on `cloud-init status --wait` with rc 2 | It means "done with recoverable errors" (deprecation warnings). The playbook already accepts rc 2. |
| Ansible `Permission denied (publickey)` | The VM was created with another key. Make sure `ssh_public_key_path` and `ssh_private_key_path` point to the same key pair (default: `.ssh/id_ed25519`), then recreate the VM. |
| Can't delete the template | Linked clones still use it. Delete the VMs first (`make destroy-instance`). |
| LVM warning "Sum of all thin volume sizes exceeds the size of thin pool" | The thin pool is over-provisioned. This is normal with thin storage, but watch the real free space in the Proxmox UI. |
| Black screen in noVNC after boot | This is expected: the template uses a serial console. Use the **xterm.js** console instead. |
| Ansible `UNREACHABLE` | Check the IP and gateway in tfvars, and make sure your machine can route to the VM subnet. |
| `Could not get lock /var/lib/dpkg/lock` | cloud-init is still running. The playbook already waits for it; if you still see this, just run it again. |
| `prometheus-nginxlog-exporter` fails with `permission denied` on `/var/log/nginx/...` | The packaged unit drops all capabilities, so even root can't read the `www-data:adm` 640 logs. The playbook adds a systemd drop-in that runs it as a `DynamicUser` in group `adm`, with our config file. |
| Grafana "Wait for Grafana to answer" retries a few times | Normal on the first run: Grafana creates its database before it answers (about 30 s). |
| Dashboard panels say "No data" | No traffic yet. Run `make load`. Latency and error panels need a few minutes of traffic to fill their windows. |
| A Prometheus target is `DOWN` | Check the exporter on that VM: `systemctl status prometheus-node-exporter prometheus-nginx-exporter prometheus-nginxlog-exporter`. |
| Disk on mon-01 fills up | Grafana takes about 2 GB. Raise `disk_size` for `mon-01` and run `make instance` and then `make monitoring`. The playbook grows the partition for you. |
| I want DHCP instead of a static IP | Install `qemu-guest-agent` and set `agent.enabled = true` so the provider can read the IP. This demo uses static IPs to keep things simple. |

## Production notes

- Limit the `TofuDemo` ACLs to the paths you really use, and use a separate token per environment.
- Keep state in a remote backend (for example S3 or MinIO) and turn on OpenTofu state encryption.
- Never commit `terraform.tfvars`. It is already in `.gitignore`.
- Harden the VMs further, for example by enabling UFW and disabling SSH password login.
- Consider full clones (`full_clone = true`) for long-lived VMs, so they don't depend on the template.
- Monitoring: add Alertmanager for notifications, put Grafana behind HTTPS and SSO instead of anonymous access, and pick SLO windows that match your users (usually 28-30 days, not 1 hour).
