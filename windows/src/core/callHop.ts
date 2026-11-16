// Il compagno che chiama («Cliccami!!!», all'inizio del giro guidato): fermo per metà del giro, poi si carica schiacciandosi, salta
// allungandosi, atterra schiacciato e fa un secondo saltino più piccolo. L'ombra resta a terra. Le stesse curve sul Mac (PetWindow.swift).
// Solo numeri: si prova da sola.

/** Quanto dura un giro, in secondi. */
export const CALL_CYCLE = 1.8;

export interface CallPose {
  /** Quanto è sollevato, in punti. */
  lift: number;
  /** La larghezza e l'altezza rispetto al normale (attorno ai piedi). */
  scaleX: number;
  scaleY: number;
}

/** I due salti: dove cominciano e finiscono nel giro (da 0 a 1) e quanto sono alti. */
const HOPS: ReadonlyArray<{ from: number; to: number; height: number }> = [
  { from: 0.58, to: 0.77, height: 18 },
  { from: 0.83, to: 0.95, height: 7 },
];

/** La forma (larghezza, altezza) nei momenti chiave; in mezzo si passa con dolcezza. */
const SHAPES: ReadonlyArray<[at: number, scaleX: number, scaleY: number]> = [
  [0, 1, 1],
  [0.5, 1, 1],
  [0.58, 1.08, 0.9],    // si carica
  [0.62, 0.95, 1.07],   // parte allungato
  [0.68, 1, 1],         // in cima
  [0.74, 0.96, 1.05],   // scende
  [0.77, 1.08, 0.9],    // atterra
  [0.81, 1.03, 0.96],   // si ricarica, meno
  [0.85, 0.98, 1.03],
  [0.89, 1, 1],
  [0.93, 0.98, 1.02],
  [0.95, 1.04, 0.95],   // atterra di nuovo
  [1, 1, 1],
];

const smooth = (t: number): number => (1 - Math.cos(Math.PI * t)) / 2;

/** La posa dopo `seconds` da quando ha cominciato a chiamare. */
export function callPose(seconds: number): CallPose {
  const phase = ((seconds % CALL_CYCLE) + CALL_CYCLE) % CALL_CYCLE / CALL_CYCLE;
  let lift = 0;
  for (const hop of HOPS) {
    if (phase > hop.from && phase < hop.to) {
      const u = (phase - hop.from) / (hop.to - hop.from);
      lift = 4 * hop.height * u * (1 - u);      // una parabola, come un salto vero
    }
  }
  let scaleX = 1, scaleY = 1;
  for (let i = 1; i < SHAPES.length; i++) {
    const [at, sx, sy] = SHAPES[i]!;
    const [before, bx, by] = SHAPES[i - 1]!;
    if (phase <= at) {
      const k = smooth((phase - before) / (at - before));
      scaleX = bx + (sx - bx) * k;
      scaleY = by + (sy - by) * k;
      break;
    }
  }
  return { lift, scaleX, scaleY };
}
