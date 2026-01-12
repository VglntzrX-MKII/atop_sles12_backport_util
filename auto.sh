  #!/bin/bash

# --- Configuration & Colors ---
set -e
CUR_DIR=$(pwd)
WORKSPACE="$CUR_DIR/atop_rpm_build"
DOWNLOAD_URL="https://www.atoptool.nl/downloadatop.php"

# Color Codes
RED='\033[38;5;196m'
GREEN='\033[38;5;40m'
YELLOW='\033[38;5;220m'
BLUE='\033[38;5;33m'
PURPLE='\033[38;5;93m'
NC='\033[0m'

# --- UI Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_tweak()   { echo -e "${PURPLE}[TWEAK]${NC} $1"; }

# Animated Spinner for long tasks
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# --- 1. Prepare Patch Content ---
PATCH_LOGIC='
# Inject Headers
sed -i "/include <sys\/times.h>/a #include <unistd.h>\\n#include <stdio.h>\\n#include <string.h>" rawlog.c

# Inject Helper Function (Using cat to avoid printf escaping issues)
cat << "EOF_HELPER" > h_helper.c
static char *get_atop_prefix(void) { 
    static char p[128]; 
    if (p[0] == 0) { 
        char h[64] = {0};
        if (gethostname(h, sizeof(h)-1) == 0 && h[0] != 0) {
            snprintf(p, sizeof(p), "atop_%s", h); 
        } else {
            snprintf(p, sizeof(p), "atop_unknown");
        }
    } 
    return p; 
}
EOF_HELPER
sed -i "/include <unistd.h>/r h_helper.c" rawlog.c
rm h_helper.c

# Surgical String Replacement
sed -i "s#\"%s/atop_#\"%s/%s_#g" rawlog.c
sed -i "/snprintf.*irawname.*%s\/%s_/,/BASEPATH/ s/BASEPATH,/BASEPATH, get_atop_prefix(),/" rawlog.c

# Service file change
sed -i "s|atop_\\\$(date|atop_\\\$(hostname)_\\\$(date|g" atop.service
'

# --- 2. Auto-detect Latest Version ---
log_info "Checking for the latest version of atop..."
# Scrapes the download page for the first mention of atop-X.XX.X.tar.gz
ATOP_VERSION=$(curl -s $DOWNLOAD_URL | grep -oP 'atop-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.gz)' | head -n 1)

if [ -z "$ATOP_VERSION" ]; then
    log_error "Could not detect latest version. Falling back to 2.12.1."
    ATOP_VERSION="2.12.1"
fi

SOURCE_TARBALL="atop-${ATOP_VERSION}.tar.gz"
log_success "Detected version: ${YELLOW}$ATOP_VERSION${NC}"

# --- 3. Prepare Workspace ---
log_info "Preparing workspace at $WORKSPACE..."
mkdir -p "$WORKSPACE"/{SOURCES,SPECS,BUILD,RPMS,SRPMS,BUILDROOT}

# --- 4. Install Dependencies ---
log_info "Installing build dependencies (sudo may be required)..."
(sudo zypper install -y gcc make ncurses-devel zlib-devel glib2-devel rpm-build tar wget > /dev/null 2>&1) &
spinner $!
log_success "Dependencies installed."

# --- 5. Download Source ---
if [ ! -f "$WORKSPACE/SOURCES/$SOURCE_TARBALL" ]; then
    log_info "Downloading $SOURCE_TARBALL..."
    # Simplified wget call to ensure compatibility
    wget -q "https://www.atoptool.nl/download/$SOURCE_TARBALL" -O "$WORKSPACE/SOURCES/$SOURCE_TARBALL"
    
    # Check if download actually succeeded
    if [ $? -ne 0 ]; then
        log_error "Download failed! Please check your internet connection."
        exit 1
    fi
else
    log_warn "Source tarball already exists, skipping download."
fi

# --- 6. Create Spec File ---
log_info "Generating RPM Spec file for version $ATOP_VERSION..."

log_tweak "Fixing Service file Writer (ExecStart) file name formatting"
log_tweak "Fixing Binary Reader (rawfile.c) file name formatting"

cat << EOF > "$WORKSPACE/SPECS/atop.spec"
Name:           atop
Version:        ${ATOP_VERSION}
Release:        1
Vendor:         SUSE LLC <https://www.suse.com/>
URL:            https://www.atoptool.nl
Packager:       Gerlof Langeveld <gerlof.langeveld@atoptool.nl>
Summary:        Advanced System and Process Monitor
License:        GPLv2+
Group: 	        System Environment
Source0:        ${SOURCE_TARBALL}
BuildRequires:  gcc, make, ncurses-devel, zlib-devel, glib2-devel

%description
The program atop is an interactive monitor to view the load on
a Linux-system. It shows the occupation of the most critical
hardware-resources (from a performance point of view) on system-level,
i.e. cpu, memory, disk and network. It also shows which processess
(and threads) are responsible for the indicated load (again cpu-,
memory-, disk- and network-load on process-level).
The program atop can also be used to log system- and process-level
information in raw format for long-term analysis.

The program atopsar can be used to view system-level statistics
as reports.

%prep
%setup -q

# The logic below is injected from the master script variable
$PATCH_LOGIC

%build
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/sbin
mkdir -p %{buildroot}/etc/default
mkdir -p %{buildroot}/usr/lib/systemd/system

make install DESTDIR=%{buildroot}

# --- Tweak: Fix paths for SLES compatibility ---
if [ -d %{buildroot}/lib/systemd/system ]; then
    mv %{buildroot}/lib/systemd/system/* %{buildroot}/usr/lib/systemd/system/
fi
if [ -d %{buildroot}/lib/systemd/system-sleep ]; then
    mkdir -p %{buildroot}/usr/lib/systemd/system-sleep/
    mv %{buildroot}/lib/systemd/system-sleep/* %{buildroot}/usr/lib/systemd/system-sleep/
fi


# --- Tweak: Remove versioned binaries ---
find %{buildroot}/usr/bin -type l -name "*-%{version}" -delete
find %{buildroot}/usr/bin -type f -name "*-%{version}" -delete

%files
%defattr(-,root,root)
# Include all atop binaries
/usr/bin/atop*
/usr/sbin/atop*
# Use %exclude with a wildcard to prevent the versioned doubles
%exclude /usr/bin/*-%{version}

/etc/default/atop
/usr/share/man/man*/*
/usr/lib/systemd/system/atop*
/usr/lib/systemd/system-sleep/*
EOF

log_tweak "Fixing paths for SLES compatibility"
log_tweak "Removing duplicated versioned binaries"

# --- 7. Build RPM ---
log_info "Starting RPM build (this may take a minute)..."
(rpmbuild --define "_topdir $WORKSPACE" -ba "$WORKSPACE/SPECS/atop.spec" > "$WORKSPACE/build.log" 2>&1) &
spinner $!

if [ $? -eq 0 ]; then
    cp "$WORKSPACE"/RPMS/x86_64/atop-${ATOP_VERSION}-1.x86_64.rpm "$CUR_DIR/"
    echo -e "\n-------------------------------------------------------"
    log_success "Build Complete!"
    log_info "Your RPM is at: ${YELLOW}$CUR_DIR/atop-${ATOP_VERSION}-1.x86_64.rpm${NC}"
    echo "-------------------------------------------------------"
else
    log_error "Build failed! Check log at $WORKSPACE/build.log"
    exit 1
fi
