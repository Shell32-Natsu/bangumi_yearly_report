package main

import (
	"fmt"
	"html"
	"log"
	"net/http"
	"os/exec"
	"strings"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)

	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "http_request_duration_seconds",
			Help: "HTTP request latency",
		},
		[]string{"method", "endpoint"},
	)
)

func initMetrics() {

	// Register metrics
	prometheus.MustRegister(requestsTotal)
	prometheus.MustRegister(requestDuration)
}

func main() {
	initMetrics()
	// Start metrics server on separate port
	go func() {
		log.Println("Starting metrics server on :9090")
		http.Handle("/metrics", promhttp.Handler())
		if err := http.ListenAndServe(":9090", nil); err != nil {
			log.Fatal("Metrics server failed:", err)
		}
	}()

	// Handler for report
	ReportHandler := func(w http.ResponseWriter, r *http.Request) {
		log.Printf("Received request: %s %s", r.Method, r.URL.Path)
		timer := prometheus.NewTimer(requestDuration.WithLabelValues(r.Method, r.URL.Path))
		defer timer.ObserveDuration()
		pathSlices := strings.Split(html.EscapeString(r.URL.Path), "/")
		username := pathSlices[len(pathSlices)-1]
		q := r.URL.Query()
		year := q.Get("year")
		if year == "" {
			year = "2018"
		}

		// Call python script
		cmd := exec.Command("./bangumi_report.py", "-u", username, "-o", "-q", "-y", year)
		out, err := cmd.CombinedOutput()
		if err == nil {
			fmt.Fprint(w, string(out))
		} else {
			// fmt.Fprint(w, "Error occurs\n" + err.Error() + "\n" + string(out))
			fmt.Fprint(w, "Error occurs\n"+err.Error())
		}
		requestsTotal.WithLabelValues(r.Method, r.URL.Path, "200").Inc()
	}

	// Main application server
	mux := http.NewServeMux()
	// Register handlers
	mux.HandleFunc("/report/", ReportHandler)

	log.Fatal(http.ListenAndServe("0.0.0.0:8080", mux))
}
