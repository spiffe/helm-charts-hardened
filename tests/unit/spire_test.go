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
		It("issuer_name when set is passed through", func() {
			objs, err := ValueStringRender(chart, `
spire-server:
  upstreamAuthority:
    certManager:
      enabled: true
      issuer_name: abc123
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
    k8sPsat:
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
    k8sPsat:
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
})
