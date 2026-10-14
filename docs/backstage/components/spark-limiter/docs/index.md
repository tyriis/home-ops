# spark-limiter

## overview

spark-limiter caps the NVIDIA GPU graphics clock on DGX Spark (GB10) hosts and keeps the cap across
reboots. Lowering the maximum clock reduces power draw, heat, and fan noise, and can keep sustained
workloads steadier. `nvidia-smi -lgc` does not survive a reboot, so a systemd unit re-applies it at boot.

- Upstream: <https://github.com/MiaAI-Lab/sparkLimiter>
- Default clock range: `0,2200` MHz
- Unit name: `spark-gpu-clock-limit.service`

## deployment

The upstream `spark-limiter.sh` script discovers Sparks and writes the unit on each host. This repository does not run that script. The unit below is the manual equivalent, which is what the script installs by default.

Unit file path: `/etc/systemd/system/spark-gpu-clock-limit.service`

```ini
[Unit]
Description=Limit NVIDIA GPU graphics clock (0,2200 MHz)
After=nvidia-persistenced.service
Wants=nvidia-persistenced.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nvidia-smi -lgc 0,2200
ExecStop=/usr/bin/nvidia-smi -rgc
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start it on the Spark:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now spark-gpu-clock-limit.service
```

To change the clock range, edit both `ExecStart` and `Description` (for example `0,1800`).

## verification

```sh
systemctl status spark-gpu-clock-limit
nvidia-smi -q -d CLOCK | grep -i -A4 "Max Clocks"
```

After a reboot the service should show `active (exited)`.

## removal

```sh
sudo systemctl disable --now spark-gpu-clock-limit.service
sudo nvidia-smi -rgc
sudo rm /etc/systemd/system/spark-gpu-clock-limit.service
sudo systemctl daemon-reload
```

## notes

- `systemctl stop` or `restart` of the service resets the clocks briefly (`-rgc`).
- The unit depends on the NVIDIA driver and, if present, `nvidia-persistenced.service`.
