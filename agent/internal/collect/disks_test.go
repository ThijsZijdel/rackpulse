package collect

import (
	"reflect"
	"testing"
)

func TestParseMountinfoUsesSuperblockReadOnly(t *testing.T) {
	data := `22 1 8:1 / / rw,relatime shared:1 - ext4 /dev/sda1 rw,errors=remount-ro
23 22 0:5 / /dev rw,nosuid shared:2 - devtmpfs udev rw,size=4000k
24 22 8:1 /var/lib/docker /var/lib/docker rw,relatime shared:1 - ext4 /dev/sda1 rw
25 22 8:15 / /boot/efi rw,relatime shared:3 - vfat /dev/sda15 rw
26 22 7:0 / /snap/core/1 ro,nodev,relatime shared:4 - squashfs /dev/loop0 ro
27 22 0:40 / /tmp rw shared:5 - tmpfs tmpfs rw
28 22 8:16 / /mnt/HC_Volume\0401 ro,relatime shared:6 - xfs /dev/sdb rw
29 22 0:41 / /var/lib/docker/overlay2/x/merged rw - overlay overlay rw,lowerdir=/a
30 22 0:42 / /data rw,relatime shared:7 master:1 - btrfs /dev/vdb1 rw,subvol=/data
31 22 0:42 / /data2/sub rw,relatime shared:8 - btrfs /dev/vdb1 rw,subvol=/
32 22 8:32 / /srv ro,nosuid,nodev,relatime shared:9 - ext4 /dev/sdc1 rw,errors=remount-ro
33 22 8:48 / /broken rw,relatime shared:10 - ext4 /dev/sdd1 ro,errors=remount-ro
34 22 7:1 / /mnt/image ro,relatime shared:11 - ext4 /dev/loop1 ro
`
	got := parseMountinfo(data)
	want := []mountEntry{
		{Mount: "/", Device: "/dev/sda1", FS: "ext4"},
		{Mount: "/boot/efi", Device: "/dev/sda15", FS: "vfat"},
		{Mount: "/broken", Device: "/dev/sdd1", FS: "ext4", ReadOnly: true},
		{Mount: "/data", Device: "/dev/vdb1", FS: "btrfs"},
		{Mount: "/mnt/HC_Volume 1", Device: "/dev/sdb", FS: "xfs"},
		{Mount: "/mnt/image", Device: "/dev/loop1", FS: "ext4", ReadOnly: true},
		{Mount: "/srv", Device: "/dev/sdc1", FS: "ext4"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v\nwant %+v", got, want)
	}
}
