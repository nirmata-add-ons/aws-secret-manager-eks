#!/bin/bash

# Step 1: Setting up Secrets Store CSI driver installed
kubectl apply -f secrets-store-csi-driver.yaml

# Step 2: Installing the AWS Provider
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

# Step 3: Permission and policy
REGION="$1"
CLUSTERNAME="$2"

if [ -z "$REGION" ] || [ -z "$CLUSTERNAME" ]; then
  echo "Please provide the REGION and CLUSTERNAME values as arguments."
  exit 1
fi

POLICY_NAME="secret-manager-policy"
POLICY_ARN=$(aws --region "$REGION" iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
  POLICY_ARN=$(aws --region "$REGION" iam create-policy --policy-name "$POLICY_NAME" --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        "Resource": ["*"]
    }]
  }' --query Policy.Arn --output text)

  if [ $? -ne 0 ]; then
    echo "Failed to create IAM policy."
    exit 1
  fi
fi

echo "$POLICY_ARN"


# Step 5: Associate IAM OIDC provider with the cluster.
  eksctl utils associate-iam-oidc-provider --region "$REGION" --cluster "$CLUSTERNAME" --approve # Only run this once

# Step 4: Check if the IAM OIDC provider is already associated with the cluster
#OIDC_PROVIDER=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTERNAME" --query "cluster.identity.oidc.issuer" --output text)

#if [ -z "$OIDC_PROVIDER" ]; then
#  echo "IAM OIDC provider is not associated with the cluster. Proceeding with association..."
#  eksctl utils associate-iam-oidc-provider --region "$REGION" --cluster "$CLUSTERNAME" --approve # Only run this once
#  if [ $? -ne 0 ]; then
#    echo "Failed to associate IAM OIDC provider with the cluster."
#    exit 1
#  fi
#else
#  echo "IAM OIDC provider is already associated with the cluster."
#fi

# Step 5: Next, create the service account to be used by the pod and associate the above IAM policy with that service account. For this example, we use secret-sa for the service account name
eksctl create iamserviceaccount --name secret-sa --region "$REGION" --cluster "$CLUSTERNAME" --attach-policy-arn "$POLICY_ARN" --approve --override-existing-serviceaccounts

if [ $? -ne 0 ]; then
  echo "Failed to create IAM service account."
  exit 1
fi
