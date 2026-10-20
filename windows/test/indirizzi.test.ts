import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { describeUrl, isAppUrl } from "../src/core/urls.ts";

describe("Indirizzi consentiti", () => {
  it("le pagine dell'app sì", () => {
    for (const url of ["ff://app/index.html", "ff://app/stats.html", "ff://app/", "ff://app/index.html?x=1#y"]) assert.equal(isAppUrl(url), true, url);
  });
  it("il resto no", () => {
    for (const url of [
      "https://example.com", "http://app/", "file:///C:/Windows/win.ini", "about:blank", "data:text/html,<p>x</p>",
      "javascript:alert(1)", "ff://altro/index.html", "ff://app.example.com/", "ftp://app/", "", "non è un indirizzo",
    ]) assert.equal(isAppUrl(url), false, url);
  });
});

describe("Indirizzi nel registro", () => {
  it("si scrivono solo schema e sito, mai percorso e parametri", () => {
    assert.equal(describeUrl("https://example.com/percorso/segreto?token=abc#x"), "https://example.com");
  });
  it("gli schemi senza sito mostrano solo lo schema", () => {
    assert.equal(describeUrl("data:text/html,<p>x</p>"), "data:…");
    assert.equal(describeUrl("javascript:alert(1)"), "javascript:…");
  });
  it("un testo qualsiasi non fa cadere niente", () => {
    assert.equal(describeUrl("non è un indirizzo"), "indirizzo non valido");
    assert.equal(describeUrl(""), "indirizzo non valido");
  });
});
