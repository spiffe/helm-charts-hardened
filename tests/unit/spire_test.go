package unit_test

import (
	"strings"

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
	Describe("pod-agent PSAT cluster", func() {
		It("renders the server pod-agent PSAT cluster", func() {
			objs, err := ValueStringRender(chart, `
global:
  spire:
    clusterName: primary-cluster
spire-server:
  nodeAttestor:
    k8sPSAT:
      allowedNodeLabelKeys:
      - primary-node-label
      allowedPodLabelKeys:
      - primary-pod-label
      podAgentsCluster:
        clusterName: broker-pods
        serviceAccountAllowList:
        - spire-tcp-broker
        allowedNodeLabelKeys:
        - broker-node-label
        allowedPodLabelKeys:
        - broker-pod-label
`)
			Expect(err).Should(Succeed())
			serverCM := objs["spire/charts/spire-server/templates/configmap.yaml"]
			Expect(serverCM).Should(ContainSubstring(`"service_account_allow_list": [`))
			Expect(serverCM).Should(ContainSubstring(`"spire-server:spire-tcp-broker"`))
			Expect(serverCM).ShouldNot(ContainSubstring(`"spire-system:spire-tcp-broker"`))
			Expect(serverCM).Should(ContainSubstring(`"use_pod_uid_for_agent_id": true`))
			Expect(serverCM).Should(MatchRegexp(`(?s)"primary-cluster": \{[^}]*"primary-node-label"[^}]*"primary-pod-label"[^}]*\}`))
			Expect(serverCM).Should(MatchRegexp(`(?s)"broker-pods": \{[^}]*"broker-node-label"[^}]*"broker-pod-label"[^}]*\}`))
			Expect(serverCM).ShouldNot(MatchRegexp(`(?s)"broker-pods": \{[^}]*"primary-(node|pod)-label"`))
		})

		It("requires service accounts for the server pod-agent cluster", func() {
			_, err := ValueStringRender(chart, `
spire-server:
  nodeAttestor:
    k8sPSAT:
      podAgentsCluster:
        clusterName: broker-pods
server:
  address: spire-server.spire-server
`)
			Expect(err).Should(MatchError(ContainSubstring("serviceAccountAllowList requires at least one service account")))
		})
	})

	Describe("spire-tcp-broker", func() {
		brokerChart, err := helmloader.Load("../../charts/spire-tcp-broker")
		Expect(err).Should(Succeed())

		It("renders a TCP-only Broker agent with the configured pod-agent cluster", func() {
			objs, err := ValueStringRender(brokerChart, `
global:
  spire:
    clusterName: primary-cluster
    recommendations:
      enabled: true
      strictMode: false
clusterName: broker-pods
server:
  address: spire-server.spire-server
controllerManagerClassName: spire-server-spire
workloadAgentAlias: spiffe://example.org/spire/agent/broker-clients
brokers:
  - name: broker
    rbacRules:
    - apiGroups: [""]
      resources: ["pods"]
    - apiGroups: ["apps"]
      resources: ["deployments"]
staticEntries:
  - path: workload/one
    selectors:
      - k8s:ns:one
      - k8s:sa:one
  - path: /workload/two
    selectors:
      - k8s:ns:two
      - k8s:sa:two
`)
			Expect(err).Should(Succeed())
			brokerCM := objs["spire-tcp-broker/templates/configmap.yaml"]

			deployment := objs["spire-tcp-broker/templates/deployment.yaml"]
			Expect(deployment).Should(ContainSubstring(`name: "spire"`))
			Expect(deployment).Should(ContainSubstring(`serviceAccountName: "spire"`))
			Expect(deployment).Should(ContainSubstring(`priorityClassName: system-cluster-critical`))

			serviceAccount := objs["spire-tcp-broker/templates/serviceaccount.yaml"]
			Expect(serviceAccount).Should(ContainSubstring(`name: "spire"`))
			Expect(serviceAccount).Should(ContainSubstring(`namespace: "spire-server"`))

			roles := objs["spire-tcp-broker/templates/roles.yaml"]
			Expect(roles).Should(ContainSubstring(`name: "spire-server-spire"`))
			Expect(roles).Should(ContainSubstring(`name: "spire-server-spire-broker"`))
			Expect(strings.Count(roles, "kind: ClusterRole\napiVersion:")).Should(Equal(2))
			Expect(strings.Count(roles, "kind: ClusterRoleBinding\napiVersion:")).Should(Equal(2))
			Expect(strings.Count(roles, "kind: Role\napiVersion:")).Should(Equal(0))
			Expect(strings.Count(roles, "kind: RoleBinding\napiVersion:")).Should(Equal(0))
			Expect(strings.Count(roles, "- impersonate-via-spire")).Should(Equal(2))
			Expect(brokerCM).Should(ContainSubstring(`bind_address = "0.0.0.0:8443"`))
			Expect(brokerCM).Should(ContainSubstring(`id = "spiffe://example.org/broker"`))
			Expect(brokerCM).Should(ContainSubstring(`server_address = "spire-server.spire-server"`))
			Expect(brokerCM).Should(ContainSubstring(`cluster = "broker-pods"`))
			Expect(brokerCM).ShouldNot(ContainSubstring(`cluster = "primary-cluster"`))
			Expect(brokerCM).Should(ContainSubstring(`disable_workload_api = true`))
			Expect(brokerCM).Should(ContainSubstring(`disable_sds_api = true`))
			Expect(brokerCM).Should(ContainSubstring(`allowed_reference_types = [`))
			Expect(strings.Count(brokerCM, `WorkloadAttestor "k8s"`)).Should(Equal(1))
			Expect(brokerCM).Should(ContainSubstring("disable_kubelet_client = true"))
			Expect(brokerCM).ShouldNot(ContainSubstring("WorkloadPIDReference"))
			Expect(brokerCM).ShouldNot(ContainSubstring("kubelet_ca_path"))
			Expect(brokerCM).ShouldNot(ContainSubstring("skip_kubelet_verification"))
			Expect(brokerCM).ShouldNot(ContainSubstring("node_name_env"))
			Expect(brokerCM).ShouldNot(ContainSubstring("disable_container_selectors"))
			Expect(brokerCM).ShouldNot(ContainSubstring("use_new_container_locator"))

			agentAlias := objs["spire-tcp-broker/templates/agent-alias.yaml"]
			Expect(agentAlias).ShouldNot(ContainSubstring("k8s_psat:cluster:primary-cluster"))
			Expect(agentAlias).Should(ContainSubstring(`className: "spire-server-spire"`))
			Expect(agentAlias).Should(ContainSubstring(`name: "spire-server-spire-agent-alias"`))
			Expect(agentAlias).Should(ContainSubstring(`spiffeID: "spiffe://example.org/agent-alias/tcp-broker/spire-server-spire"`))
			Expect(agentAlias).Should(ContainSubstring("k8s_psat:cluster:broker-pods"))

			brokerEntries := objs["spire-tcp-broker/templates/broker-entries.yaml"]
			Expect(strings.Count(brokerEntries, "kind: ClusterStaticEntry\n")).Should(Equal(1))
			Expect(brokerEntries).Should(ContainSubstring(`name: "spire-server-spire-broker-entry"`))
			Expect(brokerEntries).Should(ContainSubstring(`className: "spire-server-spire"`))
			Expect(brokerEntries).Should(ContainSubstring(`spiffeID: "spiffe://example.org/broker"`))
			Expect(brokerEntries).Should(ContainSubstring(`parentID: "spiffe://example.org/spire/agent/broker-clients"`))
			Expect(brokerEntries).Should(ContainSubstring(`"k8s:ns:spire-server"`))
			Expect(brokerEntries).Should(ContainSubstring(`"k8s:sa:broker"`))

			staticEntries := objs["spire-tcp-broker/templates/static-entries.yaml"]
			Expect(strings.Count(staticEntries, "kind: ClusterStaticEntry\n")).Should(Equal(2))
			Expect(staticEntries).Should(MatchRegexp(`name: "spire-server-spire-static-entry-[0-9a-f]{16}"`))
			Expect(staticEntries).Should(ContainSubstring(`spiffeID: "spiffe://example.org/workload/one"`))
			Expect(staticEntries).Should(ContainSubstring(`spiffeID: "spiffe://example.org/workload/two"`))
			Expect(strings.Count(staticEntries, `parentID: "spiffe://example.org/agent-alias/tcp-broker/spire-server-spire"`)).Should(Equal(2))
			Expect(staticEntries).Should(ContainSubstring(`- k8s:ns:one`))
			Expect(staticEntries).Should(ContainSubstring(`- k8s:sa:two`))
		})

		It("uses explicit Broker namespace and service account selectors", func() {
			objs, err := ValueStringRender(brokerChart, `
clusterName: broker-pods
server:
  address: spire-server.spire-server
controllerManagerClassName: spire-server-spire
workloadAgentAlias: spiffe://example.org/spire/agent/broker-clients
brokers:
  - name: broker
    namespace: broker-namespace
    serviceAccountName: broker-service-account
`)
			Expect(err).Should(Succeed())

			brokerEntries := objs["spire-tcp-broker/templates/broker-entries.yaml"]
			Expect(brokerEntries).Should(ContainSubstring(`spiffeID: "spiffe://example.org/broker"`))
			Expect(brokerEntries).Should(ContainSubstring(`"k8s:ns:broker-namespace"`))
			Expect(brokerEntries).Should(ContainSubstring(`"k8s:sa:broker-service-account"`))
			Expect(brokerEntries).ShouldNot(ContainSubstring(`"k8s:ns:spire-server"`))
			Expect(brokerEntries).ShouldNot(ContainSubstring(`"k8s:sa:broker"`))
		})

		It("requires the explicit pod-agent cluster name", func() {
			_, err := ValueStringRender(brokerChart, `
server:
  address: spire-server.spire-server
controllerManagerClassName: spire-server-spire
workloadAgentAlias: spiffe://example.org/spire/agent/broker-clients
brokers:
  - name: broker
`)
			Expect(err).Should(MatchError(ContainSubstring("clusterName must be set")))
		})

		It("requires the explicit SPIRE server address", func() {
			_, err := ValueStringRender(brokerChart, `
clusterName: broker-pods
controllerManagerClassName: spire-server-spire
workloadAgentAlias: spiffe://example.org/spire/agent/broker-clients
brokers:
  - name: broker
`)
			Expect(err).Should(MatchError(ContainSubstring("server.address must be set")))
		})

		It("requires the controller manager class for the agent alias", func() {
			_, err := ValueStringRender(brokerChart, `
clusterName: broker-pods
server:
  address: spire-server.spire-server
brokers:
  - name: broker
`)
			Expect(err).Should(MatchError(ContainSubstring("controllerManagerClassName must be set")))
		})
		It("requires the workload agent alias for Broker entries", func() {
			_, err := ValueStringRender(brokerChart, `
clusterName: broker-pods
server:
  address: spire-server.spire-server
controllerManagerClassName: spire-server-spire
brokers:
  - name: broker
`)
			Expect(err).Should(MatchError(ContainSubstring("workloadAgentAlias must be set")))
		})

		It("rejects duplicate Broker names", func() {
			_, err := ValueStringRender(brokerChart, `
clusterName: broker-pods
server:
  address: spire-server.spire-server
controllerManagerClassName: spire-server-spire
workloadAgentAlias: spiffe://example.org/spire/agent/broker-clients
brokers:
  - name: broker
  - name: broker
`)
			Expect(err).Should(MatchError(ContainSubstring(`broker name "broker" is duplicated`)))
		})

		It("rejects duplicate normalized static entry paths", func() {
			_, err := ValueStringRender(brokerChart, `
clusterName: broker-pods
server:
  address: spire-server.spire-server
controllerManagerClassName: spire-server-spire
workloadAgentAlias: spiffe://example.org/spire/agent/broker-clients
brokers:
  - name: broker
staticEntries:
  - path: workload/example
    selectors: [k8s:ns:example]
  - path: /workload/example
    selectors: [k8s:sa:example]
`)
			Expect(err).Should(MatchError(ContainSubstring(`static entry path "workload/example" is duplicated`)))
		})

		It("requires selectors for each static entry", func() {
			_, err := ValueStringRender(brokerChart, `
clusterName: broker-pods
server:
  address: spire-server.spire-server
controllerManagerClassName: spire-server-spire
workloadAgentAlias: spiffe://example.org/spire/agent/broker-clients
brokers:
  - name: broker
staticEntries:
  - path: workload/example
`)
			Expect(err).Should(MatchError(ContainSubstring("missing property 'selectors'")))
		})

		It("rejects static entries in the reserved SPIFFE ID namespace", func() {
			_, err := ValueStringRender(brokerChart, `
clusterName: broker-pods
server:
  address: spire-server.spire-server
controllerManagerClassName: spire-server-spire
workloadAgentAlias: spiffe://example.org/spire/agent/broker-clients
brokers:
  - name: broker
staticEntries:
  - path: /spire/workload
    selectors: [k8s:ns:example]
`)
			Expect(err).Should(MatchError(ContainSubstring("is in the reserved SPIFFE ID namespace")))
		})
	})

})
