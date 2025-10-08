#!/bin/bash

# Android Keystore Generator
# This script helps you create a new Android keystore for signing your apps

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Android Keystore Generator ===${NC}"
echo ""
echo "This script will help you create a new Android keystore for signing your apps."
echo ""

# Get project directory
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
DEFAULT_KEYSTORE_PATH="$HOME/android-signing.keystore"
DEFAULT_ALIAS="release"
DEFAULT_VALIDITY="10000"  # ~27 years

# Prompt for keystore location
echo -e "${YELLOW}Step 1: Keystore Location${NC}"
echo "Where do you want to save the keystore?"
echo "Default: $DEFAULT_KEYSTORE_PATH"
read -p "Press Enter for default or type a path: " KEYSTORE_PATH
KEYSTORE_PATH=${KEYSTORE_PATH:-$DEFAULT_KEYSTORE_PATH}

# Check if keystore already exists
if [ -f "$KEYSTORE_PATH" ]; then
    echo -e "${RED}Error: Keystore already exists at: $KEYSTORE_PATH${NC}"
    echo "If you want to create a new one, please delete the old one first or choose a different path."
    exit 1
fi

# Prompt for alias
echo ""
echo -e "${YELLOW}Step 2: Key Alias${NC}"
echo "Choose an alias name for your key (e.g., 'release', 'production', 'myapp')"
echo "Default: $DEFAULT_ALIAS"
read -p "Alias name: " KEY_ALIAS
KEY_ALIAS=${KEY_ALIAS:-$DEFAULT_ALIAS}

# Prompt for passwords
echo ""
echo -e "${YELLOW}Step 3: Passwords${NC}"
echo "You need to set two passwords:"
echo "  1. Keystore password (protects the keystore file)"
echo "  2. Key password (protects the specific key)"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Save these passwords in a secure location!${NC}"
echo "You will need them every time you build a release version of your app."
echo ""

