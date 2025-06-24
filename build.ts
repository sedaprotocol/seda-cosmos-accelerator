import { resolve } from "node:path";
import { readableStreamToText } from "bun";

const PLATFORM_TARGETS = ["bun-linux-x64", "bun-linux-arm64"];

const BINARY_NAME = "cosmos-health-proxy";
const BUILD_FOLDER = resolve(import.meta.dir, "./dist/");
const SRC_TARGET = [resolve(process.cwd(), "./index.ts")];

await Promise.all(
	PLATFORM_TARGETS.map(async (target) => {
		const rawTarget = target.replace("bun-", "");
		console.log(`Compiling for ${rawTarget}..`);

		// Don't fail if the folder doesn't exist
		await Bun.$`rm -rf ${BUILD_FOLDER} || true`;

		const cmd = [
			"bun",
			"build",
			"--compile",
			"--minify",
			`--target=${target}`,
			...SRC_TARGET,
			"--outfile",
			`${BUILD_FOLDER}/${BINARY_NAME}-${rawTarget}`,
		];

		const result = Bun.spawn(cmd, {
			stdout: "pipe",
			stderr: "pipe",
		});
		const exitCode = await result.exited;

		if (exitCode !== 0) {
			console.log(
				`Compilation failed for ${rawTarget}: ${await readableStreamToText(result.stderr)} \n ${await readableStreamToText(result.stdout)}`,
			);
		} else {
			console.log(`Compiled ${rawTarget}`);
		}
	}),
);
