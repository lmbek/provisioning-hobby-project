package main

import (
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func (s *AppServer) handleIndex() http.HandlerFunc {
	hostname, _ := os.Hostname()

	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}

		w.Header().Set("Content-Type", "text/html")
		port := r.Context().Value(http.LocalAddrContextKey).(interface {
			String() string
		}).String()

		theme := "default"
		themes := []string{"default", "alt", "purple", "green", "orange"}

		// Extract index from hostname: "first-time-provisioning-app-X"
		parts := strings.Split(hostname, "-")
		if len(parts) > 0 {
			lastPart := parts[len(parts)-1]
			if idx, err := strconv.Atoi(lastPart); err == nil {
				// We use (idx-1) because hostnames start at 1, but we want 0-based index
				targetIdx := idx - 1
				if targetIdx < 0 {
					targetIdx = 0
				}
				theme = themes[targetIdx%len(themes)]
			}
		}

		data := PageData{
			Hostname: hostname,
			Port:     port,
			Theme:    theme,
		}

		err := s.tmpl.Execute(w, data)
		if err != nil {
			s.config.Logger.Error("Error executing template", "error", err)
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		}
	}
}

func getPaths() (string, string) {
	// Find the executable directory to locate templates and static files
	exePath, _ := os.Executable()
	baseDir := filepath.Dir(exePath)

	templateDir := filepath.Join(baseDir, "templates")
	staticDir := filepath.Join(baseDir, "static")

	// Fallback for local development if running with 'go run'
	if _, err := os.Stat(templateDir); os.IsNotExist(err) {
		templateDir = filepath.Join("app", "templates")
		staticDir = filepath.Join("app", "static")
	}

	return templateDir, staticDir
}
