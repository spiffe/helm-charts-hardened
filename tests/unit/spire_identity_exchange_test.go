package unit_test

import (
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	helmchart "helm.sh/helm/v3/pkg/chart"
	helmloader "helm.sh/helm/v3/pkg/chart/loader"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

const (
	sixConfigMapTmpl  = "spire-identity-exchange/templates/configmap.yaml"
	sixDeploymentTmpl = "spire-identity-exchange/templates/deployment.yaml"
)

type sixPlugin struct {
	Plugin string                 `json:"plugin"`
	Config map[string]interface{} `json:"config"`
}

type sixConfig struct {
	Auth struct {
		Plugins map[string]sixPlugin `json:"plugins"`
		Stacks  map[string]struct {
			Plugins       []string `json:"plugins"`
			MintAudiences []string `json:"mintAudiences"`
		} `json:"stacks"`
	} `json:"auth"`
}

type sixVolume struct {
	Name string `json:"name"`
	CSI  *struct {
		Driver string `json:"driver"`
	} `json:"csi"`
	Secret *struct {
		SecretName string `json:"secretName"`
		Items      []struct {
			Key  string `json:"key"`
			Path string `json:"path"`
		} `json:"items"`
	} `json:"secret"`
}

type sixVolumeMount struct {
	Name      string `json:"name"`
	MountPath string `json:"mountPath"`
	ReadOnly  bool   `json:"readOnly"`
}

type sixDeployment struct {
	Spec struct {
		Template struct {
			Spec struct {
				Containers []struct {
					Name         string           `json:"name"`
					VolumeMounts []sixVolumeMount `json:"volumeMounts"`
				} `json:"containers"`
				Volumes []sixVolume `json:"volumes"`
			} `json:"spec"`
		} `json:"template"`
	} `json:"spec"`
}

func decodeYAML(doc string, out interface{}) error {
	return yamlutil.NewYAMLOrJSONDecoder(strings.NewReader(doc), 4096).Decode(out)
}

func renderSIX(chart *helmchart.Chart, values string) (sixConfig, sixDeployment, error) {
	var config sixConfig
	var deployment sixDeployment
	objs, err := ValueStringRender(chart, values)
	if err != nil {
		return config, deployment, err
	}
	var configMap struct {
		Data map[string]string `json:"data"`
	}
	if err := decodeYAML(objs[sixConfigMapTmpl], &configMap); err != nil {
		return config, deployment, err
	}
	if err := decodeYAML(configMap.Data["six.conf"], &config); err != nil {
		return config, deployment, err
	}
	err = decodeYAML(objs[sixDeploymentTmpl], &deployment)
	return config, deployment, err
}

func sixVolumeByName(d sixDeployment, name string) *sixVolume {
	for i := range d.Spec.Template.Spec.Volumes {
		if d.Spec.Template.Spec.Volumes[i].Name == name {
			return &d.Spec.Template.Spec.Volumes[i]
		}
	}
	return nil
}

func sixMounts(d sixDeployment) []sixVolumeMount {
	for _, c := range d.Spec.Template.Spec.Containers {
		if c.Name == "spire-identity-exchange" {
			return c.VolumeMounts
		}
	}
	return nil
}

var _ = Describe("spire-identity-exchange", func() {
	chart, err := helmloader.Load("../../charts/spire-identity-exchange")
	Expect(err).Should(Succeed())

	Describe("defaults", func() {
		It("keeps the spiffe plugin on the local discovery provider over the pod's own socket", func() {
			config, _, err := renderSIX(chart, ``)
			Expect(err).Should(Succeed())
			spiffe := config.Auth.Plugins["spiffe"].Config
			Expect(spiffe).Should(HaveKeyWithValue("agentWorkloadSocketPath", "/spiffe-workload-api/spire-agent.sock"))
			Expect(spiffe).Should(HaveKeyWithValue("discoveryURL", "https://spire-spiffe-oidc-discovery-provider"))
			Expect(spiffe).ShouldNot(HaveKey("keySource"))
			Expect(config.Auth.Plugins["k8s_psat"].Config).ShouldNot(HaveKey("kubeconfig"))
		})
	})

	Describe("auth.plugins.spiffe.keySource workloadAPI", func() {
		It("renders workload_api with the plugin's socket and no discovery URL", func() {
			config, deployment, err := renderSIX(chart, `
auth:
  plugins:
    spiffe:
      keySource: workloadAPI
      csiDriverName: peer.csi.spiffe.io
      config:
        connectWithTrustBundle: false
        jwksTrustDomain: peer.example.org
`)
			Expect(err).Should(Succeed())
			spiffe := config.Auth.Plugins["spiffe"].Config
			Expect(spiffe).Should(HaveKeyWithValue("keySource", "workload_api"))
			Expect(spiffe).Should(HaveKeyWithValue("jwksTrustDomain", "peer.example.org"))
			Expect(spiffe).Should(HaveKeyWithValue("agentWorkloadSocketPath", "/spiffe-workload-apis/peer.csi.spiffe.io/spire-agent.sock"))
			Expect(spiffe).ShouldNot(HaveKey("discoveryURL"))
			volume := sixVolumeByName(deployment, "spiffe-workload-api-peer-csi-spiffe-io")
			Expect(volume).ShouldNot(BeNil())
			Expect(volume.CSI.Driver).Should(Equal("peer.csi.spiffe.io"))
		})
		It("rejects connectWithTrustBundle", func() {
			_, _, err := renderSIX(chart, `
auth:
  plugins:
    spiffe:
      keySource: workloadAPI
`)
			Expect(err).Should(MatchError(ContainSubstring("config.connectWithTrustBundle cannot be used with it")))
		})
		It("rejects jwksTrustDomain with another key source", func() {
			_, _, err := renderSIX(chart, `
auth:
  plugins:
    spiffe:
      config:
        jwksTrustDomain: peer.example.org
`)
			Expect(err).Should(MatchError(ContainSubstring("jwksTrustDomain is only used when auth.plugins.spiffe.keySource is workloadAPI")))
		})
		It("rejects keySource inside config", func() {
			_, _, err := renderSIX(chart, `
auth:
  plugins:
    spiffe:
      config:
        keySource: workload_api
`)
			Expect(err).Should(MatchError(ContainSubstring("Set auth.plugins.spiffe.keySource to oidc, oidcLocal or workloadAPI instead")))
		})
	})

	Describe("github discoverySPIFFEID", func() {
		It("fills in the socket from csiDriverName and mounts the driver", func() {
			config, deployment, err := renderSIX(chart, `
auth:
  plugins:
    forgejo:
      plugin: github
      csiDriverName: gh.csi.spiffe.io
      config:
        issuerURL: https://forgejo.example.org/api/actions
        discoveryURL: https://forgejo-internal.example.org/api/actions
        discoverySPIFFEID: spiffe://example.org/forgejo
        audiences:
          - spire-identity-exchange
        allowedRepositoryOwners:
          - my-org
`)
			Expect(err).Should(Succeed())
			forgejo := config.Auth.Plugins["forgejo"]
			Expect(forgejo.Plugin).Should(Equal("github"))
			Expect(forgejo.Config).Should(HaveKeyWithValue("discoveryURL", "https://forgejo-internal.example.org/api/actions"))
			Expect(forgejo.Config).Should(HaveKeyWithValue("discoverySPIFFEID", "spiffe://example.org/forgejo"))
			Expect(forgejo.Config).Should(HaveKeyWithValue("agentWorkloadSocketPath", "/spiffe-workload-apis/gh.csi.spiffe.io/spire-agent.sock"))
			volume := sixVolumeByName(deployment, "spiffe-workload-api-gh-csi-spiffe-io")
			Expect(volume).ShouldNot(BeNil())
			Expect(volume.CSI.Driver).Should(Equal("gh.csi.spiffe.io"))
			Expect(sixMounts(deployment)).Should(ContainElement(sixVolumeMount{Name: "spiffe-workload-api-gh-csi-spiffe-io", MountPath: "/spiffe-workload-apis/gh.csi.spiffe.io", ReadOnly: true}))
		})
		It("rejects csiDriverName without discoverySPIFFEID", func() {
			_, _, err := renderSIX(chart, `
auth:
  plugins:
    gh:
      plugin: github
      csiDriverName: gh.csi.spiffe.io
      config:
        audiences:
          - spire-identity-exchange
        allowedRepositories:
          - my-org/my-repo
`)
			Expect(err).Should(MatchError(ContainSubstring("csiDriverName is only meaningful when config.discoverySPIFFEID is set")))
		})
	})

	Describe("auth.plugins.k8s_psat.kubeconfig", func() {
		It("mounts the Secret and points the plugin at it", func() {
			config, deployment, err := renderSIX(chart, `
auth:
  plugins:
    k8s_psat:
      kubeconfig:
        existingSecret:
          name: remote-kc
          key: config
`)
			Expect(err).Should(Succeed())
			Expect(config.Auth.Plugins["k8s_psat"].Config).Should(HaveKeyWithValue("kubeconfig", "/etc/spire/identity-exchange/kubeconfigs/kubeconfig-k8s-psat/kubeconfig"))
			volume := sixVolumeByName(deployment, "kubeconfig-k8s-psat")
			Expect(volume).ShouldNot(BeNil())
			Expect(volume.Secret).ShouldNot(BeNil())
			Expect(volume.Secret.SecretName).Should(Equal("remote-kc"))
			Expect(volume.Secret.Items).Should(HaveLen(1))
			Expect(volume.Secret.Items[0].Key).Should(Equal("config"))
			Expect(volume.Secret.Items[0].Path).Should(Equal("kubeconfig"))
			Expect(sixMounts(deployment)).Should(ContainElement(sixVolumeMount{Name: "kubeconfig-k8s-psat", MountPath: "/etc/spire/identity-exchange/kubeconfigs/kubeconfig-k8s-psat", ReadOnly: true}))
		})
		It("rejects kubeconfig inside config", func() {
			_, _, err := renderSIX(chart, `
auth:
  plugins:
    k8s_psat:
      config:
        kubeconfig: /etc/kubeconfig
`)
			Expect(err).Should(MatchError(ContainSubstring("Set auth.plugins.k8s_psat.kubeconfig.existingSecret.name and .key")))
		})
		It("rejects kubeconfig on other plugin types", func() {
			_, _, err := renderSIX(chart, `
auth:
  plugins:
    spiffe:
      kubeconfig:
        existingSecret:
          name: remote-kc
          key: config
`)
			Expect(err).Should(MatchError(ContainSubstring(`auth.plugins.spiffe.kubeconfig is only supported on plugins of type "k8s_psat"`)))
		})
	})

	Describe("auth.stacks.mintAudiences", func() {
		It("passes the allowlist through", func() {
			config, _, err := renderSIX(chart, `
auth:
  stacks:
    image_pull:
      mintAudiences:
        - zot
        - registry.example.com
`)
			Expect(err).Should(Succeed())
			Expect(config.Auth.Stacks["image_pull"].MintAudiences).Should(Equal([]string{"zot", "registry.example.com"}))
		})
		It("rejects duplicates", func() {
			_, _, err := renderSIX(chart, `
auth:
  stacks:
    image_pull:
      mintAudiences:
        - zot
        - zot
`)
			Expect(err).Should(MatchError(ContainSubstring(`auth.stacks.image_pull.mintAudiences: duplicate entry "zot"`)))
		})
		It("rejects empty entries", func() {
			_, _, err := renderSIX(chart, `
auth:
  stacks:
    image_pull:
      mintAudiences:
        - ""
`)
			Expect(err).Should(MatchError(ContainSubstring("auth.stacks.image_pull.mintAudiences: every entry must be a non-empty string")))
		})
	})
})
