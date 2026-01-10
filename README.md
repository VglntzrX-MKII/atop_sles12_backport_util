# Atop Backport Utility for SLES 12

This repository contains an automated build tool designed to backport modern versions of the **atop** system monitor to **SUSE Linux Enterprise Server (SLES) 12**.

SLES 12 often lags behind upstream performance monitoring tools in its official repositories since it is out of support.
This script bridges that gap by automating the compilation and RPM packaging process, ensuring modern features are available in legacy enterprise environments while respecting SLES 12's specific file system hierarchy.

---

## Technical Specifications

| Requirement | Details |
| --- | --- |
| **Target OS** | SLES 12 (SP1 through SP5) |
| **Architecture** | x86_64 |
| **Language** | Bash |
| **Build System** | RPM Build |
| **Dependencies** | GCC, Make, ncurses-devel, zlib-devel, glib2-devel |

---

## Installation and Usage

### 1. Preparation

Ensure you have the SLES 12 SDK or "Development Tools" module enabled in your SUSE registration settings, as this provides the necessary headers for compilation.

### 2. Execute Build

Run the script directly on a SLES 12 build host:

```bash
chmod +x build_atop.sh
./build_atop.sh

```

### 3. Install Resulting RPM

The script outputs the completed RPM package to your current working directory. Install it locally using `zypper`:

```bash
sudo zypper --no-gpg-checks install --force-resolution atop-[version]-1.x86_64.rpm

```

---

## Workflow Logic

The utility follows a structured pipeline to ensure a clean backport:

1. **Environment Audit**: Checks for existing build tools and installs missing dependencies via `sudo zypper`.
2. **Source Retrieval**: Downloads the latest `.tar.gz` from the official atop tool repository.
3. **Spec Generation**: Dynamically writes a `SPEC` file that includes instructions for handling SLES-specific service file locations.
4. **Compilation**: Executes `rpmbuild` and captures all output to `build.log` for troubleshooting.
5. **Artifact Deployment**: Extracts the finished binary package to the current directory for easy access.

---

## Multi-Server Deployment (Optional)

Once the RPM is built, you can deploy it across multiple SLES 12 nodes using existing automation tools.

### Using Ansible

```yaml
- name: Deploy backported atop to SLES 12 nodes
  hosts: sles12_servers
  tasks:
    - name: Copy RPM to target
      copy:
        src: ./atop-{{ atop_version }}-1.x86_64.rpm
        dest: /tmp/atop.rpm

    - name: Install RPM using zypper
      zypper:
        name: /tmp/atop.rpm
        state: present
        disable_gpg_check: yes

```

### Using SaltStack

```bash
salt 'sles12-*' cp.get_file salt://files/atop-v2.12-1.x86_64.rpm /tmp/atop.rpm
salt 'sles12-*' cmd.run 'zypper --non-interactive install /tmp/atop.rpm'

```

---

## Troubleshooting

If the build fails, refer to the generated log file located at:
`./atop_rpm_build/build.log`

Common issues in legacy SLES 12 environments:

* **Missing SDK**: If `ncurses-devel` cannot be found, verify the SLES SDK repository is enabled.
* **Permissions**: The script requires `sudo` access to install build-time dependencies.
