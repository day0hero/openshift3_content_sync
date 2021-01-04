# openshift3_content_sync
Use this program to download all of the rpms and container images from access.redhat.com and
registry.redhat.io to support the installation of OpenShift 3, and Satellite 6.x using the following:
- skopeo
- split
- cat

### Machine Requirements 
- RHEL 7.x
- 4GB RAM
- 4vCPU
- 600Gb data disk 
-- Total Used after sync and archive: 

### Account Requirements
This program requires a subscription for:
- Red Hat Enterprise Linux 7
- Red Hat Satellite (if syncing Satellite RPMS)
- Red Hat OpenShift 

A service account for `registry.redhat.io` is also required.

`This program can be run with the individual pieces or let the program do it all.`

#### To run al a carte:
```bash 
./content_sync.sh <option>

Options:
  - prereqs
  - ocp3
  - rpms
  - split
  - sync 
  - bundle
```
|option|description|
|------|-----------|
|prereqs| Authenticates to registry and CDN: Enables repositories and creates directory scaffolding |
|ocp3| Syncs container images required for OCP3 installation and S2I templates |
|split|Creates archive of content,and splits into user defined chunks|
|sync|Executes all functions except for bundle|
|bundle| Bundles the split chunks back into a single archive |
