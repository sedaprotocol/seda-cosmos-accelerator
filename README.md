# SEDA-cosmos-accelerator

Incredibly simple proxy that caches the result of `abci_queries` for as long as the block height is the same. Also exposes an extra endpoint to check the syncing status of the node that replies with a 200 when it's synced and ready to go.

## Building

To build the standalone binaries please use:

```bash
bun run build
```

and check the `dist/` directory.

You can also take a prebuilt binary from the Github releases.

## Deploying

Once you have the build for the architecture of your node simply drop it on there. Change the service file if required and install it. Point the service you want to connect to the Comet RPC to this service instead (default port 5384).

## Useful Snippets

```bash
mv seda-cosmos-accelerator-linux-x64 seda-cosmos-accelerator
sudo vi /etc/systemd/system/seda-cosmos-accelerator.service
sudo systemctl daemon-reload
sudo systemctl enable --now seda-cosmos-accelerator.service
curl -v localhost:5384/is-synced
```
