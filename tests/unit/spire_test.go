package unit_test

import (
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	helmchart "helm.sh/helm/v3/pkg/chart"
	helmloader "helm.sh/helm/v3/pkg/chart/loader"
	helmutil "helm.sh/helm/v3/pkg/chartutil"
	helmengine "helm.sh/helm/v3/pkg/engine"
)

func ValueStringRender(chart *helmchart.Chart, values string) (map[string]string, error) {
	v, err := helmutil.ReadValues([]byte(values))
	if err != nil {
		return nil, err
	}
	ro := helmutil.ReleaseOptions{Name: "spire", Namespace: "spire-server", Revision: 1, IsUpgrade: false, IsInstall: true}
	v, err = helmutil.ToRenderValues(chart, v, ro, helmutil.DefaultCapabilities)
	if err != nil {
		return nil, err
	}
	objs, err := helmengine.Render(chart, v)
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
	Describe("spire-server.nodeAttestor.x509POP", func() {
		It("renders externalPKI mode with chart-managed ca bundle", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  nodeAttestor:
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
			Expect(serverCM).Should(ContainSubstring("mode: external_pki"))
			Expect(serverCM).Should(ContainSubstring(`ca_bundle_path: "/run/spire/data/x509pop-ca-bundle.pem"`))
			Expect(objs).Should(HaveKey("spire/charts/spire-server/templates/x509pop-configmap.yaml"))
			serverResource := objs["spire/charts/spire-server/templates/server-resource.yaml"]
			Expect(serverResource).Should(ContainSubstring("x509pop-ca-bundle"))
			Expect(serverResource).Should(ContainSubstring("/run/spire/data/x509pop-ca-bundle.pem"))
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
})
