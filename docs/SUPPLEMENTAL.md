# Supplemental Documentation

## Let's Encrypt SSL/TLS Implementation Guide

This guide provides comprehensive information about domain-based vs IP-only deployments in the Coder on Scaleway infrastructure, including Let's Encrypt certificate automation and access patterns.

## Table of Contents
- [Overview](#overview)
- [Current Implementation](#current-implementation)
- [IP-Only Access (Default)](#ip-only-access-default)
- [Domain-Based Access](#domain-based-access)
- [Domain Registration Options](#domain-registration-options)
- [Configuration Guide](#configuration-guide)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

## Overview

The Coder on Scaleway infrastructure supports two deployment modes:

1. **IP-Only Access**: Uses the load balancer's public IP address directly
2. **Domain-Based Access**: Uses a custom domain with automatic Let's Encrypt SSL certificates

Both modes provide full functionality, but differ in security, user experience, and certificate management.

## Current Implementation

### Architecture Components

The SSL/TLS implementation involves three key modules:

1. **Networking Module** (`modules/networking/main.tf`):
   - Creates Scaleway Load Balancer with HTTPS frontend
   - Provisions Let's Encrypt certificates when domain is configured
   - Manages HTTP-to-HTTPS redirection

2. **Coder Deployment Module** (`modules/coder-deployment/main.tf`):
   - Configures Kubernetes ingress with TLS support
   - Sets up proper annotations for SSL redirect
   - Manages subdomain routing for workspaces

3. **Environment Configuration** (`environments/{env}/main.tf`):
   - Defines `domain_name` variable (empty by default)
   - Sets environment-specific subdomains
   - Controls SSL compatibility levels

### Key Configuration Flow

```
User Request → Load Balancer → HTTPS Frontend → Kubernetes Ingress → Coder Service
                     ↓
              SSL Certificate
           (Let's Encrypt or None)
```

## IP-Only Access (Default)

### How It Works

When `domain_name = ""` (empty), the system operates in IP-only mode:

```hcl
# Current default in all environments
module "networking" {
  domain_name = ""  # No domain configured
  subdomain   = "coder-dev"
}
```

### Access URLs

- **Main Coder URL**: `https://<load-balancer-ip>`
- **Workspace URLs**: `https://<workspace>.<load-balancer-ip>.nip.io`

### User Experience

1. **Initial Access**:
   ```bash
   # Get the load balancer IP from Terraform outputs
   terraform output coder_url
   # Output: https://51.159.123.456
   ```

2. **Browser Warning**:
   - Users will see SSL certificate warnings
   - Must click "Advanced" → "Proceed to site (unsafe)"
   - This is expected behavior without a valid certificate

3. **Workspace Access**:
   - Each workspace gets a subdomain via nip.io
   - Example: `https://main-johndoe.51.159.123.456.nip.io`
   - nip.io automatically resolves `*.51.159.123.456.nip.io` to `51.159.123.456`

### Use Cases for IP-Only

- **Development environments**: Quick testing without domain setup
- **Proof of concepts**: Demonstrating functionality before production
- **Internal tools**: When users can accept certificate warnings
- **Cost optimization**: No domain registration/renewal fees

### Limitations

- Browser security warnings on every access
- Cannot be used with strict security policies
- Some enterprise proxies may block access
- No valid SSL certificate for API integrations

## Domain-Based Access

### How It Works

When a domain is configured, Let's Encrypt certificates are automatically provisioned:

```hcl
# Example configuration with domain
module "networking" {
  domain_name = "example.com"
  subdomain   = "coder-dev"  # Results in coder-dev.example.com
}
```

### Access URLs

- **Main Coder URL**: `https://coder-dev.example.com`
- **Workspace URLs**: `https://<workspace>.coder-dev.example.com`

### Automatic Certificate Management

1. **Initial Provisioning**:
   - Scaleway automatically requests Let's Encrypt certificate
   - DNS challenge validation via your domain
   - Certificate issued within minutes

2. **Automatic Renewal**:
   - Certificates auto-renew before expiration
   - No manual intervention required
   - Managed by Scaleway Load Balancer

3. **Wildcard Support**:
   - Main certificate: `coder-dev.example.com`
   - Wildcard certificate: `*.coder-dev.example.com`
   - Enables secure workspace subdomains

### User Experience

1. **Secure Access**:
   - No browser warnings
   - Green padlock in address bar
   - Full SSL/TLS encryption

2. **Professional URLs**:
   - Branded domain names
   - Easy to remember and share
   - Suitable for customer-facing deployments

### Use Cases for Domain-Based

- **Production environments**: Professional, secure access
- **Enterprise deployments**: Meeting security requirements
- **Customer demos**: No certificate warnings
- **API integrations**: Valid certificates for programmatic access

## Domain Registration Options

### Recommended Domain Registrars

1. **Cloudflare Registrar**
   - At-cost pricing (no markup)
   - Free DNS management included
   - API support for automation
   - Built-in DDoS protection

2. **Namecheap**
   - Competitive pricing
   - Free WhoisGuard privacy
   - User-friendly interface
   - Good customer support

### Domain Selection Tips

- **For Development**: Consider cheaper TLDs like `.dev`, `.app`, `.io`
- **For Production**: Traditional TLDs like `.com`, `.org` for trust
- **Subdomain Strategy**: Use a main domain with environment subdomains
  - `dev.coder.example.com`
  - `staging.coder.example.com`
  - `coder.example.com` (production)

### DNS Configuration Requirements

1. **A Record**: Point domain to load balancer IP
   ```
   Type: A
   Name: coder-dev (or @)
   Value: <load-balancer-ip>
   TTL: 300
   ```

2. **Wildcard CNAME**: For workspace subdomains
   ```
   Type: CNAME
   Name: *.coder-dev
   Value: coder-dev.example.com
   TTL: 300
   ```

## Configuration Guide

### Enabling Domain-Based Access

1. **Update Environment Configuration**:
   ```hcl
   # environments/dev/main.tf
   module "networking" {
     source = "../../modules/networking"

     environment     = local.environment
     project_prefix  = local.project_prefix
     vpc_id          = module.cluster.vpc_id

     domain_name = "example.com"  # Add your domain here
     subdomain   = local.subdomain

     # ... other configuration
   }
   ```

2. **Apply Changes**:
   ```bash
   cd environments/dev
   terraform plan
   terraform apply
   ```

3. **Configure DNS**:
   ```bash
   # Get the load balancer IP
   terraform output load_balancer_ip

   # Add DNS records at your domain registrar
   # A record: coder-dev.example.com → <load-balancer-ip>
   # CNAME: *.coder-dev.example.com → coder-dev.example.com
   ```

4. **Verify Certificate**:
   ```bash
   # Check certificate status
   curl -I https://coder-dev.example.com

   # View certificate details
   openssl s_client -connect coder-dev.example.com:443 -servername coder-dev.example.com
   ```

### Switching from IP-Only to Domain

1. **No Data Loss**: The switch doesn't affect existing workspaces
2. **Update Access URLs**: Users need to update bookmarks
3. **API Clients**: Update any hardcoded URLs in scripts
4. **Workspace URLs**: Will automatically use new domain

### Multi-Environment Setup

```hcl
# Development: Simple subdomain
domain_name = "example.com"
subdomain = "coder-dev"
# Result: coder-dev.example.com

# Staging: Clear environment indication
domain_name = "example.com"
subdomain = "coder-staging"
# Result: coder-staging.example.com

# Production: Clean URL
domain_name = "example.com"
subdomain = "coder"  # or "" for root domain
# Result: coder.example.com or example.com
```

## Security Considerations

### IP-Only Mode Security

1. **Traffic Encryption**: Still uses HTTPS, but without certificate validation
2. **MITM Risk**: Vulnerable to man-in-the-middle attacks
3. **Browser Storage**: May not properly store cookies/sessions
4. **Recommendations**:
   - Use only for development/testing
   - Educate users about certificate warnings
   - Consider VPN for additional security

### Domain-Based Security

1. **Full TLS Validation**: Proper certificate chain validation
2. **HSTS Support**: Can enable HTTP Strict Transport Security
3. **Certificate Transparency**: Let's Encrypt certificates are CT-logged
4. **Security Headers**: Properly configured security headers

### Best Practices

1. **Production Must Use Domains**: Never deploy production with IP-only
2. **Separate Environments**: Use different subdomains per environment
3. **Monitor Certificates**: Set up alerts for expiration (though auto-renewal handles this)
4. **DNS Security**: Use DNSSEC if available from registrar

## Troubleshooting

### Common Issues and Solutions

#### Certificate Not Issued

**Symptoms**: Domain configured but still getting certificate warnings

**Solutions**:
1. Check DNS propagation:
   ```bash
   nslookup coder-dev.example.com
   dig coder-dev.example.com
   ```

2. Verify load balancer configuration:
   ```bash
   terraform show | grep -A10 "scaleway_lb_certificate"
   ```

3. Check Let's Encrypt rate limits (if multiple attempts)

#### Workspace Subdomains Not Working

**Symptoms**: Main domain works but workspace subdomains fail

**Solutions**:
1. Ensure wildcard DNS record exists
2. Check ingress configuration:
   ```bash
   kubectl describe ingress -n coder
   ```

3. Verify Coder wildcard access URL:
   ```bash
   kubectl get configmap -n coder coder -o yaml | grep WILDCARD
   ```

#### Mixed Content Warnings

**Symptoms**: Some resources load over HTTP

**Solutions**:
1. Ensure all Coder environment variables use HTTPS URLs
2. Check workspace templates for hardcoded HTTP URLs
3. Verify ingress SSL redirect annotations

### Monitoring and Validation

1. **Certificate Expiration Check**:
   ```bash
   echo | openssl s_client -servername coder-dev.example.com -connect coder-dev.example.com:443 2>/dev/null | openssl x509 -noout -dates
   ```

2. **SSL Labs Test**:
   - Visit: https://www.ssllabs.com/ssltest/
   - Enter your domain for comprehensive SSL analysis

3. **Health Check Endpoints**:
   ```bash
   # Check main site
   curl -I https://coder-dev.example.com/healthz

   # Check workspace subdomain
   curl -I https://test.coder-dev.example.com/
   ```

## Summary

The Coder on Scaleway infrastructure provides flexible deployment options:

- **IP-Only**: Quick setup for development and testing
- **Domain-Based**: Production-ready with automatic SSL certificates

The transition between modes is seamless, requiring only a domain name configuration and DNS setup. Let's Encrypt integration via Scaleway makes certificate management completely automated, providing enterprise-grade security without operational overhead.

For production deployments, always use domain-based access to ensure security, professional appearance, and compatibility with enterprise security policies.