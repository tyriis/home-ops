const fluxKustomizations = await glob([
  "kubernetes/main/**/flux-sync.yaml",
  "kubernetes/utility/**/flux-sync.yaml",
])

// echo`${JSON.stringify(fluxKustomizations, null, 2)}`

const parseYAML = async (fluxKustomization) => {
  const content = await fs.readFile(fluxKustomization, "utf-8")
  return YAML.parseAllDocuments(content).map((document) =>
    structuredClone(document.toJS())
  )
}

const data = (
  await Promise.all(fluxKustomizations.map((file) => parseYAML(file)))
).flat()

const components = data
  .filter(
    (item) =>
      item.metadata?.annotations?.["backstage.io/discovery"] === "enabled" &&
      item.metadata?.annotations?.["backstage.io/name"]
  )
  .map((item) => item.metadata.annotations["backstage.io/name"])

const componentsWithState = await Promise.all(
  components.map(async (name) => ({
    name,
    exists: await fs.pathExists(
      `docs/backstage/components/${name}/catalog-info.yaml`
    ),
  }))
)

for (const { name, exists } of componentsWithState) {
  echo(
    exists
      ? chalk.blue(`Component ${name} is already in Backstage`)
      : chalk.red(`Component ${name} is not in Backstage`)
  )
}

const catalogInfoTemplate = `---
    # yaml-language-server: $schema=https://json.schemastore.org/catalog-info.json
    apiVersion: backstage.io/v1alpha1
    kind: Component
    metadata:
      name: backstage
      description: add some description
      links: []
        # - url: https://github.com/tyriis/home-ops/tree/main/kubernetes/main/apps/backstage/backstage
        #   title: Flux definition
        #   icon: github
        #   type: github-repository
        # - url: https://backstage.techtales.io/
        #   title: You are here :)
        #   icon: dashboard
        #   type: dashboard
      tags: []
        # - devops
        # - documentation-as-code
        # - documentation
        # - service-catalog
        # - idp
    spec:
      type: service
      lifecycle: production
      system: main-cluster
      owner: home-ops
      # dependsOn:
      #  - component:cert-manager
      #  - component:envoy-gateway
      # providesApis:
      #   - test-api
    `

const missing = componentsWithState.filter((component) => !component.exists)

if (missing.length > 0) {
  const catalogPath = "docs/backstage/catalog-info.yaml"

  await Promise.all(
    missing.map(async ({ name }) => {
      const componentDir = `docs/backstage/components/${name}`
      await fs.ensureDir(componentDir)
      await fs.writeFile(
        `${componentDir}/catalog-info.yaml`,
        catalogInfoTemplate.replace(/name: .*/, `name: ${name}`)
      )
    })
  )

  // register the components in the docs/backstage/catalog-info.yaml file
  const catalogJson = YAML.parse(await fs.readFile(catalogPath, "utf-8"))
  catalogJson.spec.targets.push(
    ...missing.map(
      ({ name }) =>
        `https://github.com/tyriis/home-ops/blob/main/docs/backstage/components/${name}/catalog-info.yaml`
    )
  )
  // sort and remove duplicates
  catalogJson.spec.targets = [...new Set(catalogJson.spec.targets)].sort()

  await fs.writeFile(catalogPath, `---\n${YAML.stringify(catalogJson)}`)
}
