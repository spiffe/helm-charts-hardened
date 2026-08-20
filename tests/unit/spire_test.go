package unit_test

import (
	"encoding/json"
	"io"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	helmchart "helm.sh/helm/v3/pkg/chart"
	helmloader "helm.sh/helm/v3/pkg/chart/loader"
	helmutil "helm.sh/helm/v3/pkg/chartutil"
	helmengine "helm.sh/helm/v3/pkg/engine"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

type renderedWebhook struct {
	Name string `json:"name"`
}

type renderedDocument struct {
	Kind     string `json:"kind"`
	Metadata struct {
		Annotations map[string]string `json:"annotations"`
	} `json:"metadata"`
	Spec struct {
		Template struct {
			Spec struct {
				Containers []struct {
					Args []string `json:"args"`
				} `json:"containers"`
			} `json:"spec"`
		} `json:"template"`
	} `json:"spec"`
	Webhooks []renderedWebhook `json:"webhooks"`
}

func decodeRenderedDocuments(rendered string) ([]renderedDocument, error) {
	decoder := yamlutil.NewYAMLOrJSONDecoder(strings.NewReader(rendered), 4096)
	var documents []renderedDocument
	for {
		var document renderedDocument
		err := decoder.Decode(&document)
		if err == io.EOF {
			return documents, nil
		}
		if err != nil {
			return nil, err
		}
		if document.Kind != "" {
			documents = append(documents, document)
		}
	}
}

func patchWebhookNames(job renderedDocument) ([]string, error) {
	for _, container := range job.Spec.Template.Spec.Containers {
		for index, arg := range container.Args {
			if arg != "-p" || index+1 >= len(container.Args) {
				continue
			}
			var patch struct {
				Webhooks []renderedWebhook `json:"webhooks"`
			}
			if err := json.Unmarshal([]byte(container.Args[index+1]), &patch); err != nil {
				return nil, err
			}
			names := make([]string, 0, len(patch.Webhooks))
			for _, webhook := range patch.Webhooks {
				names = append(names, webhook.Name)
			}
			return names, nil
		}
	}
	return nil, nil
}

func ValueStringRender(chart *helmchart.Chart, values string) (map[string]string, error) {
	v, err := helmutil.ReadValues([]byte(values))
	if err != nil {
		return nil, err
	}
	merged, err := helmutil.CoalesceValues(chart, v)
	if err != nil {
		return nil, err
	}
	testChart := *chart
	testChart.Values = merged

	var activeDeps []*helmchart.Chart
        for _, dep := range testChart.Dependencies() {
                if dep.Name() != "spire-identity-exchange" {
                        activeDeps = append(activeDeps, dep)
                }
        }
        testChart.SetDependencies(activeDeps...)

	ro := helmutil.ReleaseOptions{Name: "spire", Namespace: "spire-server", Revision: 1, IsUpgrade: false, IsInstall: true}
	v, err = helmutil.ToRenderValues(&testChart, merged, ro, helmutil.DefaultCapabilities)
	if err != nil {
		return nil, err
	}
	objs, err := helmengine.Render(&testChart, v)
	return objs, err
}

var _ = Describe("Spire", func() {
	chart, err := helmloader.Load("../../charts/spire")
	Expect(err).Should(Succeed())
	Describe("spire-server.upstream.cert-manager", func() {
		It("issuerName when set is passed through", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  upstreamAuthority:
    certManager:
      enabled: true
      issuerName: abc123
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring("abc123"))
		})
	})
	Describe("spire-server.customPlugin.tpm", func() {
		It("plugin set ok", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  customPlugins:
    nodeAttestor:
      tpm:
        plugin_cmd: /bin/tpm_attestor_server
        plugin_checksum: 97442358ae946e3fb8f2464432b8c23efdc0b5d44ec1eea27babe59ef646cc2f
        plugin_data: {}
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring("tpm"))
		})
	})
	Describe("spire-server.unsupportedBuiltInPlugins", func() {
		It("plugin set ok", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  unsupportedBuiltInPlugins:
    nodeAttestor:
      join_token:
        plugin_data: {}
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring("join_token"))
		})
	})
	Describe("spire-server.keyManager.aws_kms", func() {
		It("plugin set ok", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  keyManager:
    awsKMS:
      enabled: true
      region: us-west-2
      plugin_data: {}
    disk:
      enabled: false
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring("\"aws_kms\": {"))
		})
	})
	Describe("spire-server.UpstreamAuthority.aws_pca", func() {
		It("plugin set ok", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  upstreamAuthority:
    awsPCA:
      enabled: true
      region: us-west-2
      plugin_data: {}
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring("\"aws_pca\": {"))
		})
	})
	Describe("spire-server.UpstreamAuthority.ejbca", func() {
		It("plugin set ok", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  upstreamAuthority:
    ejbca:
      enabled: true
      hostname: ejbca.example.org:8443
      caName: SpireIntermediateCA
      endEntityProfileName: SpireEEP
      certificateProfileName: SpireIntermediateCACP
      secret:
        data:
          caCert: dummy-ca
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring("\"ejbca\": {"))
			Expect(notes).Should(ContainSubstring("SpireIntermediateCA"))
			Expect(notes).Should(ContainSubstring("ca_cert_path"))
		})
	})
	Describe("spire-agent.customPlugin.tpm", func() {
		It("plugin set ok", func() {
			objs, err := ValueStringRender(chart, `
spire-agent:
  nodeAttestor:
    k8sPSAT:
      enabled: false
  customPlugins:
    nodeAttestor:
      tpm:
        plugin_cmd: /bin/tpm_attestor_agent
        plugin_checksum: bb7be714c27452231a6c7764b65912ce0cdeb66ff2a2c688d3e88bd0bd17d138
        plugin_data: {}
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-agent/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring("tpm"))
		})
	})
	Describe("spire-server.unsupportedBuiltInPlugins", func() {
		It("plugin set ok", func() {
			objs, err := ValueStringRender(chart, `
spire-agent:
  nodeAttestor:
    k8sPSAT:
      enabled: false
  unsupportedBuiltInPlugins:
    nodeAttestor:
      join_token:
        plugin_data: {}
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-agent/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring("join_token"))
		})
	})
	Describe("spire-server.disabled", func() {
		It("spire server off", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  enabled: false
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/templates/NOTES.txt"]
			Expect(notes).Should(ContainSubstring("Installed"))
		})
	})
	Describe("spire-server.nodeAttestor.x509POP", func() {
		It("renders externalPKI mode with chart-managed ca bundle", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  nodeAttestor:
    k8sPSAT:
      enabled: false
    x509POP:
      enabled: true
      mode: externalPKI
      caBundle:
        bundle: |
          -----BEGIN CERTIFICATE-----
          MIIB...
          -----END CERTIFICATE-----
`)
			Expect(err).Should(Succeed())
			serverCM := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(serverCM).Should(ContainSubstring(`"mode": "external_pki"`))
			Expect(serverCM).Should(ContainSubstring(`"ca_bundle_path": "/run/spire/data/x509pop-ca-bundle.pem"`))
			Expect(objs).Should(HaveKey("spire/charts/spire-server/templates/x509pop-configmap.yaml"))
			serverResource := objs["spire/charts/spire-server/templates/server-resource.yaml"]
			Expect(serverResource).Should(ContainSubstring("x509pop-ca-bundle"))
			Expect(serverResource).Should(ContainSubstring("/run/spire/data/x509pop-ca-bundle.pem"))
		})
		It("renders externalPKI mode with existing ConfigMap reference", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  nodeAttestor:
    k8sPSAT:
      enabled: false
    x509POP:
      enabled: true
      mode: externalPKI
      caBundle:
        existingConfigMap: my-enrollment-ca
`)
			Expect(err).Should(Succeed())
			serverCM := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(serverCM).Should(ContainSubstring(`"mode": "external_pki"`))
			Expect(serverCM).Should(ContainSubstring(`"ca_bundle_path": "/run/spire/data/x509pop-ca-bundle.pem"`))
			Expect(objs["spire/charts/spire-server/templates/x509pop-configmap.yaml"]).ShouldNot(ContainSubstring("kind: ConfigMap"))
			serverResource := objs["spire/charts/spire-server/templates/server-resource.yaml"]
			Expect(serverResource).Should(ContainSubstring("name: my-enrollment-ca"))
		})
	})
	Describe("spire-server.nodeAttestor.awsIID.verifyOrganization", func() {
		It("emits verify_organization in server config JSON", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  nodeAttestor:
    k8sPSAT:
      enabled: false
    awsIID:
      enabled: true
      verifyOrganization:
        enabled: true
        managementAccountId: "111122223333"
        assumeOrgRole: "spire-server-org-validator"
        managementAccountRegion: "us-east-1"
        orgAccountMapTTL: "5m"
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(notes).Should(ContainSubstring(`verify_organization`))
			Expect(notes).Should(ContainSubstring(`management_account_id`))
			Expect(notes).Should(ContainSubstring(`111122223333`))
			Expect(notes).Should(ContainSubstring(`spire-server-org-validator`))
			Expect(notes).Should(ContainSubstring(`us-east-1`))
			Expect(notes).Should(ContainSubstring(`5m`))
		})
	})
	Describe("spire-server.credentialComposer.uniqueID", func() {
		It("spire server uniqueid credential composer", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  credentialComposer:
    uniqueID:
      enabled: true
`)
			Expect(err).Should(Succeed())
			notes := objs["spire/templates/NOTES.txt"]
			Expect(notes).Should(ContainSubstring("Installed"))
		})
	})
	Describe("spiffe-oidc-discovery-provider.jwtIssuer", func() {
		It("auto-derives jwt_issuer from global.spire.jwtIssuer and matches spire-server", func() {
			objs, err := ValueStringRender(chart, `
global:
  spire:
    jwtIssuer: https://canonical.example.com
`)
			Expect(err).Should(Succeed())
			oidcCM := objs["spire/charts/spiffe-oidc-discovery-provider/templates/configmap.yaml"]
			Expect(oidcCM).Should(ContainSubstring(`"jwt_issuer": "https://canonical.example.com"`))
			serverCM := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(serverCM).Should(ContainSubstring(`"jwt_issuer": "https://canonical.example.com"`))
		})
		It("propagates the subchart-local jwtIssuer to jwt_issuer", func() {
			objs, err := ValueStringRender(chart, `
spiffe-oidc-discovery-provider:
  jwtIssuer: https://legacy.example.com
`)
			Expect(err).Should(Succeed())
			oidcCM := objs["spire/charts/spiffe-oidc-discovery-provider/templates/configmap.yaml"]
			Expect(oidcCM).Should(ContainSubstring(`"jwt_issuer": "https://legacy.example.com"`))
		})
		It("defaults to oidc-discovery.<trustDomain> when nothing is set and strict mode is disabled", func() {
			objs, err := ValueStringRender(chart, ``)
			Expect(err).Should(Succeed())
			oidcCM := objs["spire/charts/spiffe-oidc-discovery-provider/templates/configmap.yaml"]
			Expect(oidcCM).Should(ContainSubstring(`"jwt_issuer": "https://oidc-discovery.example.org"`))
			serverCM := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(serverCM).Should(ContainSubstring(`"jwt_issuer": "https://oidc-discovery.example.org"`))
		})
	})
	Describe("spire-server.kubeConfigs", func() {
		secretTmpl := "spire/charts/spire-server/templates/kubeconfig-secret.yaml"
		serverTmpl := "spire/charts/spire-server/templates/server-resource.yaml"
		It("inline entry generates a Secret and a projected volume source referencing it", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  kubeConfigs:
    clustera:
      kubeConfig: |
        apiVersion: v1
        kind: Config
`)
			Expect(err).Should(Succeed())
			Expect(objs[secretTmpl]).Should(ContainSubstring("kind: Secret"))
			Expect(objs[serverTmpl]).Should(ContainSubstring("projected:"))
			Expect(objs[serverTmpl]).Should(ContainSubstring("path: clustera"))
		})
		It("externalSecret entry wires a projected source and skips the generated Secret", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  kubeConfigs:
    clusterb:
      externalSecret:
        name: my-ext-secret
`)
			Expect(err).Should(Succeed())
			Expect(objs[secretTmpl]).ShouldNot(ContainSubstring("kind: Secret"))
			Expect(objs[serverTmpl]).Should(ContainSubstring("name: my-ext-secret"))
			Expect(objs[serverTmpl]).Should(ContainSubstring("path: clusterb"))
		})
		It("jwtSVIDExec entry generates the Secret and stages the exec plugin", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  jwtSVIDExecConfig:
    spiffeID: spiffe://example.org/external-spire-server
  kubeConfigs:
    clusterd:
      jwtSVIDExec:
        server: https://clusterd-api.example.com:6443
        certificateAuthorityData: TESTCADATAB64==
`)
			Expect(err).Should(Succeed())
			Expect(objs[secretTmpl]).Should(ContainSubstring("kind: Secret"))
			Expect(objs[serverTmpl]).Should(ContainSubstring("init-jwt-svid-exec"))
		})
	})
	Describe("spire-server.externalServerSubject", func() {
		It("binds the external server's downstream RBAC to a ServiceAccount subject", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  externalServer: true
  externalServerSubject:
    kind: ServiceAccount
    name: spire-external
    namespace: spire-ext
`)
			Expect(err).Should(Succeed())
			roles := objs["spire/charts/spire-server/templates/roles.yaml"]
			Expect(roles).Should(ContainSubstring("kind: ServiceAccount"))
			Expect(roles).Should(ContainSubstring(`name: "spire-external"`))
			Expect(roles).Should(ContainSubstring(`namespace: "spire-ext"`))
		})
		It("binds the external server's downstream RBAC to a Group subject", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  externalServer: true
  externalServerSubject:
    kind: Group
    name: spire-admins
`)
			Expect(err).Should(Succeed())
			roles := objs["spire/charts/spire-server/templates/roles.yaml"]
			Expect(roles).Should(ContainSubstring("apiGroup: rbac.authorization.k8s.io"))
			Expect(roles).Should(ContainSubstring("kind: Group"))
			Expect(roles).Should(ContainSubstring(`name: "spire-admins"`))
		})
	})
	Describe("spire-server.updateStrategy", func() {
		It("maps to spec.strategy when kind is deployment", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  kind: deployment
  persistence:
    type: emptyDir
  keyManager:
    disk:
      enabled: false
    memory:
      enabled: true
  dataStore:
    sql:
      databaseType: postgres
      host: db.example.org
  updateStrategy:
    type: Recreate
`)
			Expect(err).Should(Succeed())
			serverResource := objs["spire/charts/spire-server/templates/server-resource.yaml"]
			Expect(serverResource).Should(ContainSubstring("kind: Deployment"))
			Expect(serverResource).Should(ContainSubstring("\n  strategy:\n    type: Recreate\n"))
		})

		It("maps to spec.updateStrategy when kind is statefulset", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  updateStrategy:
    type: OnDelete
`)
			Expect(err).Should(Succeed())
			serverResource := objs["spire/charts/spire-server/templates/server-resource.yaml"]
			Expect(serverResource).Should(ContainSubstring("kind: StatefulSet"))
			Expect(serverResource).Should(ContainSubstring("\n  updateStrategy:\n    type: OnDelete\n"))
		})

		It("renders neither field when left unset", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  replicaCount: 1
`)
			Expect(err).Should(Succeed())
			serverResource := objs["spire/charts/spire-server/templates/server-resource.yaml"]
			Expect(serverResource).ShouldNot(ContainSubstring("\n  strategy:"))
			Expect(serverResource).ShouldNot(ContainSubstring("\n  updateStrategy:"))
		})
	})
	Describe("spire-server.kind.deployment.sqlite3", func() {
		deployment := func(sql string) string {
			return `
spire-server:
  kind: deployment
  persistence:
    type: emptyDir
  keyManager:
    disk:
      enabled: false
    memory:
      enabled: true
  updateStrategy:
    type: Recreate
  dataStore:
    sql:
` + sql
		}

		It("renders a Deployment when the sqlite3 datastore is in memory", func() {
			objs, err := ValueStringRender(chart, deployment(`      inMemory: true
`))
			Expect(err).Should(Succeed())
			serverResource := objs["spire/charts/spire-server/templates/server-resource.yaml"]
			Expect(serverResource).Should(ContainSubstring("kind: Deployment"))
			Expect(serverResource).ShouldNot(ContainSubstring("kind: StatefulSet"))
		})

		It("rejects a file backed sqlite3 datastore", func() {
			_, err := ValueStringRender(chart, deployment(`      inMemory: false
`))
			Expect(err).Should(MatchError(ContainSubstring("sqlite3 can only be used in memory")))
		})
	})
	Describe("spire-server.dataStore.sql.inMemory", func() {
		It("builds a shared cache connection string and ignores file", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  dataStore:
    sql:
      inMemory: true
      file: /run/spire/data/datastore.sqlite3
`)
			Expect(err).Should(Succeed())
			Expect(objs["spire/charts/spire-server/templates/configmap.yaml"]).
				Should(ContainSubstring(`"connection_string": "memdb?mode=memory\u0026cache=shared"`))
		})

		It("keeps the file connection string when left off", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  dataStore:
    sql:
      file: /run/spire/data/datastore.sqlite3
`)
			Expect(err).Should(Succeed())
			Expect(objs["spire/charts/spire-server/templates/configmap.yaml"]).
				Should(ContainSubstring(`"connection_string": "/run/spire/data/datastore.sqlite3"`))
		})
	})
	Describe("spire-server.dataStore.sql.inMemory warnings", func() {
		notes := func(values string) string {
			objs, err := ValueStringRender(chart, values)
			ExpectWithOffset(1, err).Should(Succeed())
			return objs["spire/templates/NOTES.txt"]
		}
		safe := `
spire-server:
  dataStore:
    sql:
      inMemory: true
  controllerManager:
    enabled: true
    reconcile:
      clusterStaticEntries: true
  upstreamAuthority:
    vault:
      enabled: true
`

		It("stays quiet on the default values", func() {
			Expect(notes(`spire-server: {}`)).ShouldNot(ContainSubstring("Warning: dataStore.sql.inMemory"))
		})

		It("stays quiet when entries are reconciled and a CA is upstream", func() {
			Expect(notes(safe)).ShouldNot(ContainSubstring("Warning: dataStore.sql.inMemory"))
		})

		It("warns when nothing recreates the registration entries", func() {
			Expect(notes(`
spire-server:
  dataStore:
    sql:
      inMemory: true
  controllerManager:
    enabled: false
`)).Should(ContainSubstring("nothing recreates them"))
		})

		It("warns when the CA is also in memory with no upstream authority", func() {
			Expect(notes(`
spire-server:
  dataStore:
    sql:
      inMemory: true
  controllerManager:
    enabled: true
    reconcile:
      clusterStaticEntries: true
  keyManager:
    disk:
      enabled: false
    memory:
      enabled: true
`)).Should(ContainSubstring("mints a new CA on every restart"))
		})

		It("stays quiet on a deployment that cannot surge", func() {
			Expect(notes(safe + `
  kind: deployment
  persistence:
    type: emptyDir
  keyManager:
    disk:
      enabled: false
    memory:
      enabled: true
  updateStrategy:
    type: Recreate
`)).ShouldNot(ContainSubstring("Warning: dataStore.sql.inMemory"))
		})
	})
	Describe("spire-server.updateStrategy surge guard", func() {
		deployment := func(strategy string) string {
			return `
spire-server:
  kind: deployment
  persistence:
    type: emptyDir
  keyManager:
    disk:
      enabled: false
    memory:
      enabled: true
  dataStore:
    sql:
      inMemory: true
` + strategy
		}

		It("rejects an in-memory deployment that can surge", func() {
			_, err := ValueStringRender(chart, deployment(``))
			Expect(err).Should(MatchError(ContainSubstring("must not surge")))
		})

		It("rejects an explicit rolling update that can surge", func() {
			_, err := ValueStringRender(chart, deployment(`  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
`))
			Expect(err).Should(MatchError(ContainSubstring("must not surge")))
		})

		It("accepts Recreate", func() {
			_, err := ValueStringRender(chart, deployment(`  updateStrategy:
    type: Recreate
`))
			Expect(err).Should(Succeed())
		})

		It("accepts a rolling update pinned to maxSurge 0", func() {
			_, err := ValueStringRender(chart, deployment(`  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 1
`))
			Expect(err).Should(Succeed())
		})

		It("accepts maxSurge expressed as a percentage", func() {
			_, err := ValueStringRender(chart, deployment(`  updateStrategy:
    rollingUpdate:
      maxSurge: 0%
`))
			Expect(err).Should(Succeed())
		})

		It("leaves a file backed statefulset alone", func() {
			_, err := ValueStringRender(chart, `
spire-server:
  updateStrategy:
    type: RollingUpdate
`)
			Expect(err).Should(Succeed())
		})
	})
	Describe("spire-server webhook patch order", func() {
		It("preserves the rendered webhook order in every strategic-merge hook", func() {
			objs, err := ValueStringRender(chart, `
global:
  installAndUpgradeHooks:
    enabled: true
spire-server:
  enabled: true
  controllerManager:
    enabled: true
`)
			Expect(err).Should(Succeed())

			canonicalDocuments, err := decodeRenderedDocuments(objs["spire/charts/spire-server/templates/controller-manager-webhook.yaml"])
			Expect(err).Should(Succeed())
			Expect(canonicalDocuments).Should(HaveLen(1))
			Expect(canonicalDocuments[0].Kind).Should(Equal("ValidatingWebhookConfiguration"))
			canonicalNames := make([]string, 0, len(canonicalDocuments[0].Webhooks))
			for _, webhook := range canonicalDocuments[0].Webhooks {
				canonicalNames = append(canonicalNames, webhook.Name)
			}

			for _, hook := range []struct {
				name     string
				template string
			}{
				{name: "post-install", template: "spire/charts/spire-server/templates/post-install-hook.yaml"},
				{name: "pre-upgrade", template: "spire/charts/spire-server/templates/pre-upgrade-hook.yaml"},
				{name: "post-upgrade", template: "spire/charts/spire-server/templates/post-upgrade-hook.yaml"},
			} {
				documents, err := decodeRenderedDocuments(objs[hook.template])
				Expect(err).Should(Succeed())
				var jobs []renderedDocument
				for _, document := range documents {
					if document.Kind == "Job" && document.Metadata.Annotations["helm.sh/hook"] == hook.name {
						jobs = append(jobs, document)
					}
				}
				Expect(jobs).Should(HaveLen(1), hook.name)
				actualNames, err := patchWebhookNames(jobs[0])
				Expect(err).Should(Succeed())
				Expect(actualNames).Should(Equal(canonicalNames), hook.name)
			}
		})
	})
})
