#!/bin/bash

# Input Validation and Security Library for Bash Scripts
# Provides secure functions to prevent command injection and validate inputs

set -euo pipefail

# ANSI color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Security configuration
readonly VALIDATION_LOG="${VALIDATION_LOG:-/dev/null}"
readonly MAX_INPUT_LENGTH="${MAX_INPUT_LENGTH:-1000}"
readonly ALLOWED_CHARACTERS_PATTERN="${ALLOWED_CHARACTERS_PATTERN:-^[a-zA-Z0-9._-]+$}"

# Logging function
log_validation() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$VALIDATION_LOG" 2>/dev/null || true
}

# Error handling
validation_error() {
    local message="$1"
    log_validation "ERROR" "$message"
    echo -e "${RED}[VALIDATION ERROR]${NC} $message" >&2
    return 1
}

# Success logging
validation_success() {
    local message="$1"
    log_validation "INFO" "$message"
    echo -e "${GREEN}[VALIDATION SUCCESS]${NC} $message" >&2
}

# Warning logging
validation_warning() {
    local message="$1"
    log_validation "WARN" "$message"
    echo -e "${YELLOW}[VALIDATION WARNING]${NC} $message" >&2
}

# Basic input sanitization
sanitize_input() {
    local input="$1"

    # Remove null bytes and control characters
    input=$(echo "$input" | tr -d '\000-\037\177')

    # Limit length
    if [[ ${#input} -gt $MAX_INPUT_LENGTH ]]; then
        validation_error "Input exceeds maximum length of $MAX_INPUT_LENGTH characters"
        return 1
    fi

    echo "$input"
}

# Validate environment name (dev, staging, prod)
validate_environment() {
    local env="$1"

    case "$env" in
        dev|staging|prod)
            validation_success "Environment '$env' is valid"
            return 0
            ;;
        *)
            validation_error "Invalid environment '$env'. Must be one of: dev, staging, prod"
            return 1
            ;;
    esac
}

# Validate boolean values
validate_boolean() {
    local value="$1"
    local var_name="${2:-value}"

    case "${value,,}" in
        true|false|yes|no|1|0|on|off)
            validation_success "Boolean '$var_name' is valid: $value"
            return 0
            ;;
        *)
            validation_error "Invalid boolean value for '$var_name': $value. Must be true/false, yes/no, 1/0, or on/off"
            return 1
            ;;
    esac
}

# Validate file path (no directory traversal)
validate_file_path() {
    local path="$1"
    local allow_absolute="${2:-false}"

    # Check for null or empty
    if [[ -z "$path" ]]; then
        validation_error "File path cannot be empty"
        return 1
    fi

    # Check for directory traversal attempts
    if [[ "$path" == *".."* ]]; then
        validation_error "Path contains directory traversal sequences: $path"
        return 1
    fi

    # Check for absolute paths if not allowed
    if [[ "$allow_absolute" == "false" && "$path" == /* ]]; then
        validation_error "Absolute paths not allowed: $path"
        return 1
    fi

    # Check for null bytes
    if [[ "$path" == *$'\0'* ]]; then
        validation_error "Path contains null bytes: $path"
        return 1
    fi

    validation_success "File path is valid: $path"
    return 0
}

# Validate AWS/Scaleway region
validate_region() {
    local region="$1"

    # Basic format validation for Scaleway regions
    if [[ "$region" =~ ^[a-z]{2}-[a-z]{3}$ ]]; then
        validation_success "Region format is valid: $region"
        return 0
    fi

    validation_error "Invalid region format: $region. Expected format: xx-xxx (e.g., fr-par)"
    return 1
}

# Validate DNS name/hostname
validate_hostname() {
    local hostname="$1"

    # RFC 1123 hostname validation
    if [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        if [[ ${#hostname} -le 253 ]]; then
            validation_success "Hostname is valid: $hostname"
            return 0
        fi
    fi

    validation_error "Invalid hostname: $hostname"
    return 1
}

# Validate email address
validate_email() {
    local email="$1"

    # Basic email validation (not perfect but good enough for most cases)
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        validation_success "Email is valid: $email"
        return 0
    fi

    validation_error "Invalid email address: $email"
    return 1
}

# Validate port number
validate_port() {
    local port="$1"
    local port_type="${2:-any}"

    # Check if it's a number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        validation_error "Port must be a number: $port"
        return 1
    fi

    # Check range
    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        validation_error "Port out of valid range (1-65535): $port"
        return 1
    fi

    # Check for privileged ports if specified
    if [[ "$port_type" == "unprivileged" && $port -lt 1024 ]]; then
        validation_error "Unprivileged port required (>=1024): $port"
        return 1
    fi

    validation_success "Port is valid: $port"
    return 0
}

# Validate UUID
validate_uuid() {
    local uuid="$1"

    if [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        validation_success "UUID is valid: $uuid"
        return 0
    fi

    validation_error "Invalid UUID format: $uuid"
    return 1
}

# Validate CIDR notation
validate_cidr() {
    local cidr="$1"

    if [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        # Extract IP and prefix
        local ip="${cidr%/*}"
        local prefix="${cidr#*/}"

        # Validate IP octets
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -lt 0 || $octet -gt 255 ]]; then
                validation_error "Invalid IP octet in CIDR: $cidr"
                return 1
            fi
        done

        # Validate prefix
        if [[ $prefix -lt 0 || $prefix -gt 32 ]]; then
            validation_error "Invalid CIDR prefix: $cidr"
            return 1
        fi

        validation_success "CIDR is valid: $cidr"
        return 0
    fi

    validation_error "Invalid CIDR format: $cidr"
    return 1
}

