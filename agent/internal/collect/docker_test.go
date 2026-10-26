package collect

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestSummarizeDisk(t *testing.T) {
	var usage diskUsage
	data := `{"LayersSize":84272262,
	"Images":[{"Containers":0,"SharedSize":4157440,"Size":6063298},{"Containers":1,"SharedSize":0,"Size":78164777},{"Containers":2,"SharedSize":4157440,"Size":4157440}],
	"Containers":[{"SizeRw":8192},{}],
	"Volumes":[{"Name":"app_pgdata","UsageData":{"RefCount":1,"Size":1000}},{"Name":"orphan","UsageData":{"RefCount":0,"Size":300}},{"Name":"unknown","UsageData":{"RefCount":-1,"Size":-1}}],
	"BuildCache":[{"Size":50,"InUse":true},{"Size":70},{"Size":900,"Shared":true}]}`
	if err := json.Unmarshal([]byte(data), &usage); err != nil {
		t.Fatal(err)
	}
	disk, volumes := summarizeDisk(usage)
	want := DockerDisk{Images: 84272262, ImagesReclaimable: 1905858, BuildCache: 120, BuildCacheReclaimable: 70, Volumes: 1300, VolumesReclaimable: 300, Containers: 8192}
	if *disk != want {
		t.Fatalf("disk %+v\nwant %+v", *disk, want)
	}
	if len(volumes) != 3 || volumes[1] != (Volume{Name: "orphan", Size: 300}) || volumes[2] != (Volume{Name: "unknown", Size: -1}) {
		t.Fatalf("volumes %+v", volumes)
	}
}

func TestListedPortsDeduplicatesAddressFamilies(t *testing.T) {
	var item listedContainer
	json.Unmarshal([]byte(`{"Ports":[
		{"IP":"::","PrivatePort":80,"PublicPort":8080,"Type":"tcp"},
		{"IP":"0.0.0.0","PrivatePort":80,"PublicPort":8080,"Type":"tcp"},
		{"PrivatePort":443,"Type":"tcp"},
		{"IP":"127.0.0.1","PrivatePort":53,"PublicPort":5353,"Type":"udp"}]}`), &item)
	ports := listedPorts(item)
	if len(ports) != 3 {
		t.Fatalf("ports %+v", ports)
	}
	if ports[0].Private != 53 || *ports[0].IP != "127.0.0.1" || ports[0].Type != "udp" {
		t.Errorf("first port %+v", ports[0])
	}
	if ports[1].Private != 80 || *ports[1].Public != 8080 || *ports[1].IP != "0.0.0.0" {
		t.Errorf("second port %+v", ports[1])
	}
	if ports[2].Private != 443 || ports[2].Public != nil || ports[2].IP != nil {
		t.Errorf("third port %+v", ports[2])
	}
}

func TestHealthEntryTrimsOutput(t *testing.T) {
	entry := healthEntry("2026-10-26T09:00:00Z", "2026-10-26T09:00:01.5Z", 1, "\n  "+strings.Repeat("é", 400)+"  \n")
	if entry == nil || entry.Time != 1793005201 || entry.ExitCode != 1 || len([]rune(entry.Output)) != 300 {
		t.Fatalf("entry %+v", entry)
	}
	if healthEntry("0001-01-01T00:00:00Z", "", 0, "x") != nil {
		t.Fatal("entry without time")
	}
}
