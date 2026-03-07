const POWER_COLORS = ["Purple", "Gold", "Teal", "Crimson", "Sapphire", "Emerald", "Amber", "Silver"];

export interface DeterministicExtras {
  fortuneScore: number;
  luckyNumbers: number[];
  powerColors: string[];
}

export function buildDeterministicExtras(
  userId: string,
  zodiacSign: string,
  readingDate: string
): DeterministicExtras {
  const seedKey = `${canonicalizeUserId(userId)}|${canonicalizeZodiacSign(zodiacSign)}|${readingDate}`;
  let state = fnv1a32(seedKey);

  const randomInt = (min: number, max: number) => {
    state = (Math.imul(1664525, state) + 1013904223) >>> 0;
    return min + (state % (max - min + 1));
  };

  const fortuneScore = randomInt(60, 95);

  const luckySet = new Set<number>();
  while (luckySet.size < 5) {
    luckySet.add(randomInt(1, 99));
  }
  const luckyNumbers = Array.from(luckySet).sort((a, b) => a - b);

  const remainingColors = [...POWER_COLORS];
  const powerColors: string[] = [];
  while (powerColors.length < 3 && remainingColors.length > 0) {
    const index = randomInt(0, remainingColors.length - 1);
    const [selected] = remainingColors.splice(index, 1);
    powerColors.push(selected);
  }

  return { fortuneScore, luckyNumbers, powerColors };
}

function canonicalizeUserId(value: string): string {
  return value.trim().toUpperCase();
}

function canonicalizeZodiacSign(value: string): string {
  return value.trim().toLowerCase();
}

function fnv1a32(input: string): number {
  let hash = 0x811c9dc5;
  const bytes = new TextEncoder().encode(input);

  for (const byte of bytes) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }

  return hash >>> 0;
}
