package unit_test

import (
	"cmp"
	"encoding/json"
	"fmt"
	"io"
	"slices"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	helmloader "helm.sh/helm/v3/pkg/chart/loader"
	helmutil "helm.sh/helm/v3/pkg/chartutil"
	corev1 "k8s.io/api/core/v1"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

type scc struct {
	Metadata struct {
		Name string `json:"name"`
	} `json:"metadata"`
	Users                    []string `json:"users"`
	AllowPrivilegedContainer bool     `json:"allowPrivilegedContainer"`
	AllowPrivilegeEscalation *bool    `json:"allowPrivilegeEscalation"`
	AllowHostPID             bool     `json:"allowHostPID"`
	AllowHostNetwork         bool     `json:"allowHostNetwork"`
	AllowHostIPC             bool     `json:"allowHostIPC"`
	AllowHostPorts           bool     `json:"allowHostPorts"`
	AllowHostDirVolumePlugin bool     `json:"allowHostDirVolumePlugin"`
	ReadOnlyRootFilesystem   bool     `json:"readOnlyRootFilesystem"`
	Volumes                  []string `json:"volumes"`
	SeccompProfiles          []string `json:"seccompProfiles"`
	AllowedCapabilities      []string `json:"allowedCapabilities"`
	RunAsUser                struct {
		Type string `json:"type"`
	} `json:"runAsUser"`
}

type workload struct {
	Kind     string `json:"kind"`
	Metadata struct {
		Name      string `json:"name"`
		Namespace string `json:"namespace"`
	} `json:"metadata"`
	Spec struct {
		Template struct {
			Spec corev1.PodSpec `json:"spec"`
		} `json:"template"`
	} `json:"spec"`
}

// restrictedV2 mirrors the OpenShift default SCC that every service account may use.
var restrictedV2 = scc{
	Volumes:             []string{"configMap", "csi", "downwardAPI", "emptyDir", "ephemeral", "persistentVolumeClaim", "projected", "secret"},
	SeccompProfiles:     []string{"runtime/default"},
	AllowedCapabilities: []string{"NET_BIND_SERVICE"},
	RunAsUser: struct {
		Type string `json:"type"`
	}{"MustRunAsRange"},
}

func volumeKind(v corev1.Volume) string {
	switch {
	case v.HostPath != nil:
		return "hostPath"
	case v.ConfigMap != nil:
		return "configMap"
	case v.Secret != nil:
		return "secret"
	case v.EmptyDir != nil:
		return "emptyDir"
	case v.Projected != nil:
		return "projected"
	case v.CSI != nil:
		return "csi"
	case v.DownwardAPI != nil:
		return "downwardAPI"
	case v.PersistentVolumeClaim != nil:
		return "persistentVolumeClaim"
	case v.Ephemeral != nil:
		return "ephemeral"
	}
	return "other"
}

func seccompName(p *corev1.SeccompProfile) string {
	switch {
	case p == nil:
		return ""
	case p.Type == corev1.SeccompProfileTypeRuntimeDefault:
		return "runtime/default"
	case p.Type == corev1.SeccompProfileTypeLocalhost && p.LocalhostProfile != nil:
		return "localhost/" + *p.LocalhostProfile
	}
	return strings.ToLower(string(p.Type))
}

// admits lists why s rejects pod; an empty list means OpenShift admits it.
func (s scc) admits(pod corev1.PodSpec) (why []string) {
	deny := func(format string, a ...any) { why = append(why, fmt.Sprintf(format, a...)) }
	allowed := func(list []string, v string) bool {
		return slices.Contains(list, "*") || slices.Contains(list, v)
	}
	if pod.HostPID && !s.AllowHostPID {
		deny("hostPID")
	}
	if pod.HostNetwork && !s.AllowHostNetwork {
		deny("hostNetwork")
	}
	if pod.HostIPC && !s.AllowHostIPC {
		deny("hostIPC")
	}
	for _, v := range pod.Volumes {
		if k := volumeKind(v); !allowed(s.Volumes, k) && !(k == "hostPath" && s.AllowHostDirVolumePlugin) {
			deny("volume %s of type %s", v.Name, k)
		}
	}
	podSC := pod.SecurityContext
	if podSC == nil {
		podSC = &corev1.PodSecurityContext{}
	}
	for _, c := range slices.Concat(pod.InitContainers, pod.Containers) {
		sc := c.SecurityContext
		if sc == nil {
			sc = &corev1.SecurityContext{}
		}
		privileged := sc.Privileged != nil && *sc.Privileged
		if privileged && !s.AllowPrivilegedContainer {
			deny("%s: privileged", c.Name)
		}
		if (privileged || sc.AllowPrivilegeEscalation != nil && *sc.AllowPrivilegeEscalation) && s.AllowPrivilegeEscalation != nil && !*s.AllowPrivilegeEscalation {
			deny("%s: privilege escalation", c.Name)
		}
		if sc.ReadOnlyRootFilesystem != nil && !*sc.ReadOnlyRootFilesystem && s.ReadOnlyRootFilesystem {
			deny("%s: writable root filesystem", c.Name)
		}
		if p := seccompName(cmpOr(sc.SeccompProfile, podSC.SeccompProfile)); p != "" && !allowed(s.SeccompProfiles, p) {
			deny("%s: seccomp profile %s", c.Name, p)
		}
		if uid := cmpOr(sc.RunAsUser, podSC.RunAsUser); uid != nil && s.RunAsUser.Type == "MustRunAsRange" {
			deny("%s: runAsUser %d outside the namespace range", c.Name, *uid)
		}
		if sc.Capabilities != nil {
			for _, add := range sc.Capabilities.Add {
				if !allowed(s.AllowedCapabilities, string(add)) {
					deny("%s: capability %s", c.Name, add)
				}
			}
		}
		for _, p := range c.Ports {
			if p.HostPort != 0 && !s.AllowHostPorts {
				deny("%s: hostPort %d", c.Name, p.HostPort)
			}
		}
	}
	return why
}

func cmpOr[T any](a, b *T) *T {
	if a != nil {
		return a
	}
	return b
}

func convert(raw map[string]any, out any) error {
	b, err := json.Marshal(raw)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, out)
}

