import { Command, Option } from "@commander-js/extra-typings";
import { isLogLevel, logger } from "@seda-protocol/cosmos-accelerator-logger";
import { createServer } from "@seda-protocol/cosmos-accelerator-server";
import { version } from "../package.json";

const program = new Command()
	.description("SEDA Cosmos Accelerator")
	.addCommand(
		new Command("version")
			.description("Print the version of the CLI and server")
			.action(() => {
				logger.info(`SEDA Cosmos Accelerator v${version}`);
			}),
	)
	.addCommand(
		new Command("start")
			.addOption(
				new Option("-p, --port <port>", "Port to listen on")
					.default("5384")
					.env("SERVER_PORT"),
			)
			.addOption(
				new Option("-s, --server <server>", "Server to proxy to")
					.default("localhost:26657")
					.env("RPC_SERVER"),
			)
			.addOption(
				new Option(
					"-i, --height-check-interval <heightCheckInterval>",
					"Interval to check the height of the server in milliseconds",
				).default("1000"),
			)
			.addOption(
				new Option("-l, --log-level <logLevel>", "Log level to use").default(
					"info",
				),
			)
			.action(async (opts) => {
				if (!isLogLevel(opts.logLevel)) {
					logger.error(`Invalid log level: ${opts.logLevel}`);
					process.exit(1);
				}
				logger.level = opts.logLevel;

				const port = Number(opts.port);
				if (Number.isNaN(port)) {
					logger.error(`Invalid port: ${opts.port}`);
					process.exit(1);
				}

				const heightCheckIntervalMs = Number(opts.heightCheckInterval);
				if (Number.isNaN(heightCheckIntervalMs)) {
					logger.error(
						`Invalid height check interval: ${opts.heightCheckInterval}`,
					);
					process.exit(1);
				}

				logger.info(`SEDA Cosmos Accelerator v${version}`);

				const server = await createServer({
					server: opts.server,
					port,
					heightCheckIntervalMs,
				});

				server.match({
					Err: (e) => {
						logger.error(`Failed to start server: ${e}`);
						process.exit(1);
					},
					Ok: () => {},
				});
			}),
	);

program.parse(process.argv);
