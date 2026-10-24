# Lab 08: oVirt Engine (optional, advanced)

**Runs on:** `lab-ovirt-engine` + `lab-vdsm` · **Needs:** ~14 GB RAM free on the Proxmox node ·
**Time:** 30-45 min of mostly waiting

## Why this layer exists

Lab 06 drove VDSM by hand. Here, **oVirt Engine** takes over: it adds `lab-vdsm` as a host, gives
it TLS certificates, attaches shared storage, and from then on every VM operation flows
**web UI/REST API → engine → VDSM → libvirt → QEMU → KVM**.

## Set it up

1. In `.env`, set `OVIRT_ADMIN_PASSWORD` (8+ characters).
2. In `terraform/terraform.tfvars`, set `ovirt_engine = true` (that also turns on the vdsm VM).
3. `make lab`. engine-setup and host deploy take a while: around 15-25 minutes in total.

The playbook ([roles/ovirt_engine](../../ansible/roles/ovirt_engine/tasks/main.yml)) does what an
admin would do in the UI:

1. Installs `ovirt-engine` and runs `engine-setup` with an
   [answer file](../../ansible/roles/ovirt_engine/templates/answers.conf.j2). It turns off the
   optional extras, including Keycloak SSO, which oVirt 4.5 enables by default.
2. Exports an NFS share from the engine VM, to use as shared storage.
3. Authorizes the engine's SSH key for root on `lab-vdsm`, then adds it as a host through the REST
   API. The engine SSHes in and redeploys VDSM with TLS ("host deploy"), then **reboots the host**.
4. Creates a `data` storage domain on the NFS share and attaches it to the `Default` data center.

When it's done, the REST API shows the whole data center up (tested with oVirt 4.5.7):

```
hosts:            lab-vdsm  status=up
storage domains:  data      type=data, attached to Default: status=active master=true
data centers:     Default   status=up
```

## Do it

Open `https://<lab-ovirt-engine IP>/ovirt-engine/` and log in as `admin` (profile `internal`).
Accept the self-signed certificate.

> **If the page doesn't load or loops back to the login page:** oVirt is strict about its own
> name. The playbook allows logins by IP, but some links still redirect to
> `lab-ovirt-engine.kvm-lab.test`, which your computer can't resolve. Add it to your hosts file
> and use that name instead:
>
> ```bash
> echo "<engine IP> lab-ovirt-engine.kvm-lab.test" | sudo tee -a /etc/hosts
> ```

1. **Compute → Hosts:** `lab-vdsm` is **Up**. Look at its *General* and *Host Devices* tabs. That's
   lab 06's `getCapabilities` output, rendered.
2. **Compute → Virtual Machines → New:** a 1 vCPU, 512 MB VM with a 1 GB disk on `data`. Start it
   (it has no OS, which is fine for this exercise).
3. On `lab-vdsm` (`make ssh VM=vdsm`), watch what that did:

   ```bash
   sudo vdsm-client Host getVMList    # no --insecure any more: VDSM speaks TLS now (needs root for the certs)
   virsh -r list
   virsh -r dumpxml <name> | less    # look for the <ovirt-vm:...> metadata block
   sudo tail -f /var/log/vdsm/vdsm.log
   ```

   For a test VM called `lab-test`:

   ```
   $ sudo vdsm-client Host getVMList
   [ { "status": "Up", "vmId": "3864da04-8efd-4c43-af88-9fabb4cd1e39", ... } ]

   $ virsh -r list
    Id   Name       State
    1    lab-test   running

   $ virsh -r dumpxml lab-test        # trimmed
     <metadata xmlns:ns1="http://ovirt.org/vm/tune/1.0" xmlns:ovirt-vm="http://ovirt.org/vm/1.0">
       <ovirt-vm:vm>
       <ovirt-vm:clusterVersion>4.8</ovirt-vm:clusterVersion>
       <ovirt-vm:resumeBehavior>auto_resume</ovirt-vm:resumeBehavior>
       <ovirt-vm:device devtype="disk" name="vda">
           <ovirt-vm:domainID>3d7dc820-...</ovirt-vm:domainID>
           <ovirt-vm:imageID>bf451f2e-...</ovirt-vm:imageID>
           <ovirt-vm:poolID>c88beb7e-...</ovirt-vm:poolID>
           <ovirt-vm:volumeID>e43d4e45-...</ovirt-vm:volumeID>
   ```

4. Try the REST API the playbook used:

   ```bash
   curl -sk -u 'admin@internal:<password>' -H 'Accept: application/json' \
     https://<engine IP>/ovirt-engine/api/vms | jq '.vm[] | {name, status}'
   ```

## What to notice

- **The XML now carries oVirt metadata.** VDSM stores its own state in the domain XML's
  `<metadata>` section: the storage pool, domain, image and volume IDs of every disk, its
  ballooning target, what to do after a storage outage (`resumeBehavior`). That's how it rebuilds
  its view of a VM after a restart.
- **The storage layout:** the host mounts the NFS export under `/rhev/data-center/mnt/`, and the
  storage domain's directory holds `dom_md/` (domain metadata and sanlock leases), `master/`, and
  `images/`. Each disk is `images/<disk UUID>/<volume UUID>`, next to a `.meta` file and a
  `.lease` file, the sanlock lease that stops two hosts from writing the disk at once.
- **Host deploy took over the host's networking.** Before, the VM's address sat on `eth0`. After:

  ```
  eth0             UP
  ovirtmgmt        UP             <host IP>/24
  ```

  `supervdsmd` built the `ovirtmgmt` bridge and moved the IP onto it, so VMs can attach to the
  management network.
- **VDSM's lab 06 shortcut is gone.** The playbook removed `ssl = false`, and the engine issued
  `/etc/pki/vdsm/certs/cacert.pem` and `vdsmcert.pem`. `vdsm-client --insecure` now just hangs,
  because the server only speaks TLS.
- **The engine never runs QEMU or touches libvirt.** It only ever talks JSON-RPC to VDSM.
- **A real-world snag:** host deploy reboots the host, and on boot cloud-init regenerates
  `/etc/hosts` (Proxmox's cloud-init sets `manage_etc_hosts: true`), wiping any names you added
  there. The playbook writes the oVirt names into cloud-init's template,
  `/etc/cloud/templates/hosts.redhat.tmpl`, as well. Two layers of automation that don't know
  about each other is a common source of "it worked until the reboot".

## Clean up

Set `ovirt_engine = false` (and `vdsm = false`) and `make up`, or `make down` for everything.
