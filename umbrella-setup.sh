#!/bin/bash
set -e

echo "=== CyberMaxx Umbrella AWS Setup ==="

USER_NAME="CyberMaxx-Umbrella-SIEM"
POLICY_NAME="CyberMaxx-Umbrella"

# ===== CREATE POLICY FILE =====
cat <<EOF > policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadForElasticIngestion",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:GetObject"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# ===== CREATE OR GET POLICY =====
POLICY_ARN=$(aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document file://policy.json \
  --query 'Policy.Arn' \
  --output text 2>/dev/null || \
aws iam list-policies \
  --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" \
  --output text)

# ===== CREATE USER (SAFE) =====
aws iam create-user --user-name "$USER_NAME" 2>/dev/null || true

# ===== ATTACH POLICY =====
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn "$POLICY_ARN"

# ===== CREATE ACCESS KEY =====
KEY_OUTPUT=$(aws iam create-access-key --user-name "$USER_NAME")

ACCESS_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
SECRET_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')

# ===== SAVE CREDENTIALS =====
echo "AccessKeyId: $ACCESS_KEY" > CyberMaxxUmbrellaCreds.txt
echo "SecretAccessKey: $SECRET_KEY" >> CyberMaxxUmbrellaCreds.txt

chmod 600 CyberMaxxUmbrellaCreds.txt

# ===== OUTPUT (NO SECRETS) =====
echo ""
echo "===== CYBERMAXX UMBRELLA SETUP COMPLETE ====="
echo "Credentials saved to: CyberMaxxUmbrellaCreds.txt"
echo "Run: cat CyberMaxxUmbrellaCreds.txt"
echo "After copying, delete the file:"
echo "rm CyberMaxxUmbrellaCreds.txt"
echo "============================================"

# cleanup
rm -f policy.json
