#!/bin/bash

CURR_DIR=$(pwd)
PYCLOUDSTACK_PATH="$CURR_DIR/tdx-tools/utils/pycloudstack"
PYTDXMEASURE_PATH="$CURR_DIR/tdx-tools/utils/pytdxmeasure"

REQUIRED_PACKAGES=(
  python3-libvirt
  libvirt-devel
  python36-devel
  python3-pip
)

# Check whether required packages already been installed.
for package in "${REQUIRED_PACKAGES[@]}"; do
  dnf list installed | grep $package 2>&1 >/dev/null
  if [ ! $? -eq 0 ]; then
    echo "Please install package $package via dnf."
    return 1
  fi
done

# Setup the python virtualenv
if [[ ! -d ${CURR_DIR}/venv ]]; then
  python3 -m virtualenv -p python3 ${CURR_DIR}/venv
  source ${CURR_DIR}/venv/bin/activate
  pip3 install -r requirements.txt
  if [ ! $? -eq 0 ]; then
    echo "Fail to install python PIP packages, please check your proxy (https_proxy) or setup PyPi mirror."
    deactivate
    rm ${CURR_DIR}/venv -fr
    return 1
  fi
else
  source ${CURR_DIR}/venv/bin/activate
fi

# Install tests_tdx into the PYTHON path, so you can use "python3 -m pytest tests_tdx/xxx.py" to
# run the case module individually
export PYTHONPATH=$PYTHONPATH:$CURR_DIR/tests_tdx

# Add pycloudstack into PYTHONPATH in case not installing it via pip3
if [[ -d $PYCLOUDSTACK_PATH ]]; then
  if [[ $(pip3 list | grep "pycloudstack") ]]; then
    echo "pycloudstack is already installed but will be replaced by $PYCLOUDSTACK_PATH"
  fi

  # pycloudstack package could be installed via "pip3" or copied to $PYCLOUDSTACK_PATH
  export PYTHONPATH=$PYCLOUDSTACK_PATH:$PYTHONPATH
fi

# Add pytdxmeasure into PYTHONPATH for guest testing in case not installing it via pip3
if [[ -d $PYTDXMEASURE_PATH ]]; then
  if [[ $(pip3 list | grep "pytdxmeasure") ]]; then
    echo "pytdxmeasure is already installed but will be replaced by $PYTDXMEASURE_PATH"
  fi

  # pytdxmeasure package could be installed via "pip3" or copied to $PYTDXMEASURE_PATH
  export PYTHONPATH=$PYTDXMEASURE_PATH:$PYTHONPATH
fi

# Check whether virt-customize tool was installed
if ! command -v virt-customize &>/dev/null; then
  echo WARNING! Please \"dnf install libguestfs-tools\"
  return 1
fi

# Check whether libvirt service started
if [[ ! $(systemctl --all --type service | grep "libvirtd") ]]; then
  echo WARNING! Please \"dnf install intel-mvp-tdx-libvirt\" then \"systemctl start libvirtd\"
  return 1
fi

# Check whether virtual bridge virbr0 was created
if [[ ! $(ip a | grep virbr0) ]]; then
  echo WARNING! Please enable virbr0 via \"virsh net-start default\", you may need remove firewall via \"dnf remove firewalld\"
  return 1
fi

# Check whether current user belong to libvirt
if [[ ! $(id -nG "$USER") == *"libvirt"* ]]; then
  echo WARNING! Please add user "$USER" into group "libvirt" via \"sudo usermod -aG libvirt $USER\"
  return 1
fi

#
# Start from qemu 6.2's commit: https://github.com/qemu/qemu/commit/5dacda5167560b3af8eadbce5814f60ba44b467e.
# LIBGUESTFS_BACKEND=direct is required
#
export LIBGUESTFS_BACKEND=direct
