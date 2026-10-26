package collect

import (
	"context"
	"time"
)

type dfImage struct {
	Size       int64 `json:"Size"`
	SharedSize int64 `json:"SharedSize"`
	Containers int64 `json:"Containers"`
}

type dfContainer struct {
	SizeRw int64 `json:"SizeRw"`
}

type dfVolume struct {
	Name      string `json:"Name"`
	UsageData *struct {
		Size     int64 `json:"Size"`
		RefCount int64 `json:"RefCount"`
	} `json:"UsageData"`
}

type dfBuildCache struct {
	Size   int64 `json:"Size"`
	InUse  bool  `json:"InUse"`
	Shared bool  `json:"Shared"`
}

type diskUsage struct {
	LayersSize int64          `json:"LayersSize"`
	Images     []dfImage      `json:"Images"`
	Containers []dfContainer  `json:"Containers"`
	Volumes    []dfVolume     `json:"Volumes"`
	BuildCache []dfBuildCache `json:"BuildCache"`
	ImageUsage *struct {
		TotalSize int64     `json:"TotalSize"`
		Items     []dfImage `json:"Items"`
	} `json:"ImageUsage"`
	ContainerUsage *struct {
		Items []dfContainer `json:"Items"`
	} `json:"ContainerUsage"`
	VolumeUsage *struct {
		Items []dfVolume `json:"Items"`
	} `json:"VolumeUsage"`
	BuildCacheUsage *struct {
		Items []dfBuildCache `json:"Items"`
	} `json:"BuildCacheUsage"`
}

func (u *diskUsage) useNewFormat() {
	if u.ImageUsage != nil {
		u.LayersSize = u.ImageUsage.TotalSize
		u.Images = u.ImageUsage.Items
	}
	if u.ContainerUsage != nil {
		u.Containers = u.ContainerUsage.Items
	}
	if u.VolumeUsage != nil {
		u.Volumes = u.VolumeUsage.Items
	}
	if u.BuildCacheUsage != nil {
		u.BuildCache = u.BuildCacheUsage.Items
	}
}

func summarizeDisk(usage diskUsage) (*DockerDisk, []Volume) {
	disk := &DockerDisk{Images: usage.LayersSize}
	for _, image := range usage.Images {
		if image.Containers == 0 && image.Size > 0 {
			disk.ImagesReclaimable += image.Size - max(image.SharedSize, 0)
		}
	}
	for _, container := range usage.Containers {
		disk.Containers += max(container.SizeRw, 0)
	}
	for _, record := range usage.BuildCache {
		if record.Shared {
			continue
		}
		disk.BuildCache += record.Size
		if !record.InUse {
			disk.BuildCacheReclaimable += record.Size
		}
	}
	volumes := make([]Volume, 0, len(usage.Volumes))
	for _, item := range usage.Volumes {
		volume := Volume{Name: item.Name, Size: -1}
		if item.UsageData != nil {
			volume.Size = item.UsageData.Size
			volume.Containers = int(max(item.UsageData.RefCount, 0))
		}
		if volume.Size > 0 {
			disk.Volumes += volume.Size
			if volume.Containers == 0 {
				disk.VolumesReclaimable += volume.Size
			}
		}
		volumes = append(volumes, volume)
	}
	return disk, volumes
}

func (d *dockerCollector) refreshDisk(ctx context.Context) error {
	if !dockerInstalled() {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	var usage diskUsage
	if err := d.get(ctx, "/system/df", &usage); err != nil {
		return err
	}
	if usage.Images == nil && usage.ImageUsage != nil {
		usage = diskUsage{}
		if err := d.get(ctx, "/system/df?verbose=1", &usage); err != nil {
			return err
		}
		usage.useNewFormat()
	}
	disk, volumes := summarizeDisk(usage)
	now := time.Now().Unix()
	d.volumesMu.Lock()
	d.disk = disk
	d.volumes = volumes
	d.volumesTime = &now
	d.volumesMu.Unlock()
	return nil
}
