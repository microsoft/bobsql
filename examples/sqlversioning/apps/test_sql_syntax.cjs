"use strict";

const assert = require("node:assert/strict");
const { readFileSync, readdirSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const { runInNewContext } = require("node:vm");

class Element {
  constructor(tagName) { this.tagName = tagName; this.children = []; this.className = ""; }
  append(...nodes) { this.children.push(...nodes); }
  set textContent(value) { this.children = [{ textContent: value }]; }
  get textContent() { return this.children.map(node => node.textContent).join(""); }
  set innerHTML(_value) { throw new Error("SQL must never be rendered as HTML."); }
}

const context = {
  document: {
    createElement: tag => new Element(tag),
    createTextNode: text => ({ textContent: text })
  }
};
runInNewContext(readFileSync(path.join(__dirname, "static", "sql-syntax.js"), "utf8"), context);
const { render } = context.SqlSyntax;
const spans = pre => pre.children.filter(node => node.tagName === "span")
  .map(node => [node.className, node.textContent]);

test("colours SQL while preserving whitespace, case and source exactly", () => {
  const source = "select\t@balance + 100.00, N'Bob''s account' AS Name; -- Read it\r\n";
  const pre = render(source, "step-sql");
  assert.equal(pre.textContent, source);
  assert.equal(pre.className, "step-sql sql-source");
  assert.deepEqual(spans(pre), [
    ["sql-keyword", "select"], ["sql-variable", "@balance"], ["sql-number", "100.00"],
    ["sql-string", "N'Bob''s account'"], ["sql-keyword", "AS"], ["sql-comment", "-- Read it"]
  ]);
});

test("does not highlight keywords inside strings or escaped identifiers", () => {
  const source = "SELECT [SELECT]]FROM], \"UPDATE\"\"DELETE\", 'COMMIT -- no', #table FROM dbo.Accounts;";
  const pre = render(source);
  assert.equal(pre.textContent, source);
  assert.deepEqual(spans(pre), [
    ["sql-keyword", "SELECT"], ["sql-string", "'COMMIT -- no'"], ["sql-keyword", "FROM"]
  ]);
});

test("handles SQL Server nested block comments", () => {
  const source = "/* SELECT /* 'nested' */ UPDATE */ SELECT 1;";
  const pre = render(source);
  assert.equal(pre.textContent, source);
  assert.deepEqual(spans(pre), [
    ["sql-comment", "/* SELECT /* 'nested' */ UPDATE */"],
    ["sql-keyword", "SELECT"], ["sql-number", "1"]
  ]);
});

test("colours functions, system variables, hex and scientific numbers", () => {
  const source = "SELECT COUNT(*), @@TRANCOUNT, 0xA1, .5, 1e-3;";
  assert.deepEqual(spans(render(source)), [
    ["sql-keyword", "SELECT"], ["sql-function", "COUNT"], ["sql-variable", "@@TRANCOUNT"],
    ["sql-number", "0xA1"], ["sql-number", ".5"], ["sql-number", "1e-3"]
  ]);
});

test("preserves incomplete tokens and Unicode without dropping text", () => {
  for (const source of ["", "/* nested /* still open", "SELECT N'unclosed",
    "SELECT [unfinished", 'SELECT "unfinished', "SELECT N'\u00e9\u03b1';\n"]) {
    assert.equal(render(source).textContent, source);
    assert.equal(render(source).textContent, source);
  }
});

test("renders markup as text, never HTML", () => {
  const source = "SELECT N'<img src=x onerror=alert(1)>'; <script>alert('x')</script>";
  const pre = render(source);
  assert.equal(pre.textContent, source);
  assert.ok(pre.children.every(node => !node.tagName || node.tagName === "span"));
  assert.throws(() => render(null), /SQL source must be a string/);
});

test("preserves every original lab SQL file", () => {
  const root = path.dirname(__dirname);
  let count = 0;
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory() || !/^demo[0-4]-/.test(entry.name)) continue;
    const folder = path.join(root, entry.name);
    for (const name of readdirSync(folder).filter(name => name.endsWith(".sql"))) {
      const source = readFileSync(path.join(folder, name), "utf8");
      assert.equal(render(source).textContent, source, name);
      count++;
    }
  }
  assert.equal(count, 25);
});

test("syntax colours meet 4.5:1 contrast on the SQL pane", () => {
  const luminance = hex => {
    const rgb = hex.slice(1).match(/../g).map(channel => {
      const value = parseInt(channel, 16) / 255;
      return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
    });
    return rgb[0] * .2126 + rgb[1] * .7152 + rgb[2] * .0722;
  };
  const css = readFileSync(path.join(__dirname, "static", "sql-syntax.css"), "utf8");
  const background = luminance("#dfe4e8");
  for (const [, colour] of css.matchAll(/\bcolor:\s*(#[\da-f]{6})/gi)) {
    assert.ok((background + .05) / (luminance(colour) + .05) >= 4.5, colour);
  }
});
