package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"golang.org/x/crypto/ssh"
)

type Config struct {
	IPs              []string
	Passwords        []string
	PAMTokens        []string
	SSHKeyPath       string
	SSHKeyPassphrase string
	AppPorts         string
	BinaryPath       string
	TemplatesPath    string
	StaticPath       string
	SSHConfigPath    string
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	config, err := loadConfig()
	if err != nil {
		log.Fatalf("❌ Error loading configuration: %v", err)
	}

	switch os.Args[1] {
	case "deploy":
		handleDeploy(config)
	case "tunnels":
		handleTunnels(config)
	case "ssh":
		handleSSH(config)
	case "askpass":
		handleAskpass()
	default:
		fmt.Printf("Unknown command: %s\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println("Usage: deploy <command> [args]")
	fmt.Println("Commands:")
	fmt.Println("  deploy    - Deploy the Go application to all servers")
	fmt.Println("  tunnels   - Establish secure MFA tunnels for all servers")
	fmt.Println("  ssh       - Connect to one of the servers")
}

func loadConfig() (*Config, error) {
	ips, err := readLines("deploy/state/ips")
	if err != nil {
		return nil, err
	}
	passwords, err := readLines("deploy/state/deployer_passwords")
	if err != nil {
		return nil, err
	}
	pamTokens, err := readLines("deploy/state/pam_tokens")
	if err != nil {
		return nil, err
	}
	passphrase, err := os.ReadFile("deploy/state/ssh_key_passphrase")
	if err != nil {
		return nil, err
	}

	appPorts := os.Getenv("APP_PORTS")
	if appPorts == "" {
		appPorts = "80,443"
	}

	home, _ := os.UserHomeDir()
	sshKeyPath := os.Getenv("SSH_KEY_PATH")
	if sshKeyPath == "" {
		sshKeyPath = filepath.Join(home, ".ssh", "first-time-provisioning", "id_ed25519")
	}

	return &Config{
		IPs:              ips,
		Passwords:        passwords,
		PAMTokens:        pamTokens,
		SSHKeyPath:       sshKeyPath,
		SSHKeyPassphrase: strings.TrimSpace(string(passphrase)),
		AppPorts:         appPorts,
		BinaryPath:       "bin/helloworld",
		TemplatesPath:    "app/templates",
		StaticPath:       "app/static",
		SSHConfigPath:    "deploy/state/ssh_config",
	}, nil
}

func readLines(path string) ([]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var lines []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		lines = append(lines, strings.TrimSpace(scanner.Text()))
	}
	return lines, scanner.Err()
}

func handleDeploy(config *Config) {
	for i, ip := range config.IPs {
		fmt.Printf("🌐 Deploying to %s...\n", ip)
		err := deployToServer(ip, config.Passwords[i], config.PAMTokens[i], config)
		if err != nil {
			log.Printf("❌ Failed to deploy to %s: %v", ip, err)
			continue
		}
		fmt.Printf("✅ Successfully deployed to %s\n", ip)
	}
}

func deployToServer(ip, password, pamToken string, config *Config) error {
	client, err := getSSHClient(ip, password, pamToken, config)

	if err != nil {
		return err
	}

	// 1. Ensure directories exist
	err = runCommand(client, "sudo mkdir -p /opt/app/templates /opt/app/static && sudo chown -R deployer:deployer /opt/app")
	if err != nil {
		return err
	}

	// 2. Stop service
	runCommand(client, "sudo systemctl stop helloworld")

	// 3. Upload binary
	err = uploadFile(client, config.BinaryPath, "/opt/app/helloworld", 0755)
	if err != nil {
		return err
	}

	// 4. Upload templates
	err = uploadDirectory(client, config.TemplatesPath, "/opt/app/templates")
	if err != nil {
		return err
	}

	// 5. Upload static files
	err = uploadDirectory(client, config.StaticPath, "/opt/app/static")
	if err != nil {
		return err
	}

	// 6. Create environment file
	envContent := fmt.Sprintf("APP_PORTS=%s\n", config.AppPorts)
	err = runCommand(client, fmt.Sprintf("echo '%s' | sudo tee /etc/helloworld.env > /dev/null", envContent))
	if err != nil {
		return err
	}

	// 7. Set capabilities
	err = runCommand(client, "sudo setcap cap_net_bind_service=+ep /opt/app/helloworld")
	if err != nil {
		return err
	}

	// 8. Create systemd service unit
	serviceContent := `[Unit]
Description=Helloworld Go App
After=network.target

[Service]
ExecStart=/opt/app/helloworld
User=deployer
Group=deployer
EnvironmentFile=/etc/helloworld.env
Restart=always

[Install]
WantedBy=multi-user.target
`
	err = runCommand(client, fmt.Sprintf("echo '%s' | sudo tee /etc/systemd/system/helloworld.service > /dev/null", serviceContent))
	if err != nil {
		return err
	}

	// 9. Reload and restart
	err = runCommand(client, "sudo systemctl daemon-reload && sudo systemctl enable helloworld && sudo systemctl restart helloworld")
	if err != nil {
		return err
	}

	return nil
}

func getSSHClient(ip, password, pamToken string, config *Config) (*ssh.Client, error) {
	keyBytes, err := ioutil.ReadFile(config.SSHKeyPath)
	if err != nil {
		return nil, fmt.Errorf("could not read SSH key: %v", err)
	}

	signer, err := ssh.ParsePrivateKeyWithPassphrase(keyBytes, []byte(config.SSHKeyPassphrase))
	if err != nil {
		return nil, fmt.Errorf("could not parse SSH key with passphrase: %v", err)
	}

	sshConfig := &ssh.ClientConfig{
		User: "deployer",
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(signer),
			ssh.KeyboardInteractive(func(user, instruction string, questions []string, echos []bool) (answers []string, err error) {
				answers = make([]string, len(questions))
				for i, q := range questions {
					if strings.Contains(q, "Password") {
						answers[i] = password
					} else if strings.Contains(q, "Verification code") {
						totp, err := generateTOTP(pamToken)
						if err != nil {
							return nil, err
						}
						answers[i] = totp
					}
				}
				return answers, nil
			}),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
	}

	return ssh.Dial("tcp", ip+":22", sshConfig)
}

func handleTunnels(config *Config) {
	fmt.Println("🔐 Opening secure 4-factor tunnels for all servers...")
	for i, ip := range config.IPs {
		err := openTunnel(ip, config.Passwords[i], config.PAMTokens[i], config)
		if err != nil {
			log.Printf("❌ Failed to open tunnel to %s: %v", ip, err)
			continue
		}
	}
	fmt.Println("✅ All tunnels established.")
}

func openTunnel(ip, password, pamToken string, config *Config) error {
	// Check if tunnel exists
	checkCmd := exec.Command("ssh", "-F", config.SSHConfigPath, "-O", "check", "deployer@"+ip)
	if err := checkCmd.Run(); err == nil {
		fmt.Printf("✅ Tunnel to %s already active.\n", ip)
		return nil
	}

	fmt.Printf("🌐 Establishing tunnel to %s...\n", ip)
	totp, err := generateTOTP(pamToken)
	if err != nil {
		return err
	}

	cmd := exec.Command("ssh", "-F", config.SSHConfigPath, "deployer@"+ip, "true")

	// Use SSH_ASKPASS to handle prompts automatically
	self, _ := filepath.Abs(os.Args[0])
	cmd.Env = append(os.Environ(),
		"SSH_ASKPASS="+self,
		"SSH_ASKPASS_REQUIRE=force",
		"ASKPASS_PASSPHRASE="+config.SSHKeyPassphrase,
		"ASKPASS_PASSWORD="+password,
		"ASKPASS_TOTP="+totp,
		"DISPLAY=:0",
	)

	// Suppress output unless there's an error
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ssh failed: %v, stderr: %s", err, stderr.String())
	}

	return nil
}

