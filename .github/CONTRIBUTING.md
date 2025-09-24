# Contributing to Bootstrap Coder on Scaleway

Thank you for your interest in contributing to Bootstrap Coder on Scaleway! This document provides guidelines for contributing to this project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [How to Contribute](#how-to-contribute)
- [Contribution Guidelines](#contribution-guidelines)
- [Testing Requirements](#testing-requirements)
- [Documentation Standards](#documentation-standards)
- [Submitting Changes](#submitting-changes)
- [Review Process](#review-process)
- [Community and Support](#community-and-support)

## Code of Conduct

This project adheres to a [Code of Conduct](CODE_OF_CONDUCT.md) to ensure a welcoming environment for all contributors. By participating, you are expected to uphold this code.

## Getting Started

### Prerequisites

Before contributing, ensure you have the following tools installed:

- **Terraform** ≥1.13.3
- **kubectl** ≥1.32.0
- **Helm** ≥3.12.0
- **Git** for version control
- **jq** for JSON processing
- **GitHub CLI** (optional but recommended)

### Scaleway Account Setup

You'll need a Scaleway account with appropriate permissions:

1. Create a [Scaleway account](https://www.scaleway.com/)
2. Generate [API credentials](https://www.scaleway.com/en/docs/identity-and-access-management/iam/how-to/create-api-keys/)
3. Set environment variables:
   ```bash
   export SCW_ACCESS_KEY="your-access-key"
   export SCW_SECRET_KEY="your-secret-key"
   export SCW_DEFAULT_PROJECT_ID="your-project-id"
   ```

## Development Setup

1. **Fork the repository**
   ```bash
   gh repo fork your-org/bootstrap-coder-on-scaleway
   cd bootstrap-coder-on-scaleway
   ```

2. **Create a development branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Run the test suite**
   ```bash
   ./scripts/test-runner.sh --suite=all
   ```

4. **Deploy a test environment** (optional)
   ```bash
   ./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai
   ```

## How to Contribute

### Types of Contributions

We welcome several types of contributions:

- 🐛 **Bug Reports**: Issues with existing functionality
- ✨ **Feature Requests**: New features or enhancements
- 📝 **Documentation**: Improvements to docs, README, or guides
- 🔧 **Templates**: New workspace templates or template improvements
- 🏗️ **Infrastructure**: Terraform module improvements
- 🧪 **Tests**: Additional testing coverage
- 🎨 **UI/UX**: GitHub Actions workflows, scripts, or tooling improvements

### Before You Start

1. **Check existing issues** to avoid duplicate work
2. **Open an issue** to discuss significant changes before implementation
3. **Review the architecture** in [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)
4. **Understand the codebase** using [CLAUDE.md](../CLAUDE.md)

## Contribution Guidelines

### Code Style and Standards

#### Terraform Code
- Follow [Terraform style conventions](https://www.terraform.io/docs/language/syntax/style.html)
- Use consistent naming: `snake_case` for resources, variables, and outputs
- Include meaningful descriptions for all variables
- Use data sources instead of hardcoded values when possible
- Organize code logically with proper file structure

#### Shell Scripts
- Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use `#!/bin/bash` shebang
- Include error handling with `set -euo pipefail`
- Use meaningful variable names and add comments for complex logic
- Validate inputs and provide helpful error messages

#### Template Development
- Follow existing template patterns in `templates/` directories
- Include comprehensive README.md with usage instructions
- Ensure containers use official base images where possible
- Test templates thoroughly before submission
- Document any special requirements or dependencies

### File Structure

When adding new components:

```
├── modules/                    # Terraform modules
│   └── your-module/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
├── templates/                  # Coder workspace templates
│   └── category/
│       └── your-template/
│           ├── main.tf
│           ├── README.md
│           └── build/
├── scripts/                    # Management scripts
│   ├── utils/                 # Utility scripts
│   └── hooks/                 # Extensible hooks
└── docs/                      # Additional documentation
```

### Commit Message Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(templates): add rust actix web template with async support

fix(networking): resolve security group rule conflicts in production

docs(readme): update installation instructions for helm 3.12+

test(scripts): add comprehensive validation for cost calculator
```

## Testing Requirements

### Before Submitting

All contributions must pass the following tests:

```bash
# Run comprehensive test suite
./scripts/test-runner.sh --suite=all --verbose

# Test specific components
./scripts/test-runner.sh --suite=templates --template=your-template
./scripts/test-runner.sh --suite=infrastructure --env=dev
```

### Test Categories

1. **Prerequisites**: Verify required tools and versions
2. **Syntax**: Terraform and shell script validation
3. **Templates**: Template functionality and deployment
4. **Infrastructure**: Terraform plan validation
5. **Integration**: End-to-end deployment testing (optional)

### Adding New Tests

When adding new features, include appropriate tests:

- **Template tests**: Add test cases in `scripts/test-runner.sh`
- **Infrastructure tests**: Include Terraform validation
- **Script tests**: Add unit tests for new utility functions
- **Documentation tests**: Verify links and examples work

## Documentation Standards

### Required Documentation

- **README.md**: Update if adding new features or changing workflows
- **Module documentation**: Each Terraform module needs a README.md
- **Template documentation**: Each template needs usage instructions
- **Script documentation**: Add inline comments and usage examples

### Documentation Guidelines

- Use clear, concise language
- Include practical examples with expected outputs
- Update table of contents when adding new sections
- Verify all links work correctly
- Include screenshots for UI-related changes

## Submitting Changes

### Pull Request Process

1. **Ensure tests pass**
   ```bash
   ./scripts/test-runner.sh --suite=all
   ```

2. **Update documentation** as needed

3. **Create pull request** with descriptive title and body:
   ```bash
   gh pr create --title "feat(templates): add new python ai/ml template" \
     --body "Adds comprehensive Python AI/ML template with Jupyter, pandas, and scikit-learn"
   ```

4. **Link related issues** using keywords (fixes #123, closes #456)

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Other (please describe)

## Testing
- [ ] Tests pass locally
- [ ] Added new tests for new functionality
- [ ] Updated documentation

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No breaking changes (or clearly documented)
```

## Review Process

### What to Expect

1. **Automated checks**: GitHub Actions will run tests automatically
2. **Maintainer review**: Project maintainers will review code and approach
3. **Feedback incorporation**: Address any requested changes
4. **Final approval**: Maintainer approval required before merge

### Review Criteria

- **Functionality**: Does it work as intended?
- **Code quality**: Follows project standards and best practices
- **Testing**: Adequate test coverage and validation
- **Documentation**: Clear and up-to-date documentation
- **Impact**: Considers effects on existing functionality
- **Security**: No security vulnerabilities introduced

### Timeline

- Initial response: Within 48 hours
- Full review: Within 1 week for most contributions
- Complex features: May require additional discussion and iteration

## Community and Support

### Getting Help

- **Documentation**: Check [docs/](../docs/) directory
- **Issues**: Search existing [GitHub issues](../../issues)
- **Discussions**: Use [GitHub Discussions](../../discussions) for questions
- **Architecture**: Review [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and community interaction
- **Pull Request Comments**: Code-specific discussions

### Recognition

Contributors will be recognized in:
- Repository contributors list
- Release notes for significant contributions
- Special recognition for major features or improvements

## Advanced Contributing

### Template Development

When creating new workspace templates:

1. **Research existing templates** for patterns and conventions
2. **Choose appropriate base images** with security considerations
3. **Include comprehensive tooling** for the target development workflow
4. **Test thoroughly** with different use cases and configurations
5. **Document requirements** and provide troubleshooting guidance

### Infrastructure Modules

When developing Terraform modules:

1. **Follow module best practices** with clear inputs/outputs
2. **Include validation rules** for input variables
3. **Support multiple environments** (dev/staging/prod)
4. **Consider resource dependencies** and ordering
5. **Add comprehensive examples** and usage documentation

### Script Development

When adding management scripts:

1. **Follow existing script patterns** for consistency
2. **Include comprehensive error handling** and user feedback
3. **Support common options** (--help, --verbose, --dry-run)
4. **Add logging and validation** for debugging
5. **Consider extensibility** through hooks framework

## Questions?

If you have questions about contributing, please:

1. Check existing documentation and issues
2. Open a [GitHub Discussion](../../discussions)
3. Create an issue with the `question` label

Thank you for contributing to Bootstrap Coder on Scaleway! 🚀
