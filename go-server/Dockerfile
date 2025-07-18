FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git

WORKDIR /build

COPY go-server/go.mod ./
COPY go-server/main.go .

RUN go mod tidy

RUN go build -o bangumi-server main.go

FROM python:3.13-alpine

RUN apk add --no-cache ca-certificates

WORKDIR /app

COPY --from=builder /build/bangumi-server .

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bangumi_report.py .
COPY template.html .

RUN mkdir -p data

COPY go-server/docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

EXPOSE 8080
EXPOSE 9090

ENTRYPOINT ["./docker-entrypoint.sh"]
