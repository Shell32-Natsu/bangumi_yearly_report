package main

import (
	"bufio"
	"fmt"
	"html"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
	"os/exec"

	"github.com/bitly/go-simplejson"
	"github.com/boltdb/bolt"
)

func main() {
	// Handler for report
	ReportHandler := func(w http.ResponseWriter, r *http.Request) {
		pathSlices := strings.Split(html.EscapeString(r.URL.Path), "/")
		username := pathSlices[len(pathSlices)-1]
		q := r.URL.Query()
		year := q.Get("year")
		if year == "" {
			year = "2018"
		}

		// Call python script
		cmd := exec.Command("./bangumi_report.py", "-u", username, "-o", "-q", "-y", year)
		cmd.Dir = ".."
		out, err := cmd.CombinedOutput()
		if err == nil {
			fmt.Fprint(w, string(out))
		} else {
			// fmt.Fprint(w, "Error occurs\n" + err.Error() + "\n" + string(out))
			fmt.Fprint(w, "Error occurs\n" + err.Error())
		}
	}

	// Register handlers
	http.HandleFunc("/report/", ReportHandler)

	log.Fatal(http.ListenAndServe("127.0.0.1:8080", nil))
}
