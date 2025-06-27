import { tryParseSync } from "@seda-protocol/utils";
import { Result } from "true-myth";
import * as v from "valibot";

const blockchainSchema = v.object({
	result: v.object({
		last_height: v.pipe(
			v.string(),
			v.transform((s) => BigInt(s)),
		),
	}),
});

export async function getCurrentHeight(
	server: string,
): Promise<Result<bigint, Error>> {
	try {
		const response = await fetch(`${server}/blockchain`);
		const data = await response.json();

		const result = tryParseSync(blockchainSchema, data);

		return result
			.map((t) => t.result.last_height)
			.mapErr((e) => {
				const flattened = e
					.map((err) => {
						const key = err.path?.reduce((path, segment) => {
							return path.concat(".", segment.key as string);
						}, "");
						return `${key}: ${err.message}`;
					})
					.join("\n");

				return new Error(`Failed to parse blockchain response: ${flattened}`, {
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
