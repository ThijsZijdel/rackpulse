package install

import (
	"errors"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"

	"github.com/en3sis/rackpulse/agent/internal/atomicfile"
	"github.com/en3sis/rackpulse/agent/internal/config"
)

const (
	legacyName       = "rackbar-agent"
	legacyUser       = "rackbar"
	legacyConfigDir  = "/etc/rackbar-agent"
	legacyConfigPath = legacyConfigDir + "/config.json"
	legacyStateDir   = "/var/lib/rackbar-agent"
	legacyBinPath    = "/usr/local/bin/rackbar-agent"
	legacyUnitPath   = "/etc/systemd/system/rackbar-agent.service"
)

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

func legacyInstallFound() bool {
	return exists(legacyUnitPath) || exists(legacyConfigDir) || exists(legacyStateDir)
}

func legacyLeftoversFound() bool {
	if legacyInstallFound() || exists(legacyBinPath) {
		return true
	}
	_, err := user.Lookup(legacyUser)
	return err == nil
}

func stopLegacyService() {
	exec.Command("systemctl", "disable", "--now", legacyName).Run()
}

func copyLegacyFile(name string) (bool, error) {
	source := filepath.Join(legacyStateDir, name)
	target := filepath.Join(config.StateDir, name)
	info, err := os.Stat(source)
	if err != nil || exists(target) {
		return false, nil
	}
	data, err := os.ReadFile(source)
	if err != nil {
		return false, err
	}
	return true, atomicfile.Write(target, data, info.Mode().Perm())
}

func copyLegacyState() (bool, error) {
	if err := os.MkdirAll(config.StateDir, 0o700); err != nil {
		return false, err
	}
	certKept := false
	if !exists(config.CertPath) && !exists(config.KeyPath) && exists(filepath.Join(legacyStateDir, "cert.pem")) && exists(filepath.Join(legacyStateDir, "key.pem")) {
		if _, err := copyLegacyFile("key.pem"); err != nil {
			return false, err
		}
		copied, err := copyLegacyFile("cert.pem")
		if err != nil {
			return false, err
		}
		certKept = copied
	}
	for _, name := range []string{"history.json", "containers.json"} {
		if _, err := copyLegacyFile(name); err != nil {
			return certKept, err
		}
	}
	return certKept, nil
}

func removeLegacy() error {
	stopLegacyService()
	if err := os.Remove(legacyUnitPath); err == nil {
		exec.Command("systemctl", "daemon-reload").Run()
	}
	exec.Command("systemctl", "reset-failed", legacyName).Run()
	var problems []error
	for _, path := range []string{legacyBinPath, legacyConfigDir, legacyStateDir} {
		if err := os.RemoveAll(path); err != nil {
			problems = append(problems, err)
		}
	}
	if _, err := user.Lookup(legacyUser); err == nil {
		if err := command("userdel", legacyUser); err != nil {
			problems = append(problems, err)
		}
	}
	if _, err := user.LookupGroup(legacyUser); err == nil {
		exec.Command("groupdel", legacyUser).Run()
	}
	return errors.Join(problems...)
}
