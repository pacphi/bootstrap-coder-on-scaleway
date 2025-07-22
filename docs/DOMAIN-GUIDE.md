# Domain Configuration Guide

This guide provides complete instructions for configuring custom domains with your Coder deployment on Scaleway.

## Overview

The Bootstrap Coder on Scaleway system supports two deployment modes:

- **IP-Based Access**: Uses the load balancer's IP address directly (default)
- **Domain-Based Access**: Uses a custom domain with automatic Let's Encrypt SSL certificates

## When to Use Each Mode

### IP-Based Access (No Domain)

**✅ Use for:**
- Development and testing environments
- Proof of concepts and demos
- Internal tools where certificate warnings are acceptable
- Quick setup without DNS configuration

**❌ Limitations:**
- Browser security warnings for self-signed certificates
- Not suitable for production use
- May be blocked by enterprise proxies
- Cannot be used with strict security policies

### Domain-Based Access (With Domain)

**✅ Use for:**
- Production environments
- Customer-facing deployments
- Enterprise environments
- API integrations requiring valid SSL certificates
- Professional, branded deployments

**✅ Benefits:**
- Valid Let's Encrypt SSL certificates
- No browser security warnings
- Professional appearance
- Enterprise security compliance

## Implementation

### 1. Script-Based Deployment

#### Basic Domain Configuration
```bash
# Development with custom domain
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=python-django-crewai \
  --domain=example.com

# Production with custom subdomain
./scripts/lifecycle/setup.sh \
  --env=prod \
  --template=claude-flow-enterprise \
  --domain=company.com \
  --subdomain=coder \
  --enable-monitoring
```

#### Default Subdomains
If `--subdomain` is not specified, defaults are:
- **dev**: `coder-dev`
- **staging**: `coder-staging`
- **prod**: `coder`

#### Examples with Results
```bash
# Example 1: Development with default subdomain
./scripts/lifecycle/setup.sh --env=dev --domain=example.com
# Result: coder-dev.example.com

# Example 2: Production with custom subdomain
./scripts/lifecycle/setup.sh --env=prod --domain=company.com --subdomain=devops
# Result: devops.company.com

# Example 3: IP-based deployment (no domain)
./scripts/lifecycle/setup.sh --env=dev
# Result: https://51.159.123.456 (with certificate warnings)
```

### 2. GitHub Actions Workflow

#### Manual Deployment with Domain
1. Navigate to **Actions** → **Deploy Coder Environment**
2. Click **"Run workflow"**
3. Configure:
   - **Environment**: `prod`
   - **Template**: `claude-flow-enterprise`
   - **Domain name**: `company.com`
   - **Subdomain**: `coder` (optional)
   - **Enable monitoring**: `true`
4. Click **"Run workflow"**

The workflow will:
- Deploy the infrastructure with domain configuration
- Display DNS setup instructions in the workflow output
- Show the exact DNS records needed

#### Workflow Output Example
```
## 🌐 DNS Configuration Required

**Domain:** coder.company.com

Configure these DNS records at your domain registrar:

**A Record:**
- Name: `coder.company.com`
- Value: `51.159.123.456`
- TTL: `300`

**CNAME Record (Wildcard):**
- Name: `*.coder.company.com`
- Value: `coder.company.com`
- TTL: `300`

After DNS propagation (5-15 minutes):
- SSL certificates will be issued automatically
- Access Coder at: https://coder.company.com
- Workspaces will use: https://*.coder.company.com
```

## DNS Configuration

### Required DNS Records

For a domain deployment, you need two DNS records:

#### 1. A Record (Main Domain)
- **Name**: Your full domain (e.g., `coder.company.com`)
- **Type**: `A`
- **Value**: Load balancer IP address
- **TTL**: `300` (5 minutes)

#### 2. CNAME Record (Wildcard for Workspaces)
- **Name**: Wildcard subdomain (e.g., `*.coder.company.com`)
- **Type**: `CNAME`
- **Value**: Main domain (e.g., `coder.company.com`)
- **TTL**: `300` (5 minutes)

### Getting the Load Balancer IP

After deployment, get the IP address:

