import {ConfigAddon, Paths} from "./config";
import {
	parseAnnotations,
	parseEmojiTest,
	parseEmojiVersions,
	parseNamesList,
	parseUnicodeData,
	UnicodeData
} from "./unicode";
import {consolidateUnicodeData, UnicodeDataSource} from "./consolidated";
import {ahkDownloadUnicode, ahkSaveUnicodeData} from "../ahk";
import {IgnoreForName} from "../unicodeInterface";
import {app} from "../appVar";

function getFullName(code: number[], ctx: { unicodeData: UnicodeData }): string {
	const parts: string[] = [];
	for (const c of code) {
		if (IgnoreForName.includes(c)) continue;
		if (c >= 19968 && c <= 40956) {
			parts.push(`CJK UNIFIED IDEOGRAPH-${c.toString(16)}`);
		} else {
			parts.push(ctx.unicodeData[c].name ?? `U+${c.toString(16)}`);
		}
	}
	return parts.join(", ");
}

export function toCodePoints(s: string): number[] {
	return [...s].map(c => c.codePointAt(0)!);
}

type FirstPassEmoji = {
	keywords?: string[];
	symbol: string;
	group: string;
	subGroup: string;
	name: string;
	fullName?: string;
	code?: number[];
	alternates?: FirstPassEmoji[];
	style?: "space" | null;
	show?: string;
}

function getEmoji(addon: ConfigAddon, symbol: string | string[] | null, ctx: { unicodeData: UnicodeData }): FirstPassEmoji {
	let blank = 0;
	if (symbol === null) {
		return {
			symbol: "",
			group: addon.group,
			subGroup: addon.subGroup,
			name: "BLANK " + blank++
		};
	} else if (typeof symbol === "string") {
		const code = toCodePoints(symbol);
		const fullName = getFullName(code, ctx);
		const name = fullName.toLocaleLowerCase().replace(/\b\w/g, l => l.toUpperCase());
		return {
			symbol,
			group: addon.group,
			subGroup: addon.subGroup,
			fullName,
			name,
			code
		};
	} else if (Array.isArray(symbol)) {
		const emoji = getEmoji(addon, symbol[0], ctx);
		emoji.alternates = [];
		for (const sym of symbol) {
			emoji.alternates.push(getEmoji(addon, sym, ctx));
		}
		return emoji;
	} else {
		throw new Error("Unexpected value: " + symbol);
	}
}

let building = false;
export async function makeBuild() {
	if (building) return;
	try {
		app().setBuilding(true);
		building = true;
		await build();
	} catch (e) {
		console.error(e);
		alert(`Build failed: ${e}`)
	} finally {
		app().setBuilding(false);
		building = false;
	}
}

async function build() {
	await ahkDownloadUnicode();
	const paths: Paths = {
		emojiTestPath: '../res/data/emoji/15.0/emoji-test.txt',
		emojiDataPath: '../res/data/15.0.0/ucd/emoji/emoji-data.txt',
		unicodeDataPath: '../res/data/15.0.0/ucd/UnicodeData.txt',
		namesListPath: '../res/data/15.0.0/ucd/NamesList.txt',
		annotationsPath: '../res/data/cldr-json/42.0.0/cldr-json/cldr-annotations-full/annotations/en/annotations.json',
	};

	const ctx: UnicodeDataSource = {
		unicodeData: await parseUnicodeData(paths),
		emojiVersion: await parseEmojiVersions(paths.emojiDataPath),
		emojiTest: await parseEmojiTest(paths),
		namesList: await parseNamesList(paths),
		annotations: await parseAnnotations(paths),
	};

	const u = consolidateUnicodeData(ctx);
	console.log(u);

	ahkSaveUnicodeData(u);

	const emojiCount = u.groups.map(g => g.sub.reduce((v, s) => v + (s.clusters?.length ?? 0), 0)).reduce((a, b) => a + b, 0);
	alert(
		`Finished building “${u.name}”\n` +
		` – ${u.chars.length} codepoints in ${u.blocks.length} blocks\n` +
		` – ${u.clusters.length} grapheme clusters with length > 1\n` +
		` – ${u.groups.length} emoji groups with ${emojiCount} base emojis\n\n` +
		`Reload the app to load the new data file`
	)
}

