# Release Management

This document describes the release process for Bootstrap Coder on Scaleway.

## Release Process

### Automated Release Creation

Releases are automatically created when you push a git tag with semantic versioning format:

```bash
# Create and push a stable release
git tag v1.2.3
git push origin v1.2.3

# Create and push a pre-release
git tag v1.2.3-alpha.1
git push origin v1.2.3-alpha.1
```

### Release Types

- **Stable releases**: `v1.2.3` - Production-ready releases
- **Pre-releases**: `v1.2.3-alpha.1`, `v1.2.3-beta.2`, `v1.2.3-rc.1` - Testing and preview releases

### What Happens Automatically

When you push a tag, the release workflow:

1. **Validates** the tag format (semantic versioning)
2. **Generates** changelog from git commits since the last release
3. **Categorizes** changes into:
   - ✨ Features
   - 🐛 Bug Fixes
   - 🏗️ Infrastructure
   - 🔧 Scripts & CI/CD
   - 📚 Documentation
   - 🔧 Other Changes
4. **Creates** release assets:
   - `install.sh` - Quick installation script
   - `QUICK_REFERENCE.md` - Command reference
   - `example.env` - Environment configuration template
5. **Publishes** the GitHub release with generated notes
6. **Updates** version badges automatically

### Release Assets

Each release includes:

- **install.sh**: Automated installation script with prerequisite checks
- **QUICK_REFERENCE.md**: Quick command reference for common operations
- **example.env**: Template for environment variable configuration

### Commit Message Conventions

For better changelog generation, use these commit prefixes:

```bash
# Features
feat: add new workspace template for React Native
feat(templates): add Flutter development environment

# Bug fixes
fix: resolve Terraform state locking issue
fix(k8s): correct ingress configuration for staging

# Infrastructure
infra: upgrade Kubernetes cluster to 1.29.1
terraform: add support for database encryption

# Scripts and CI/CD
script: improve cost calculation accuracy
ci: add security scanning to workflows
workflow: optimize deployment performance

# Documentation
docs: update quick start guide
docs(templates): add template development guide
```

### Manual Release Steps

If you need to create a release manually:

1. **Prepare the release**:

   ```bash
   # Ensure main branch is up to date
   git checkout main
   git pull origin main

   # Run validation
   ./scripts/validate.sh --env=dev --quick
   ./scripts/test-runner.sh --suite=prerequisites
   ```

2. **Create and push the tag**:

   ```bash
   # For stable release
   git tag v1.2.3 -m "Release v1.2.3"
   git push origin v1.2.3

   # For pre-release
   git tag v1.2.3-alpha.1 -m "Pre-release v1.2.3-alpha.1"
   git push origin v1.2.3-alpha.1
   ```

3. **Monitor the workflow**: Check the GitHub Actions tab to ensure the release workflow completes successfully.

### Release Validation

Before creating a release, ensure:

- [ ] All CI/CD workflows are passing
- [ ] Resource validation passes (scripts, Terraform, YAML, Markdown)
- [ ] Cost calculations are accurate for all environments
- [ ] Documentation is up to date
- [ ] Security scans are clean
- [ ] Template validation passes

### Hotfix Releases

For urgent fixes to production:

1. Create a hotfix branch from the release tag:
   ```bash
   git checkout v1.2.3
   git checkout -b hotfix/1.2.4
   ```

2. Make the minimal necessary changes

3. Test thoroughly in development environment

4. Create the hotfix release:

   ```bash
   git tag v1.2.4 -m "Hotfix v1.2.4: fix critical security issue"
   git push origin v1.2.4
   ```

### Release Notes

The automated changelog includes:

- **Categorized changes** based on commit messages
- **Deployment instructions** for the new version
- **Links to full changelog** showing all changes
- **Installation scripts** with prerequisite validation
- **Environment-specific deployment examples**

### Pre-release Guidelines

Pre-releases should be used for:

- Testing new features before stable release
- Beta testing with early adopters
- Release candidates before major versions
- Experimental features that need validation

### Version Strategy

Follow semantic versioning (semver):

- **MAJOR** (1.0.0): Breaking changes, incompatible API changes
- **MINOR** (0.1.0): New features, backward compatible
- **PATCH** (0.0.1): Bug fixes, backward compatible

### Release Communication

Stable releases are automatically:

- Published on GitHub Releases page
- Linked in repository README badges
- Available through installation scripts

### Troubleshooting Releases

If a release fails:

1. Check the workflow logs in GitHub Actions
2. An issue will be automatically created for failed releases
3. Fix the underlying problem and create a new tag
4. Delete the failed tag if necessary:

   ```bash
   git tag -d v1.2.3
   git push origin :refs/tags/v1.2.3
   ```

### Release Rollback

To rollback to a previous release:

1. Use the previous release's installation script
2. Or checkout the previous tag:

   ```bash
   git checkout v1.2.2
   ./scripts/lifecycle/setup.sh --env=staging
   ```

### Support Policy

- **Latest stable release**: Full support with security updates
- **Previous minor release**: Security updates only
- **Pre-releases**: Community support, no guaranteed updates

For questions about releases, create an issue using the question template.
