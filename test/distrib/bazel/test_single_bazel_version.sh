#!/usr/bin/env bash
# Copyright 2021 The gRPC authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

if [ "$#" != "1" ] ; then
    echo "Must supply bazel version to be tested." >/dev/stderr
    exit 1
fi

VERSION="$1"

cd "$(dirname "$0")"/../../..

EXCLUDED_TARGETS=(
  # iOS platform fails the analysis phase since there is no toolchain available
  # for it.
  "-//src/objective-c/..."
  "-//third_party/objective_c/..."

  # Targets here need C++17 to build via a different configuration, so this is
  # done separately
  "-//fuzztest/..."

  # This could be a legitmate failure due to bitrot.
  "-//src/proto/grpc/testing:test_gen_proto"

  # This appears to be a legitimately broken BUILD file. There's a reference to
  # a non-existent "link_dynamic_library.sh".
  "-//third_party/toolchains/rbe_windows_bazel_5.2.0_vs2019:all"
  "-//third_party/toolchains:rbe_windows_default_toolchain_suite"

  # TODO(jtattermusch): add back once fixed
  "-//examples/android/binder/..."

  # Exclude bazelified tests as they contain some bazel hackery
  "-//tools/bazelify_tests/..."
)

TEST_DIRECTORIES=(
  "cpp"
  "python"
)

FAILED_TESTS=""

export OVERRIDE_BAZEL_VERSION="$VERSION"
# when running under bazel docker image, the workspace is read only.
export OVERRIDE_BAZEL_WRAPPER_DOWNLOAD_DIR=/tmp

ACTION_ENV_FLAG="--action_env=bazel_cache_invalidate=version_${VERSION}"

tools/bazel version | grep "$VERSION" || { echo "Detected bazel version did not match expected value of $VERSION" >/dev/stderr; exit 1; }
tools/bazel build "${ACTION_ENV_FLAG}" -- //... "${EXCLUDED_TARGETS[@]}" || FAILED_TESTS="${FAILED_TESTS}buildtest "
tools/bazel build "${ACTION_ENV_FLAG}" --config fuzztest -- //fuzztest/... || FAILED_TESTS="${FAILED_TESTS}fuzztest_buildtest "

for TEST_DIRECTORY in "${TEST_DIRECTORIES[@]}"; do
  pushd "test/distrib/bazel/$TEST_DIRECTORY/"

  tools/bazel version | grep "$VERSION" || { echo "Detected bazel version did not match expected value of $VERSION" >/dev/stderr; exit 1; }
  tools/bazel test "${ACTION_ENV_FLAG}" --test_output=all //:all || FAILED_TESTS="${FAILED_TESTS}distribtest_${TEST_DIRECTORY} "

  popd
done

if [ "$FAILED_TESTS" != "" ]
then
  echo "Failed tests at version ${VERSION}: ${FAILED_TESTS}"
  exit 1
fi
