#!/usr/bin/env bash
# s3-setup.sh - Interactive setup for S3-compatible storage providers
#
# Usage: bash s3-setup.sh [provider]
#
# Supported providers: aws, r2, minio, b2, do-spaces, wasabi, custom
#
# This script helps configure AWS CLI profiles and rclone remotes
# for S3-compatible storage providers.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== S3-Compatible Storage Setup ===${NC}"
echo ""

# Check available tools
HAS_AWS=false
HAS_RCLONE=false

command -v aws &>/dev/null && HAS_AWS=true
command -v rclone &>/dev/null && HAS_RCLONE=true

echo "Available tools:"
$HAS_AWS && echo -e "  ${GREEN}[x] aws cli${NC}" || echo -e "  ${YELLOW}[ ] aws cli (not installed)${NC}"
$HAS_RCLONE && echo -e "  ${GREEN}[x] rclone${NC}" || echo -e "  ${YELLOW}[ ] rclone (not installed)${NC}"
echo ""

if ! $HAS_AWS && ! $HAS_RCLONE; then
    echo "No S3 tools found. Install at least one:"
    echo "  AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    echo "  rclone:  https://rclone.org/install/"
    exit 1
fi

# Provider selection
PROVIDER="${1:-}"
if [ -z "$PROVIDER" ]; then
    echo "Select a provider:"
    echo "  1) AWS S3"
    echo "  2) Cloudflare R2"
    echo "  3) MinIO (self-hosted)"
    echo "  4) Backblaze B2"
    echo "  5) DigitalOcean Spaces"
    echo "  6) Wasabi"
    echo "  7) Custom S3-compatible"
    echo ""
    read -rp "Choice [1-7]: " CHOICE

    case $CHOICE in
        1) PROVIDER="aws" ;;
        2) PROVIDER="r2" ;;
        3) PROVIDER="minio" ;;
        4) PROVIDER="b2" ;;
        5) PROVIDER="do-spaces" ;;
        6) PROVIDER="wasabi" ;;
        7) PROVIDER="custom" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

# Provider-specific defaults
case $PROVIDER in
    aws)
        PROFILE_NAME="default"
        ENDPOINT=""
        RCLONE_PROVIDER="AWS"
        echo -e "${CYAN}Setting up AWS S3${NC}"
        read -rp "AWS Region [us-east-1]: " REGION
        REGION="${REGION:-us-east-1}"
        ;;
    r2)
        PROFILE_NAME="r2"
        RCLONE_PROVIDER="Cloudflare"
        echo -e "${CYAN}Setting up Cloudflare R2${NC}"
        read -rp "Cloudflare Account ID: " ACCOUNT_ID
        ENDPOINT="https://${ACCOUNT_ID}.r2.cloudflarestorage.com"
        REGION="auto"
        ;;
    minio)
        PROFILE_NAME="minio"
        RCLONE_PROVIDER="Minio"
        echo -e "${CYAN}Setting up MinIO${NC}"
        read -rp "MinIO endpoint [http://localhost:9000]: " ENDPOINT
        ENDPOINT="${ENDPOINT:-http://localhost:9000}"
        REGION="us-east-1"
        ;;
    b2)
        PROFILE_NAME="b2"
        RCLONE_PROVIDER="Backblaze"
        echo -e "${CYAN}Setting up Backblaze B2${NC}"
        read -rp "B2 region (e.g. us-west-004): " REGION
        ENDPOINT="https://s3.${REGION}.backblazeb2.com"
        ;;
    do-spaces)
        PROFILE_NAME="do-spaces"
        RCLONE_PROVIDER="DigitalOcean"
        echo -e "${CYAN}Setting up DigitalOcean Spaces${NC}"
        read -rp "Spaces region (e.g. nyc3, sfo3, ams3): " REGION
        ENDPOINT="https://${REGION}.digitaloceanspaces.com"
        ;;
    wasabi)
        PROFILE_NAME="wasabi"
        RCLONE_PROVIDER="Wasabi"
        echo -e "${CYAN}Setting up Wasabi${NC}"
        read -rp "Wasabi region [us-east-1]: " REGION
        REGION="${REGION:-us-east-1}"
        ENDPOINT="https://s3.${REGION}.wasabisys.com"
        ;;
    custom)
        echo -e "${CYAN}Setting up Custom S3-Compatible Provider${NC}"
        read -rp "Profile/remote name: " PROFILE_NAME
        read -rp "S3 endpoint URL: " ENDPOINT
        read -rp "Region [us-east-1]: " REGION
        REGION="${REGION:-us-east-1}"
        RCLONE_PROVIDER="Other"
        ;;
    *)
        echo "Unknown provider: $PROVIDER"
        exit 1
        ;;
