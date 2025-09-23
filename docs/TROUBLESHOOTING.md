# Troubleshooting

Common issues, two-phase deployment problems, cost overruns, scaling issues, and support channels.

## Common Issues

### Prerequisites Missing

```bash
# Check system requirements
./scripts/test-runner.sh --suite=prerequisites
```

### Template Deployment Fails

```bash
# Validate templates
./scripts/test-runner.sh --suite=templates

# Check template syntax
gh workflow run validate-templates.yml -f validation_scope=syntax
```

### Two-Phase Deployment Issues

```bash
# Infrastructure deployment failed (Phase 1)
# Check Scaleway console and workflow logs
gh run list --workflow=deploy-infrastructure.yml

# Coder deployment failed (Phase 2) - Infrastructure still accessible
# Use kubeconfig to troubleshoot
export KUBECONFIG=~/.kube/config-coder-<env>
kubectl get storageclass  # Check if scw-bssd storage class exists
kubectl get pvc -n coder  # Check persistent volume claims

# Retry only Coder deployment
gh workflow run deploy-coder.yml -f environment=<env>
```

### Cost Overruns

```bash
# Analyze current costs
./scripts/utils/cost-calculator.sh --env=all --detailed

# Set budget alerts
./scripts/utils/cost-calculator.sh --env=prod --set-budget=300 --alert-threshold=80
```

### Scaling Issues

```bash
# Check cluster capacity
./scripts/validate.sh --env=prod --focus=resources

# Analyze scaling recommendations
./scripts/scale.sh --env=prod --analyze-only
```

## Support Channels

- **[Usage Guide](USAGE.md)** - Comprehensive documentation
- **[GitHub Issues](../../issues)** - Bug reports and feature requests
- **[Architecture Guide](ARCHITECTURE.md)** - System design and troubleshooting
- **[Hooks Examples](../scripts/hooks/README.md)** - Custom integration patterns
