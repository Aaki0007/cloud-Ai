#!/bin/bash
awslocal s3 rm s3://chatbot-conversations --recursive
terraform destroy -auto-approve
rm -rf package/ lambda_function.zip
mkdir -p package
pip install -r requirements.txt -t ./package
cp handler.py package/
terraform init
terraform apply -auto-approve
bash -c "while true; do awslocal lambda invoke --function-name telegram-bot out.json && cat out.json | jq ; sleep 1; done"
