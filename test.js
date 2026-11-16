const { build } = require('./test/helpers')

build('test/fixtures/addon')
build('test/fixtures/debug', { debug: true })
build('test/fixtures/cdylib-dependency')
build('test/fixtures/workspace')
