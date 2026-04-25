package main

import (
	"html/template"
	"log/slog"
	"net/http"
)

// PageData represents the data passed to the HTML templates.
type PageData struct {
	Hostname string
	Port     string
	Theme    string
}

// Config holds the application configuration.
type Config struct {
	Ports       []string
	TemplateDir string
	StaticDir   string
	Logger      *slog.Logger
}

// WebServer defines the interface for our application server.
type WebServer interface {
	Start() error
}

// AppServer implements the WebServer interface.
type AppServer struct {
	config Config
	mux    *http.ServeMux
	tmpl   *template.Template
}
