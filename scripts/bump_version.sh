#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: $0 <major|minor|patch> [stable|beta|alpha]"
	exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
	usage
fi

bump_type="$1"
if [[ "$bump_type" != "major" && "$bump_type" != "minor" && "$bump_type" != "patch" ]]; then
	usage
fi

release_channel="${2:-stable}"
if [[ "$release_channel" != "stable" && "$release_channel" != "beta" && "$release_channel" != "alpha" ]]; then
	usage
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
	echo "Error: not inside a git repository."
	exit 1
fi
cd "$repo_root"

toc_file="QuestTogether.toc"
if [[ ! -f "$toc_file" ]]; then
	echo "Error: $toc_file not found at repo root."
	exit 1
fi

latest_stable_tag="$(git tag --list | awk '/^v[0-9]+\.[0-9]+\.[0-9]+$/' | sort -V | tail -n 1)"
stable_base_version_source=""
stable_base_version=""

if [[ -n "$latest_stable_tag" ]]; then
	stable_base_version="${latest_stable_tag#v}"
	stable_base_version_source="git tag ${latest_stable_tag}"
else
	toc_version="$(sed -n 's/^## Version:[[:space:]]*//p' "$toc_file" | head -n 1)"
	if [[ -z "$toc_version" ]]; then
		echo "Error: could not find a stable vX.Y.Z tag and could not find '## Version:' in $toc_file."
		exit 1
	fi
	if [[ "$toc_version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-(alpha|beta)\.[0-9]+)?$ ]]; then
		stable_base_version="${BASH_REMATCH[1]}"
		stable_base_version_source="${toc_file}"
	else
		echo "Error: version '$toc_version' from ${toc_file} is not in x.y.z[-alpha.N|-beta.N] format."
		exit 1
	fi
fi

if [[ ! "$stable_base_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
	echo "Error: base version '$stable_base_version' is not in x.y.z format."
	exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$bump_type" in
major)
	major=$((major + 1))
	minor=0
	patch=0
	;;
minor)
	minor=$((minor + 1))
	patch=0
	;;
	patch)
		patch=$((patch + 1))
		;;
esac

target_base_version="${major}.${minor}.${patch}"
new_version=""
new_tag=""

if [[ "$release_channel" == "stable" ]]; then
	new_version="${target_base_version}"
	new_tag="v${new_version}"
else
	channel_max="$(git tag --list "v${target_base_version}-${release_channel}.*" \
		| sed -n "s/^v${target_base_version}-${release_channel}\.\([0-9][0-9]*\)$/\1/p" \
		| sort -n \
		| tail -n 1)"
	if [[ -n "$channel_max" ]]; then
		channel_next=$((channel_max + 1))
	else
		channel_next=1
	fi
	new_version="${target_base_version}-${release_channel}.${channel_next}"
	new_tag="v${new_version}"
fi

if git rev-parse -q --verify "refs/tags/${new_tag}" >/dev/null; then
	echo "Error: local tag '${new_tag}' already exists."
	exit 1
fi

if git ls-remote --tags origin "refs/tags/${new_tag}" | grep -q .; then
	echo "Error: remote tag '${new_tag}' already exists on origin."
	exit 1
fi

echo "Stable base version: ${stable_base_version} (from ${stable_base_version_source})"
echo "Release channel: ${release_channel}"
echo "Bump type: ${bump_type}"
echo "Target base version: ${target_base_version}"
echo "New version: ${new_version}"

echo "Updating ${toc_file} to version ${new_version}..."
tmp_file="$(mktemp)"
awk -v version="${new_version}" '
BEGIN { updated = 0 }
/^## Version:[[:space:]]*/ && updated == 0 {
	print "## Version: " version
	updated = 1
	next
}
{ print }
END {
	if (updated == 0) {
		exit 1
	}
}
' "$toc_file" > "$tmp_file"
mv "$tmp_file" "$toc_file"

echo "Committing ${toc_file}..."
git add "$toc_file"
if git diff --cached --quiet -- "$toc_file"; then
	echo "Error: ${toc_file} did not change; nothing to commit."
	exit 1
fi
git commit -m "Bump version to ${new_version}" -- "$toc_file"

release_commit="$(git rev-parse --short HEAD)"
echo "Tagging ${release_commit} as ${new_tag}..."
git tag -a "${new_tag}" -m "Release ${new_tag}" HEAD

echo "Pushing tag ${new_tag} to origin..."
git push origin "${new_tag}"

echo "Done."
echo "Committed: ${release_commit}"
echo "Tag pushed: ${new_tag}"
echo "Updated file: ${toc_file}"
