#!/usr/bin/env bash
# Netlify build hook.
#
# This repository stores a pre-rendered static site artifact. There is nothing to
# build here: the source project renders the site and the artifact is imported and
# committed. This script only verifies that the artifact is present so that a
# misconfigured deployment fails loudly instead of publishing an empty site.

set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-_site}"

if [ ! -d "${ARTIFACT_DIR}" ]; then
    echo "Error: artifact directory '${ARTIFACT_DIR}' not found." >&2
    echo "Import it from the source project frontend before deploying." >&2
    exit 1
fi

if [ -z "$(find "${ARTIFACT_DIR}" -type f -name '*.html' -print -quit)" ]; then
    echo "Error: artifact directory '${ARTIFACT_DIR}' contains no HTML files." >&2
    exit 1
fi

echo "Serving pre-rendered artifact from '${ARTIFACT_DIR}'."
