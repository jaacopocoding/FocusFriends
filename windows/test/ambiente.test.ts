import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { dataDirectoryOverride, testValue } from "../src/core/environment.ts";

describe("Variabili di prova", () => {
  it("senza FF_SELFTEST non se ne legge nessuna", () => {
    const env = { FF_NO_LOCK: "1", FF_SELFTEST_CONFIRM: "1", FF_SELFTEST_SAVE: "/tmp/x.csv", FF_FAKE_DISPLAYS: "[]" };
    for (const name of Object.keys(env)) assert.equal(testValue(env, name), undefined, name);
  });
  it("con FF_SELFTEST valgono", () => {
    const env = { FF_SELFTEST: "1", FF_NO_LOCK: "1", FF_SELFTEST_CONFIRM: "1" };
    assert.equal(testValue(env, "FF_NO_LOCK"), "1");
    assert.equal(testValue(env, "FF_SELFTEST_CONFIRM"), "1");
    assert.equal(testValue(env, "FF_FAKE_DISPLAYS"), undefined);
  });
  it("FF_SELFTEST vuoto accende comunque le prove (come sempre: conta che ci sia)", () => {
    assert.equal(testValue({ FF_SELFTEST: "", FF_NO_LOCK: "1" }, "FF_NO_LOCK"), "1");
  });
});

describe("Cartella dei dati scelta da fuori", () => {
  it("dai sorgenti (app non installata) vale", () => {
    assert.equal(dataDirectoryOverride({ FF_DATA_DIR: "/prova/dati" }, false), "/prova/dati");
  });
  it("nell'app installata si ignora", () => {
    assert.equal(dataDirectoryOverride({ FF_DATA_DIR: "/prova/dati" }, true), undefined);
  });
  it("nell'app installata vale solo durante le prove", () => {
    assert.equal(dataDirectoryOverride({ FF_DATA_DIR: "/prova/dati", FF_SELFTEST: "1" }, true), "/prova/dati");
  });
  it("vuota o assente: nessuna scelta", () => {
    assert.equal(dataDirectoryOverride({}, false), undefined);
    assert.equal(dataDirectoryOverride({ FF_DATA_DIR: "" }, false), undefined);
  });
});
