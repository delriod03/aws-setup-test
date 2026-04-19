#!/bin/bash
set -e

echo "=== CyberMaxx AWS Setup ==="

USER_NAME="CyberMaxx-Cloud"
POLICY_NAME="CyberMaxx-CloudTrail"

# ===== CREATE POLICY FILE =====
cat <<EOF > policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:GetObject"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "ce:GetCostAndUsage",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "inspector2:ListFindings",
        "logs:DescribeLogGroups",
        "logs:FilterLogEvents",
        "organizations:ListAccounts",
        "rds:DescribeDBInstances",
        "rds:ListTagsForResource",
        "iam:ListAccountAliases",
        "sns:ListTopics",
        "tag:GetResources"
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

# ===== SAVE CREDENTIALS (SECURE FILE) =====
echo "AccessKeyId: $ACCESS_KEY" > CyberMaxxCreds.txt
echo "SecretAccessKey: $SECRET_KEY" >> CyberMaxxCreds.txt

chmod 600 CyberMaxxCreds.txt

# ===== OUTPUT (NO SECRETS) =====
echo ""
echo "===== CYBERMAXX SETUP COMPLETE ====="
echo "Credentials saved to: CyberMaxxCreds.txt"
echo "Run: cat CyberMaxxCreds.txt"
echo "After copying, delete the file with:"
echo "rm CyberMaxxCreds.txt"
echo "===================================="

# cleanup
rm -f policy.json