```bash
cd environments/prod  # or your environment
terraform output load_balancer_ip
# Output: 51.159.123.456
```

### DNS Configuration by Registrar

#### Cloudflare
1. Go to **DNS** → **Records**
2. Click **"Add record"**
3. **A Record**:
   - Type: `A`
   - Name: `coder`
   - IPv4 address: `51.159.123.456`
   - TTL: `Auto`
4. **CNAME Record**:
   - Type: `CNAME`
   - Name: `*.coder`
   - Target: `coder.company.com`
   - TTL: `Auto`

#### Namecheap
1. Go to **Domain List** → **Manage** → **Advanced DNS**
2. **A Record**:
   - Type: `A Record`
   - Host: `coder`
   - Value: `51.159.123.456`
   - TTL: `Automatic`
3. **CNAME Record**:
   - Type: `CNAME Record`
   - Host: `*.coder`
   - Value: `coder.company.com`
   - TTL: `Automatic`

### DNS Verification

Check DNS propagation:

```bash
# Check A record
nslookup coder.company.com
dig coder.company.com A

# Check CNAME record
nslookup test.coder.company.com
dig test.coder.company.com CNAME

# Alternative: Use online tools
# - whatsmydns.net
# - dnschecker.org
```

## SSL Certificate Management

### Automatic Certificate Issuance

When you deploy with a domain name:

1. **Scaleway Load Balancer** automatically requests Let's Encrypt certificates
2. **DNS validation** occurs using your configured DNS records
3. **Certificate installation** happens automatically
4. **Auto-renewal** is handled by Scaleway (no manual intervention needed)

### Certificate Validation

Check certificate status:

```bash
# Test HTTPS connection
curl -I https://coder.company.com

# Detailed certificate information
openssl s_client -connect coder.company.com:443 -servername coder.company.com

# Check certificate expiration
echo | openssl s_client -servername coder.company.com -connect coder.company.com:443 2>/dev/null | openssl x509 -noout -dates
```

### Certificate Troubleshooting

If certificates aren't issued:

1. **Verify DNS Resolution**:
   ```bash
   nslookup coder.company.com
   # Should return the load balancer IP
   ```

2. **Check DNS Propagation**:
   - Wait 5-15 minutes for DNS changes to propagate
   - Use online tools like whatsmydns.net to verify global propagation

3. **Validate Domain Configuration**:
   ```bash
   cd environments/prod
   terraform show | grep -A5 "scaleway_lb_certificate"
   ```

4. **Check Let's Encrypt Rate Limits**:
   - Let's Encrypt has rate limits (5 certificates per domain per week)
   - Wait if you've hit the limit, or use a different subdomain

## Post-Deployment Access

### IP-Based Deployment

```bash
# Setup completes with output:
# ✅ Setup completed successfully!
# 📋 Access Information:
#    URL: https://51.159.123.456
#    Username: admin
#    Password: [Retrieved from Terraform output]

# Access Coder (accept browser warning)
open https://51.159.123.456
```

### Domain-Based Deployment

```bash
# Setup completes with output:
# ✅ Setup completed successfully!
# 📋 Access Information:
#    URL: https://coder.company.com
#    Load Balancer IP: 51.159.123.456
#
# 🌐 DNS Configuration Required:
#    Configure these DNS records at your domain registrar:
#    A Record: coder.company.com → 51.159.123.456
#    CNAME Record: *.coder.company.com → coder.company.com

# After DNS configuration and propagation:
open https://coder.company.com
```

### Workspace Access

#### IP-Based
- **Main Coder**: `https://51.159.123.456`
- **Workspaces**: `https://workspace-name.51.159.123.456.nip.io`

#### Domain-Based
- **Main Coder**: `https://coder.company.com`
- **Workspaces**: `https://workspace-name.coder.company.com`

## Migration: IP to Domain

### Converting Existing Deployment

1. **Update Environment Configuration**:
   ```bash
   cd environments/prod

   # Run setup with domain
   ../../scripts/lifecycle/setup.sh \
     --env=prod \
     --domain=company.com \
     --subdomain=coder
   ```