# Keystore password
while true; do
    read -s -p "Enter keystore password (min 6 characters): " KEYSTORE_PASS
    echo ""
    if [ ${#KEYSTORE_PASS} -lt 6 ]; then
        echo -e "${RED}Password must be at least 6 characters${NC}"
        continue
    fi
    read -s -p "Confirm keystore password: " KEYSTORE_PASS_CONFIRM
    echo ""
    if [ "$KEYSTORE_PASS" != "$KEYSTORE_PASS_CONFIRM" ]; then
        echo -e "${RED}Passwords don't match. Try again.${NC}"
        continue
    fi
    break
done

# Key password
echo ""
echo "Now set the key password (can be the same as keystore password)"
while true; do
    read -s -p "Enter key password (min 6 characters): " KEY_PASS
    echo ""
    if [ ${#KEY_PASS} -lt 6 ]; then
        echo -e "${RED}Password must be at least 6 characters${NC}"
        continue
    fi
    read -s -p "Confirm key password: " KEY_PASS_CONFIRM
    echo ""
    if [ "$KEY_PASS" != "$KEY_PASS_CONFIRM" ]; then
        echo -e "${RED}Passwords don't match. Try again.${NC}"
        continue
    fi
    break
done

# Prompt for certificate information
echo ""
echo -e "${YELLOW}Step 4: Certificate Information${NC}"
echo "This information will be embedded in your certificate."
echo "(You can press Enter to use defaults for testing, but use real info for production)"
echo ""

read -p "First and Last Name [Boardible Team]: " CN
CN=${CN:-"Boardible Team"}

read -p "Organization Unit [Development]: " OU
OU=${OU:-"Development"}

read -p "Organization [Boardible]: " O
O=${O:-"Boardible"}

read -p "City or Locality [Your City]: " L
L=${L:-"Your City"}

read -p "State or Province [Your State]: " ST
ST=${ST:-"Your State"}

read -p "Country Code (2 letters) [US]: " C
C=${C:-"US"}

# Create keystore directory if needed
mkdir -p "$(dirname "$KEYSTORE_PATH")"

# Generate the keystore
echo ""
echo -e "${BLUE}Generating keystore...${NC}"
keytool -genkeypair -v \
    -keystore "$KEYSTORE_PATH" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity "$DEFAULT_VALIDITY" \
    -storepass "$KEYSTORE_PASS" \
    -keypass "$KEY_PASS" \
    -dname "CN=$CN, OU=$OU, O=$O, L=$L, ST=$ST, C=$C"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Keystore created successfully!${NC}"
    echo ""
    echo -e "${BLUE}Keystore Information:${NC}"
    echo "  Location: $KEYSTORE_PATH"
    echo "  Alias: $KEY_ALIAS"
    echo "  Validity: $DEFAULT_VALIDITY days (~27 years)"
    echo ""
    
    # Verify the keystore
    echo -e "${BLUE}Verifying keystore...${NC}"
    keytool -list -v -keystore "$KEYSTORE_PATH" -storepass "$KEYSTORE_PASS" | head -20
    
    echo ""
    echo -e "${GREEN}=== Next Steps ===${NC}"
    echo ""
    echo "1. Update your .env.android.local file with these values:"
    echo ""
    echo -e "${YELLOW}export ANDROID_KEYSTORE_PATH=\"$KEYSTORE_PATH\"${NC}"
    echo -e "${YELLOW}export ANDROID_KEYSTORE_PASS=\"$KEYSTORE_PASS\"${NC}"
    echo -e "${YELLOW}export ANDROID_KEY_ALIAS=\"$KEY_ALIAS\"${NC}"
    echo -e "${YELLOW}export ANDROID_KEY_PASS=\"$KEY_PASS\"${NC}"
    echo ""
    echo "2. ⚠️  BACKUP YOUR KEYSTORE AND PASSWORDS!"
    echo "   - Store keystore file in a secure location"
    echo "   - Save passwords in a password manager"
    echo "   - If you lose these, you cannot update your app on Google Play!"
    echo ""
    echo "3. Optional: Add keystore to your CI/CD:"
    echo "   - Base64 encode: cat \"$KEYSTORE_PATH\" | base64 > keystore.txt"
    echo "   - Add to GitHub Secrets as ANDROID_KEYSTORE_BASE64"
    echo ""
    
    # Offer to update .env file
    ENV_FILE="$SCRIPT_DIR/.env.android.local"
    if [ -f "$ENV_FILE" ]; then
        echo ""
        read -p "Do you want to automatically update $ENV_FILE? (yes/no): " UPDATE_ENV
        if [ "$UPDATE_ENV" = "yes" ]; then
            # Create backup
            cp "$ENV_FILE" "$ENV_FILE.backup"
            echo "Backup created: $ENV_FILE.backup"
            
            # Update the file
            sed -i '' "s|^export ANDROID_KEYSTORE_PATH=.*|export ANDROID_KEYSTORE_PATH=\"$KEYSTORE_PATH\"|" "$ENV_FILE"
            sed -i '' "s|^export ANDROID_KEYSTORE_PASS=.*|export ANDROID_KEYSTORE_PASS=\"$KEYSTORE_PASS\"|" "$ENV_FILE"
            sed -i '' "s|^export ANDROID_KEY_ALIAS=.*|export ANDROID_KEY_ALIAS=\"$KEY_ALIAS\"|" "$ENV_FILE"
            sed -i '' "s|^export ANDROID_KEY_PASS=.*|export ANDROID_KEY_PASS=\"$KEY_PASS\"|" "$ENV_FILE"
            
            echo -e "${GREEN}✅ Updated $ENV_FILE${NC}"
            echo ""
            echo "You can now build and sign your Android app:"
            echo "  source Scripts/.env.android.local"
            echo "  ./Scripts/unityBuild.sh --platform android --profile production"
        fi
    fi
else
    echo -e "${RED}❌ Failed to create keystore${NC}"
    exit 1
fi
