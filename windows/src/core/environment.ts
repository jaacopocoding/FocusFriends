// Le variabili d'ambiente di prova (FF_…). In uso normale l'app non ne legge nessuna: valgono solo se c'è `FF_SELFTEST`,
// l'interruttore delle prove automatiche. Così una variabile rimasta nell'ambiente non cambia il comportamento dell'app
// (per esempio saltando la conferma di «Cancella tutto…»).

export type Env = Readonly<Record<string, string | undefined>>;

/** Il valore di una variabile di prova: `undefined` se le prove non sono accese. */
export function testValue(env: Env, name: string): string | undefined {
  return env["FF_SELFTEST"] !== undefined ? env[name] : undefined;
}

/**
 * La cartella dei dati scelta da fuori (`FF_DATA_DIR`): vale quando si lavora dai sorgenti (`npm start`) o durante le prove,
 * mai nell'app installata, che usa sempre `%APPDATA%\FocusFriends`.
 */
export function dataDirectoryOverride(env: Env, packaged: boolean): string | undefined {
  const value = env["FF_DATA_DIR"];
  if (!value) return undefined;
  return packaged && env["FF_SELFTEST"] === undefined ? undefined : value;
}
