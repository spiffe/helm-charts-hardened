# AWS IID Node Attestor

This document provides a concise guide to the AWS IID node attestor plugin support in your system. The AWS IID attestor plugin automatically verifies instances using AWS's Instance Metadata API and Instance Identity Document.

## Configuration

The AWS IID node attestor can be configured with the following properties:

| Parameter                     | Description                                         | Default |
|-------------------------------|-----------------------------------------------------|---------|
| **nodeAttestor.awsIID.enabled** | Enable the AWS IID node attestor                    | false   |
| **nodeAttestor.awsIID.region** | AWS region to use for the attestation               | ""      |
| **nodeAttestor.awsIID.assumeRole** | AWS IAM Role NAME to use for the attestation      | ""      |

### Sample Configuration

Here's a minimal configuration example for the server:

```yaml
awsIID:
  enabled: true
  region: "us-west-2"  # Specify your desired AWS region
  assumeRole: "example-role"  # Specify the IAM Role NAME
```

For the agent, ensure that the `awsIID` is also enabled:

```yaml
awsIID:
  enabled: true
```

**Note:** When the `awsIID` node attestor is enabled on the server, it must also be enabled on the agent to ensure proper attestation.

### IAM Role

The `assumeRole` parameter requires the name of the IAM Role you wish to use for the attestation process. Ensure this role has the appropriate permissions.

### Required IAM Policy

To facilitate the node attestation, the following IAM policy example should be attached to the IAM Role mentioned in the `assumeRole`. This policy example is needed to get the instance's info from AWS:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "iam:GetInstanceProfile"
            ],
            "Resource": "*"
        }
    ]
}
```

## Security Considerations

It’s important to note that while the AWS Instance Identity Document is used to prove node identity, it is accessible to any process running on the instance. Therefore, precautions should be made to ensure only the desired agent uses it for attestation.

Always monitor your systems for unauthorized access attempts and ensure your IAM roles follow the principle of least privilege.

For more information on AWS IAM roles and security best practices, refer to the [AWS IAM documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html).

## Additional Information

For more information on the server plugin, see the [Server Plugin Documentation](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_aws_iid.md).

And for the agent, see the [Agent Plugin Documentation](https://github.com/spiffe/spire/blob/main/doc/plugin_agent_nodeattestor_aws_iid.md).

---

By following the above guidelines, you can ensure a simple yet secure implementation of the AWS IID node attestor within your system.
