#!/usr/bin/env bash
set -euo pipefail

# =========================
# CyberMaxx AWS IAM Setup
# Creates/ensures:
#   - IAM Policy: CyberMaxx-CloudTrail
#   - IAM User:   CyberMaxx-Cloud
#   - Attaches policy to user
#   - Creates access key and writes CyberMaxxCreds.txt
# =========================

USER_NAME="${USER_NAME:-CyberMaxx-Cloud}"
POLICY_NAME="${POLICY_NAME:-CyberMaxx-CloudTrail}"
OUT_FILE="${OUT_FILE:-CyberMaxxCreds.txt}"

echo "=== CyberMaxx AWS Setup ==="
echo "User:   ${USER_NAME}"
echo "Policy: ${POLICY_NAME}"
echo

# ---- prereqs
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found. Run in AWS CloudShell or install awscli." >&2; exit 1; }

# jq is optional; we can do --query/--output instead
HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; fi

# ---- write policy doc locally
cat > policy.json <<'EOF'
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

# ---- ensure policy exists and capture ARN
echo "Ensuring policy exists..."
POLICY_ARN="$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn | [0]" \
  --output text 2>/dev/null || true)"

if [[ -z "${POLICY_ARN}" || "${POLICY_ARN}" == "None" ]]; then
  POLICY_ARN="$(aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file://policy.json \
    --query 'Policy.Arn' \
    --output text)"
  echo "Created policy: ${POLICY_ARN}"
else
  echo "Policy already exists: ${POLICY_ARN}"
fi

# ---- ensure user exists
echo "Ensuring user exists..."
if aws iam get-user --user-name "${USER_NAME}" >/dev/null 2>&1; then
  echo "User already exists: ${USER_NAME}"
else
  aws iam create-user --user-name "${USER_NAME}" >/dev/null
  echo "Created user: ${USER_NAME}"
fi

# ---- attach policy (idempotent)
echo "Attaching policy to user..."
aws iam attach-user-policy --user-name "${USER_NAME}" --policy-arn "${POLICY_ARN}" >/dev/null
echo "Attached."

# ---- create access key
# NOTE: IAM users can have max 2 access keys. If you hit that limit, you'll need to delete an older key.
echo "Creating access key..."
if [[ "${HAVE_JQ}" -eq 1 ]]; then
  KEY_JSON="$(aws iam create-access-key --user-name "${USER_NAME}")"
  ACCESS_KEY_ID="$(echo "${KEY_JSON}" | jq -r '.AccessKey.AccessKeyId')"
  SECRET_ACCESS_KEY="$(echo "${KEY_JSON}" | jq -r '.AccessKey.SecretAccessKey')"
else
  # no jq: use --query/--output
  ACCESS_KEY_ID="$(aws iam create-access-key --user-name "${USER_NAME}" --query 'AccessKey.AccessKeyId' --output text)"
  SECRET_ACCESS_KEY="$(aws iam list-access-keys --user-name "${USER_NAME}" --query 'AccessKeyMetadata[0].AccessKeyId' --output text >/dev/null 2>&1 || true)"
  # Re-fetch secret by creating a new key with both fields in one call:
  # (We already created a key above; so we do it again properly without jq)
  read -r ACCESS_KEY_ID SECRET_ACCESS_KEY <<<"$(aws iam create-access-key \
    --user-name "${USER_NAME}" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' \
    --output text)"
fi

# ---- write output file (match your current format)
cat > "${OUT_FILE}" <<EOF
AccessKeyId: ${ACCESS_KEY_ID}
SecretAccessKey: ${SECRET_ACCESS_KEY}
EOF

echo
echo "===== PROVIDE TO CYBERMAXX ====="
echo "AccessKeyId: ${ACCESS_KEY_ID}"
echo "SecretAccessKey: ${SECRET_ACCESS_KEY}"
echo "Saved to: ${OUT_FILE}"
echo "================================"
echo
echo "TIP: Download the file from CloudShell (Actions -> Download file) and then remove local artifacts:"
echo "     rm -f ${OUT_FILE} policy.json"
