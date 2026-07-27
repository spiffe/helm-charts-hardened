// brokerclient is a manual integration-test driver for the SPIFFE Broker API.
// It fetches its own X509-SVID from the Workload API, then dials a Broker API
// TCP endpoint with mTLS and requests an X509-SVID for a workload reference.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"time"

	"github.com/spiffe/go-spiffe/v2/exp/proto/spiffe/broker"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/anypb"
)

var (
	workloadAPIAddr  = flag.String("workload-api", "unix:///run/spire/agent-sockets/spire-agent.sock", "Workload API socket URI")
	brokerAddr       = flag.String("broker-addr", "dns:///spire-tcp-broker:8443", "Broker API endpoint URI")
	trustDomain      = flag.String("trust-domain", "example.org", "Trust domain to authorize when dialing the Broker API")
	refType          = flag.String("ref-type", "", "Reference type: pid or object")
	pid              = flag.Int("pid", 0, "PID for a WorkloadPIDReference")
	plural           = flag.String("plural", "", "Kubernetes resource plural, for example pods or configmaps")
	group            = flag.String("group", "", "Kubernetes resource group; use core for core API resources")
	namespace        = flag.String("namespace", "", "Kubernetes object namespace")
	name             = flag.String("name", "", "Kubernetes object name")
	uid              = flag.String("uid", "", "Kubernetes object UID")
	expectedOwnID    = flag.String("expected-own-spiffe", "", "Expected SPIFFE ID fetched from the Workload API")
	expectedSPIFFEID = flag.String("expected-spiffe", "", "Expected SPIFFE ID in the Broker API response")
	expectEmpty      = flag.Bool("expect-empty", false, "Expect the Broker API response to contain no X509-SVIDs")
	expectOwnError   = flag.Bool("expect-own-error", false, "Expect fetching the workload's own X509-SVID to fail")
	expectErr        = flag.String("expect-err", "", "Expected gRPC status code, for example PermissionDenied or Unavailable")
	skipBroker       = flag.Bool("skip-broker", false, "Only fetch and verify the workload's own X509-SVID")
	timeout          = flag.Duration("timeout", 90*time.Second, "Overall request timeout")
)

func main() {
	flag.Parse()
	if err := run(); err != nil {
		log.Fatalf("brokerclient: %v", err)
	}
	log.Print("brokerclient: OK")
}

func run() error {
	if *expectEmpty && *expectedSPIFFEID != "" {
		return errors.New("-expect-empty and -expected-spiffe cannot be used together")
	}
	if *expectEmpty && *expectErr != "" {
		return errors.New("-expect-empty and -expect-err cannot be used together")
	}

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	source, err := workloadapi.NewX509Source(ctx,
		workloadapi.WithClientOptions(workloadapi.WithAddr(*workloadAPIAddr)),
	)
	if err != nil {
		if *expectOwnError {
			log.Printf("got expected Workload API error: %v", err)
			return nil
		}
		return fmt.Errorf("create Workload API X509 source: %w", err)
	}
	defer source.Close()

	ownSVID, err := source.GetX509SVID()
	if err != nil {
		if *expectOwnError {
			log.Printf("got expected Workload API error: %v", err)
			return nil
		}
		return fmt.Errorf("get own X509-SVID: %w", err)
	}
	if *expectOwnError {
		return errors.New("expected fetching own X509-SVID to fail")
	}
	log.Printf("own SPIFFE ID: %s", ownSVID.ID)

	if *expectedOwnID != "" && ownSVID.ID.String() != *expectedOwnID {
		return fmt.Errorf("expected own SPIFFE ID %s, got %s", *expectedOwnID, ownSVID.ID)
	}
	if *skipBroker {
		return nil
	}

	request, err := buildRequest()
	if err != nil {
		return err
	}

	td, err := spiffeid.TrustDomainFromString(*trustDomain)
	if err != nil {
		return fmt.Errorf("parse trust domain: %w", err)
	}
	tlsConfig := tlsconfig.MTLSClientConfig(source, source, tlsconfig.AuthorizeMemberOf(td))

	conn, err := grpc.NewClient(*brokerAddr,
		grpc.WithTransportCredentials(credentials.NewTLS(tlsConfig)),
	)
	if err != nil {
		return fmt.Errorf("create Broker API connection: %w", err)
	}
	defer conn.Close()

	client := broker.NewAPIClient(conn)
	ctx = metadata.AppendToOutgoingContext(ctx, "broker.spiffe.io", "true")

	stream, err := client.SubscribeToX509SVID(ctx, request)
	if err != nil {
		return checkError(err)
	}
	response, err := stream.Recv()
	if err != nil {
		return checkError(err)
	}
	return checkResponse(response)
}

func buildRequest() (*broker.SubscribeToX509SVIDRequest, error) {
	var (
		reference *anypb.Any
		err       error
	)

	switch *refType {
	case "pid":
		reference, err = anypb.New(&broker.WorkloadPIDReference{Pid: int32(*pid)})
	case "object":
		if *plural == "" || *group == "" {
			return nil, errors.New("object references require -plural and -group")
		}
		if *uid == "" && *name == "" {
			return nil, errors.New("object references require -uid or -name")
		}

		objectReference := &broker.KubernetesObjectReference{
			Type: &broker.KubernetesObjectType{
				Plural: *plural,
				Group:  *group,
			},
		}
		if *namespace != "" || *name != "" {
			objectReference.Key = &broker.KubernetesObjectKey{
				Namespace: *namespace,
				Name:      *name,
			}
		}
		if *uid != "" {
			objectReference.Uid = *uid
		}
		reference, err = anypb.New(objectReference)
	default:
		return nil, fmt.Errorf("unknown -ref-type %q", *refType)
	}
	if err != nil {
		return nil, fmt.Errorf("pack workload reference: %w", err)
	}

	return &broker.SubscribeToX509SVIDRequest{
		Reference: &broker.WorkloadReference{Reference: reference},
	}, nil
}

func checkError(err error) error {
	code := status.Code(err).String()
	if *expectErr == "" {
		return fmt.Errorf("unexpected Broker API error (code %s): %w", code, err)
	}
	if code != *expectErr {
		return fmt.Errorf("expected gRPC code %s, got %s: %w", *expectErr, code, err)
	}
	log.Printf("got expected gRPC code %s: %v", code, err)
	return nil
}

func checkResponse(response *broker.SubscribeToX509SVIDResponse) error {
	if *expectErr != "" {
		return fmt.Errorf("expected gRPC code %s, but received %d X509-SVIDs", *expectErr, len(response.Svids))
	}

	log.Printf("received %d X509-SVIDs", len(response.Svids))
	if *expectEmpty {
		if len(response.Svids) != 0 {
			return fmt.Errorf("expected no X509-SVIDs, got %d", len(response.Svids))
		}
		log.Print("Broker API response was empty as expected")
		return nil
	}

	if *expectedSPIFFEID == "" {
		if len(response.Svids) == 0 {
			return errors.New("Broker API response contained no X509-SVIDs")
		}
		return nil
	}

	var receivedIDs []string
	for _, svid := range response.Svids {
		receivedIDs = append(receivedIDs, svid.SpiffeId)
		if svid.SpiffeId == *expectedSPIFFEID {
			log.Printf("found expected SPIFFE ID: %s", svid.SpiffeId)
			return nil
		}
	}
	return fmt.Errorf("expected SPIFFE ID %s, response contained %v", *expectedSPIFFEID, receivedIDs)
}
