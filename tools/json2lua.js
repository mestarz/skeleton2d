#!/usr/bin/env node
/*
 json2lua.js — 把 skeleton.json / animations.json 转成 .lua

 复用 editor/lua-export.js 的序列化器（它原本依赖浏览器 window）。
 这里桩一个 window 对象后 require 进来。

 用法:
   node tools/json2lua.js <input.json> <output.lua> [--kind skeleton|animations]
*/
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('usage: node tools/json2lua.js <input.json> <output.lua> [--kind skeleton|animations]');
  process.exit(2);
}

const input  = args[0];
const output = args[1];
let kind = 'skeleton';
const ki = args.indexOf('--kind');
if (ki >= 0 && args[ki + 1]) kind = args[ki + 1];

const win = {};
global.window = win;
require(path.resolve(__dirname, '..', 'editor', 'lua-export.js'));
const LuaExport = win.LuaExport;
if (!LuaExport) { console.error('failed to load LuaExport'); process.exit(1); }

const json = JSON.parse(fs.readFileSync(input, 'utf-8'));
const fn = kind === 'animations' ? LuaExport.animations : LuaExport.skeleton;
const lua = fn(json);
fs.writeFileSync(output, lua, 'utf-8');
console.log('[out]', output, `(${lua.length} bytes)`);
