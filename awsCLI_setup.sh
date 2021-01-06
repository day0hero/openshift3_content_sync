#!/bin/bash

ACCESS_KEY_ID=
ACCESS_KEY=
REGION=

aws_credentials() {
echo "Making directory for aws credentials"
  mkdir -p ~/.aws

cat << EOF > ~/.aws/credentials
[default]
aws_access_key_id = ${ACCESS_KEY_ID}
aws_secret_access_key = ${ACCESS_KEY}
region = ${REGION}
EOF
}

aws_cli_setup () {
echo "Installing unzip"
if [ $(rpm -qa | grep unzip > /dev/null; echo $?) != 0 ]; then
  yum -y install unzip
fi
echo "Downloading awsCLI: https://s3.amazonaws.com/aws-cli/awscli-bundle.zip"
 curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
 unzip awscli-bundle.zip
 ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws

 echo "removing aws artifacts"
 rm -rf ./awscli-bundle awscli-bundle.zip
}

aws_credentials
aws_cli_setup
