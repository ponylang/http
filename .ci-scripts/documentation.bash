#!/bin/bash

set -o errexit
set -o nounset

base=$(dirname "$0")
source "${base}/env.bash"

# Gather expected arguments.
if [ $# -lt 2 ]
then
  echo "Tag and GH personal access token are required"
  exit 1
fi

# Directory we are going to do additional work in
GEN_MD="$(mktemp -d)"

# From command line
TAG=$1
GITHUB_TOKEN=$2

# Shouldn't need to touch these
BUILD_DIR="build/http-docs"
DOCS_DIR="${GEN_MD}/http/${TAG}"

# Generated markdown repo
echo "Cloning main.actor-package-markdown repo into ${GEN_MD}"
git clone \
  "https://${GITHUB_TOKEN}@github.com/${REPO_OWNER}/main.actor-package-markdown.git" \
  "${GEN_MD}"

# Make the docs
# We make assumptions about the location for the docs
make docs

# $BUILD_DIR contains the raw generated markdown for our documentation
pushd "${BUILD_DIR}" || exit 1
mkdir -p "${DOCS_DIR}"
cp -r docs/* "${DOCS_DIR}"/
cp -r mkdocs.yml "${DOCS_DIR}"

# Upload any new documentation
echo "Preparing to upload generated markdown content from ${GEN_MD}"
echo "Git fiddling commences..."
pushd "${GEN_MD}" || exit 1
echo "Creating a branch for generated documentation..."
branch_name="http-${TAG}"
git checkout -b "${branch_name}"
echo "Adding content..."
git add .
git commit -m "Add docs for package: http version: ${TAG}"
echo "Uploading new generated markdown content..."
git push --set-upstream origin "${branch_name}"
echo "Generated markdown content has been uploaded!"
popd || exit 1

# Create a PR
echo "Preparing to create a pull request..."
jsontemplate="
{
  \"title\":\$title,
  \"head\":\$incoming_repo_and_branch,
  \"base\":\"master\"
}
"

json=$(jq -n \
--arg title "http ${TAG}" \
--arg incoming_repo_and_branch "${REPO_OWNER}:${branch_name}" \
"${jsontemplate}")


echo "Curling..."
result=$(curl -X POST \
  https://api.github.com/repos/ponylang/main.actor-package-markdown/pulls \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "${GITHUB_USER}:${GITHUB_TOKEN}" \
  --data "${json}")

rslt_scan=$(echo "${result}" | jq -r '.id')
if [ "$rslt_scan" != null ]
then
  echo "PR successfully created!"
else
  echo "Unable to create PR, here's the curl output..."
  echo "${result}"
  exit 1
fi
