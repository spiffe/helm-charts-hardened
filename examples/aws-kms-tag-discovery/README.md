# AWS KMS Tag-Based Key Discovery

This example configures the AWS KMS KeyManager to discover its keys through the
AWS Resource Groups Tagging API, using the tags SPIRE applies to every key it
manages, instead of listing every key and alias in the account.

Tag-based discovery is available from SPIRE 1.15.2. Alias-based discovery, the
current default, is deprecated upstream and will be removed in a future release.

## Configuration

| Parameter                                         | Description                                                     | Default |
|---------------------------------------------------|-----------------------------------------------------------------|---------|
| **keyManager.awsKMS.enabled**                     | Enable AWS KMS key manager                                      | false   |
| **keyManager.awsKMS.region**                      | AWS region for KMS keys                                         | ""      |
| **keyManager.awsKMS.enableTagBasedKeyDiscovery**  | Discover keys by their SPIRE tags via the Tagging API           | false   |

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
      enableTagBasedKeyDiscovery: true
```

## Migration from alias-based discovery

No manual steps. On the first start with the option enabled, the plugin finds the
keys it previously managed through aliases and applies the SPIRE tags to them
(`spire-server-td`, `spire-server-id`, `spire-active`, `spire-key-id`,
`spire-last-update`). Aliases keep being created and refreshed, so switching back
to alias-based discovery stays safe within the two-week key-liveness window.

Within a trust domain, configure the option consistently across all servers.

## IAM permissions

In addition to the KMS permissions the plugin always needs, tag-based discovery
requires:

- `kms:TagResource`
- `tag:GetResources`

`tag:GetResources` belongs to the Resource Groups Tagging API and must be granted
in an identity-based IAM policy on the server's role. It cannot be granted through
a KMS key policy. `kms:ListKeys` is only needed by alias-based discovery and can be
dropped once the switch is complete.
