# CSS, HTML and SVG Engine for Roblox

[Leia em português](README.pt-BR.md)

This plugin lets you build Roblox interfaces by writing HTML, CSS and SVG, the same way you would for a web page. You write the code in an editor inside Studio and the plugin turns it into real Roblox GUI objects.

To make that work I basically had to write a small browser engine in Luau. There is an HTML tokenizer and parser that build the document tree, and a CSS engine with cascade, variables, colors and color spaces, gradients, counters, container and media queries, anchors and logical properties. Layout supports normal flow, flexbox, grid with subgrid, tables, multiple columns and positioned elements, with inline text that wraps the same way it does on the web. Fonts are read straight from the binary files, including WOFF2 with its Brotli compression, and support shaping, variations and OpenType features. The SVG side covers paths, gradients and patterns, filters, markers, text and SMIL animations. There are also CSS animations and transitions, motion paths, form controls, pseudo elements, pointer input and hit testing.

Rendering only redraws the parts of the screen that changed, using dirty regions, tiles and a render budget so Studio stays responsive. A conformance harness compares the output with reference results taken from Chromium.

## How to use

The CssPlugin folder follows the Rojo layout, where the Main folder becomes a Script with the Modules and Templates folders inside it. Bring it into a place with Rojo or another sync tool, right click Main in the Explorer and choose Save as Local Plugin. The plugin editor opens from the Plugins tab. The Templates folder has the client scripts the plugin uses as a base, including a bootstrap script and a demo page that shows what it can do.

## Development time

The plugin took about two and a half months to build and it is finished.

## License

GNU General Public License version 3. The full text is in the LICENSE file.
