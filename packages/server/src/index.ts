import { randomUUID } from "node:crypto";
import { logger } from "@seda-protocol/cosmos-accelerator-logger";
import { tryAsync } from "@seda-protocol/utils";
import { Elysia } from "elysia";
import { Result } from "true-myth";
import { version } from "../package.json";
import { isServerCatchingUp } from "./queries/is-server-catching-up";
import { isJSONRpcResponse, SimpleHeightCache } from "./simple-height-cache";

interface ServerOpts {
	heightCheckIntervalMs: number;
	port: number;
	server: string;
}

const serverLogger = logger.child({
	id: "server",
});

export { version };

export async function createServer(opts: ServerOpts) {
	serverLogger.info(`Starting server v${version}`);

	const startupCheck = await isServerCatchingUp(opts.server);
	if (startupCheck.isErr) {
		return Result.err(startupCheck.error);
	}

	const heightCache = new SimpleHeightCache(
		opts.server,
		opts.heightCheckIntervalMs,
	);

	heightCache.start();

	// TODO: Put this in a separate folder/functions
	const server = new Elysia()
		.derive(() => {
			return {
				requestId: randomUUID(),
			};
		})
		.get("/is-synced", async (ctx) => {
			const requestLogger = logger.child({
				id: `is-synced-${ctx.requestId}`,
			});
			requestLogger.debug("Handling request");

			requestLogger.silly("Checking if server is synced");
			const isCatchingUpResult = await isServerCatchingUp(opts.server);
			requestLogger.silly("Server synced check complete");

			return isCatchingUpResult.match({
				Err: (e) => {
					requestLogger.error(`Failed to retrieve RPC status: ${e}`);

					return new Response("Failed to retrieve RPC status", {
						status: 502,
					});
				},
				Ok: (isCatchingUp) => {
					requestLogger.debug("Returning response");

					return new Response("", {
						// Not technically a 503 since it's the upstream that's not ready
						status: isCatchingUp ? 503 : 200,
					});
				},
			});
		})
		.all(
			"/*",
			async (ctx) => {
				const requestLogger = logger.child({
					id: `proxy-request-${ctx.requestId}`,
				});
				requestLogger.debug("Handling request");

				const url = new URL(`${opts.server}/${ctx.params["*"]}`);
				// Preserve original query parameters
				Object.entries(ctx.query).forEach(([key, value]) => {
					url.searchParams.set(key, value);
				});

				requestLogger.silly(`URL: ${url.toString()}`);

				const headers = new Headers(ctx.request.headers);
				headers.delete("host");

				requestLogger.silly(`Headers: ${JSON.stringify(headers)}`);

				if (typeof ctx.body !== "string") {
					requestLogger.warn("Body is not a string, skipping cache");

					return fetch(url, {
						method: ctx.request.method,
						// @ts-expect-error - ctx.body is unknown
						body: ctx.body,
						headers,
					});
				}

				if (!ctx.body.includes(`"method":"abci_query"`)) {
					requestLogger.debug("Not an ABCI query, skipping cache");

					return fetch(url, {
						method: ctx.request.method,
						body: ctx.body,
						headers,
					});
				}

				const query = JSON.parse(ctx.body);

				if (query?.params === undefined || query?.id === undefined) {
					requestLogger.warn("Query params or id is undefined, skipping cache");

					return fetch(url, {
						method: ctx.request.method,
						body: ctx.body,
						headers,
					});
				}

				const paramsString = JSON.stringify(query.params);
				requestLogger.silly(`Params string: ${paramsString}`);

				const cachedResponse = heightCache.get(paramsString);

				if (cachedResponse.isJust) {
					requestLogger.debug("Cache hit");

					// Replace the cached id with the request id
					const response = { ...cachedResponse.value, id: query.id };
					const resBody = JSON.stringify(response);

					requestLogger.debug("Returning cached response with id replaced");
					return new Response(resBody, {
						status: 200,
					});
				}

				requestLogger.debug("Cache miss, fetching from RPC");

				const res = await fetch(url, {
					method: ctx.request.method,
					body: ctx.body,
					headers,
				});

				requestLogger.silly("Fetching from RPC complete");

				if (!res.ok) {
					requestLogger.error(
						`Fetch from RPC failed, returning error response: ${res.status}`,
					);

					return res;
				}

				requestLogger.silly("Parsing response body");
				const resBodyResult = await tryAsync(res.clone().json());
				if (resBodyResult.isErr) {
					requestLogger.error(
						`Failed to parse response body: ${resBodyResult.error}, returning response`,
					);
					return res;
				}
				requestLogger.silly("Response body parsed");

				const body = resBodyResult.value;
				requestLogger.silly(`Body: ${JSON.stringify(body)}`);
				if (!isJSONRpcResponse(body)) {
					requestLogger.error(
						"Response body is not a JSON-RPC response, skipping cache",
					);
					return res;
				}

				requestLogger.silly("Setting cache");
				heightCache.set(paramsString, body);

				requestLogger.debug("Returning response");

				return res;
			},
			{
				parse: "text",
			},
		)
		.listen(opts.port);

	serverLogger.info(`Server listening on port ${opts.port}`);
	serverLogger.info(`Proxying to ${opts.server}`);

	return Result.ok(server);
}