func decodeAll(objs map[string]string, values helmutil.Values) (sccs []scc, workloads []workload) {
	for name, rendered := range objs {
		sub, _, _ := strings.Cut(strings.TrimPrefix(name, "spire/charts/"), "/")
		if enabled, err := values.PathValue(sub + ".enabled"); !strings.HasSuffix(name, ".yaml") || (err == nil && enabled == false) {
			continue
		}
		dec := yamlutil.NewYAMLOrJSONDecoder(strings.NewReader(rendered), 4096)
		for {
			var raw map[string]any
			if err := dec.Decode(&raw); err == io.EOF {
				break
			} else {
				Expect(err).ShouldNot(HaveOccurred(), name)
			}
			switch raw["kind"] {
			case "SecurityContextConstraints":
				var s scc
				Expect(convert(raw, &s)).Should(Succeed())
				sccs = append(sccs, s)
			case "Deployment", "DaemonSet", "StatefulSet":
				var w workload
				Expect(convert(raw, &w)).Should(Succeed())
				workloads = append(workloads, w)
			}
		}
	}
	return sccs, workloads
}

var _ = Describe("OpenShift SCC admission", func() {
	DescribeTable("admits every workload the chart renders under an SCC its service account may use",
		func(values string) {
			chart, err := helmloader.Load("../../charts/spire")
			Expect(err).Should(Succeed())
			objs, err := ValueStringRender(chart, values)
			Expect(err).Should(Succeed())
			v, err := helmutil.ReadValues([]byte(values))
			Expect(err).Should(Succeed())
			merged, err := helmutil.CoalesceValues(chart, v)
			Expect(err).Should(Succeed())
			sccs, workloads := decodeAll(objs, merged)
			Expect(workloads).ShouldNot(BeEmpty())
			for _, w := range workloads {
				ns := cmp.Or(w.Metadata.Namespace, "spire-server")
				sa := cmp.Or(w.Spec.Template.Spec.ServiceAccountName, "default")
				reasons := map[string][]string{"restricted-v2": restrictedV2.admits(w.Spec.Template.Spec)}
				for _, s := range sccs {
					if slices.Contains(s.Users, "system:serviceaccount:"+ns+":"+sa) {
						reasons[s.Metadata.Name] = s.admits(w.Spec.Template.Spec)
					}
				}
				admitted := false
				for _, why := range reasons {
					admitted = admitted || len(why) == 0
				}
				Expect(admitted).Should(BeTrue(), "%s %s/%s rejected by every SCC: %v", w.Kind, ns, w.Metadata.Name, reasons)
			}
		},
		Entry("with the default values", `
global:
  openshift: true
`),
		Entry("with the recommended security contexts", `
global:
  openshift: true
  spire:
    recommendations:
      enabled: true
      strictMode: false
`),
		Entry("with a hardened agent", `
global:
  openshift: true
spire-agent:
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: [ALL]
    seccompProfile:
      type: RuntimeDefault
`),
	)
})
