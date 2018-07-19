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

var bucketName = "BGMReport"

func HandleError(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

func main() {
	// Database
	db, err := bolt.Open("my.db", 0600, nil)
	if err != nil {
		log.Fatal(err)
		return
	}
	defer db.Close()
	// Create bucket
	db.Update(func(tx *bolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists([]byte(bucketName))
		if err != nil {
			log.Fatal(fmt.Errorf("create bucket: %s", err))
		}
		return nil
	})
	// Read config
	appid := ""
	secretid := ""
	configFile, err := os.Open("config.txt")
	HandleError(err)
	scanner := bufio.NewScanner(configFile)
	i := 0
	for scanner.Scan() {
		switch i {
		case 0:
			appid = scanner.Text()
		case 1:
			secretid = scanner.Text()
		default:
			break
		}
		i++
	}

	if err := scanner.Err(); err != nil {
		log.Fatal(err)
	}

	log.Printf("Appid: %s, Secretid: %s", appid, secretid)

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

	// Handler for BGM callback
	CallbackHandler := func(w http.ResponseWriter, r *http.Request) {
		// Get access code
		q := r.URL.Query()
		code := q.Get("code")
		resp, err := http.PostForm("https://bgm.tv/oauth/access_token",
			url.Values{
				"grant_type":    {"authorization_code"},
				"client_id":     {appid},
				"client_secret": {secretid},
				"code":          {code},
				"redirect_uri":  {"http://bgm.xiadong.info:8080/callback"},
			})

		HandleError(err)

		body, err := ioutil.ReadAll(resp.Body)
		HandleError(err)

		resp.Body.Close()

		json, err := simplejson.NewJson(body)
		HandleError(err)
		// Modify expire time
		expireTime := json.Get("expires_in").MustInt64()
		json.Set("expires_in", expireTime+time.Now().Unix())
		uid := fmt.Sprintf("%d", json.Get("user_id").MustInt())
		// Get username
		resp, err = http.Get("https://api.bgm.tv/user/" + uid)
		HandleError(err)
		body, err = ioutil.ReadAll(resp.Body)
		HandleError(err)

		resp.Body.Close()
		userinfo, err := simplejson.NewJson(body)
		HandleError(err)
		username := userinfo.Get("username").MustString()
		// Add to data base
		db.Update(func(tx *bolt.Tx) error {
			b := tx.Bucket([]byte(bucketName))
			value, err := json.MarshalJSON()
			HandleError(err)
			err = b.Put([]byte(username), value)
			return err
		})
		// Redirect
		http.Redirect(w, r, "/report/"+username, 301)
	}

	// Register handlers
	http.HandleFunc("/report/", ReportHandler)
	http.HandleFunc("/callback", CallbackHandler)

	log.Fatal(http.ListenAndServe("127.0.0.1:8080", nil))
}
