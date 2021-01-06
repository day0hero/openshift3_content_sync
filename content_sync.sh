#!/bin/bash
REGISTRY=registry.redhat.io
REGISTRY_USER=<registry.redhat.io|serviceAccount>
REG_USER=<access.redhat.com|userAccount>
POOL_ID=<subscription_manager_pool_id>
PREFIX=export
SYNC_DIR=/opt/sync/content
SPLIT_DIR=/opt/sync/split
SPLIT_TARBALL="${SPLIT_DIR}"/synced-content.tar
BUNDLE_DIR="${SYNC_DIR}"/bundle
BUNDLE_TARBALL=${BUNDLE_DIR}/${PREFIX}-bundle.tar
CHUNK_SIZE=4096M

if [ $UID != 0 ]; then
  echo "You shold be root or use SUDO to run this program"
fi

#####################################################################
prereqs () {
echo "Enter the password for your CDN (access.redhat.com) account | password will be hidden"
read -s REG_PASSWORD
subscription-manager register --username ${REG_USER} --password ${REG_PASSWORD}
subscription-manager attach --pool ${POOL_ID}
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

echo "Enabling ${stringArray} repository"
subscription-manager repos --enable=rhel-7-server-rpms \
--enable=rhel-7-server-extras-rpms \
--enable=rhel-7-server-ose-3.11-rpms \
--enable=rhel-7-server-ansible-2.8-rpms \
--enable=rhel-7-server-ansible-2.9-rpms \
--enable=rhel-7-server-satellite-6.8-rpms \
--enable=rhel-7-server-satellite-maintenance-6-rpms \
--enable=rhel-server-rhscl-7-rpms 

echo "installing packages"
declare -a StringArray=("podman" "skopeo" "unzip" "createrepo" "yum-utils" "git")
for val in ${StringArray[@]}; do
  yum -y install ${val};
done

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

}

#####################################################################
ocp3 () {
echo "Configure registry authentication"
if [ -f ~/.docker/config.json ]; then
  echo "Logging into ${REGISTRY} with provided credentials"
  podman login --username ${REGISTRY_USER} registry.redhat.io --authfile ~/.docker/config.json
else
  echo "Enter service account password - password will be hidden"
  read -s registry_password
  mkdir -p ~/.docker/
  echo "Logging into ${REGISTRY} with provided credentials"
  podman login --username ${REGISTRY_USER} --password ${registry_password} registry.redhat.io --authfile ~/.docker/config.json
  echo "Credentials are stored ~/.docker/config.json"
fi

echo "Syncing OpenShift3 container images"
while read lines; do
  base=$(echo "$lines" | awk -F'[/]' '{print $2}')
  tagMod=$(echo "$lines" | awk -F'[/]' '{print $3}' | grep ':' | sed 's/:/-/')
  image=$(echo "$lines" | awk -F'[/]' '{print $3}')
  
  echo -e "Syncing ${image} to ${SYNC_DIR}/${base}/${tagMod}"
  if [[ ! -d ${base}/${tagMod} ]]; then
    mkdir -p ${SYNC_DIR}/${base}/${tagMod}
  fi

  skopeo copy --all docker://"$lines" dir:${SYNC_DIR}/${base}/${tagMod} 
done < ./images

echo "Syncing OpenShift S2I container images"
while read lines; do
  base=$(echo "$lines" | awk -F'[/]' '{print $2}')
  tagMod=$(echo "$lines" | awk -F'[/]' '{print $3}' | grep ':' | sed 's/:/-/')
  image=$(echo "$lines" | awk -F'[/]' '{print $3}')
  
  echo -e "Syncing ${image} to ${SYNC_DIR}/${base}/${tagMod}"
  if [[ ! -d ${base}/${tagMod} ]]; then
    mkdir -p ${SYNC_DIR}/${base}/${tagMod}
  fi

  skopeo copy --all docker://"$lines" dir:${SYNC_DIR}/${base}/${tagMod} 
done < ./s2i_images

}

