# Build go binary, zip it for Terraform upload
build	:; bash scripts/build.sh

# Update Lambda function code - Terraform has bug where different zip is not detected
update	:; make build && aws lambda update-function-code --function-name AWS-Signer-POC --zip-file fileb://terraform/signer.zip