esac

echo ""
read -rp "Access Key ID: " ACCESS_KEY
read -rsp "Secret Access Key: " SECRET_KEY
echo ""

# Configure AWS CLI
if $HAS_AWS; then
    echo ""
    echo -e "${GREEN}Configuring AWS CLI profile '${PROFILE_NAME}'...${NC}"

    aws configure set aws_access_key_id "$ACCESS_KEY" --profile "$PROFILE_NAME"
    aws configure set aws_secret_access_key "$SECRET_KEY" --profile "$PROFILE_NAME"
    aws configure set region "$REGION" --profile "$PROFILE_NAME"
    aws configure set output json --profile "$PROFILE_NAME"

    if [ -n "$ENDPOINT" ]; then
        aws configure set endpoint_url "$ENDPOINT" --profile "$PROFILE_NAME"
    fi

    # Path-style for non-AWS providers
    if [ "$PROVIDER" != "aws" ]; then
        aws configure set "profile.${PROFILE_NAME}.s3.addressing_style" path 2>/dev/null || true
    fi

    echo -e "${GREEN}AWS CLI profile '${PROFILE_NAME}' configured.${NC}"
fi

# Configure rclone
if $HAS_RCLONE; then
    echo ""
    echo -e "${GREEN}Configuring rclone remote '${PROFILE_NAME}'...${NC}"

    RCLONE_CONF="${RCLONE_CONFIG:-${HOME}/.config/rclone/rclone.conf}"
    mkdir -p "$(dirname "$RCLONE_CONF")"

    # Check if remote already exists
    if rclone listremotes 2>/dev/null | grep -q "^${PROFILE_NAME}:$"; then
        echo -e "${YELLOW}Remote '${PROFILE_NAME}' already exists in rclone. Updating...${NC}"
        rclone config delete "$PROFILE_NAME" 2>/dev/null || true
    fi

    # Build config
    {
        echo ""
        echo "[${PROFILE_NAME}]"
        echo "type = s3"
        echo "provider = ${RCLONE_PROVIDER}"
        echo "access_key_id = ${ACCESS_KEY}"
        echo "secret_access_key = ${SECRET_KEY}"
        [ -n "$ENDPOINT" ] && echo "endpoint = ${ENDPOINT}"
        echo "region = ${REGION}"
        echo "acl = private"
        [ "$PROVIDER" != "aws" ] && echo "force_path_style = true"
        [ "$PROVIDER" = "r2" ] && echo "no_check_bucket = true"
    } >> "$RCLONE_CONF"

    echo -e "${GREEN}rclone remote '${PROFILE_NAME}' configured.${NC}"
fi

# Verify connection
echo ""
echo -e "${GREEN}Verifying connection...${NC}"

VERIFIED=false

if $HAS_AWS; then
    if [ -n "$ENDPOINT" ]; then
        if aws s3 ls --profile "$PROFILE_NAME" --endpoint-url "$ENDPOINT" 2>/dev/null; then
            echo -e "${GREEN}AWS CLI: Connection successful${NC}"
            VERIFIED=true
        else
            echo -e "${YELLOW}AWS CLI: Could not list buckets (check credentials)${NC}"
        fi
    else
        if aws s3 ls --profile "$PROFILE_NAME" 2>/dev/null; then
            echo -e "${GREEN}AWS CLI: Connection successful${NC}"
            VERIFIED=true
        else
            echo -e "${YELLOW}AWS CLI: Could not list buckets (check credentials)${NC}"
        fi
    fi
fi

if $HAS_RCLONE; then
    if rclone lsd "${PROFILE_NAME}:" 2>/dev/null; then
        echo -e "${GREEN}rclone: Connection successful${NC}"
        VERIFIED=true
    else
        echo -e "${YELLOW}rclone: Could not list buckets (check credentials)${NC}"
    fi
fi

echo ""
if $VERIFIED; then
    echo -e "${GREEN}Setup complete!${NC}"
    echo ""
    echo "Quick start commands:"
    if $HAS_AWS; then
        if [ -n "$ENDPOINT" ]; then
            echo "  aws s3 ls --profile ${PROFILE_NAME} --endpoint-url ${ENDPOINT}"
        else
            echo "  aws s3 ls --profile ${PROFILE_NAME}"
        fi
    fi
    if $HAS_RCLONE; then
        echo "  rclone lsd ${PROFILE_NAME}:"
    fi
else
    echo -e "${YELLOW}Could not verify connection. Please check your credentials and endpoint.${NC}"
fi
