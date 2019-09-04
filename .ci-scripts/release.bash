#!/bin/bash

set -o errexit
set -o nounset

base=$(dirname "$0")
source "${base}/env.bash"

# Gather expected arguments.
if [ $# -lt 3 ]
then
  echo "Tag, GH personal access token, and Ponylang zulip access token are required"
  exit 1
fi

TAG=$1
GITHUB_TOKEN=$2
ZULIP_TOKEN=$3
# changes tag from "release-1.0.0" to "1.0.0"
VERSION="${TAG/release-/}"

### this doesn't account for master changing commit, assumes we are HEAD
# or can otherwise push without issue. that shouldl error out without issue.
# leaving us to restart from a different HEAD commit
# update CHANGELOG
changelog-tool release "${VERSION}" -e

# commit CHANGELOG updates
git add CHANGELOG.md
git commit -m "Release ${VERSION}"

# tag release
git tag "${VERSION}"

# push to release to remote
git push origin HEAD:master "${VERSION}"

# delete release-VERSION tag
git push --delete origin "release-${VERSION}"

# update CHANGELOG for new entries
changelog-tool unreleased -e

# commit changelog and push to master
git add CHANGELOG.md
git commit -m "Add unreleased section to CHANGELOG post ${VERSION} release

[skip ci]"
git push origin HEAD:master

# release body
echo "Preparing to update GitHub release notes..."

body=$(changelog-tool get "${VERSION}")

jsontemplate="
{
  \"tag_name\":\$version,
  \"name\":\$version,
  \"body\":\$body
}
"

json=$(jq -n \
--arg version "$VERSION" \
--arg body "$body" \
"${jsontemplate}")

echo "Uploading release notes..."

result=$(curl -X POST "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "${GITHUB_USER}:${GITHUB_TOKEN}" \
  --data "${json}")

rslt_scan=$(echo "${result}" | jq -r '.id')
if [ "$rslt_scan" != null ]
then
  echo "Release notes uploaded"
else
  echo "Unable to upload release notes, here's the curl output..."
  echo "${result}"
  exit 1
fi

# Update Last Week in Pony
echo "Adding release to Last Week in Pony..."

result=$(curl https://api.github.com/repos/ponylang/ponylang-website/issues?labels=last-week-in-pony)

lwip_url=$(echo "${result}" | jq -r '.[].url')
if [ "$lwip_url" != "" ]
then
  body="
Version ${VERSION} of http has been released.

See the [release notes](https://github.com/ponylang/http/releases/tag/${VERSION}) for more details.
"

  jsontemplate="
  {
    \"body\":\$body
  }
  "

  json=$(jq -n \
  --arg body "$body" \
  "${jsontemplate}")

  result=$(curl -X POST "$lwip_url/comments" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -u "${GITHUB_USER}:${GITHUB_TOKEN}" \
    --data "${json}")

  rslt_scan=$(echo "${result}" | jq -r '.id')
  if [ "$rslt_scan" != null ]
  then
    echo "Release notice posted to LWIP"
  else
    echo "Unable to post to LWIP, here's the curl output..."
    echo "${result}"
  fi
else
  echo "Unable to post to Last Week in Pony. Can't find the issue."
fi

message="
Version ${VERSION} of http has been released.

See the [release notes](https://github.com/ponylang/http/releases/tag/${VERSION}) for more details.
"

curl -X POST https://ponylang.zulipchat.com/api/v1/messages \
  -u ${ZULIP_TOKEN} \
  -d "type=stream" \
  -d "to=announce" \
  -d "topic=http" \
  -d "content=${message}"
