#!/bin/bash

REGISTRY=registry.redhat.io
SYNC_PATH=/opt/sync
REGISTRY_USER='<registry.io_ServiceAccount>'
REG_USER='<redhat_portal_username>'
POOL_ID='<subscription_pool_id>'
SYNC_DIR=/opt/sync
BUNDLE_TARBALL=<name_of_bundle_tarball> # Disconnected name of repackaged tarball #
BUNDLE_DIR=${SYNC_PATH}/data
PREFIX=export
CHUNK_SIZE=4096M


if [ $UID != 0 ]; then
  echo "You must be root to run this program"
fi

prereqs () {
echo "installing prereq packages"
declare -a StringArray=("podman" "skopeo" "unzip" "createrepo" "yum-utils")
for val in ${StringArray[@]}; do
  yum -y install ${val};
done

if [ -f ~/.docker/config.json ]; then
  echo "Logging into ${REGISTRY} with provided credentials"
  podman login --username ${REGISTRY_USER} --password ${registry_password} registry.redhat.io --authfile ~/.docker/config.json
else
  echo "Enter service account password - password will be masked"
  read -s registry_password

  mkdir -p ~/.docker/
  echo "Logging into ${REGISTRY} with provided credentials"
  podman login --username ${REGISTRY_USER} --password ${registry_password} registry.redhat.io --authfile ~/.docker/config.json
  echo "Credentials are stored ~/.docker/config.json"
fi
}

ocp3_sync () {
echo "Syncing OpenShift3 container images"
while read lines; do
  base=$(echo "$lines" | awk -F'[/]' '{print $2}')
  tagMod=$(echo "$lines" | awk -F'[/]' '{print $3}' | grep ':' | sed 's/:/-/')
  image=$(echo "$lines" | awk -F'[/]' '{print $3}')

  echo -e "Syncing ${image} to ${SYNC_PATH}/${base}/${tagMod}"
  if [[ ! -d ${base}/${tagMod} ]]; then
    mkdir -p ${SYNC_PATH}/${base}/${tagMod}
  fi

  skopeo copy --all docker://"$lines" dir:${SYNC_PATH}/${base}/${tagMod}
done < ./images

echo "Syncing OpenShift S2I container images"
while read lines; do
  base=$(echo "$lines" | awk -F'[/]' '{print $2}')
  tagMod=$(echo "$lines" | awk -F'[/]' '{print $3}' | grep ':' | sed 's/:/-/')
  image=$(echo "$lines" | awk -F'[/]' '{print $3}')

  echo -e "Syncing ${image} to ${SYNC_PATH}/${base}/${tagMod}"
  if [[ ! -d ${base}/${tagMod} ]]; then
    mkdir -p ${SYNC_PATH}/${base}/${tagMod}
  fi

  skopeo copy --all docker://"$lines" dir:${SYNC_PATH}/${base}/${tagMod}
done < ./s2i_images
}

rpm_sync () {
echo "Enter the password for your CDN account | password will be masked"
read -s REG_PASSWORD
#
subscription-manager register --username ${REG_USER} --password ${REG_PASSWORD}
#
subscription-manager attach --pool ${POOL_ID}
#
subscription-manager repos --disable='*'

declare -a stringArray=('rhel-7-server-rpms' \
'rhel-7-server-extras-rpms' \
'rhel-7-server-extras-rpms' \
'rhel-7-server-ose-3.11-rpms' \
'rhel-7-server-ansible-2.8-rpms' \
'rhel-7-server-ansible-2.9-rpms' \
'rhel-7-server-satellite-6.8-rpms' \
'rhel-7-server-satellite-maintenance-6-rpms' \
'rhel-server-rhscl-7-rpms')

for val in "${stringArray[@]}";
 do
  echo "Enabling ${val}";
  subscription-manager repos --enable=${val} ;
 done

echo "install packages to begin syncing rpms from CDN"
sudo yum -y install createrepo git yum-utils

if [ -z "${SYNC_DIR}" ]; then
  echo "Absolute path where content should be sync'd | ex: /tmp/sync"
  read SYNCDIR
  if [ -z "${SYNCDIR}" ]; then
    echo "Default directory created: /tmp/sync"
    mkdir -p /tmp/sync
    SYNC_DIR=${SYNCDIR}
  else
    echo "Creating ${SYNCDIR}"
    mkdir -p ${SYNCDIR}
    SYNC_DIR=${SYNCDIR}
  fi
else
  echo "Creating ${SYNC_DIR}"
  mkdir -p ${SYNC_DIR}
fi

echo "Running reposync"
for repo in "${stringArray[@]}"
 do
  echo "Running reposync on ${repo}"
  reposync --gpgcheck -lm --repoid=${repo} --download_path=${SYNC_DIR}
 done
}

#This function splits the syncrhonized content into predefined chunks
split () {
  echo "Splitting "${BUNDLE_TARBALL}" into ${CHUNK_SIZE} pieces"
  split -b ${CHUNK_SIZE} "${BUNDLE_TARBALL}" "${BUNDLE_DIR}"/${PREFIX}
  for chunk in ${BUNDLE_DIR}/*;
    do
      echo -e $(sha256sum ${chunk}) >> ${BUNDLE_DIR}/bundle_split-manifest.txt
    done
}

#This function is to re-bundle the split pieces on the airgapped environment.
bundle () {
echo "putting the chunks back together"
cat ${BUNDLE_DIR}/${PREFIX}* > ${BUNDLE_DIR}/${PREFIX}-bundled.tar

echo "run shasum and validate that it matches"
sha256sum ${BUNDLE_DIR}/${PREFIX}-bundled.tar > ${PREFIX}-bundled-sha.txt
}

case $1 in
 sync)
  echo "Running the pre-requisite function"
   prereqs
  echo "Running the OCP3 image sync"
   ocp3_sync
  echo "Running the RPM sync"
   rpm_sync
  echo "Splitting the content"
   split
 ;;
 bundle)
   echo "Re-Bundling the split files back into a single tarball"
   bundle
 ;;
 *)
  echo -e "Usage: content_sync.sh <argument>
            ./content_sync.sh sync
            ./content_sycn.sh bundle
           bundle   : Puts content chunks back into single file
           sync     : Downloads and splits content into moveable chunks"
 ;;
