package collect

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"strings"
	"time"
)

type SystemInfo struct {
	RebootRequired bool     `json:"rebootRequired"`
	FailedUnits    []string `json:"failedUnits"`
}

func readSystem(ctx context.Context) SystemInfo {
	info := SystemInfo{FailedUnits: []string{}}
	if _, err := os.Stat("/var/run/reboot-required"); err == nil {
		info.RebootRequired = true
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "systemctl", "list-units", "--state=failed", "--no-legend", "--plain", "--no-pager").Output()
	if err != nil {
		return info
	}
	info.FailedUnits = parseFailedUnits(out)
	return info
}

func parseFailedUnits(out []byte) []string {
	units := []string{}
	for _, line := range bytes.Split(out, []byte("\n")) {
		fields := strings.Fields(string(line))
		if len(fields) > 0 {
			units = append(units, fields[0])
		}
	}
	return units
}
