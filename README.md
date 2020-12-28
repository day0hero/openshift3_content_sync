# openshift3_content_sync
Use this program to download all of the rpms and container images from access.redhat.com and
registry.redhat.io to support the installation of OpenShift 3, and Satellite 6.x
- skopeo
- split
- cat

### Requirements
A Red Hat subscription is required to run this script as well as a Service Account used for
registry.redhat.io

This program can be run with the individual pieces or let the program do it all. 

#### To run al a carte:
```bash 
./content_sync.sh <option>

Options:
  - prereqs
  - ocp3_sync
  - rpm_sync
  - split
  - sync 
  - bundle
```
|option|description|
|------|-----------|
|prereqs| Configures authentication for `registry.redhat.io`|
|ocp3_sync|This function is for logging into the red hat registry and pulling images required for OpenShift3|
|split|Takes the downloaded content, creates archive and then splits into `4096M` chunks|
|sync|Runs the prereqs, ocp3_sync, rpm_sync and split functions in a single call|
|bundle|Uses `cat` to put the pieces back together on the air-gapped side|
