package install

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/user"
	"strconv"
	"strings"
	"time"

	"github.com/en3sis/rackpulse/agent/internal/config"
)

func SetKey(args []string) error {
	if len(args) > 1 {
		return errors.New("Usage: rackpulse-agent set-key <key>")
	}
	if err := requireRoot(); err != nil {
		return err
	}
	key, err := readKey(args)
	if err != nil {
		return err
	}
	if err := config.ValidateToken(key); err != nil {
		return err
	}
	cfg, err := config.Load(config.Path)
	if errors.Is(err, os.ErrNotExist) {
		return errors.New("The agent is not installed. Run the install command from Rackpulse")
	}
	if err != nil {
		return err
	}
	group, err := user.LookupGroup(userName)
	if err != nil {
		return fmt.Errorf("group %s not found: %w", userName, err)
	}
	gid, _ := strconv.Atoi(group.Gid)
	cfg.Token = key
	if err := cfg.Validate(); err != nil {
		return err
	}
	if err := writeConfig(cfg, account{gid: gid}); err != nil {
		return fmt.Errorf("write %s: %w", config.Path, err)
	}
	if err := command("systemctl", "restart", serviceName); err != nil {
		return err
	}
	if !waitForListening(cfg, 5*time.Second) {
		return fmt.Errorf("The key is saved, but the service did not start listening on %s. See: journalctl -u rackpulse-agent -n 20", cfg.Address())
	}
	fmt.Println("Key changed. The old key no longer works. Rackpulse reconnects within a few seconds.")
	return nil
}

func readKey(args []string) (string, error) {
	if len(args) == 1 {
		return strings.TrimSpace(args[0]), nil
	}
	if info, err := os.Stdin.Stat(); err == nil && info.Mode()&os.ModeCharDevice != 0 {
		return "", errors.New("Pass the key as an argument or on stdin: echo rb1_... | sudo rackpulse-agent set-key")
	}
	line, err := bufio.NewReader(io.LimitReader(os.Stdin, 4096)).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", err
	}
	return strings.TrimSpace(line), nil
}
