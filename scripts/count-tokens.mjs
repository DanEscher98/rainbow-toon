#!/usr/bin/env node
// Token counter script using gpt-tokenizer
// Usage: echo "text" | node count-tokens.mjs
// Or:    node count-tokens.mjs < file.txt

import { execSync } from 'child_process'
import { createRequire } from 'module'
import { join } from 'path'

// Get npm global root to find globally installed packages
const npmRoot = execSync('npm root -g', { encoding: 'utf8' }).trim()
const require = createRequire(join(npmRoot, 'gpt-tokenizer', 'package.json'))
const { countTokens } = require('gpt-tokenizer')

let input = ''

process.stdin.setEncoding('utf8')

process.stdin.on('data', (chunk) => {
  input += chunk
})

process.stdin.on('end', () => {
  const count = countTokens(input)
  process.stdout.write(String(count))
})
