#!/bin/bash

cd signer-lambda
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -tags lambda.norpc -o bootstrap handler.go
zip signer.zip bootstrap
mv signer.zip ../terraform/signer.zip
rm -rf bootstrap
cd ..