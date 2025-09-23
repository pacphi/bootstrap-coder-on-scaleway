# Management Scripts

## Comprehensive Testing

```bash
# Run all validation tests
./scripts/test-runner.sh --suite=all

# Run specific test suites
./scripts/test-runner.sh --suite=smoke,templates --format=json

# Test external integrations
./scripts/test-runner.sh --suite=integrations
```

## Environment Validation

```bash
# Quick health check
./scripts/validate.sh --env=prod --quick

# Comprehensive validation with detailed report
./scripts/validate.sh --env=staging --comprehensive --format=json
```

## Dynamic Scaling

```bash
# Scale cluster with cost analysis
./scripts/scale.sh --env=prod --nodes=8 --analyze-cost

# Auto-scale based on workload
./scripts/scale.sh --env=staging --auto --target-cpu=70
```

## Automated Backups

```bash
# Complete environment backup
./scripts/lifecycle/backup.sh --env=prod --include-all

# Pre-destroy backup with retention
./scripts/lifecycle/backup.sh --env=staging --pre-destroy --retention-days=90
```
