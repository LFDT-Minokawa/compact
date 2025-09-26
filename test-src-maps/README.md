# Examples and tests for source maps

## Example source maps for compact

1. neg - simplified file without type checks  
   [neg.compact](neg.compact) - original compact file  
   [neg.js](neg.js) - simplified JS file corresponding to neg.compact  
   [neg.js.map](neg.js.map) - source maps mapping from generated neg.js to original neg.compact file   
   [neg.js.map.fmt](neg.js.map.fmt.json) - mappings (from source map file) formatted  
   [neg.js.map.decoded](neg.js.map.decoded.json) - mappings (from source map file) formatted

## Testing using online source maps visualizer

You can see visualization how source maps relates original (*.compact file) and generated file (*.js file) at [sokra.github.io/source-map-visualization](http://sokra.github.io/source-map-visualization/#custom)

## TypeScript Tools

Testing uses libraries:
* [vlq](https://www.npmjs.com/package/vlq) encode numbers using VLQ format into letters
* [source-map](https://www.npmjs.com/package/source-map) check if given mapping exist, create mappings from AST

## Tests

Unit tests here are intended to verify source maps generated in compact compiler

```sh
yarn
yarn test
```
