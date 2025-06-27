import { Maybe } from "true-myth";
import { createLogger, format, transports } from "winston";
import "winston-daily-rotate-file";

const logFormat = (withColors: boolean) =>
	format.printf((info) => {
		// @ts-ignore
		const id = Maybe.of(info.metadata?.id).mapOr("", (t) => {
			return withColors ? `[${cyan(t)}] ` : `[${t}] `;
		});
		const logMsg = `${info.timestamp} ${info.level}: ${id}`;

		// @ts-ignore
		return Maybe.of(info.metadata?.error).mapOr(
			`${logMsg}${info.message}`,
			(err) => `${logMsg} ${info.message} ${err}`,
		);
	});

export type LogLevel = "silly" | "debug" | "info" | "warn" | "error";
export function isLogLevel(logLevel: string): logLevel is LogLevel {
	return ["silly", "debug", "info", "warn", "error"].includes(logLevel);
}

function cyan(val: string) {
	return `\x1b[36m${val}\x1b[0m`;
}

const consoleTransport = new transports.Console({
	format: format.combine(format.colorize(), logFormat(true)),
});

export const logger = createLogger({
	transports: consoleTransport,
	format: format.combine(
		format.timestamp({ format: "YYYY-MM-DD HH:mm:ss.SSS" }),
		format.metadata({
			fillExcept: ["message", "level", "timestamp", "label"],
		}),
		format.errors({ stack: true }),
	),
});
