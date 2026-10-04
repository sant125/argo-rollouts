FROM golang:1-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /app .

# distroless: sem shell, sem pacote, já roda como não-root
FROM gcr.io/distroless/static:nonroot
COPY --from=build /app /app
EXPOSE 8080
ENTRYPOINT ["/app"]
