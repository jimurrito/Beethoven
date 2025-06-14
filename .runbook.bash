#!/bin/bash

# Publish to Hex - ENSURE YOU ITERATE THE VERSION OF THE PACKAGE!
HEX_API_KEY=95a484b47ed2829c9b4c5b2a602be6f3 mix hex.publish --yes

# if you need a new key, run this. Key was saved to Bitwarden
#mix hex.user auth
#mix hex.user key generate --key-name publish-cli --permission api:write
