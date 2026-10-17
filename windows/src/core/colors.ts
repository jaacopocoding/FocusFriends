// I colori delle materie: uno per ognuna, sempre lo stesso per lo stesso nome (Paper.subjectColors in PaperUI.swift).

/** terracotta, salvia, senape, verde acqua, prugna, rosa antico, azzurro polvere, lavanda. */
export const SUBJECT_COLORS: ReadonlyArray<readonly [number, number, number]> = [
  [217, 120, 56], [112, 158, 102], [219, 171, 56], [71, 140, 148], [158, 97, 140], [204, 115, 128], [92, 120, 179], [140, 128, 199],
];

/**
 * Quale dei colori tocca a questa materia. Una somma semplice e stabile (Swift cambia l'hash delle stringhe a ogni avvio): lo
 * stesso calcolo dell'app per Mac, con i numeri a 64 bit che «girano» come i suoi, così una materia ha lo stesso colore.
 */
export function subjectColorIndex(subject: string): number {
  let sum = 5381n;
  for (const character of subject.toLowerCase()) sum = BigInt.asIntN(64, sum * 33n + BigInt(character.codePointAt(0) ?? 0));
  const absolute = sum < 0n ? -sum : sum;
  return Number(absolute % BigInt(SUBJECT_COLORS.length));
}

export function subjectColor(subject: string): string {
  const [r, g, b] = SUBJECT_COLORS[subjectColorIndex(subject)]!;
  return `rgb(${r}, ${g}, ${b})`;
}
