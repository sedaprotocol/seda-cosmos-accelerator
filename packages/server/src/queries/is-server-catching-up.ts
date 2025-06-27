import { tryParseSync } from "@seda-protocol/utils";
import { Result } from "true-myth";
import * as v from "valibot";

const statusSchema = v.object({
	result: v.object({
		sync_info: v.object({
			catching_up: v.boolean(),
		}),
	}),
});

export async function isServerCatchingUp(
	server: string,
): Promise<Result<boolean, Error>> {
	try {
		const response = await fetch(`${server}/status`);
		if (!response.ok) {
			return Result.err(
				new Error(`Failed to fetch status: ${response.status}`, {
					cause: response,
				}),
			);
		}

		const data = await response.json();

		const result = tryParseSync(statusSchema, data);

		return result
			.map((t) => t.result.sync_info.catching_up)
			.mapErr((e) => {
				const flattened = e
					.map((err) => {
						const key = err.path?.reduce((path, segment) => {
							return path.concat(".", segment.key as string);
						}, "");
						return `${key}: ${err.message}`;
					})
					.join("\n");

				return new Error(`Failed to parse status response: ${flattened}`, {
					cause: e,
				});
			});
	} catch (error) {
		if (error instanceof Error) {
			return Result.err(error);
		}

		return Result.err(new Error(`Unknown error: ${error}`, { cause: error }));
	}
}
