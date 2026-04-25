package main

import (
	"fmt"
	"html/template"
	"net/http"
	"path/filepath"
	"strings"
	"sync"
)

// NewWebServer initializes a new AppServer with the provided configuration.
func NewWebServer(cfg Config) (WebServer, error) {
	templatePath := filepath.Join(cfg.TemplateDir, "index.html")
	tmpl, err := template.ParseFiles(templatePath)
	if err != nil {
		return nil, fmt.Errorf("failed to parse template: %w", err)
	}

	s := &AppServer{
		config: cfg,
		mux:    http.NewServeMux(),
		tmpl:   tmpl,
	}

	s.routes()
	return s, nil
}

// routes defines the application routing.
func (s *AppServer) routes() {
	// Serve static files
	s.mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir(s.config.StaticDir))))

	// Root handler
	s.mux.HandleFunc("/", s.handleIndex())
}

// Start launches the web server on all configured ports.
func (s *AppServer) Start() error {
	var wg sync.WaitGroup
	errChan := make(chan error, len(s.config.Ports))

	for _, p := range s.config.Ports {
		port := strings.TrimSpace(p)
		wg.Add(1)
		go func(p string) {
			defer wg.Done()
			s.config.Logger.Info("Starting server", "port", p)
			if err := http.ListenAndServe(":"+p, s.mux); err != nil {
				errChan <- fmt.Errorf("server on port %s failed: %w", p, err)
			}
		}(port)
	}

	// This is a simplified wait. In a production app, we'd handle signals.
	// For now, we return the first error we get.
	return <-errChan
}
