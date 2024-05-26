const fluxKustomizations = await glob([
  "kubernetes/talos-flux/**/flux-sync.yaml",
])

// echo`${JSON.stringify(fluxKustomizations, null, 2)}`

const parseYAML = async (fluxKustomizations) => {
  const result = []
  for (const fluxKustomization of fluxKustomizations) {
    const data = (await fs.readFile(fluxKustomization, "utf-8")).toString()
    result.push(...JSON.parse(JSON.stringify(YAML.parseAllDocuments(data))))
  }
  return result
}

let data = await parseYAML(fluxKustomizations)
// let json = JSON.parse(JSON.stringify(data))

for (const item of data) {
  if (
    item.metadata?.annotations?.["backstage.io/discovery"] === "enabled" &&
    item.metadata?.annotations?.["backstage.io/name"]
  ) {
    const name = item.metadata.annotations["backstage.io/name"]
    // echo`${name}`
    const exists = await fs.pathExists(
      `.backstage/components/${name}/catalog-info.yaml`
    )
    if (exists) {
      echo(chalk.blue(`Component ${name} is already in Backstage`))
      continue
    }
    echo(chalk.red(`Component ${name} is not in Backstage`))
    // create backstage component with template
    let catalogInfo = `---
    # yaml-language-server: $schema=https://json.schemastore.org/catalog-info.json
    apiVersion: backstage.io/v1alpha1
    kind: Component
    metadata:
      name: backstage
      description: add some description
      links: []
        # - url: https://github.com/tyriis/home-ops/tree/main/kubernetes/talos-flux/apps/backstage/backstage
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
      system: talos-flux
      owner: home-ops
      # dependsOn:
      #  - component:cert-manager
      #  - component:traefik
      # providesApis:
      #   - test-api
    `
    catalogInfo = catalogInfo.replace(/name: .*/, `name: ${name}`)
    await fs.ensureDir(`.backstage/components/${name}`)
    await fs.writeFile(
      `.backstage/components/${name}/catalog-info.yaml`,
      catalogInfo
    )
    // register the component in the .backstage/catalog-info.yaml file
    const catalog = await fs.readFile(".backstage/catalog-info.yaml", "utf-8")
    const catalogJson = YAML.parse(catalog)
    catalogJson.spec.targets.push(
      `https://github.com/tyriis/home-ops/blob/main/.backstage/components/${name}/catalog-info.yaml`
    )
    catalogJson.spec.targets = catalogJson.spec.targets.sort()
    // remove duplicates
    catalogJson.spec.targets = catalogJson.spec.targets.filter(
      (item, index) => catalogJson.spec.targets.indexOf(item) === index
    )
    await fs.writeFile(
      ".backstage/catalog-info.yaml",
      `---\n${YAML.stringify(catalogJson)}`
    )
  }
}

// console.log(json[0])

// echo`${JSON.stringify(json[0].metadata, null, 2)}`
