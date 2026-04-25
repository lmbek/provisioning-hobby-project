package main

import (
	"net/http"
	"os"
	"path/filepath"
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
		if hostname == "hello-app-1" {
			theme = "alt"
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