#####################################################################
# Use this function to sync all of the rpms required for:
# - Satellite 6.8
# - OpenShift 3.11
rpms () {
declare -a stringArray=('rhel-7-server-rpms' \
'rhel-7-server-extras-rpms' \
'rhel-7-server-extras-rpms' \
'rhel-7-server-ose-3.11-rpms' \
'rhel-7-server-ansible-2.8-rpms' \
'rhel-7-server-ansible-2.9-rpms' \
'rhel-7-server-satellite-6.8-rpms' \
'rhel-7-server-satellite-maintenance-6-rpms' \
'rhel-server-rhscl-7-rpms')

echo "Running reposync"
for repo in "${stringArray[@]}"
 do
  echo "Running reposync on ${repo}"
  reposync --gpgcheck -lm --repoid=${repo} --download_path=${SYNC_DIR} 
 done

}

#####################################################################
#This function splits the syncrhonized content into predefined chunks
split () {
  echo "Creating archive of sync'd content"
    mkdir -p ${SPLIT_DIR}
    tar cvf ${SPLIT_TARBALL} ${SYNC_DIR}
    sha256sum ${SPLIT_TARBALL} >> ${SPLIT_DIR}/split-manifest.txt

  echo "Splitting "${SPLIT_TARBALL}" into ${CHUNK_SIZE} pieces to "${SPLIT_DIR}"/"${PREFIX}-" "
    /bin/split -b "${CHUNK_SIZE}" "${SPLIT_TARBALL}" "${SPLIT_DIR}"/"${PREFIX}"-
    sha256sum "${SPLIT_TARBALL}" > ${SPLIT_DIR}/content-archive-sha256sum.txt

  for chunk in ${SPLIT_DIR}/"${PREFIX}"-*; 
    do
      echo -e $(sha256sum ${chunk}) >> ${SPLIT_DIR}/split-manifest-sha256sum.txt
    done

}

#####################################################################
#This function is to re-bundle the split pieces on the airgapped environment.
bundle () {
  echo "creating "${BUNDLE_DIR}""
    mkdir -p "${BUNDLE_DIR}"

  echo "putting the chunks back together"
    /usr/bin/cat "${SPLIT_DIR}"/"${PREFIX}"-* > "${BUNDLE_DIR}"/"${PREFIX}"-bundled.tar
  
  echo "run shasum and validate that it matches"
    sha256sum ${BUNDLE_DIR}/${PREFIX}-bundled.tar > ${BUNDLE_DIR}/${PREFIX}-bundled-sha256sum.txt

}

#####################################################################
#This function is to validate the shasums between the original content
#tarball and the bundled tarball.
validate_archive () {
  echo "Validating the shasums"
    BUNDLE_ARCHIVE=$(awk '{print $1}' ${BUNDLE_DIR}/${PREFIX}-bundled-sha256sum.txt)
    CONTENT_ARCHIVE=$(awk '{print $1}' ${SPLIT_DIR}/content-archive-sha256sum.txt)

  if [[ "${BUNDLE_ARCHIVE}" == "${CONTENT_ARCHIVE}" ]] ; then
     echo "The shasums match"
    else
     echo "They don't match"
  fi

}
######################################################################
case $1 in
 prereqs)
   echo "Running pre-reqs"
   prereqs
 ;;
 bundle)
   echo "Re-Bundling the split files back into a single tarball"
   bundle
 ;;
 ocp3)
  echo "Syncing openshift images"
  ocp3
 ;;
 rpms)
  echo "Running the RPM sync"
  rpms
 ;;
 split)
  echo "Splitting the content"
  split
 ;;
 sync)
  echo "Sync openshift, satellite images and rpms then splitting"
   prereqs
   ocp3
   rpms
   split
 ;;
 validate)
  echo "Validate the shasums"
    validate_archive
 ;;
 *)
  echo -e "Usage: content_sync.sh <argument>
           prereqs  : Registers to CDN and installs packages
           bundle   : Puts content chunks back into single file
           ocp3     : Syncs OpenShift and S2I images 
           rpms     : Syncs RPMs for OpenShift and Satellite products
           split    : Splits content into moveable chunks
           sync     : Downloads and splits content into moveable chunks
           validate : Validate the sha256sum's from the content archive and bundle archive"
 ;;
esac
