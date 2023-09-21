#!/usr/bin/env zx
$.verbose = false

const latestVersion = argv["version"]
const helmRelease = argv["helm-release"]

const yq = await which("yq")
const yamlPath = ".spec.values.env.VERSION"

// get the current bedrock version from yaml
const result = await $`${yq} ${yamlPath} ${helmRelease}`
const currentVersion = result.stdout.trim().replace(new RegExp('"', "g"), "")
echo(`${currentVersion}`)
if (latestVersion !== currentVersion) {
  await $`sed -i "s%${currentVersion}%${latestVersion}%g" ${helmRelease}`
  echo(`${latestVersion}`)
}