2. **Configure DNS** (as described above)

3. **Verify Migration**:
   ```bash
   # Old URL should still work during transition
   curl -I https://51.159.123.456

   # New URL should work after DNS propagation
   curl -I https://coder.company.com
   ```

4. **Update User Bookmarks**:
   - Send communication to users about new URL
   - Old IP-based access will continue to work
   - Workspaces will automatically use new domain

### No Data Loss

- **Workspaces**: Remain intact and accessible
- **User Data**: Preserved in persistent volumes
- **Templates**: Continue to function normally
- **Settings**: Maintained across the migration

## Domain Validation

The system includes built-in domain validation:

### Format Validation
```bash
# Valid domain formats:
example.com
my-site.co.uk
dev.company.com
coder-platform.example.org

# Invalid domain formats:
-invalid.com       # Cannot start with hyphen
invalid-.com       # Cannot end with hyphen
invalid..com       # Double dots not allowed
192.168.1.1       # IP addresses not allowed
```

### Subdomain Validation
```bash
# Valid subdomain formats:
coder
coder-dev
staging-env
prod-01

# Invalid subdomain formats:
-invalid          # Cannot start with hyphen
invalid-          # Cannot end with hyphen
invalid_name      # Underscores not allowed
```

## Common Domain Patterns

### Multi-Environment Strategy

```bash
# Development
./scripts/lifecycle/setup.sh \
  --env=dev \
  --domain=company.com \
  --subdomain=coder-dev
# Result: coder-dev.company.com

# Staging
./scripts/lifecycle/setup.sh \
  --env=staging \
  --domain=company.com \
  --subdomain=coder-staging
# Result: coder-staging.company.com

# Production
./scripts/lifecycle/setup.sh \
  --env=prod \
  --domain=company.com \
  --subdomain=coder
# Result: coder.company.com
```

### Team-Based Strategy

```bash
# Frontend Team
./scripts/lifecycle/setup.sh \
  --env=prod \
  --domain=company.com \
  --subdomain=frontend-coder
# Result: frontend-coder.company.com

# Backend Team
./scripts/lifecycle/setup.sh \
  --env=prod \
  --domain=company.com \
  --subdomain=backend-coder
# Result: backend-coder.company.com
```

## Security Considerations

### Domain-Based Security

- **Valid SSL/TLS Certificates**: Full certificate chain validation
- **HSTS Support**: HTTP Strict Transport Security can be enabled
- **Certificate Transparency**: All certificates are logged in CT logs
- **Enterprise Compliance**: Meets security requirements for enterprise environments

### IP-Based Security Risks

- **Certificate Warnings**: Users may ignore important security warnings
- **MITM Vulnerability**: Susceptible to man-in-the-middle attacks
- **Session Issues**: Browsers may not properly store cookies/sessions
- **Proxy Blocks**: Corporate proxies may block invalid certificate connections

## Troubleshooting

### Common Issues

#### Domain Not Resolving
```bash
# Check DNS configuration
nslookup coder.company.com

# If no result, verify:
# 1. DNS records are correctly configured
# 2. TTL period has elapsed
# 3. DNS propagation is complete
```

#### Certificate Not Issued
```bash
# Check load balancer certificate status
terraform show | grep -A10 "scaleway_lb_certificate"

# Common causes:
# - DNS not resolving to load balancer IP
# - Let's Encrypt rate limits reached
# - Domain validation failed
```

#### Mixed Content Warnings
```bash
# Ensure all URLs in environment use HTTPS
terraform output -json | jq '.coder_url.value'
terraform output -json | jq '.wildcard_access_url.value'

# Both should start with https://
```

### Support

For domain configuration issues:

1. **Verify Prerequisites**: Ensure domain ownership and DNS access
2. **Check Deployment Logs**: Review setup.sh output for errors
3. **Test DNS Resolution**: Use multiple DNS testing tools
4. **Monitor Certificate Status**: Check Scaleway console for certificate status
5. **Contact Domain Registrar**: For DNS propagation issues

This guide provides complete coverage of domain configuration for your Coder deployment. For additional support, refer to the main documentation or create an issue in the project repository.