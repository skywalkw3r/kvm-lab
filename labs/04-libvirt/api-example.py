#!/usr/bin/env python3
"""The libvirt API in a few lines. `virsh` is just a CLI over these same calls,
and so are the management layers in labs 06-08 (VDSM is written in Python on
exactly these bindings)."""
import libvirt

STATES = {
    libvirt.VIR_DOMAIN_RUNNING: "running",
    libvirt.VIR_DOMAIN_PAUSED: "paused",
    libvirt.VIR_DOMAIN_SHUTOFF: "shut off",
}

def version(v):
    """libvirt encodes versions as major * 1,000,000 + minor * 1,000 + release."""
    return f"{v // 1_000_000}.{v // 1_000 % 1_000}.{v % 1_000}"


conn = libvirt.open("qemu:///system")
print(f"hypervisor: {conn.getType()} {version(conn.getVersion())} on {conn.getHostname()}, "
      f"libvirt {version(conn.getLibVersion())}, {conn.getInfo()[2]} host CPUs")

for dom in conn.listAllDomains():
    state, _, mem_kib, vcpus, cpu_ns = dom.info()
    print(f"  {dom.name():<14} {STATES.get(state, state):<9} "
          f"{vcpus} vCPU  {mem_kib // 1024} MiB  {cpu_ns / 1e9:.1f}s CPU used")
conn.close()
