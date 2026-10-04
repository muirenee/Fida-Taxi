FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/telemetry ./main.go

FROM alpine:3.22
RUN adduser -D -u 10001 app
USER app
COPY --from=build /out/telemetry /usr/local/bin/telemetry
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/telemetry"]
