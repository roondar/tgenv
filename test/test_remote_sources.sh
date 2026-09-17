#!/usr/bin/env bash

set -uo pipefail
declare -a errors

source "${TGENV_ROOT}/libexec/helpers"

[ "${TGENV_DEBUG:-0}" -gt 0 ] && set -x
source "$(dirname "$0")/helpers.sh" \
  || error_and_die "Failed to load test helpers: $(dirname "${0}")/helpers.sh"

tmp_dir="$(mktemp -d /tmp/tgenv-remote-test.XXXXXXXX)"
trap 'rm -rf "${tmp_dir}"' EXIT

##################################################
# Test custom release discovery endpoint
##################################################
echo "### List versions from custom release source"

cat > "${tmp_dir}/releases.json" <<'EOF'
[
  {"tag_name":"v0.58.8"},
  {"tag_name":"v1.0.0"},
  {"tag_name":"v0.58.8"},
  {"tag_name":"v1.1.0-beta.1"},
  {"tag":"0.58.7"}
]
EOF

result="$(TGENV_REMOTE_RELEASES="file://${tmp_dir}/releases.json" tgenv list-remote)"
expected="$(cat <<'EOF'
1.0.0
0.58.8
0.58.7
EOF
)"

if [ "${expected}" != "${result}" ]; then
  error_and_proceed "Custom release source mismatch.\nExpected:\n${expected}\nGot:\n${result}"
fi

##################################################
# Test custom release discovery + binary download
##################################################
echo "### Install from custom release and download sources"
cleanup || error_and_die "Cleanup failed?!"

version="0.58.8"

case "$(uname -m)" in
  aarch64* | arm64*)
    arch="arm64"
    ;;
  *)
    arch="amd64"
    ;;
esac

case "$(uname -s)" in
  Darwin*)
    os="darwin_${arch}"
    ;;
  MINGW64* | MSYS_NT* | CYGWIN_NT*)
    os="windows_${arch}"
    ;;
  *)
    os="linux_${arch}"
    ;;
esac

mkdir -p "${tmp_dir}/downloads/v${version}"
cat > "${tmp_dir}/downloads/v${version}/terragrunt_${os}" <<EOF
#!/usr/bin/env bash
echo "terragrunt version v${version}"
EOF
chmod +x "${tmp_dir}/downloads/v${version}/terragrunt_${os}"

(
  export TGENV_REMOTE_RELEASES="file://${tmp_dir}/releases.json"
  export TGENV_REMOTE_DOWNLOAD_FORMAT="file://${tmp_dir}/downloads/v{version}/terragrunt_{os}"
  tgenv install "${version}" || exit 1
  check_version "${version}" || exit 1
) || error_and_proceed "Installing ${version} from custom remote sources"

if [ ${#errors[@]} -gt 0 ]; then
  echo -e "\033[0;31m===== The following remote source tests failed =====\033[0;39m" >&2
  for error in "${errors[@]}"; do
    echo -e "\t${error}"
  done
  exit 1
else
  echo -e "\033[0;32mAll remote source tests passed.\033[0;39m"
fi
exit 0
