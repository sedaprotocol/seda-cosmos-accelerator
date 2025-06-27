import { logger as loggerBase } from "@seda-protocol/cosmos-accelerator-logger";
import { Maybe } from "true-myth";
import * as v from "valibot";
import { getCurrentHeight } from "./queries/get-current-height";

const logger = loggerBase.child({
	id: "height-check",
});

const jsonRpcSchema = v.object({
	jsonrpc: v.string(),
	id: v.number(),
	result: v.unknown(),
});

type JSONRpcResponse = v.InferOutput<typeof jsonRpcSchema>;

export function isJSONRpcResponse(value: unknown): value is JSONRpcResponse {
	return v.safeParse(jsonRpcSchema, value).success;
}

export class SimpleHeightCache {
	private cache = new Map<string, JSONRpcResponse>();
	private currentHeight: Maybe<bigint> = Maybe.nothing();
	private isFetchingHeight = false;
	private interval: Maybe<NodeJS.Timeout> = Maybe.nothing();

	constructor(
		private readonly server: string,
		private readonly heightCheckIntervalMs: number,
	) {}

	start() {
		logger.info("Starting height check");

		this.interval = Maybe.of(
			setInterval(this.checkHeight.bind(this), this.heightCheckIntervalMs),
		);
	}

	stop() {
		logger.info("Stopping height check");

		this.interval.match({
			Nothing: () => {
				logger.silly("Height check is not running, skipping stop");
			},
			Just: (interval) => {
				logger.silly("Clearing interval");
				clearInterval(interval);
				this.interval = Maybe.nothing();
			},
		});
	}

	get(key: string): Maybe<JSONRpcResponse> {
		logger.silly("Getting cache", { key });

		if (this.currentHeight.isNothing) {
			logger.warn("Current height is nothing, skipping cache get");
			return Maybe.nothing();
		}

		const result = Maybe.of(this.cache.get(key));
		result.match({
			Nothing: () => {
				logger.silly("Cache miss", { key });
			},
			Just: () => {
				logger.silly("Cache hit", { key });
			},
		});

		return result;
	}

	set(key: string, value: JSONRpcResponse) {
		logger.silly("Updating cache", { key });

		if (this.currentHeight.isNothing) {
			logger.warn("Current height is nothing, skipping cache update");
			return;
		}

		this.cache.set(key, value);

		logger.silly("Cache updated", { key });
	}

	private async checkHeight() {
		if (this.isFetchingHeight) {
			logger.silly("Skipping height check, already fetching");
			return;
		}
		logger.silly("Checking height");

		this.isFetchingHeight = true;

		logger.silly("Fetching height from server");
		const height = await getCurrentHeight(this.server);
		logger.silly("Height fetched from server");

		height.match({
			Err: (e) => {
				logger.error(
					`Failed to retrieve current height, resetting height and cache: ${e}`,
				);
				this.updateCurrentHeight(Maybe.nothing());
			},
			Ok: (h) => {
				this.updateCurrentHeight(Maybe.just(h));
			},
		});

		this.isFetchingHeight = false;
		logger.silly("Height check complete");
	}

	private updateCurrentHeight(height: Maybe<bigint>) {
		if (height.isNothing) {
			logger.warn("New height is nothing, resetting current height and cache");
			this.currentHeight = Maybe.nothing();
			this.cache.clear();
			return;
		}

		if (this.currentHeight.isNothing) {
			logger.info(`Current height is nothing, updating to ${height.value}`);
			this.currentHeight = height;
			return;
		}

		if (height.value <= this.currentHeight.value) {
			logger.silly(
				"Height is less than or equal to current height, skipping update",
			);
			return;
		}

		logger.info(
			`Updating current height to ${height.value} and clearing cache`,
		);
		this.cache.clear();
		this.currentHeight = height;
	}
}
