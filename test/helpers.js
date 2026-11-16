const test = require('brittle')
const path = require('path')
const make = require('bare-make')

const modules = path.resolve(__dirname, '..', 'node_modules')

const isBare = typeof Bare !== 'undefined'

exports.build = function build(fixture, opts = {}) {
  const { debug = false } = opts

  test(`${fixture}${debug ? ' (debug)' : ''}`, { timeout: 300000 }, async (t) => {
    const cwd = path.resolve(__dirname, '..', fixture)

    await make.generate({
      cwd,
      source: '.',
      build: 'build',
      cache: false,
      debug,
      define: [`CMAKE_PREFIX_PATH=${modules}`],
      stdio: 'inherit'
    })

    await make.build({ cwd, build: 'build', clean: true, stdio: 'inherit' })

    await make.install({ cwd, build: 'build', prefix: 'prebuilds', stdio: 'inherit' })

    if (isBare) {
      t.is(require(path.join(cwd, 'index.js')), 42, 'calls into Rust')
    } else {
      t.pass('built')
    }
  })
}
