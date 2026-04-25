package main

import (
	"log/slog"
	"os"
	"strings"
)

func main() {
	// Initialize structured logger
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	// Load configuration
	ports := os.Getenv("APP_PORTS")
	if ports == "" {
		ports = "80"
	}

	templateDir, staticDir := getPaths()

	cfg := Config{
		Ports:       strings.Split(ports, ","),
		TemplateDir: templateDir,
		StaticDir:   staticDir,
		Logger:      logger,
	}

	// Initialize and start server
	server, err := NewWebServer(cfg)
	if err != nil {
		logger.Error("Failed to initialize server", "error", err)
		os.Exit(1)
	}

	logger.Info("Starting application", "ports", cfg.Ports)
	if err := server.Start(); err != nil {
		logger.Error("Application shutdown unexpectedly", "error", err)
		os.Exit(1)
	}
}
