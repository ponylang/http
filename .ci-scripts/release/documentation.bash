#!/bin/bash

# Generates documentation for the release and uploads to main.actor
#
# Tools required in the environment that runs this:
#
# - bash
# - curl
# - jq
# - git
# - make
# - ponyc
# - corral

set -o errexit

# Pull in shared configuration specific to this repo
base=$(dirname "$0")
# shellcheck source=.ci-scripts/release/config.bash
source "${base}/config.bash"

# Verify ENV is set up correctly
# We validate all that need to be set in case, in an absolute emergency,
# we need to run this by hand. Otherwise the GitHub actions environment should
# provide all of these if properly configured
if [[ -z "${RELEASE_TOKEN}" ]]; then
  echo -e "\e[31mA personal access token needs to be set in RELEASE_TOKEN."
  echo -e "\e[31mIt should not be secrets.GITHUB_TOKEN. It has to be a"
  echo -e "\e[31mpersonal access token otherwise next steps in the release"
  echo -e "\e[31mprocess WILL NOT trigger."
  echo -e "\e[31mPersonal access tokens are in the form:"
  echo -e "\e[31m     TOKEN"
  echo -e "\e[31mfor example:"
  echo -e "\e[31m     1234567890"
  echo -e "\e[31mExiting.\e[0m"
  exit 1
fi

if [[ -z "${GITHUB_REF}" ]]; then
  echo -e "\e[31mThe release tag needs to be set in GITHUB_REF."
  echo -e "\e[31mThe tag should be in the following GitHub specific form:"
  echo -e "\e[31m    /refs/tags/X.Y.Z"
  echo -e "\e[31mwhere X.Y.Z is the version we are releasing"
  echo -e "\e[31mExiting.\e[0m"
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY}" ]]; then
  echo -e "\e[31mName of this repository needs to be set in GITHUB_REPOSITORY."
  echo -e "\e[31mShould be in the form OWNER/REPO, for example:"
  echo -e "\e[31m     ponylang/ponyup"
  echo -e "\e[31mExiting.\e[0m"
  exit 1
fi

# no unset variables allowed from here on out
# allow above so we can display nice error messages for expected unset variables
set -o nounset

# Set up GitHub credentials
git config --global user.name 'Ponylang Main Bot'
git config --global user.email 'ponylang.main@gmail.com'
git config --global push.default simple

# Extract version from tag reference
# Tag ref version: "refs/tags/1.0.0"
# Version: "1.0.0"
VERSION="${GITHUB_REF/refs\/tags\//}"

# Directory we are going to do additional work in
GEN_MD="$(mktemp -d)"

DOCS_DIR="${GEN_MD}/${LIBRARY_NAME}/${VERSION}"

# extract owner from GITHUB_REPOSITORY
IFS="/"
read -ra SPLIT <<< "${GITHUB_REPOSITORY}"
REPO_OWNER="${SPLIT[0]}"

echo -e "\e[34mCloning main.actor-package-markdown repo into ${GEN_MD}\e[0m"
git clone \
  "https://${RELEASE_TOKEN}@github.com/${REPO_OWNER}/main.actor-package-markdown.git" \
  "${GEN_MD}"

# Make the docs
# We make assumptions about the location for the docs
make docs

# $DOCS_BUILD_DIR contains the raw generated markdown for our documentation
pushd "${DOCS_BUILD_DIR}" || exit 1
mkdir -p "${DOCS_DIR}"
cp -r docs/* "${DOCS_DIR}"/
cp -r mkdocs.yml "${DOCS_DIR}"

# Upload any new documentation
echo -e "\e[34mPreparing to upload generated markdown content from ${GEN_MD}\e[0m"
echo -e "\e[34mGit fiddling commences...\e[0m"
pushd "${GEN_MD}" || exit 1
echo -e "\e[34mCreating a branch for generated documentation...\e[0m"
branch_name="${LIBRARY_NAME}-${VERSION}"
git checkout -b "${branch_name}"
echo -e "\e[34mAdding content...\e[0m"
git add .
git commit -m "Add docs for package: ${LIBRARY_NAME} version: ${VERSION}"
echo -e "\e[34mUploading new generated markdown content...\e[0m"
git push --set-upstream origin "${branch_name}"
echo -e "\e[34mGenerated markdown content has been uploaded!\e[0m"
popd || exit 1

# Create a PR
echo -e "\e[34mPreparing to create a pull request...\e[0m"
jsontemplate="
{
  \"title\":\$title,
  \"head\":\$incoming_repo_and_branch,
  \"base\":\"master\"
}
"

json=$(jq -n \
--arg title "${LIBRARY_NAME} ${VERSION}" \
--arg incoming_repo_and_branch "${REPO_OWNER}:${branch_name}" \
"${jsontemplate}")


echo -e "\e[34mCurling...\e[0m"
result=$(curl -X POST \
  https://api.github.com/repos/ponylang/main.actor-package-markdown/pulls \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "${RELEASE_TOKEN}" \
  --data "${json}")

rslt_scan=$(echo "${result}" | jq -r '.id')
if [ "$rslt_scan" != null ]; then
  echo "\e[34mPR successfully created!\e[0m"
else
  echo "\e[31mUnable to create PR, here's the curl output..."
  echo "${result}\e[0m"
  exit 1
fi
