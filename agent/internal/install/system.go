package install

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/en3sis/rackpulse/agent/internal/config"
)

func requireRoot() error {
	if os.Geteuid() != 0 {
		return errors.New("Run this command as root, for example with sudo")
	}
	return nil
}

func requireSystemd() error {
	if _, err := os.Stat("/run/systemd/system"); err != nil {
		return errors.New("This server does not run systemd. The Rackpulse agent needs systemd")
	}
	return nil
}

func command(name string, args ...string) error {
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		text := strings.TrimSpace(string(out))
		if text == "" {
			return fmt.Errorf("%s %s: %w", name, strings.Join(args, " "), err)
		}
		return fmt.Errorf("%s %s: %s", name, strings.Join(args, " "), text)
	}
	return nil
}

func commandOutput(name string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, _ := exec.CommandContext(ctx, name, args...).Output()
	return strings.TrimSpace(string(out))
}

func serviceActive() bool {
	return commandOutput("systemctl", "is-active", serviceName) == "active"
}

func waitForListening(cfg config.Config, timeout time.Duration) bool {
	host := cfg.Listen
	if host == "" {
		host = "127.0.0.1"
	}
	address := net.JoinHostPort(host, strconv.Itoa(cfg.Port))
	deadline := time.Now().Add(timeout)
	for {
		if serviceActive() {
			if conn, err := net.DialTimeout("tcp", address, time.Second); err == nil {
				conn.Close()
				return true
			}
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(250 * time.Millisecond)
	}
}

type account struct {
	uid, gid int
}

func ensureUser() (account, error) {
	if _, err := user.Lookup(userName); err != nil {
		if _, lookErr := exec.LookPath("useradd"); lookErr == nil {
			err = command("useradd", "--system", "--user-group", "--no-create-home", "--home-dir", "/nonexistent", "--shell", "/usr/sbin/nologin", userName)
		} else {
			err = command("adduser", "--system", "--group", "--no-create-home", "--home", "/nonexistent", "--shell", "/usr/sbin/nologin", userName)
		}
		if err != nil {
			return account{}, fmt.Errorf("create user %s: %w", userName, err)
		}
	}
	found, err := user.Lookup(userName)
	if err != nil {
		return account{}, err
	}
	group, err := user.LookupGroup(userName)
	if err != nil {
		return account{}, fmt.Errorf("group %s not found: %w", userName, err)
	}
	if _, err := user.LookupGroup("docker"); err == nil {
		if err := command("usermod", "-aG", "docker", userName); err != nil {
			return account{}, err
		}
	}
	uid, _ := strconv.Atoi(found.Uid)
	gid, _ := strconv.Atoi(group.Gid)
	return account{uid: uid, gid: gid}, nil
}

func writeConfig(cfg config.Config, owner account) error {
	if err := os.MkdirAll(config.Dir, 0o750); err != nil {
		return err
	}
	if err := os.Chown(config.Dir, 0, owner.gid); err != nil {
		return err
	}
	if err := os.Chmod(config.Dir, 0o750); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	tmp := config.Path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o640); err != nil {
		return err
	}
	if err := os.Chown(tmp, 0, owner.gid); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Chmod(tmp, 0o640); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, config.Path)
}

func chownTree(root string, owner account) error {
	return filepath.Walk(root, func(path string, _ os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		return os.Lchown(path, owner.uid, owner.gid)
	})
}
