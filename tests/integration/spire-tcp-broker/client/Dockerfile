FROM golang:1.26.2-alpine3.23 AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY integration/spire-tcp-broker/client ./integration/spire-tcp-broker/client
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/brokerclient ./integration/spire-tcp-broker/client

FROM scratch
COPY --from=build /out/brokerclient /brokerclient
USER 65532:65532
ENTRYPOINT ["/brokerclient"]