func handleAskpass() {
	if len(os.Args) < 3 {
		os.Exit(0)
	}
	prompt := os.Args[2]
	if strings.Contains(strings.ToLower(prompt), "passphrase") {
		fmt.Println(os.Getenv("ASKPASS_PASSPHRASE"))
	} else if strings.Contains(strings.ToLower(prompt), "password") {
		fmt.Println(os.Getenv("ASKPASS_PASSWORD"))
	} else if strings.Contains(strings.ToLower(prompt), "verification code") {
		fmt.Println(os.Getenv("ASKPASS_TOTP"))
	}
	os.Exit(0)
}

func handleSSH(config *Config) {
	if len(config.IPs) == 0 {
		fmt.Println("❌ No servers found.")
		return
	}

	var ip string
	var choice int
	if len(config.IPs) == 1 {
		ip = config.IPs[0]
		choice = 0
	} else {
		fmt.Println("Found servers:")
		for i, ip := range config.IPs {
			fmt.Printf("[%d] %s\n", i+1, ip)
		}
		fmt.Print("Select a server: ")
		fmt.Scanln(&choice)
		if choice < 1 || choice > len(config.IPs) {
			fmt.Println("❌ Invalid selection.")
			return
		}
		choice--
		ip = config.IPs[choice]
	}

	// Show secrets
	fmt.Printf("🔑 Deployer Password: %s\n", config.Passwords[choice])
	totp, _ := generateTOTP(config.PAMTokens[choice])
	fmt.Printf("🔐 Verification Code: %s\n", totp)
	fmt.Printf("🔑 SSH Key Passphrase: %s\n", config.SSHKeyPassphrase)

	fmt.Printf("🌐 Connecting to %s...\n", ip)
	cmd := exec.Command("ssh", "-F", config.SSHConfigPath, "deployer@"+ip)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()
}

func generateTOTP(secret string) (string, error) {
	out, err := exec.Command("oathtool", "--base32", "--totp", secret).Output()
	if err != nil {
		return "", fmt.Errorf("oathtool failed: %v", err)
	}
	return strings.TrimSpace(string(out)), nil
}

func runCommand(client *ssh.Client, cmd string) error {
	session, err := client.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()

	if err := session.Run(cmd); err != nil {
		return fmt.Errorf("failed to run command '%s': %v", cmd, err)
	}
	return nil
}

func uploadFile(client *ssh.Client, src, dest string, mode os.FileMode) error {
	content, err := ioutil.ReadFile(src)
	if err != nil {
		return err
	}

	session, err := client.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()

	session.Stdin = bytes.NewReader(content)
	cmd := fmt.Sprintf("cat > %s && chmod %o %s", dest, mode, dest)
	if err := session.Run(cmd); err != nil {
		return fmt.Errorf("failed to upload file to %s: %v", dest, err)
	}
	return nil
}

func uploadDirectory(client *ssh.Client, src, dest string) error {
	files, err := ioutil.ReadDir(src)
	if err != nil {
		return err
	}

	for _, f := range files {
		if f.IsDir() {
			newDest := filepath.Join(dest, f.Name())
			err = runCommand(client, fmt.Sprintf("mkdir -p %s", newDest))
			if err != nil {
				return err
			}
			err = uploadDirectory(client, filepath.Join(src, f.Name()), newDest)
			if err != nil {
				return err
			}
		} else {
			err = uploadFile(client, filepath.Join(src, f.Name()), filepath.Join(dest, f.Name()), 0644)
			if err != nil {
				return err
			}
		}
	}
	return nil
}
