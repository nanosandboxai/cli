#!/usr/bin/env bash
# Builds the Kotlin SDK jar.
#
# The Kotlin facade wraps the Java SDK (sdks/java), so the build compiles the
# Java SDK sources plus the KtJson shim with javac, then compiles the Kotlin
# facade, conformance driver, and smoke test with kotlinc against those
# classes, and finally merges the Java classes into the jar so it is
# self-contained.
#
# Usage (from anywhere):
#     bash sdks/kotlin/build.sh
set -euo pipefail
cd "$(dirname "$0")"

KOTLINC="${KOTLINC:-kotlinc}"
JAVAC="${JAVAC:-javac}"
JAR="${JAR:-jar}"

rm -rf classes
mkdir -p classes

"$JAVAC" -d classes \
  ../java/src/main/java/nanosandbox/*.java \
  src/nanosandbox/KtJson.java

"$KOTLINC" -cp classes \
  src/nanosandbox/*.kt \
  conformance/Run.kt \
  src/test/nanosandbox/SmokeTest.kt \
  -include-runtime -d nanosandbox-kotlin.jar

"$JAR" uf nanosandbox-kotlin.jar -C classes .

echo "built nanosandbox-kotlin.jar"