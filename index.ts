import { Elysia } from "elysia";
import { Command, Option } from "@commander-js/extra-typings";
import { version } from "./package.json";
import { Result } from "true-myth";

const program = new Command()
	.description("Cosmos Health proxy")
	.addHelpText("after", "\r")
	.addCommand(
		new Command("version").action(() => {
			console.log(`Cosmos Health proxy v${version}`);
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
			.action(async (opts) => {
				console.log(`Starting Cosmos Health proxy v${version}`);

				const startupCheck = await isServerCatchingUp(opts.server);
				if (startupCheck.isErr) {
					console.error(
						`Startup check failed to connect: ${startupCheck.error}`,
					);
					return;
				}

				const server = new Elysia()
					.get("/node-status", async () => {
						const isCatchingUp = await isServerCatchingUp(opts.server);
						if (isCatchingUp.isErr) {
							return new Response("Failed to retrieve RPC status", {
								status: 502,
							});
						}

						return new Response("", {
							// Not technically a 503 since it's the upstream that's not ready
							status: isCatchingUp.value ? 503 : 200,
						});
					})
					.listen(opts.port);

				console.log(`Listening on port ${opts.port}`);
				console.log(`Proxying to ${opts.server}`);
			}),
	);

program.parse(process.argv);

async function isServerCatchingUp(server: string) {
	try {
		const response = await fetch(`${server}/status`);
		const data = await response.json();
		if (typeof data !== "object") {
			return Result.err(new Error("Invalid response format"));
		}

		if (
			data &&
			"result" in data &&
			typeof data.result === "object" &&
			data.result &&
			"sync_info" in data.result &&
			typeof data.result.sync_info === "object" &&
			data.result.sync_info &&
			"catching_up" in data.result.sync_info &&
			typeof data.result.sync_info.catching_up === "boolean"
		) {
			return Result.ok(data.result.sync_info.catching_up);
		}

		return Result.err(new Error("Invalid response format"));
	} catch (error) {
		return Result.err(error);
	}
}