# Validate JSON string
validate_json() {
    local json_string="$1"

    if command -v jq >/dev/null 2>&1; then
        if echo "$json_string" | jq . >/dev/null 2>&1; then
            validation_success "JSON is valid"
            return 0
        else
            validation_error "Invalid JSON format"
            return 1
        fi
    else
        validation_warning "jq not available, skipping JSON validation"
        return 0
    fi
}

# Secure command execution with validation
secure_execute() {
    local cmd=("$@")

    # Log the command for auditing
    log_validation "EXEC" "Executing: ${cmd[*]}"

    # Execute with error handling
    if "${cmd[@]}"; then
        log_validation "EXEC_SUCCESS" "Command completed successfully: ${cmd[*]}"
        return 0
    else
        local exit_code=$?
        log_validation "EXEC_FAILURE" "Command failed with exit code $exit_code: ${cmd[*]}"
        return $exit_code
    fi
}

# Quote arguments to prevent command injection
quote_args() {
    local quoted_args=()
    for arg in "$@"; do
        # Use printf %q to properly quote the argument
        quoted_args+=("$(printf %q "$arg")")
    done
    echo "${quoted_args[*]}"
}

# Validate and sanitize user input for specific contexts
validate_terraform_var() {
    local var_name="$1"
    local var_value="$2"

    case "$var_name" in
        environment)
            validate_environment "$var_value"
            ;;
        region)
            validate_region "$var_value"
            ;;
        *_email)
            validate_email "$var_value"
            ;;
        *_port)
            validate_port "$var_value"
            ;;
        *_cidr)
            validate_cidr "$var_value"
            ;;
        *)
            # Generic validation for unknown variables
            sanitize_input "$var_value" >/dev/null
            validation_success "Variable '$var_name' passed generic validation"
            ;;
    esac
}

# Main validation function for script arguments
validate_script_args() {
    local script_name="$1"
    shift
    local args=("$@")

    log_validation "START" "Starting validation for script: $script_name"

    for arg in "${args[@]}"; do
        # Basic sanitization
        if ! sanitize_input "$arg" >/dev/null; then
            validation_error "Argument failed sanitization: $arg"
            return 1
        fi
    done

    validation_success "All arguments passed validation for script: $script_name"
    return 0
}

# Export functions for use in other scripts
export -f sanitize_input validate_environment validate_boolean validate_file_path
export -f validate_region validate_hostname validate_email validate_port validate_uuid
export -f validate_cidr validate_json secure_execute quote_args validate_terraform_var
export -f validate_script_args validation_error validation_success validation_warning