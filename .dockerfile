# Build stage
FROM golang:1.20 AS builder
WORKDIR /app
# Copy go modules files and download dependencies.
COPY go.mod go.sum ./
RUN go mod download
# Copy source code.
COPY . .
# Build the binary (statically linked).
RUN CGO_ENABLED=0 GOOS=linux go build -o go-wrapper .

# Final stage: a minimal image.
FROM scratch
COPY --from=builder /app/go-wrapper /go-wrapper
EXPOSE 8080
ENTRYPOINT ["/go-wrapper"]
