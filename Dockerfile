# Thin deployment image: pulled from GitHub Container Registry
# Built via .github/workflows/docker-publish.yml
FROM ghcr.io/aadhiishvar/librarian-ai:latest

# The following is just to ensure HF triggers a rebuild when this file changes
# Metadata: librarian-ai-deployment-v1.11
