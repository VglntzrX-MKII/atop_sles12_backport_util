#!/bin/bash
set -e

CUR_DIR=$(pwd)
WORKSPACE="$CUR_DIR/atop_rpm_build"
ATOP_VERSION="2.12.1"
SOURCE_TARBALL="atop-${ATOP_VERSION}.tar.gz"

echo ">>> Preparing workspace..."
mkdir -p "$WORKSPACE"/{SOURCES,SPECS,BUILD,RPMS,SRPMS,BUILDROOT}

echo ">>> Installing dependencies..."
sudo zypper install -y gcc make ncurses-devel zlib-devel glib2-devel rpm-build tar wget

if [ ! -f "$WORKSPACE/SOURCES/$SOURCE_TARBALL" ]; then
    wget "https://www.atoptool.nl/download/$SOURCE_TARBALL" -O "$WORKSPACE/SOURCES/$SOURCE_TARBALL"
fi

echo ">>> Creating Spec file..."
cat << 'EOF' > "$WORKSPACE/SPECS/atop.spec"
Name:           atop
Version:        2.12.1
Release:        1
Summary:        Advanced System and Process Monitor
License:        GPLv2+
Source0:        atop-2.12.1.tar.gz
BuildRequires:  gcc, make, ncurses-devel, zlib-devel, glib2-devel

%description
Atop is an interactive monitor to view the load on a Linux system.

%prep
%setup -q

%build
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/sbin
mkdir -p %{buildroot}/usr/share/man/man1
mkdir -p %{buildroot}/usr/share/man/man5
mkdir -p %{buildroot}/usr/share/man/man8
mkdir -p %{buildroot}/etc/default
mkdir -p %{buildroot}/usr/lib/systemd/system
mkdir -p %{buildroot}/usr/lib/systemd/system-sleep

make install DESTDIR=%{buildroot}

# Fix paths for SLES 12 compatibility
if [ -d %{buildroot}/lib/systemd/system ]; then
    mv %{buildroot}/lib/systemd/system/* %{buildroot}/usr/lib/systemd/system/
fi
if [ -d %{buildroot}/lib/systemd/system-sleep ]; then
    mv %{buildroot}/lib/systemd/system-sleep/* %{buildroot}/usr/lib/systemd/system-sleep/
fi

%files
%defattr(-,root,root)
/usr/bin/atop*
/usr/sbin/atop*
/etc/default/atop
/usr/share/man/man*/*
/usr/lib/systemd/system/atop.service
/usr/lib/systemd/system/atopacct.service
/usr/lib/systemd/system/atop-rotate.service
/usr/lib/systemd/system/atop-rotate.timer
/usr/lib/systemd/system/atopgpu.service
/usr/lib/systemd/system-sleep/*
EOF

echo ">>> Starting RPM build..."
rpmbuild --define "_topdir $WORKSPACE" -ba "$WORKSPACE/SPECS/atop.spec"

cp "$WORKSPACE"/RPMS/x86_64/atop-${ATOP_VERSION}-1.x86_64.rpm "$CUR_DIR/"

echo "-------------------------------------------------------"
echo "DONE! Your RPM is at: $CUR_DIR/atop-${ATOP_VERSION}-1.x86_64.rpm"
echo "-------------------------------------------------------"
