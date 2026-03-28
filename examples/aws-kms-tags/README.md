# AWS KMS Key Tagging

This example demonstrates how to configure custom tags for AWS KMS keys created by the SPIRE server.

## Configuration

The AWS KMS KeyManager supports tagging of KMS keys with user-defined tags:

| Parameter                     | Description                                         | Default |
|-------------------------------|-----------------------------------------------------|---------|
| **keyManager.awsKMS.enabled** | Enable AWS KMS key manager                          | false   |
| **keyManager.awsKMS.region**  | AWS region for KMS keys                             | ""      |
| **keyManager.awsKMS.keyTags** | Custom tags to apply to KMS keys (key-value pairs)  | {}      |

### Sample Configuration

```yaml
spire-server:
  keyManager:
    disk:
      enabled: false
    awsKMS:
      enabled: true
      region: "us-east-1"
      keyIdentifierFile:
        enabled: true
      keyTags:
        Environment: "production"
        Team: "security"
        Component: "spire"
```

## Tag Constraints

- Tag keys: 1-128 characters
- Tag values: 0-256 characters
- Maximum: 50 tags per key
- Valid characters: letters, numbers, spaces, `+ - = . _ : / @`
- Keys cannot start with `aws:` (AWS reserved) or `spire-` (SPIRE reserved)

## Required IAM Permissions

When using key tagging, the IAM role must include the `kms:TagResource` permission:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:CreateAlias",
        "kms:CreateKey",
        "kms:DescribeKey",
        "kms:GetPublicKey",
        "kms:ListKeys",
        "kms:ListAliases",
        "kms:ScheduleKeyDeletion",
        "kms:Sign",
        "kms:TagResource",
        "kms:UpdateAlias",
        "kms:DeleteAlias"
      ],
      "Resource": "*"
    }
  ]
}
```

**Note:** It's recommended to use [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) instead of access keys.

## Additional Information

For more details on the AWS KMS plugin, see the [SPIRE AWS KMS KeyManager Documentation](https://github.com/spiffe/spire/blob/main/doc/plugin_server_keymanager_aws_kms.md).
