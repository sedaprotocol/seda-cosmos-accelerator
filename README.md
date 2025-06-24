# cosmos-health-proxy

Incredibly simple health proxy that simply checks if the node is reachable and whether it is catching up.

To build the standalone binaries please use:

```bash
bun run build
```

Then you take the build for the architecture of your node and simply drop it on there. Then change and install the service file, and point your health check to the port exposed (default 5384).

## Useful Snippets

```bash
mv cosmos-health-proxy-linux-x64 cosmos-health-proxy
sudo vi /etc/systemd/system/cosmos-health-proxy.service
sudo systemctl daemon-reload
sudo systemctl enable --now cosmos-health-proxy.service
curl -v localhost:5384/node-status
```
